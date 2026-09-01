// Composing the ground-nav volume feature onto an entity.
//
// Scope note, stated rather than implied: this is the COMPOSITION contract only — what Add puts on the
// entity, what the accessors report before anything has baked, and that a request lands on the queue.
// Driving a build to completion needs a physics world for the geometry backend and the real processor
// graph to tick it, neither of which a headless registry has; that verification is owed elsewhere.

#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/World/CkEcsWorld.h"

#include "CkGroundNav/Volume/CkGroundNavVolume_Utils.h"

#include "CkShapes/Capsule/CkShapeCapsule_Fragment_Data.h"

#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_groundnav_volume
{
    auto Make_Params() -> FCk_Fragment_GroundNavVolume_ParamsData
    {
        auto Config = FCk_GroundNav_BakeConfig{25.0f, 10.0f};
        Config.Set_TileSizeUu(400.0f);

        const auto Profile = FCk_GroundNav_AgentProfile{
            FCk_AnyShape{FCk_ShapeCapsule_Dimensions{70.0f, 20.0f}}};

        const auto Bounds = FBox{FVector{0.0, 0.0, -50.0}, FVector{800.0, 800.0, 300.0}};

        return FCk_Fragment_GroundNavVolume_ParamsData{Bounds, Config, Profile};
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Volume_AddComposesTheFeature,
    "CkTests.UnitTests.CkGroundNav.Bake.Volume_AddComposesTheFeature",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Volume_AddComposesTheFeature::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_volume;

    auto World = ck::FEcsWorld{};

    auto Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());

    TestFalse(TEXT("an owner has no volume feature before it is added"),
        UCk_Utils_GroundNavVolume_UE::Has(Owner));

    auto Volume = UCk_Utils_GroundNavVolume_UE::Add(Owner, Make_Params());

    if (NOT TestTrue(TEXT("adding the feature yields a valid volume handle"), ck::IsValid(Volume)))
    { return false; }

    TestTrue(TEXT("and the volume carries the feature"), UCk_Utils_GroundNavVolume_UE::Has(Volume));

    // The volume is a CHILD entity, not the owner. Composing onto the owner itself would mean an entity
    // could only ever host one, and would put a bake on whatever else that entity is.
    TestFalse(TEXT("while the owner itself does not"), UCk_Utils_GroundNavVolume_UE::Has(Owner));

    TestTrue(TEXT("it is armed for setup"), Volume.Has<ck::FTag_GroundNavVolume_NeedsSetup>());
    TestTrue(TEXT("with a build state"), Volume.Has<ck::FFragment_GroundNavVolume_BuildState>());
    TestTrue(TEXT("and a slot for the field it will publish"),
        Volume.Has<ck::FFragment_GroundNavVolume_BuiltField>());

    // Nothing has baked, and the accessors say exactly that rather than reporting an empty field as a
    // built one — the distinction the whole status vocabulary exists for.
    TestFalse(TEXT("nothing is built yet"), UCk_Utils_GroundNavVolume_UE::Get_IsBuilt(Volume));
    TestFalse(TEXT("and nothing is building yet"), UCk_Utils_GroundNavVolume_UE::Get_IsBuilding(Volume));

    TestEqual(TEXT("the epoch starts at zero"), UCk_Utils_GroundNavVolume_UE::Get_BuildEpoch(Volume),
        static_cast<int64>(0));

    TestFalse(TEXT("and there is no field to read"),
        UCk_Utils_GroundNavVolume_UE::Get_Field(Volume).IsValid());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Volume_RequestBuildEnqueues,
    "CkTests.UnitTests.CkGroundNav.Bake.Volume_RequestBuildEnqueues",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Volume_RequestBuildEnqueues::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_volume;

    auto World = ck::FEcsWorld{};

    auto Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());
    auto Volume = UCk_Utils_GroundNavVolume_UE::Add(Owner, Make_Params());

    if (NOT TestTrue(TEXT("the volume composes"), ck::IsValid(Volume)))
    { return false; }

    TestFalse(TEXT("no requests are queued before one is made"),
        Volume.Has<ck::FFragment_GroundNavVolume_Requests>());

    UCk_Utils_GroundNavVolume_UE::Request_Build(Volume, FCk_Request_GroundNavVolume_Build{}, {});

    if (NOT TestTrue(TEXT("requesting a build creates the queue"),
        Volume.Has<ck::FFragment_GroundNavVolume_Requests>()))
    { return false; }

    TestEqual(TEXT("with the request on it"),
        Volume.Get<ck::FFragment_GroundNavVolume_Requests>().Get_Requests().Num(), 1);

    // Deferred, not immediate: the mutation belongs to a processor, and the request is how it gets
    // there. A util that baked inline would run a multi-tick job inside whatever called it.
    TestFalse(TEXT("and nothing has been built by the call itself"),
        UCk_Utils_GroundNavVolume_UE::Get_IsBuilt(Volume));

    UCk_Utils_GroundNavVolume_UE::Request_Build(Volume, FCk_Request_GroundNavVolume_Build{}, {});

    TestEqual(TEXT("a second request queues behind the first rather than replacing it"),
        Volume.Get<ck::FFragment_GroundNavVolume_Requests>().Get_Requests().Num(), 2);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
