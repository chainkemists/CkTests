// Two worlds alive at once, and the per-world state that must never bleed between them.
//
// Three separate maps are keyed by TWeakObjectPtr<UWorld> and each of them is a process-wide static:
// the GroundNav world-field registry (CkGroundNav_WorldFieldRegistry.cpp), and the provider table's
// two mirrors, WorldProviders and WorldShadowModes (CkNavSurface_ProviderTable.cpp). A single-world
// test cannot tell a per-world map from a global one - every read returns what the only writer wrote
// either way. Two worlds is the smallest fixture in which the difference is observable, and PIE plus
// a dedicated server, or an editor preview world beside a running game, is the shipping shape that
// makes it matter.
//
// The cleanup half is the other reason this file exists. Each of those maps drops a world's entry on
// FWorldDelegates::OnWorldCleanup, and UWorld::DestroyWorld reaches that broadcast through
// CleanupWorld -> CleanupWorldInternal. DestroyWorld does NOT mark the world object as garbage - it
// only unroots it - so the destroyed world's pointer is still a valid UObject when the assertions
// below read through it, and an empty answer for it is the hook's doing rather than a validity guard
// short-circuiting the lookup.
//
// Real UWorlds rather than bare ck::FEcsWorlds, because a world is the key: none of the state under
// test is reachable from a registry alone.

#include "CkCore/Time/CkTime.h"

#include "CkEcs/EntityLifetime/CkEntityLifetime_Fragment.h"
#include "CkEcs/EntityLifetime/CkEntityLifetime_Processor.h"
#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/Subsystem/CkEcsWorld_Subsystem.h"

#include "CkGroundNav/Backend/CkGroundNav_GeometryBackend_Stub.h"
#include "CkGroundNav/Facade/CkGroundNav_WorldFieldRegistry.h"
#include "CkGroundNav/Field/CkGroundNav_Field.h"
#include "CkGroundNav/Volume/CkGroundNavVolume_Processor.h"
#include "CkGroundNav/Volume/CkGroundNavVolume_Utils.h"

#include "CkNavigation/NavSurface/CkNavSurface_ProviderTable.h"

#include "CkShapes/Capsule/CkShapeCapsule_Fragment_Data.h"

#include "../CkUnitTest_Common.h"

#include <Engine/World.h>

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_groundnav_multiworld
{
    using ck::groundnav::DoBake_Field;
    using ck::groundnav::FCk_GroundNav_Epoch;
    using ck::groundnav::FCk_GroundNav_Field;
    using ck::groundnav::FCk_GroundNav_FieldParams;
    using ck::groundnav::FCk_GroundNav_FieldPtr;
    using ck::groundnav::FCk_GroundNav_GeometryBackend_Stub;

    namespace world_fields = ck::groundnav::world_fields;

    constexpr auto InformEngineOfWorld = false;
    constexpr auto kSixtyHertz = 1.0f / 60.0f;

    constexpr auto kCellSize = 25.0f;
    constexpr auto kCellHeight = 10.0f;
    constexpr auto kTileSize = 400.0f;
    constexpr auto kMaxClearance = 100.0f;

    // World A's ground and world B's ground are placed far enough apart that neither field's lattice
    // reaches the other's, so a point inside one is outside the other's bounds and a leaked pointer
    // cannot pass as a legitimate bounds hit.
    constexpr auto kVolumeSpanUu = 800.0;
    constexpr auto kWorldAOriginUu = 0.0;
    constexpr auto kWorldBOriginUu = 4000.0;

    struct FWorldFixture
    {
        UWorld* _World = nullptr;
        FCk_Handle _WorldEntity;
        FCk_Handle_GroundNavVolume _Volume;
    };

    auto Make_Profile() -> FCk_GroundNav_AgentProfile
    {
        // The ledge filter is off for the same reason Test_GroundNav_RevisionWorld turns it off: the
        // subject is which world holds what, and the conservative default would trim the fixture's
        // borders for reasons this file has nothing to say about.
        auto Profile = FCk_GroundNav_AgentProfile{
            FCk_AnyShape{FCk_ShapeCapsule_Dimensions{70.0f, 20.0f}}};
        Profile.Set_LedgeSensitivity(0.0f);

        return Profile;
    }

    auto Make_FieldParams(
        double InOriginUu) -> FCk_GroundNav_FieldParams
    {
        auto Config = FCk_GroundNav_BakeConfig{kCellSize, kCellHeight};
        Config.Set_TileSizeUu(kTileSize);

        auto Params = FCk_GroundNav_FieldParams{};

        Params._OriginXY = FVector2D{InOriginUu, InOriginUu};
        Params._Divisions = FIntPoint{2, 2};
        Params._MinZUu = -50.0f;
        Params._MaxZUu = 300.0f;
        Params._Config = Config;
        Params._Profile = Make_Profile();
        Params._MaxClearanceUu = kMaxClearance;

        return Params;
    }

    auto Make_VolumeParams(
        double InOriginUu) -> FCk_Fragment_GroundNavVolume_ParamsData
    {
        auto Config = FCk_GroundNav_BakeConfig{kCellSize, kCellHeight};
        Config.Set_TileSizeUu(kTileSize);

        const auto Bounds = FBox{
            FVector{InOriginUu, InOriginUu, -50.0},
            FVector{InOriginUu + kVolumeSpanUu, InOriginUu + kVolumeSpanUu, 300.0}};

        return FCk_Fragment_GroundNavVolume_ParamsData{Bounds, Config, Make_Profile()};
    }

    // Ground reaching past the lattice on every side, so every tile's halo has real world in it.
    auto Bake_Field(
        double                     InOriginUu,
        const FCk_GroundNav_Epoch& InEpoch) -> FCk_GroundNav_FieldPtr
    {
        const auto Backend = FCk_GroundNav_GeometryBackend_Stub{
            TArray<FBox>{FBox{
                FVector{InOriginUu - 400.0, InOriginUu - 400.0, -10.0},
                FVector{InOriginUu + 1200.0, InOriginUu + 1200.0, 0.0}}}};

        auto Field = MakeShared<FCk_GroundNav_Field>();

        if (NOT DoBake_Field(Backend, Make_FieldParams(InOriginUu), InEpoch, *Field).Get_IsCompleted())
        { return {}; }

        return FCk_GroundNav_FieldPtr{Field};
    }

    // A point well inside the field baked at the given origin, and therefore well outside the other
    // world's.
    auto Make_PointInside(
        double InOriginUu) -> FVector
    {
        return FVector{InOriginUu + 400.0, InOriginUu + 400.0, 0.0};
    }

    auto Make_Fixture(
        const TCHAR* InWorldName,
        double       InOriginUu) -> FWorldFixture
    {
        auto Fixture = FWorldFixture{};

        Fixture._World = UWorld::CreateWorld(EWorldType::Game, InformEngineOfWorld, FName{InWorldName});

        if (Fixture._World == nullptr)
        { return Fixture; }

        Fixture._WorldEntity = UCk_Utils_EcsWorld_Subsystem_UE::Get_TransientEntity(Fixture._World);

        if (ck::Is_NOT_Valid(Fixture._WorldEntity))
        { return Fixture; }

        auto Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Fixture._WorldEntity);

        Fixture._Volume = UCk_Utils_GroundNavVolume_UE::Add(Owner, Make_VolumeParams(InOriginUu));

        return Fixture;
    }

    auto Get_IsReady(
        const FWorldFixture& InFixture) -> bool
    {
        return InFixture._World != nullptr &&
               ck::IsValid(InFixture._WorldEntity) &&
               ck::IsValid(InFixture._Volume);
    }

    auto Destroy_Fixture(
        FWorldFixture& InFixture) -> void
    {
        if (InFixture._World != nullptr)
        { InFixture._World->DestroyWorld(InformEngineOfWorld); }

        InFixture._World = nullptr;
    }

    // The provider's own revision body, reached the way the neutral seam reaches it. Reproducing the
    // fold here instead would test this file's arithmetic rather than the provider's.
    auto Get_WorldRevision(
        UWorld* InWorld) -> int64
    {
        const auto* Table = ck::nav_surface::TryGet_ProviderTable(ECk_NavSurface_Provider::GroundNav);

        if (Table == nullptr || NOT Table->_SurfaceRevision)
        { return int64{-1}; }

        return Table->_SurfaceRevision(InWorld);
    }

    // The value a world could only be reading back because something SET it: whatever the project
    // default is not. A world set to the default value reads the same whether its entry survived or
    // was dropped, which would make the cleanup assertions vacuous.
    auto Get_NonDefaultProvider() -> ECk_NavSurface_Provider
    {
        return ck::nav_surface::Get_DefaultProvider() == ECk_NavSurface_Provider::GroundNav
            ? ECk_NavSurface_Provider::Recast
            : ECk_NavSurface_Provider::GroundNav;
    }

    auto Get_NonDefaultShadowMode() -> ECk_NavSurface_ShadowMode
    {
        return ck::nav_surface::Get_DefaultShadowMode() == ECk_NavSurface_ShadowMode::GroundNavShadowsRecast
            ? ECk_NavSurface_ShadowMode::Off
            : ECk_NavSurface_ShadowMode::GroundNavShadowsRecast;
    }

    // The teardown shape Test_GroundNav_RevisionWorld drives: the entity is STAMPED for destruction
    // rather than retired, because the pipeline that retires it is the scheduler's and a headless
    // world has none. Deliberately stops short of the end-play unpublish, so what it pins is a volume
    // whose entry is still listed; the full chain, and the entry leaving with it, is DoDestroy_Volume.
    auto DoTearDown_Volume(
        FCk_Handle_GroundNavVolume& InVolume) -> void
    {
        auto VolumeEntity = InVolume.ConvertToHandle();

        UCk_Utils_EntityLifetime_UE::Request_DestroyEntity(VolumeEntity);

        // The request fragments are lazily composed by the request utils, and this volume was never
        // asked for anything - so they are added here to give the EndPlay drains something to walk.
        InVolume.AddOrGet<ck::FFragment_GroundNavVolume_Requests>();
        InVolume.AddOrGet<ck::FFragment_GroundNavVolume_MarkupRequests>();

        ck::FProcessor_GroundNavVolume_CancelPendingRequests::ForEachEntity(
            FCk_Time{kSixtyHertz},
            InVolume,
            InVolume.Get<ck::FFragment_GroundNavVolume_BuildState>(),
            InVolume.Get<ck::FFragment_GroundNavVolume_Requests>());

        ck::FProcessor_GroundNavVolume_CancelPendingMarkupRequests::ForEachEntity(
            FCk_Time{kSixtyHertz},
            InVolume,
            InVolume.Get<ck::FFragment_GroundNavVolume_MarkupRequests>());
    }

    // The OTHER teardown shape: the whole destruction chain, driven by hand as
    // Test_GroundNav_MarkupAdmission drives it, with the volume's own end-play unpublish standing in the
    // FGroup_EndPlay slot the scheduler would run it in. Request_DestroyEntity only STAMPS
    // FTag_DestroyEntity_Initiate, so each phase processor is called in the order its tag gates demand
    // and the last one retires the entity for real - which the registry assertion needs, because an
    // entry keyed on a live handle and one keyed on a retired handle are different claims.
    auto DoDestroy_Volume(
        FWorldFixture& InFixture) -> void
    {
        const auto DeltaT = FCk_Time{kSixtyHertz};

        auto VolumeEntity = InFixture._Volume.ConvertToHandle();

        UCk_Utils_EntityLifetime_UE::Request_DestroyEntity(VolumeEntity);

        ck::FProcessor_GroundNavVolume_Unpublish::ForEachEntity(
            DeltaT,
            InFixture._Volume,
            InFixture._Volume.Get<ck::FFragment_GroundNavVolume_BuiltField>());

        ck::FProcessor_EntityLifetime_DestructionPhase_Endplay::ForEachEntity(DeltaT, VolumeEntity);
        ck::FProcessor_EntityLifetime_DestructionPhase_Teardown::ForEachEntity(DeltaT, VolumeEntity);
        ck::FProcessor_EntityLifetime_DestructionPhase_Await::ForEachEntity(DeltaT, VolumeEntity);
        ck::FProcessor_EntityLifetime_DestructionPhase_Finalize::ForEachEntity(DeltaT, VolumeEntity);

        // The subsystem's registry rather than the handle's view: only the former carries the transient
        // entity the processor resolves at construction. Present whenever Get_IsReady passed, which
        // every caller checks - a missing one leaves the volume unretired and the assertions say so.
        const auto* EcsWorld = InFixture._World->GetSubsystem<UCk_EcsWorld_Subsystem_UE>();

        if (EcsWorld == nullptr)
        { return; }

        auto DestroyEntities = ck::FProcessor_EntityLifetime_DestroyEntity{EcsWorld->Get_Registry()};
        DestroyEntities.DoTick(DeltaT);
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_MultiWorld_TwoWorldsDoNotShareFields,
    "CkTests.UnitTests.CkGroundNav.MultiWorld.TwoWorldsDoNotShareFields",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_MultiWorld_TwoWorldsDoNotShareFields::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_multiworld;

    auto WorldA = Make_Fixture(TEXT("CkGroundNavMultiWorldFieldsA"), kWorldAOriginUu);
    auto WorldB = Make_Fixture(TEXT("CkGroundNavMultiWorldFieldsB"), kWorldBOriginUu);

    if (NOT TestTrue(TEXT("both world A and world B compose a volume to publish through"),
        Get_IsReady(WorldA) && Get_IsReady(WorldB)))
    {
        Destroy_Fixture(WorldA);
        Destroy_Fixture(WorldB);
        return false;
    }

    const auto FieldA = Bake_Field(kWorldAOriginUu, FCk_GroundNav_Epoch{1});
    const auto FieldB = Bake_Field(kWorldBOriginUu, FCk_GroundNav_Epoch{1});

    if (NOT TestTrue(TEXT("world A's field and world B's field both bake"),
        FieldA.IsValid() && FieldB.IsValid()))
    {
        Destroy_Fixture(WorldA);
        Destroy_Fixture(WorldB);
        return false;
    }

    world_fields::Publish(WorldA._World, WorldA._Volume, FieldA);
    world_fields::Publish(WorldB._World, WorldB._Volume, FieldB);

    TestEqual(TEXT("world A holds exactly the one field published on world A"),
        world_fields::Get_FieldCount(WorldA._World), 1);

    TestEqual(TEXT("world B holds exactly the one field published on world B"),
        world_fields::Get_FieldCount(WorldB._World), 1);

    const auto FieldsOfA = world_fields::Get_Fields(WorldA._World);
    const auto FieldsOfB = world_fields::Get_Fields(WorldB._World);

    if (NOT TestTrue(TEXT("world A's and world B's field lists each have one entry to name"),
        FieldsOfA.Num() == 1 && FieldsOfB.Num() == 1))
    {
        Destroy_Fixture(WorldA);
        Destroy_Fixture(WorldB);
        return false;
    }

    // Pointer identity, not a count: two worlds each holding ONE field would satisfy the counts above
    // even if both entries named the same field.
    TestTrue(TEXT("world A's list names world A's field pointer and no other"),
        FieldsOfA[0] == FieldA);

    TestTrue(TEXT("world B's list names world B's field pointer and no other"),
        FieldsOfB[0] == FieldB);

    const auto PointInA = Make_PointInside(kWorldAOriginUu);
    const auto PointInB = Make_PointInside(kWorldBOriginUu);

    TestTrue(TEXT("world A resolves a point inside world A's ground to world A's field"),
        world_fields::TryGet_Field(WorldA._World, PointInA) == FieldA);

    TestTrue(TEXT("world B resolves a point inside world B's ground to world B's field"),
        world_fields::TryGet_Field(WorldB._World, PointInB) == FieldB);

    // TryGet_Field falls back to the world's FIRST registered field when no bounds contain the point,
    // so the honest statement about a foreign point is not "null" - world B still has a field and
    // still answers with it. What must never happen is world B handing back world A's pointer.
    TestTrue(TEXT("world B never answers with world A's field, even for a point only world A covers"),
        world_fields::TryGet_Field(WorldB._World, PointInA) != FieldA);

    TestTrue(TEXT("world B answers a point only world A covers with its own field, by fallback"),
        world_fields::TryGet_Field(WorldB._World, PointInA) == FieldB);

    TestTrue(TEXT("world A never answers with world B's field, even for a point only world B covers"),
        world_fields::TryGet_Field(WorldA._World, PointInB) != FieldB);

    TestTrue(TEXT("world A answers a point only world B covers with its own field, by fallback"),
        world_fields::TryGet_Field(WorldA._World, PointInB) == FieldA);

    Destroy_Fixture(WorldA);
    Destroy_Fixture(WorldB);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_MultiWorld_RevisionOfOneWorldIsUnmovedByAnother,
    "CkTests.UnitTests.CkGroundNav.MultiWorld.RevisionOfOneWorldIsUnmovedByAnother",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_MultiWorld_RevisionOfOneWorldIsUnmovedByAnother::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_multiworld;

    auto WorldA = Make_Fixture(TEXT("CkGroundNavMultiWorldRevisionA"), kWorldAOriginUu);
    auto WorldB = Make_Fixture(TEXT("CkGroundNavMultiWorldRevisionB"), kWorldBOriginUu);

    if (NOT TestTrue(TEXT("both world A and world B compose a volume to publish through"),
        Get_IsReady(WorldA) && Get_IsReady(WorldB)))
    {
        Destroy_Fixture(WorldA);
        Destroy_Fixture(WorldB);
        return false;
    }

    if (NOT TestTrue(TEXT("GroundNav registered a provider table with a revision entry"),
        Get_WorldRevision(WorldA._World) >= 0))
    {
        Destroy_Fixture(WorldA);
        Destroy_Fixture(WorldB);
        return false;
    }

    const auto FirstFieldOfA = Bake_Field(kWorldAOriginUu, FCk_GroundNav_Epoch{1});
    const auto FieldOfB = Bake_Field(kWorldBOriginUu, FCk_GroundNav_Epoch{1});

    if (NOT TestTrue(TEXT("world A's first field and world B's field both bake"),
        FirstFieldOfA.IsValid() && FieldOfB.IsValid()))
    {
        Destroy_Fixture(WorldA);
        Destroy_Fixture(WorldB);
        return false;
    }

    world_fields::Publish(WorldA._World, WorldA._Volume, FirstFieldOfA);
    world_fields::Publish(WorldB._World, WorldB._Volume, FieldOfB);

    const auto RevisionOfABefore = Get_WorldRevision(WorldA._World);
    const auto RevisionOfBBefore = Get_WorldRevision(WorldB._World);

    TestEqual(TEXT("world A's revision is the epoch sum of what world A published"),
        RevisionOfABefore, FirstFieldOfA->Get_AggregatedTileEpochSum());

    TestEqual(TEXT("world B's revision is the epoch sum of what world B published"),
        RevisionOfBBefore, FieldOfB->Get_AggregatedTileEpochSum());

    // The shape a cost derive publishes: the SAME volume, a new field value, the next epoch. Publish
    // replaces that volume's entry rather than adding one, so world A's fold moves because its tiles
    // are newer and not because it now counts two fields.
    const auto SecondFieldOfA = Bake_Field(kWorldAOriginUu, FCk_GroundNav_Epoch{2});

    if (NOT TestTrue(TEXT("world A's second field bakes"), SecondFieldOfA.IsValid()))
    {
        Destroy_Fixture(WorldA);
        Destroy_Fixture(WorldB);
        return false;
    }

    world_fields::Publish(WorldA._World, WorldA._Volume, SecondFieldOfA);

    TestEqual(TEXT("world A still holds one field: the republish replaced its volume's entry"),
        world_fields::Get_FieldCount(WorldA._World), 1);

    const auto RevisionOfAAfter = Get_WorldRevision(WorldA._World);
    const auto RevisionOfBAfter = Get_WorldRevision(WorldB._World);

    TestEqual(TEXT("world A's revision is now the epoch sum of world A's second field"),
        RevisionOfAAfter, SecondFieldOfA->Get_AggregatedTileEpochSum());

    TestTrue(TEXT("and world A's revision rose"), RevisionOfAAfter > RevisionOfABefore);

    // The whole contract, and exact rather than "did not fall": world B published nothing, so a
    // consumer watching world B must see a number it has already caught up to. Any move at all would
    // announce a rebuild of world B that never happened.
    TestEqual(TEXT("world B's revision is unchanged by world A's publish"),
        RevisionOfBAfter, RevisionOfBBefore);

    TestEqual(TEXT("world B still reads its own field's epoch sum and nothing of world A's"),
        RevisionOfBAfter, FieldOfB->Get_AggregatedTileEpochSum());

    Destroy_Fixture(WorldA);
    Destroy_Fixture(WorldB);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_MultiWorld_ProviderAndShadowModeAreSetPerWorld,
    "CkTests.UnitTests.CkGroundNav.MultiWorld.ProviderAndShadowModeAreSetPerWorld",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_MultiWorld_ProviderAndShadowModeAreSetPerWorld::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_multiworld;

    auto WorldA = Make_Fixture(TEXT("CkGroundNavMultiWorldProviderA"), kWorldAOriginUu);
    auto WorldB = Make_Fixture(TEXT("CkGroundNavMultiWorldProviderB"), kWorldBOriginUu);

    if (NOT TestTrue(TEXT("both world A and world B exist to be told which provider answers them"),
        WorldA._World != nullptr && WorldB._World != nullptr))
    {
        Destroy_Fixture(WorldA);
        Destroy_Fixture(WorldB);
        return false;
    }

    ck::nav_surface::Set_ProviderForWorld(WorldA._World, ECk_NavSurface_Provider::GroundNav);
    ck::nav_surface::Set_ProviderForWorld(WorldB._World, ECk_NavSurface_Provider::Recast);

    ck::nav_surface::Set_ShadowModeForWorld(
        WorldA._World, ECk_NavSurface_ShadowMode::GroundNavShadowsRecast);
    ck::nav_surface::Set_ShadowModeForWorld(WorldB._World, ECk_NavSurface_ShadowMode::Off);

    TestTrue(TEXT("world A reads back the provider world A was set to"),
        ck::nav_surface::Get_ProviderForWorld(WorldA._World) == ECk_NavSurface_Provider::GroundNav);

    TestTrue(TEXT("world B reads back the provider world B was set to"),
        ck::nav_surface::Get_ProviderForWorld(WorldB._World) == ECk_NavSurface_Provider::Recast);

    TestTrue(TEXT("world A reads back the shadow mode world A was set to"),
        ck::nav_surface::Get_ShadowModeForWorld(WorldA._World) ==
            ECk_NavSurface_ShadowMode::GroundNavShadowsRecast);

    TestTrue(TEXT("world B reads back the shadow mode world B was set to"),
        ck::nav_surface::Get_ShadowModeForWorld(WorldB._World) == ECk_NavSurface_ShadowMode::Off);

    // Writing world B second must not have overwritten world A. A single global would leave both reads
    // answering with world B's values, which the per-world reads above would still call sane if world
    // A had happened to be written last.
    TestTrue(TEXT("world A's provider is not world B's"),
        ck::nav_surface::Get_ProviderForWorld(WorldA._World) !=
            ck::nav_surface::Get_ProviderForWorld(WorldB._World));

    TestTrue(TEXT("world A's shadow mode is not world B's"),
        ck::nav_surface::Get_ShadowModeForWorld(WorldA._World) !=
            ck::nav_surface::Get_ShadowModeForWorld(WorldB._World));

    Destroy_Fixture(WorldA);
    Destroy_Fixture(WorldB);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_MultiWorld_CleanupDropsOnlyItsOwnWorld,
    "CkTests.UnitTests.CkGroundNav.MultiWorld.CleanupDropsOnlyItsOwnWorld",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_MultiWorld_CleanupDropsOnlyItsOwnWorld::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_multiworld;

    auto WorldA = Make_Fixture(TEXT("CkGroundNavMultiWorldCleanupA"), kWorldAOriginUu);
    auto WorldB = Make_Fixture(TEXT("CkGroundNavMultiWorldCleanupB"), kWorldBOriginUu);

    if (NOT TestTrue(TEXT("both world A and world B compose a volume to publish through"),
        Get_IsReady(WorldA) && Get_IsReady(WorldB)))
    {
        Destroy_Fixture(WorldA);
        Destroy_Fixture(WorldB);
        return false;
    }

    const auto FieldA = Bake_Field(kWorldAOriginUu, FCk_GroundNav_Epoch{1});
    const auto FieldB = Bake_Field(kWorldBOriginUu, FCk_GroundNav_Epoch{1});

    if (NOT TestTrue(TEXT("world A's field and world B's field both bake"),
        FieldA.IsValid() && FieldB.IsValid()))
    {
        Destroy_Fixture(WorldA);
        Destroy_Fixture(WorldB);
        return false;
    }

    world_fields::Publish(WorldA._World, WorldA._Volume, FieldA);
    world_fields::Publish(WorldB._World, WorldB._Volume, FieldB);

    // Both worlds are set to the value the project default is NOT, so the post-cleanup reads below
    // distinguish "the entry survived" from "the entry is gone and the default answered".
    const auto ChosenProvider = Get_NonDefaultProvider();
    const auto ChosenShadowMode = Get_NonDefaultShadowMode();

    ck::nav_surface::Set_ProviderForWorld(WorldA._World, ChosenProvider);
    ck::nav_surface::Set_ProviderForWorld(WorldB._World, ChosenProvider);

    ck::nav_surface::Set_ShadowModeForWorld(WorldA._World, ChosenShadowMode);
    ck::nav_surface::Set_ShadowModeForWorld(WorldB._World, ChosenShadowMode);

    const auto RevisionOfBBefore = Get_WorldRevision(WorldB._World);

    if (NOT TestTrue(TEXT("world B's state is established before world A is cleaned up"),
        world_fields::Get_FieldCount(WorldB._World) == 1 &&
        ck::nav_surface::Get_ProviderForWorld(WorldB._World) == ChosenProvider &&
        ck::nav_surface::Get_ShadowModeForWorld(WorldB._World) == ChosenShadowMode))
    {
        Destroy_Fixture(WorldA);
        Destroy_Fixture(WorldB);
        return false;
    }

    // DestroyWorld reaches FWorldDelegates::OnWorldCleanup through CleanupWorld, and unroots world A
    // WITHOUT marking it garbage - so every read of world A below passes the validity guards and is
    // answered by the maps themselves.
    auto* DestroyedWorldA = WorldA._World;
    Destroy_Fixture(WorldA);

    TestEqual(TEXT("world B still holds exactly its own one field after world A was cleaned up"),
        world_fields::Get_FieldCount(WorldB._World), 1);

    const auto FieldsOfB = world_fields::Get_Fields(WorldB._World);

    if (TestTrue(TEXT("world B's field list still has its one entry"), FieldsOfB.Num() == 1))
    {
        TestTrue(TEXT("and that entry is still world B's own field pointer"), FieldsOfB[0] == FieldB);
    }

    TestEqual(TEXT("world B's revision is unmoved by world A's cleanup"),
        Get_WorldRevision(WorldB._World), RevisionOfBBefore);

    TestTrue(TEXT("world B still reads back the provider it was set to"),
        ck::nav_surface::Get_ProviderForWorld(WorldB._World) == ChosenProvider);

    TestTrue(TEXT("world B still reads back the shadow mode it was set to"),
        ck::nav_surface::Get_ShadowModeForWorld(WorldB._World) == ChosenShadowMode);

    TestEqual(TEXT("world A holds no fields after its cleanup"),
        world_fields::Get_FieldCount(DestroyedWorldA), 0);

    TestEqual(TEXT("world A lists no volume entities after its cleanup"),
        world_fields::Get_VolumeEntities(DestroyedWorldA).Num(), 0);

    TestEqual(TEXT("so world A's revision folds nothing and reads zero"),
        Get_WorldRevision(DestroyedWorldA), int64{0});

    TestTrue(TEXT("world A falls back to the default provider after its cleanup"),
        ck::nav_surface::Get_ProviderForWorld(DestroyedWorldA) ==
            ck::nav_surface::Get_DefaultProvider());

    TestTrue(TEXT("world A falls back to the default shadow mode after its cleanup"),
        ck::nav_surface::Get_ShadowModeForWorld(DestroyedWorldA) ==
            ck::nav_surface::Get_DefaultShadowMode());

    Destroy_Fixture(WorldB);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_MultiWorld_TeardownOfAVolumeLeavesTheWorldTermInPlace,
    "CkTests.UnitTests.CkGroundNav.MultiWorld.TeardownOfAVolumeLeavesTheWorldTermInPlace",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_MultiWorld_TeardownOfAVolumeLeavesTheWorldTermInPlace::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_multiworld;

    // The deliberate asymmetry between the two ways a term leaves the fold. A WORLD's cleanup drops its
    // whole list (the test above); a volume's teardown drops its entry only once it reaches the end-play
    // unpublish, which this drive stops short of - so the term is still here, and the revision cannot
    // fall for a teardown that published nothing.
    auto WorldA = Make_Fixture(TEXT("CkGroundNavMultiWorldVolumeTeardownA"), kWorldAOriginUu);

    if (NOT TestTrue(TEXT("world A composes a volume to publish through"), Get_IsReady(WorldA)))
    {
        Destroy_Fixture(WorldA);
        return false;
    }

    const auto FieldA = Bake_Field(kWorldAOriginUu, FCk_GroundNav_Epoch{1});

    if (NOT TestTrue(TEXT("world A's field bakes"), FieldA.IsValid()))
    {
        Destroy_Fixture(WorldA);
        return false;
    }

    world_fields::Publish(WorldA._World, WorldA._Volume, FieldA);

    const auto RevisionOfABefore = Get_WorldRevision(WorldA._World);

    if (NOT TestEqual(TEXT("world A holds its volume's field before the teardown"),
        world_fields::Get_FieldCount(WorldA._World), 1))
    {
        Destroy_Fixture(WorldA);
        return false;
    }

    const auto TornDownVolumeEntity = WorldA._Volume.ConvertToHandle();

    DoTearDown_Volume(WorldA._Volume);

    TestTrue(TEXT("world A's registry still lists the torn-down volume"),
        world_fields::Get_VolumeEntities(WorldA._World).Contains(TornDownVolumeEntity));

    TestEqual(TEXT("world A still counts the torn-down volume's field"),
        world_fields::Get_FieldCount(WorldA._World), 1);

    const auto FieldsOfA = world_fields::Get_Fields(WorldA._World);

    if (TestTrue(TEXT("world A's field list still has its one entry"), FieldsOfA.Num() == 1))
    {
        TestTrue(TEXT("and that entry is still the torn-down volume's field pointer"),
            FieldsOfA[0] == FieldA);
    }

    TestEqual(TEXT("so world A's revision does not move at all: a teardown publishes nothing"),
        Get_WorldRevision(WorldA._World), RevisionOfABefore);

    Destroy_Fixture(WorldA);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

// The half the teardown test above deliberately leaves out. That one drives only the two cancel
// processors, so its volume never reaches the end-play unpublish and the registry keeps listing it.
// Here the whole chain runs, and the volume LEAVES the fold: one that stayed would keep answering its
// world's queries through the last field it published, for the life of the world, with nothing alive
// standing behind that ground.

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_MultiWorld_DestroyedVolumeLeavesTheRegistry,
    "CkTests.UnitTests.CkGroundNav.MultiWorld.DestroyedVolumeLeavesTheRegistry",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_MultiWorld_DestroyedVolumeLeavesTheRegistry::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_multiworld;

    auto WorldA = Make_Fixture(TEXT("CkGroundNavMultiWorldVolumeUnpublishA"), kWorldAOriginUu);

    if (NOT TestTrue(TEXT("world A composes a volume to publish through"), Get_IsReady(WorldA)))
    {
        Destroy_Fixture(WorldA);
        return false;
    }

    const auto FieldA = Bake_Field(kWorldAOriginUu, FCk_GroundNav_Epoch{1});

    if (NOT TestTrue(TEXT("world A's field bakes"), FieldA.IsValid()))
    {
        Destroy_Fixture(WorldA);
        return false;
    }

    world_fields::Publish(WorldA._World, WorldA._Volume, FieldA);

    const auto PointInA = Make_PointInside(kWorldAOriginUu);

    if (NOT TestEqual(TEXT("world A holds its volume's field before the destruction"),
        world_fields::Get_FieldCount(WorldA._World), 1))
    {
        Destroy_Fixture(WorldA);
        return false;
    }

    TestTrue(TEXT("and resolves a point inside that field's ground to it"),
        world_fields::TryGet_Field(WorldA._World, PointInA) == FieldA);

    DoDestroy_Volume(WorldA);

    if (NOT TestTrue(TEXT("the volume is really retired, not merely stamped for destruction"),
        ck::Is_NOT_Valid(WorldA._Volume)))
    {
        Destroy_Fixture(WorldA);
        return false;
    }

    TestEqual(TEXT("world A holds no field once the volume that published it is destroyed"),
        world_fields::Get_FieldCount(WorldA._World), 0);

    // Not a fallback to some other field either: TryGet_Field answers with the world's FIRST registered
    // one when no bounds contain the point, and there is no longer a first.
    TestFalse(TEXT("so a point the destroyed volume's field covered resolves to nothing at all"),
        world_fields::TryGet_Field(WorldA._World, PointInA).IsValid());

    TestEqual(TEXT("and world A lists no volume entities"),
        world_fields::Get_VolumeEntities(WorldA._World).Num(), 0);

    Destroy_Fixture(WorldA);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------
