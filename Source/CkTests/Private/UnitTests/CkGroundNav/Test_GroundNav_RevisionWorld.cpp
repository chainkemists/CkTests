// The revision GroundNav reports for a WORLD, and why tearing a volume down cannot make it fall.
//
// Test_GroundNav_Revision owns the epoch arithmetic over a single field. This file asks the question
// one level up, where the number a consumer actually watches is assembled: the provider table's
// _SurfaceRevision folds every field the world-field registry currently holds PLUS the epoch sums of
// the fields it has unpublished. A volume torn down mid-session leaves the registry, and that
// retained sum is the entire reason the number is monotone. A consumer reads any move as "the
// surface changed", so a FALL would announce a rebuild that never happened.
//
// A real UWorld is created for this rather than a bare ck::FEcsWorld, because the registry is keyed by
// world and the revision is reached through the provider table with a UWorld* and nothing else.
//
// The teardown is stamped rather than completed: Request_DestroyEntity adds FTag_DestroyEntity_Initiate
// synchronously and the destruction pipeline that retires the entity is the scheduler's, which a
// headless world does not have. That is the same teardown shape Test_GroundNav_MarkupAdmission drives,
// and it is enough here — the volume's own end-play unpublish is driven alongside the cancel drains,
// standing in the FGroup_EndPlay slot the scheduler would run it in, which is the property under test.

#include "CkCore/Time/CkTime.h"

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

namespace ck_test_groundnav_revision_world
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

    // The two volumes sit far enough apart that neither field's ground reaches the other's lattice, so
    // a revision that folded one field twice could not pass as the sum of two.
    constexpr auto kVolumeSpanUu = 800.0;
    constexpr auto kSecondVolumeOriginUu = 4000.0;

    struct FWorldFixture
    {
        UWorld* _World = nullptr;
        FCk_Handle _WorldEntity;
    };

    auto Make_Fixture(
        const TCHAR* InWorldName) -> FWorldFixture
    {
        auto Fixture = FWorldFixture{};

        Fixture._World = UWorld::CreateWorld(EWorldType::Game, InformEngineOfWorld, FName{InWorldName});

        if (Fixture._World == nullptr)
        { return Fixture; }

        Fixture._WorldEntity = UCk_Utils_EcsWorld_Subsystem_UE::Get_TransientEntity(Fixture._World);

        return Fixture;
    }

    auto Destroy_Fixture(
        FWorldFixture& InFixture) -> void
    {
        if (InFixture._World != nullptr)
        { InFixture._World->DestroyWorld(InformEngineOfWorld); }
    }

    auto Make_Profile() -> FCk_GroundNav_AgentProfile
    {
        // The ledge filter is off: the subject is the revision fold, and the conservative default would
        // trim the fixture's borders for reasons this file has nothing to say about.
        auto Profile = FCk_GroundNav_AgentProfile{
            FCk_AnyShape{FCk_ShapeCapsule_Dimensions{70.0f, 20.0f}}};
        Profile.Set_LedgeSensitivity(0.0f);

        return Profile;
    }

    // 2x2 tiles of 400uu from the given origin.
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

    auto Get_WorldListsVolume(
        UWorld*           InWorld,
        const FCk_Handle& InVolumeEntity) -> bool
    {
        return world_fields::Get_VolumeEntities(InWorld).Contains(InVolumeEntity);
    }

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

        ck::FProcessor_GroundNavVolume_Unpublish::ForEachEntity(
            FCk_Time{kSixtyHertz},
            InVolume,
            InVolume.Get<ck::FFragment_GroundNavVolume_BuiltField>());
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Revision_WorldRevisionDoesNotFallWhenAVolumeIsTornDown,
    "CkTests.UnitTests.CkGroundNav.Revision.WorldRevisionDoesNotFallWhenAVolumeIsTornDown",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Revision_WorldRevisionDoesNotFallWhenAVolumeIsTornDown::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_revision_world;

    auto Fixture = Make_Fixture(TEXT("CkGroundNavRevisionWorldTeardown"));

    if (NOT TestTrue(TEXT("the probe world has an ECS transient entity to hang volumes off"),
        ck::IsValid(Fixture._WorldEntity)))
    {
        Destroy_Fixture(Fixture);
        return false;
    }

    if (NOT TestTrue(TEXT("and GroundNav registered a provider table with a revision entry"),
        Get_WorldRevision(Fixture._World) >= 0))
    {
        Destroy_Fixture(Fixture);
        return false;
    }

    auto FirstOwner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Fixture._WorldEntity);
    auto SecondOwner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Fixture._WorldEntity);

    auto FirstVolume = UCk_Utils_GroundNavVolume_UE::Add(FirstOwner, Make_VolumeParams(0.0));
    auto SecondVolume = UCk_Utils_GroundNavVolume_UE::Add(
        SecondOwner, Make_VolumeParams(kSecondVolumeOriginUu));

    if (NOT TestTrue(TEXT("both volumes compose"),
        ck::IsValid(FirstVolume) && ck::IsValid(SecondVolume)))
    {
        Destroy_Fixture(Fixture);
        return false;
    }

    const auto FirstField = Bake_Field(0.0, FCk_GroundNav_Epoch{1});
    const auto SecondField = Bake_Field(kSecondVolumeOriginUu, FCk_GroundNav_Epoch{1});

    if (NOT TestTrue(TEXT("both fields bake"), FirstField.IsValid() && SecondField.IsValid()))
    {
        Destroy_Fixture(Fixture);
        return false;
    }

    world_fields::Publish(Fixture._World, FirstVolume, FirstField, {});
    world_fields::Publish(Fixture._World, SecondVolume, SecondField, {});

    if (NOT TestEqual(TEXT("the world holds one field per volume"),
        world_fields::Get_FieldCount(Fixture._World), 2))
    {
        Destroy_Fixture(Fixture);
        return false;
    }

    const auto RevisionBefore = Get_WorldRevision(Fixture._World);

    // Exact, not merely positive: the world's number is the fold over BOTH volumes, so a revision that
    // silently answered from whichever field the registry happened to list first would read as sane.
    TestEqual(TEXT("and its revision is the sum of what both volumes published"),
        RevisionBefore,
        FirstField->Get_AggregatedTileEpochSum() + SecondField->Get_AggregatedTileEpochSum());

    DoTearDown_Volume(SecondVolume);

    const auto RevisionAfter = Get_WorldRevision(Fixture._World);

    // The whole contract. A consumer watching this number reads any move as news, so a fall would
    // announce a rebuild that never happened - and could land back on a value it had already seen.
    TestTrue(TEXT("tearing a volume down does not lower the world's revision"),
        RevisionAfter >= RevisionBefore);

    TestEqual(TEXT("it does not move it at all: a teardown publishes nothing"),
        RevisionAfter, RevisionBefore);

    // The mechanism behind that, stated on its own: the torn-down volume is GONE from the registry -
    // its field answers no query on this world any more - and what it had published is carried as
    // retired revision, so the sum reads exactly as it did. Both halves matter: a registry that kept
    // the dead volume would keep answering from its ground, and one that dropped its epochs would
    // hand a consumer a number it had already seen.
    TestFalse(TEXT("because the registry no longer lists the torn-down volume"),
        Get_WorldListsVolume(Fixture._World, SecondVolume.ConvertToHandle()));

    TestEqual(TEXT("and holds only the live volume's field"),
        world_fields::Get_FieldCount(Fixture._World), 1);

    TestEqual(TEXT("with the torn-down field's epochs carried as retired revision"),
        world_fields::Get_RetiredRevision(Fixture._World),
        SecondField->Get_AggregatedTileEpochSum());

    Destroy_Fixture(Fixture);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------
