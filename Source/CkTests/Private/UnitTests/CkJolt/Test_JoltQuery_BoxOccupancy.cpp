#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/World.h"

#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/Subsystem/CkEcsWorld_Subsystem.h"

#include "CkEcsExt/Transform/CkTransform_Utils.h"

#include "CkJolt/Body/CkJoltBody_Fragment.h"
#include "CkJolt/Body/CkJoltBody_Utils.h"
#include "CkJolt/Query/CkJoltOccupancy_Session.h"

#include "CkTests/Net/CkNetAutomation_Common.h"

// --------------------------------------------------------------------------------------------------------------------
// Pins CkJolt's occupancy surface — the JPH-free FCk_Jolt_QuerySession / FCk_Jolt_BoxProbe pair — against a
// known static box inside a real PIE world. One Static-motion JoltBody is composed high above the map so a
// tight query volume around it can only ever contain the body this test spawned; the assertions then read
// occupied inside it, free well clear of it, get exactly that body back from the broadphase AABox query, and
// see the segment query blocked straight through it and clear alongside it.
//
// The session resolves UCk_Jolt_Subsystem off a UWorld, so a live PIE world is the only fixture that provides
// one — the same multi-client harness (NumClients=1, single ListenServer world on /Engine/Maps/Entry) the
// JoltBody lifecycle test uses. Sessions are cheap to build by design, so each assertion builds its own
// instead of parking a move-only value in cross-command state.
// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_jolt_occupancy
{
    // Cross-latent-command state: the spawned body survives between the spawn RunOnServer and the later
    // query assertions. Reset at each test start.
    static FCk_Handle_JoltBody GBoxBody;

    const auto EntryMapPath = FString{TEXT("/Engine/Maps/Entry")};

    // Far above the map's own geometry, so an enclosing query volume around the box contains nothing else.
    const auto BoxCenter = FVector{0.0, 0.0, 20000.0};

    // FCk_Jolt_ShapeDimensions' Box default is a 50uu half extent — the body spans BoxCenter +/- 50uu.
    const auto ProbeHalfExtents = FVector{10.0};
    const auto ClearlyOutsideOffset = FVector{1000.0, 0.0, 0.0};

    // Reaches well past the box's own 50uu half extent on each side, so a segment built from it crosses the
    // whole body rather than terminating inside it.
    const auto SegmentReach = FVector{0.0, 0.0, 200.0};

    constexpr auto kTestFlags = EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter;

    constexpr int32 SettleFrames = 30;

    static auto Make_StaticBoxParams() -> FCk_Fragment_JoltBody_ParamsData
    {
        auto Params = FCk_Fragment_JoltBody_ParamsData{ECk_JoltBody_ShapeSource::ExplicitShape};
        Params.Set_ShapeDimensions(FCk_Jolt_ShapeDimensions{ECk_Jolt_ShapeType::Box});
        Params.Set_MotionType(ECk_MotionType::Static);
        return Params;
    }

    static auto Make_QuerySession() -> ck::jolt::FCk_Jolt_QuerySession
    {
        return ck::jolt::FCk_Jolt_QuerySession{ck::auto_test::net::Get_ServerWorld()};
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_JoltQuery_BoxOccupancy_StaticBoxOccupancyAndBroadPhase,
    "Ck.Jolt.Query.BoxOccupancy.StaticBoxOccupancyAndBroadPhase",
    ck_test_jolt_occupancy::kTestFlags)

bool FCkTest_JoltQuery_BoxOccupancy_StaticBoxOccupancyAndBroadPhase::RunTest(const FString& Parameters)
{
    using namespace ck_test_jolt_occupancy;

    bSuppressLogWarnings = true;
    // /Engine/Maps/Entry ships a default BrushComponent with collision but no runtime BrushBodySetup;
    // the Jolt static-world bake ensures on it at PIE start. Unrelated to occupancy — whitelist it.
    AddExpectedError(TEXT("BodySetup"), EAutomationExpectedErrorFlags::Contains, /*Occurrences=*/-1);

    GBoxBody = FCk_Handle_JoltBody{};

    constexpr auto ReadyTimeoutSeconds = 30.0f;
    constexpr auto BodyAddedTimeoutSeconds = 15.0;
    constexpr int32 NumClients = 1;
    constexpr int32 ExpectedWorlds = 1;

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(NumClients, EntryMapPath));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(ExpectedWorlds, ReadyTimeoutSeconds));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(SettleFrames));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto* Ecs = InServer->GetSubsystem<UCk_EcsWorld_Subsystem_UE>();
            if (ck::Is_NOT_Valid(Ecs))
            { AddError(TEXT("ECS world subsystem not available on the server world")); return; }

            auto Entity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Ecs->Get_Registry());
            UCk_Utils_Transform_UE::Add(Entity, FTransform{BoxCenter}, ECk_Replication::DoesNotReplicate);

            GBoxBody = UCk_Utils_JoltBody_UE::Add(Entity, Make_StaticBoxParams());

            TestTrue(TEXT("static box JoltBody composed"), ck::IsValid(GBoxBody));
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda([]() -> bool
        {
            return ck::IsValid(GBoxBody) && UCk_Utils_JoltBody_UE::Get_IsBodyAdded(GBoxBody);
        }),
        BodyAddedTimeoutSeconds,
        TEXT("the static box's body was added to the Jolt world")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            return TestTrue(TEXT("query session resolves against the PIE server world"),
                Make_QuerySession().Get_IsValid());
        }),
        TEXT("query session resolved")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            const auto Session = Make_QuerySession();
            const auto Probe = ck::jolt::FCk_Jolt_BoxProbe{ProbeHalfExtents};

            const auto ProbeInside = TestTrue(TEXT("probe centered inside the static box reads occupied"),
                Session.Get_IsBoxOccupied(Probe, BoxCenter));

            const auto ProbeOutside = TestFalse(TEXT("probe well clear of the static box reads unoccupied"),
                Session.Get_IsBoxOccupied(Probe, BoxCenter + ClearlyOutsideOffset));

            const auto OneOffInside = TestTrue(TEXT("one-off half-extent overload agrees inside the box"),
                Session.Get_IsBoxOccupied(BoxCenter, ProbeHalfExtents));

            const auto OneOffOutside = TestFalse(TEXT("one-off half-extent overload agrees outside the box"),
                Session.Get_IsBoxOccupied(BoxCenter + ClearlyOutsideOffset, ProbeHalfExtents));

            return ProbeInside && ProbeOutside && OneOffInside && OneOffOutside;
        }),
        TEXT("box occupancy reads occupied inside the static box and free outside it")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            const auto Session = Make_QuerySession();

            const auto Through = TestTrue(TEXT("a segment driven straight through the static box is blocked"),
                Session.Get_IsSegmentBlocked(BoxCenter - SegmentReach, BoxCenter + SegmentReach));

            const auto Alongside = TestFalse(TEXT("the same segment offset well clear of the box is not blocked"),
                Session.Get_IsSegmentBlocked(
                    BoxCenter + ClearlyOutsideOffset - SegmentReach,
                    BoxCenter + ClearlyOutsideOffset + SegmentReach));

            const auto FromInside = TestTrue(TEXT("a segment starting inside the box is blocked"),
                Session.Get_IsSegmentBlocked(BoxCenter, BoxCenter + SegmentReach));

            return Through && Alongside && FromInside;
        }),
        TEXT("segment queries are blocked through the static box and clear alongside it")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            if (NOT TestTrue(TEXT("the spawned static box survived to the broadphase assertion"),
                ck::IsValid(GBoxBody)))
            { return false; }

            const auto Session = Make_QuerySession();

            const auto EnclosingHalfSize = FVector{200.0};
            auto EnclosingBodyIds = TArray<uint64>{};
            Session.Get_BodiesInAABox(
                FBox{BoxCenter - EnclosingHalfSize, BoxCenter + EnclosingHalfSize}, EnclosingBodyIds);

            const auto FoundExactlyOne = TestEqual(TEXT("enclosing AABox returns exactly one body"),
                EnclosingBodyIds.Num(), 1);

            const auto ExpectedBodyId = static_cast<uint64>(
                GBoxBody.Get<ck::FFragment_JoltBody_Current>().Get_BodyId().GetIndexAndSequenceNumber());

            const auto FoundTheBox = FoundExactlyOne && TestTrue(
                *FString::Printf(TEXT("the returned body [%llu] is the spawned static box [%llu]"),
                    EnclosingBodyIds[0], ExpectedBodyId),
                EnclosingBodyIds[0] == ExpectedBodyId);

            auto DistantBodyIds = TArray<uint64>{};
            Session.Get_BodiesInAABox(
                FBox{BoxCenter + ClearlyOutsideOffset - EnclosingHalfSize,
                     BoxCenter + ClearlyOutsideOffset + EnclosingHalfSize}, DistantBodyIds);

            const auto DistantIsEmpty = TestEqual(TEXT("distant AABox returns no bodies"),
                DistantBodyIds.Num(), 0);

            return FoundExactlyOne && FoundTheBox && DistantIsEmpty;
        }),
        TEXT("broadphase AABox returns exactly the static box's body")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
