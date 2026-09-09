#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "CkCore/Time/CkTime.h"
#include "CkCore/Validation/CkIsValid.h"

#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/Subsystem/CkEcsWorld_Subsystem.h"

#include "CkGroundNav/Facade/CkGroundNav_WorldFieldRegistry.h"
#include "CkGroundNav/Volume/CkGroundNavVolume_Processor.h"
#include "CkGroundNav/Volume/CkGroundNavVolume_Utils.h"

#include "CkShapes/Capsule/CkShapeCapsule_Fragment_Data.h"

#include "../CkUnitTest_Common.h"

#include <Engine/World.h>
#include <Misc/ScopeExit.h>

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_groundnav_buildinvoker_integration
{
    constexpr auto kInformEngineOfWorld = false;
    constexpr auto kStreamingVolumeId = int32{7011};

    auto Make_Params() -> FCk_Fragment_GroundNavVolume_ParamsData
    {
        auto Config = FCk_GroundNav_BakeConfig{25.0f, 10.0f};
        Config.Set_TileSizeUu(400.0f);
        auto Profile = FCk_GroundNav_AgentProfile{
            FCk_AnyShape{FCk_ShapeCapsule_Dimensions{70.0f, 20.0f}}};
        auto Params = FCk_Fragment_GroundNavVolume_ParamsData{
            FBox{FVector{0.0, 0.0, -50.0}, FVector{800.0, 800.0, 300.0}}, Config, Profile};
        Params.Set_AutoBuildOnSetup(ECk_EnableDisable::Enable);
        Params.Set_StreamingVolumeId(kStreamingVolumeId);
        Params.Set_StreamingBuildScope(ECk_GroundNav_StreamingBuildScope::InvokerDriven);
        return Params;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_BuildInvokerIntegration_SetupPublishesOnlyCanonicalEmptyLattice,
    "CkTests.UnitTests.CkGroundNav.BuildInvokerIntegration.SetupPublishesOnlyCanonicalEmptyLattice",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_GroundNav_BuildInvokerIntegration_SetupPublishesOnlyCanonicalEmptyLattice::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_buildinvoker_integration;

    auto* World = UWorld::CreateWorld(EWorldType::Game, kInformEngineOfWorld,
        FName{TEXT("CkGroundNavBuildInvokerCanonicalEmpty")});
    if (NOT TestNotNull(TEXT("the runtime world exists"), World))
    { return false; }
    ON_SCOPE_EXIT { World->DestroyWorld(kInformEngineOfWorld); };

    const auto WorldEntity = UCk_Utils_EcsWorld_Subsystem_UE::Get_TransientEntity(World);
    auto Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(WorldEntity);
    auto Volume = UCk_Utils_GroundNavVolume_UE::Add(Owner, Make_Params());
    if (NOT TestTrue(TEXT("the streaming volume is created"), ck::IsValid(Volume)))
    { return false; }

    ck::FProcessor_GroundNavVolume_Setup{WorldEntity.Get_RegistryView()}.ForEachEntity(
        FCk_Time{}, Volume, Volume.Get<ck::FFragment_GroundNavVolume_Params>(),
        Volume.Get<ck::FFragment_GroundNavVolume_BuiltField>());

    const auto VolumeId = ck::groundnav::FCk_GroundNav_VolumeId{kStreamingVolumeId};
    const auto Snapshot = ck::groundnav::world_fields::TryGet_StreamOwnerSnapshot(World, VolumeId);
    if (NOT TestTrue(TEXT("setup registers the canonical streaming owner"), Snapshot.IsSet()))
    { return false; }

    const auto& Built = Volume.Get<ck::FFragment_GroundNavVolume_BuiltField>();
    TestTrue(TEXT("setup retains the canonical producer lattice"), Built.Get_Field().IsValid());
    const auto& InvokerState = Volume.Get<ck::FFragment_GroundNavVolume_InvokerState>();
    TestTrue(TEXT("setup creates the opaque source lifecycle state"), InvokerState.Get_Source().Get_IsValid());
    TestEqual(TEXT("the query-enabled mask starts empty independently of producer retention"),
        InvokerState.Get_EnabledTileIndices().Num(), 0);
    TestFalse(TEXT("setup does not arm an eager whole-volume build"),
        Volume.Has<ck::FTag_GroundNavVolume_NeedsBuild>());
    TestEqual(TEXT("the producer has no built tiles before an invoker selects one"),
        Built.Get_Field()->Get_BuiltTileCount(), 0);
    TestEqual(TEXT("the query snapshot has no built tiles before an invoker selects one"),
        Snapshot->_DefaultField->Get_BuiltTileCount(), 0);
    TestTrue(TEXT("producer and query snapshot share the registration epoch"),
        Built.Get_Field()->_Epoch == Snapshot->_DefaultField->_Epoch);

    ck::FProcessor_GroundNavVolume_Unpublish::ForEachEntity(
        FCk_Time{}, Volume, Volume.Get<ck::FFragment_GroundNavVolume_Params>(),
        Volume.Get<ck::FFragment_GroundNavVolume_BuiltField>());
    TestFalse(TEXT("teardown removes the canonical owner"),
        ck::groundnav::world_fields::TryGet_StreamOwnerSnapshot(World, VolumeId).IsSet());
    return true;
}

#endif
