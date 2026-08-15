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
// Pins the one thing that separates an OBSTACLE from a TRIGGER in the occupancy surface.
//
// The static body domain holds both: baked level geometry and Static-motion JoltBodies, and the Jolt bake
// filter bakes Overlap-only components by DEFAULT (_BakeExcludeOverlapOnlyComponents = Disable). The
// occupancy filter used to admit a body on domain alone, so a trigger volume read as SOLID — and since
// these queries are what volumetric navigation bakes and clearance sweeps run on, a large trigger could
// silently carve navigable space out of a bake. Nothing failed loudly; the space was simply gone.
//
// Two Static bodies are composed far apart above the map, identical but for their collision profile:
// BlockAll (QueryAndPhysics) vs OverlapAll (QueryOnly). The blocker must read occupied and block a
// segment; the trigger must read free on both. Distinguishing them is the whole point — asserting only
// the blocker would pass just as well against the old domain-only filter.
//
// PHYSICS-enabled collision is what separates them, NOT "does it block a channel". A UE profile's
// CustomResponses only override the channels it NAMES, so OverlapAll still Blocks every unlisted
// project-defined custom channel — a blocks-anything test calls this trigger solid. This test caught
// exactly that, so keep OverlapAll (not a hand-built all-Overlap signature) as the fixture: it is the
// realistic shape of the bug.
// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_jolt_overlap_occupancy
{
    // Cross-latent-command state: the spawned bodies survive from the spawn RunOnServer to the later
    // assertions. Reset at each test start.
    static FCk_Handle_JoltBody GBlockingBody;
    static FCk_Handle_JoltBody GOverlapOnlyBody;

    const auto EntryMapPath = FString{TEXT("/Engine/Maps/Entry")};

    // Far above the map's own geometry, and far apart from each other, so each probe can only ever
    // contain the body it is aimed at.
    const auto BlockingCenter = FVector{0.0, 0.0, 20000.0};
    const auto OverlapOnlyCenter = FVector{5000.0, 0.0, 20000.0};

    // FCk_Jolt_ShapeDimensions' Box default is a 50uu half extent.
    const auto ProbeHalfExtents = FVector{10.0};
    const auto SegmentReach = FVector{0.0, 0.0, 200.0};

    constexpr auto kTestFlags = EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter;

    constexpr int32 SettleFrames = 30;

    static auto Make_StaticBoxParams(FName InCollisionProfile) -> FCk_Fragment_JoltBody_ParamsData
    {
        auto Params = FCk_Fragment_JoltBody_ParamsData{ECk_JoltBody_ShapeSource::ExplicitShape};
        Params.Set_ShapeDimensions(FCk_Jolt_ShapeDimensions{ECk_Jolt_ShapeType::Box});
        Params.Set_MotionType(ECk_MotionType::Static);
        Params.Set_CollisionProfileName(InCollisionProfile);
        return Params;
    }

    static auto Spawn_StaticBox(
        UWorld* InServer,
        const FVector& InLocation,
        FName InCollisionProfile)
        -> FCk_Handle_JoltBody
    {
        auto* Ecs = InServer->GetSubsystem<UCk_EcsWorld_Subsystem_UE>();
        if (ck::Is_NOT_Valid(Ecs))
        { return {}; }

        auto Entity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Ecs->Get_Registry());
        UCk_Utils_Transform_UE::Add(Entity, FTransform{InLocation}, ECk_Replication::DoesNotReplicate);

        return UCk_Utils_JoltBody_UE::Add(Entity, Make_StaticBoxParams(InCollisionProfile));
    }

    static auto Make_QuerySession() -> ck::jolt::FCk_Jolt_QuerySession
    {
        return ck::jolt::FCk_Jolt_QuerySession{ck::auto_test::net::Get_ServerWorld()};
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_JoltQuery_BoxOccupancy_OverlapOnlyBodyIsNotOccupied,
    "Ck.Jolt.Query.BoxOccupancy.OverlapOnlyBodyIsNotOccupied",
    ck_test_jolt_overlap_occupancy::kTestFlags)

bool FCkTest_JoltQuery_BoxOccupancy_OverlapOnlyBodyIsNotOccupied::RunTest(const FString& Parameters)
{
    using namespace ck_test_jolt_overlap_occupancy;

    bSuppressLogWarnings = true;
    // /Engine/Maps/Entry ships a default BrushComponent with collision but no runtime BrushBodySetup;
    // the Jolt static-world bake ensures on it at PIE start. Unrelated to occupancy — whitelist it.
    AddExpectedError(TEXT("BodySetup"), EAutomationExpectedErrorFlags::Contains, /*Occurrences=*/-1);

    GBlockingBody = FCk_Handle_JoltBody{};
    GOverlapOnlyBody = FCk_Handle_JoltBody{};

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
            GBlockingBody = Spawn_StaticBox(InServer, BlockingCenter, TEXT("BlockAll"));
            GOverlapOnlyBody = Spawn_StaticBox(InServer, OverlapOnlyCenter, TEXT("OverlapAll"));

            TestTrue(TEXT("blocking static box composed"), ck::IsValid(GBlockingBody));
            TestTrue(TEXT("overlap-only static box composed"), ck::IsValid(GOverlapOnlyBody));
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda([]() -> bool
        {
            return ck::IsValid(GBlockingBody) && UCk_Utils_JoltBody_UE::Get_IsBodyAdded(GBlockingBody)
                && ck::IsValid(GOverlapOnlyBody) && UCk_Utils_JoltBody_UE::Get_IsBodyAdded(GOverlapOnlyBody);
        }),
        BodyAddedTimeoutSeconds,
        TEXT("both static boxes were added to the Jolt world")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            const auto Session = Make_QuerySession();
            const auto Probe = ck::jolt::FCk_Jolt_BoxProbe{ProbeHalfExtents};

            // The control: without this, the test would also pass if occupancy returned false for
            // EVERYTHING, which is the opposite failure and just as broken.
            const auto BlockerOccupied = TestTrue(
                TEXT("a BLOCKING static body reads occupied"),
                Session.Get_IsBoxOccupied(Probe, BlockingCenter));

            const auto TriggerFree = TestFalse(
                TEXT("an OVERLAP-ONLY static body does NOT read occupied — a trigger is not solid space"),
                Session.Get_IsBoxOccupied(Probe, OverlapOnlyCenter));

            return BlockerOccupied && TriggerFree;
        }),
        TEXT("box occupancy separates blockers from trigger volumes")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            const auto Session = Make_QuerySession();

            const auto ThroughBlocker = TestTrue(
                TEXT("a segment through the BLOCKING body is blocked"),
                Session.Get_IsSegmentBlocked(BlockingCenter - SegmentReach, BlockingCenter + SegmentReach));

            const auto ThroughTrigger = TestFalse(
                TEXT("a segment through the OVERLAP-ONLY body is NOT blocked — line of sight passes through a trigger"),
                Session.Get_IsSegmentBlocked(
                    OverlapOnlyCenter - SegmentReach, OverlapOnlyCenter + SegmentReach));

            return ThroughBlocker && ThroughTrigger;
        }),
        TEXT("segment queries pass through trigger volumes and stop at blockers")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

#endif
