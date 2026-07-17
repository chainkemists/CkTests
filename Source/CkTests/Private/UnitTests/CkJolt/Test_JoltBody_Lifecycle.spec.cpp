#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/World.h"

#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/Subsystem/CkEcsWorld_Subsystem.h"

#include "CkEcsExt/Transform/CkTransform_Utils.h"

#include "CkJolt/Body/CkJoltBody_Utils.h"
#include "CkJolt/Subsystem/CkJolt_Subsystem.h"

#include "CkTests/Net/CkNetAutomation_Common.h"

#include <Jolt/Jolt.h>
#include <Jolt/Physics/PhysicsSystem.h>

// --------------------------------------------------------------------------------------------------------------------
// Pins the JoltBody teardown contract inside a real PIE world with a live JPH::PhysicsSystem: every body a
// destroyed entity added must be removed from the world. Bodies are composed, the world ticks so the Setup
// processor adds them (GetNumBodies climbs by the exact count), the entities are destroyed, the world ticks so
// the EndPlay processor RemoveBody's them, and the count must return to the captured pre-churn baseline. This is
// the leak-fix regression at the JoltBody level (a leaked body would leave GetNumBodies above baseline).
//
// The count comparison is a delta against a baseline captured at runtime, so any bodies the map itself owns are
// tolerated as long as they are stable across the window. Uses the multi-client net harness with NumClients=1
// (single ListenServer world) on the minimal /Engine/Maps/Entry map.
// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_jolt_lifecycle
{
    // Cross-latent-command state: created entities survive between a spawn RunOnServer and a later destroy
    // RunOnServer; the baseline body count survives between capture and assertion. Reset at each test start.
    static TArray<FCk_Handle> GEntities;
    static int32              GBaseline = 0;

    const auto EntryMapPath = FString{TEXT("/Engine/Maps/Entry")};

    static auto Get_NumJoltBodies(UWorld* InWorld) -> int32
    {
        if (InWorld == nullptr)
        { return -1; }

        auto* Jolt = InWorld->GetSubsystem<UCk_Jolt_Subsystem>();
        if (Jolt == nullptr)
        { return -1; }

        const auto PhysicsSystem = Jolt->Get_PhysicsSystem().Pin();
        if (NOT PhysicsSystem.IsValid())
        { return -1; }

        return static_cast<int32>(PhysicsSystem->GetNumBodies());
    }

    static auto Spawn_JoltBoxEntity(
        UWorld* InWorld,
        const FVector& InLocation,
        ECk_MotionType InMotionType,
        ECk_Jolt_SleepState InInitialSleepState) -> FCk_Handle
    {
        auto* Ecs = InWorld->GetSubsystem<UCk_EcsWorld_Subsystem_UE>();
        if (ck::Is_NOT_Valid(Ecs))
        { return {}; }

        auto Entity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Ecs->Get_Registry());
        UCk_Utils_Transform_UE::Add(Entity, FTransform{InLocation}, ECk_Replication::DoesNotReplicate);

        auto Params = FCk_Fragment_JoltBody_ParamsData{ECk_JoltBody_ShapeSource::ExplicitShape};
        Params.Set_ShapeDimensions(FCk_Jolt_ShapeDimensions{ECk_Jolt_ShapeType::Box});
        Params.Set_MotionType(InMotionType);
        Params.Set_InitialSleepState(InInitialSleepState);

        UCk_Utils_JoltBody_UE::Add(Entity, Params);
        return Entity;
    }

    // Spread bodies out on a coarse grid, high up, so free-fall never brings them into contact — the count is
    // all that matters, and a 1000-body contact pile would just burn frames.
    static auto Grid_Location(int32 InIndex) -> FVector
    {
        constexpr auto Stride = 200.0;
        constexpr auto PerRow = 32;
        return FVector{(InIndex % PerRow) * Stride, (InIndex / PerRow) * Stride, 5000.0};
    }

    constexpr auto kTestFlags = EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter;

    // Frame budgets: generous so batched body add/remove and end-of-frame deferred destruction fully drain.
    constexpr int32 SettleFrames = 30;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_JoltBody_Lifecycle_ChurnThousandReturnsToBaseline,
    "Ck.Jolt.Body.Lifecycle.ChurnThousandReturnsToBaseline",
    ck_test_jolt_lifecycle::kTestFlags)

bool FCkTest_JoltBody_Lifecycle_ChurnThousandReturnsToBaseline::RunTest(const FString& Parameters)
{
    using namespace ck_test_jolt_lifecycle;

    bSuppressLogWarnings = true;
    // /Engine/Maps/Entry ships a default BrushComponent with collision but no runtime BrushBodySetup;
    // the Jolt static-world bake ensures on it at PIE start. Unrelated to JoltBody lifecycle — whitelist it.
    AddExpectedError(TEXT("BodySetup"), EAutomationExpectedErrorFlags::Contains, /*Occurrences=*/-1);

    GEntities.Reset();
    GBaseline = 0;

    constexpr int32 BodyCount = 1000;
    constexpr auto ReadyTimeoutSeconds = 30.0f;
    constexpr int32 NumClients = 1;
    constexpr int32 ExpectedWorlds = 1;

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(NumClients, EntryMapPath));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(ExpectedWorlds, ReadyTimeoutSeconds));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(SettleFrames));

    // Capture baseline + spawn 1000 dynamic boxes.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            GBaseline = Get_NumJoltBodies(InServer);
            if (GBaseline < 0)
            { AddError(TEXT("Jolt PhysicsSystem not available on the server world at baseline")); return; }

            for (auto Index = 0; Index < BodyCount; ++Index)
            {
                auto Entity = Spawn_JoltBoxEntity(
                    InServer, Grid_Location(Index), ECk_MotionType::Dynamic, ECk_Jolt_SleepState::Awake);
                if (ck::IsValid(Entity))
                { GEntities.Add(Entity); }
            }

            TestEqual(TEXT("all 1000 JoltBody entities composed"), GEntities.Num(), BodyCount);
        })));

    // Tick so the Setup processor adds every body.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(SettleFrames));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            const auto Num = Get_NumJoltBodies(ck::auto_test::net::Get_ServerWorld());
            return TestEqual(TEXT("body count climbed by exactly 1000 after add"), Num, GBaseline + BodyCount);
        }),
        TEXT("1000 bodies added to the Jolt world")));

    // Destroy every entity.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([](UWorld* InServer) -> void
        {
            UCk_Utils_EntityLifetime_UE::Request_DestroyEntities(GEntities);
        })));

    // Pump destruction: deferred entity teardown + the JoltBody EndPlay processor removing each body.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(SettleFrames));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            const auto Num = Get_NumJoltBodies(ck::auto_test::net::Get_ServerWorld());
            return TestEqual(TEXT("body count returned to the pre-churn baseline (no leaked bodies)"),
                Num, GBaseline);
        }),
        TEXT("all 1000 bodies removed after entity destruction")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_JoltBody_Lifecycle_BatchFiveHundredSingleFrame,
    "Ck.Jolt.Body.Lifecycle.BatchFiveHundredSingleFrame",
    ck_test_jolt_lifecycle::kTestFlags)

bool FCkTest_JoltBody_Lifecycle_BatchFiveHundredSingleFrame::RunTest(const FString& Parameters)
{
    using namespace ck_test_jolt_lifecycle;

    bSuppressLogWarnings = true;
    AddExpectedError(TEXT("BodySetup"), EAutomationExpectedErrorFlags::Contains, /*Occurrences=*/-1);

    GEntities.Reset();
    GBaseline = 0;

    constexpr int32 BodyCount = 500;
    constexpr auto ReadyTimeoutSeconds = 30.0f;
    constexpr int32 NumClients = 1;
    constexpr int32 ExpectedWorlds = 1;

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(NumClients, EntryMapPath));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(ExpectedWorlds, ReadyTimeoutSeconds));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(SettleFrames));

    // Compose all 500 in ONE server action (single frame).
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            GBaseline = Get_NumJoltBodies(InServer);
            if (GBaseline < 0)
            { AddError(TEXT("Jolt PhysicsSystem not available on the server world at baseline")); return; }

            for (auto Index = 0; Index < BodyCount; ++Index)
            {
                auto Entity = Spawn_JoltBoxEntity(
                    InServer, Grid_Location(Index), ECk_MotionType::Dynamic, ECk_Jolt_SleepState::Awake);
                if (ck::IsValid(Entity))
                { GEntities.Add(Entity); }
            }

            TestEqual(TEXT("all 500 JoltBody entities composed in one frame"), GEntities.Num(), BodyCount);
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(SettleFrames));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            const auto Num = Get_NumJoltBodies(ck::auto_test::net::Get_ServerWorld());
            return TestEqual(TEXT("all 500 single-frame-batched bodies present in the Jolt world"),
                Num, GBaseline + BodyCount);
        }),
        TEXT("500 bodies batched in one frame all added")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_JoltBody_Lifecycle_DestroyWhileSleepingReturnsToBaseline,
    "Ck.Jolt.Body.Lifecycle.DestroyWhileSleepingReturnsToBaseline",
    ck_test_jolt_lifecycle::kTestFlags)

bool FCkTest_JoltBody_Lifecycle_DestroyWhileSleepingReturnsToBaseline::RunTest(const FString& Parameters)
{
    using namespace ck_test_jolt_lifecycle;

    bSuppressLogWarnings = true;
    AddExpectedError(TEXT("BodySetup"), EAutomationExpectedErrorFlags::Contains, /*Occurrences=*/-1);

    GEntities.Reset();
    GBaseline = 0;

    constexpr int32 BodyCount = 8;
    constexpr auto ReadyTimeoutSeconds = 30.0f;
    constexpr int32 NumClients = 1;
    constexpr int32 ExpectedWorlds = 1;

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(NumClients, EntryMapPath));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(ExpectedWorlds, ReadyTimeoutSeconds));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(SettleFrames));

    // Compose bodies that start Asleep (batch-added DontActivate) — they are still real bodies in the world.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            GBaseline = Get_NumJoltBodies(InServer);
            if (GBaseline < 0)
            { AddError(TEXT("Jolt PhysicsSystem not available on the server world at baseline")); return; }

            for (auto Index = 0; Index < BodyCount; ++Index)
            {
                auto Entity = Spawn_JoltBoxEntity(
                    InServer, Grid_Location(Index), ECk_MotionType::Dynamic, ECk_Jolt_SleepState::Asleep);
                if (ck::IsValid(Entity))
                { GEntities.Add(Entity); }
            }

            TestEqual(TEXT("all sleeping JoltBody entities composed"), GEntities.Num(), BodyCount);
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(SettleFrames));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            const auto Num = Get_NumJoltBodies(ck::auto_test::net::Get_ServerWorld());
            return TestEqual(TEXT("sleeping bodies are added to the world"), Num, GBaseline + BodyCount);
        }),
        TEXT("sleeping bodies added")));

    // Destroy while still asleep — a never-activated body must still be removed cleanly.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([](UWorld* InServer) -> void
        {
            UCk_Utils_EntityLifetime_UE::Request_DestroyEntities(GEntities);
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(SettleFrames));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            const auto Num = Get_NumJoltBodies(ck::auto_test::net::Get_ServerWorld());
            return TestEqual(TEXT("destroying sleeping bodies returns the count to baseline"), Num, GBaseline);
        }),
        TEXT("sleeping bodies removed cleanly")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
