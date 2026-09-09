// Selector overrides on real GroundNav volume build requests.
//
// This reaches the production request queue and HandleRequests processor against a runtime UWorld.
// It deliberately stops before StartBuild: that processor obtains the live Jolt static-world backend,
// which a bounded unit fixture must not manufacture. The assertions here are the admission and
// supersession boundary before geometry work begins.

#include "CkCore/Time/CkTime.h"
#include "CkCore/Validation/CkIsValid.h"

#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/Request/CkRequest_Completion.h"
#include "CkEcs/Subsystem/CkEcsWorld_Subsystem.h"

#include "CkGroundNav/Bake/CkGroundNav_DataLayerSelector.h"
#include "CkGroundNav/Volume/CkGroundNavVolume_Processor.h"
#include "CkGroundNav/Volume/CkGroundNavVolume_Utils.h"

#include "CkShapes/Capsule/CkShapeCapsule_Fragment_Data.h"

#include "../CkTest_CompletionListener.h"
#include "../CkUnitTest_Common.h"

#include <Engine/World.h>
#include <UObject/StrongObjectPtr.h>

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_groundnav_buildrequestselector
{
    constexpr auto kInformEngineOfWorld = false;

    auto Make_Selector(TConstArrayView<FName> InNames) -> ck::groundnav::FCk_GroundNav_DataLayerSelector
    {
        auto Selector = ck::groundnav::FCk_GroundNav_DataLayerSelector{};
        ck::groundnav::TryMake_DataLayerSelector(InNames, Selector);
        return Selector;
    }

    auto Make_Params() -> FCk_Fragment_GroundNavVolume_ParamsData
    {
        auto Config = FCk_GroundNav_BakeConfig{25.0f, 10.0f};
        Config.Set_TileSizeUu(400.0f);
        const auto Profile = FCk_GroundNav_AgentProfile{
            FCk_AnyShape{FCk_ShapeCapsule_Dimensions{70.0f, 20.0f}}};
        auto Params = FCk_Fragment_GroundNavVolume_ParamsData{
            FBox{FVector{0.0, 0.0, -50.0}, FVector{800.0, 800.0, 300.0}}, Config, Profile};
        Params.Set_AutoBuildOnSetup(ECk_EnableDisable::Disable);
        Params.Set_DataLayerSelector(Make_Selector(TArray<FName>{FName{TEXT("Gameplay")}}));
        return Params;
    }

    auto Make_Listener() -> TStrongObjectPtr<UCk_Test_CompletionListener_UE>
    {
        return TStrongObjectPtr<UCk_Test_CompletionListener_UE>{
            NewObject<UCk_Test_CompletionListener_UE>(GetTransientPackage())};
    }

    auto Make_Delegate(UCk_Test_CompletionListener_UE* InListener) -> FCk_Delegate_Request_OnCompleted
    {
        auto Delegate = FCk_Delegate_Request_OnCompleted{};
        Delegate.BindDynamic(InListener, &UCk_Test_CompletionListener_UE::OnRequestCompleted);
        return Delegate;
    }

    auto Drain_BuildRequests(
        const FCk_Handle&           InWorldEntity,
        FCk_Handle_GroundNavVolume& InVolume) -> void
    {
        ck::FProcessor_GroundNavVolume_HandleRequests{InWorldEntity.Get_RegistryView()}.ForEachEntity(
            FCk_Time{1.0f / 60.0f}, InVolume,
            InVolume.Get<ck::FFragment_GroundNavVolume_Params>(),
            InVolume.Get<ck::FFragment_GroundNavVolume_BuiltField>(),
            InVolume.Get<ck::FFragment_GroundNavVolume_BuildState>(),
            InVolume.Get<ck::FFragment_GroundNavVolume_RepairState>(),
            InVolume.Get<ck::FFragment_GroundNavVolume_Requests>());
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_BuildRequestSelector_EmptyOverrideSupersedesPendingSelector,
    "CkTests.UnitTests.CkGroundNav.BuildRequestSelector.EmptyOverrideSupersedesPendingSelector",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_BuildRequestSelector_EmptyOverrideSupersedesPendingSelector::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_buildrequestselector;

    auto* World = UWorld::CreateWorld(EWorldType::Game, kInformEngineOfWorld,
        FName{TEXT("CkGroundNavBuildRequestSelector")});
    if (NOT TestNotNull(TEXT("the runtime world exists"), World))
    { return false; }
    ON_SCOPE_EXIT { World->DestroyWorld(kInformEngineOfWorld); };

    const auto WorldEntity = UCk_Utils_EcsWorld_Subsystem_UE::Get_TransientEntity(World);
    auto Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(WorldEntity);
    auto Volume = UCk_Utils_GroundNavVolume_UE::Add(Owner, Make_Params());

    if (NOT TestTrue(TEXT("the volume is composed"), ck::IsValid(Volume)))
    { return false; }

    // Setup is production state too: HandleRequests excludes a not-yet-setup volume in the scheduler.
    ck::FProcessor_GroundNavVolume_Setup{WorldEntity.Get_RegistryView()}.ForEachEntity(
        FCk_Time{1.0f / 60.0f}, Volume,
        Volume.Get<ck::FFragment_GroundNavVolume_Params>(),
        Volume.Get<ck::FFragment_GroundNavVolume_BuiltField>());

    if (NOT TestFalse(TEXT("setup did not arm an automatic build"),
        Volume.Has<ck::FTag_GroundNavVolume_NeedsBuild>()))
    { return false; }

    // Enabled override with an empty canonical selector means all layers; it must not silently inherit
    // the non-empty authored Gameplay selector.
    auto EmptyOverride = FCk_Request_GroundNavVolume_Build{};
    EmptyOverride.Set_OverrideDataLayerSelector(ECk_EnableDisable::Enable);
    const auto FirstListener = Make_Listener();
    UCk_Utils_GroundNavVolume_UE::Request_Build(Volume, EmptyOverride, Make_Delegate(FirstListener.Get()));
    Drain_BuildRequests(WorldEntity, Volume);

    TestTrue(TEXT("the explicit empty override arms production build state"),
        Volume.Has<ck::FTag_GroundNavVolume_NeedsBuild>());
    TestEqual(TEXT("the first request remains pending until a build publishes"),
        FirstListener->_TimesRequestCompleted, 0);

    // A changed selector is a different geometry identity, so it supersedes pending work even without
    // ForceRestart. The first caller hears cancellation instead of waiting on work that no longer holds.
    auto ChangedSelectorRequest = FCk_Request_GroundNavVolume_Build{};
    ChangedSelectorRequest.Set_OverrideDataLayerSelector(ECk_EnableDisable::Enable);
    ChangedSelectorRequest.Set_DataLayerSelector(Make_Selector(TArray<FName>{FName{TEXT("Props")}}));
    const auto SecondListener = Make_Listener();
    UCk_Utils_GroundNavVolume_UE::Request_Build(
        Volume, ChangedSelectorRequest, Make_Delegate(SecondListener.Get()));
    Drain_BuildRequests(WorldEntity, Volume);

    TestEqual(TEXT("the superseded selector request completes once"),
        FirstListener->_TimesRequestCompleted, 1);
    TestTrue(TEXT("the superseded selector request is cancelled"),
        FirstListener->_LastRequestResult == ECk_Request_OperationResult::Failed_Cancelled);
    TestEqual(TEXT("the replacement selector request remains pending"),
        SecondListener->_TimesRequestCompleted, 0);
    TestTrue(TEXT("the replacement selector keeps the volume armed"),
        Volume.Has<ck::FTag_GroundNavVolume_NeedsBuild>());
    TestEqual(TEXT("the production request queue was consumed"),
        Volume.Get<ck::FFragment_GroundNavVolume_Requests>().Get_Requests().Num(), 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
