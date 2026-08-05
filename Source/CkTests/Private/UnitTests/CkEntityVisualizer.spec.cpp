#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "CkEntityVisualizer/CkEntityVisualizer_Fragment.h"
#include "CkEntityVisualizer/Settings/CkEntityVisualizer_Settings.h"
#include "CkEntityVisualizer/CkEntityVisualizer_Utils.h"

#include "CkCore/Validation/CkIsValid.h"
#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/World/CkEcsWorld.h"
#include "CkEcsExt/SceneNode/CkSceneNode_Utils.h"
#include "CkEcsExt/Transform/CkTransform_Utils.h"
#include "CkPmg/CkPmg_Fragment.h"
#include "CkIsmRenderer/Proxy/CkIsmProxy_Fragment.h"
#include "CkIsmRenderer/Proxy/CkIsmProxy_Processor.h"

#include "CkTests/Net/CkNetAutomation_Common.h"

#include <type_traits>
#include <HAL/IConsoleManager.h>

namespace ck_tests_entity_visualizer
{
    constexpr auto kTestFlags =
        EAutomationTestFlags::EditorContext |
        EAutomationTestFlags::EngineFilter;
    constexpr int32 kHighCountIsmSourceCount = 1024;

    auto CountVisuals(FCk_Registry& InRegistry) -> int32
    {
        auto Result = int32{0};
        InRegistry.View<ck::FTag_EntityVisualizer_Visual>().ForEach(
            [&Result](const FCk_Entity /*InEntity*/)
            {
                ++Result;
            });
        return Result;
    }

    auto HasExpectedAttachment(
        const FCk_Handle& InVisual,
        const FCk_Handle_Transform& InSource) -> bool
    {
        if (NOT InVisual.Has<ck::FTag_EntityVisualizer_Visual>() ||
            NOT UCk_Utils_SceneNode_UE::Has(InVisual))
        { return false; }

        const auto Node = UCk_Utils_SceneNode_UE::CastChecked(InVisual);
        const auto Parent = UCk_Utils_SceneNode_UE::Get_Parent(Node);
        return ck::IsValid(Parent) &&
            Parent.ConvertToHandle().Get_Entity() == InSource.ConvertToHandle().Get_Entity();
    }
}

static_assert(std::is_same_v<
    ck::FProcessor_IsmProxy_TransformInstance::MainPassRequiredFragments,
    entt::type_list<ck::FTag_Transform_Updated>>);

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkEntityVisualizer_VisibilityPolicy,
    "Ck.EntityVisualizer.Visibility.Policy",
    ck_tests_entity_visualizer::kTestFlags)

bool FCkEntityVisualizer_VisibilityPolicy::RunTest(const FString& Parameters)
{
    using enum ECk_EntityVisualizer_VisibilityMode;

    TestFalse(TEXT("Disabled hides an unselected owned entity"),
        ck::entity_visualizer::ShouldVisualize(Disabled, true, false));
    TestFalse(TEXT("Disabled hides a selected owned entity"),
        ck::entity_visualizer::ShouldVisualize(Disabled, true, true));
    TestFalse(TEXT("Disabled hides an ownerless entity"),
        ck::entity_visualizer::ShouldVisualize(Disabled, false, false));

    TestFalse(TEXT("Selected Only hides an unselected owned entity"),
        ck::entity_visualizer::ShouldVisualize(SelectedOnly, true, false));
    TestTrue(TEXT("Selected Only shows a selected owned entity"),
        ck::entity_visualizer::ShouldVisualize(SelectedOnly, true, true));
    TestFalse(TEXT("Selected Only hides an ownerless entity"),
        ck::entity_visualizer::ShouldVisualize(SelectedOnly, false, false));

    TestTrue(TEXT("All shows an unselected owned entity"),
        ck::entity_visualizer::ShouldVisualize(All, true, false));
    TestTrue(TEXT("All shows a selected owned entity"),
        ck::entity_visualizer::ShouldVisualize(All, true, true));
    TestTrue(TEXT("All shows an ownerless entity"),
        ck::entity_visualizer::ShouldVisualize(All, false, false));

    TestFalse(TEXT("Invalid visibility modes fail closed"),
        ck::entity_visualizer::ShouldVisualize(
            static_cast<ECk_EntityVisualizer_VisibilityMode>(255), true, true));

    const auto* ModeCVar = IConsoleManager::Get().FindConsoleVariable(
        TEXT("ck.EntityVisualizer.VisibilityMode"));
    const auto* Settings = GetDefault<UCk_EntityVisualizer_UserSettings_UE>();
    TestNotNull(TEXT("Visibility mode CVar is registered"), ModeCVar);
    TestNotNull(TEXT("Entity Visualizer per-user settings are registered"), Settings);
    if (ModeCVar != nullptr && Settings != nullptr)
    {
        TestEqual(TEXT("CVar and per-user setting are synchronized"),
            ModeCVar->GetInt(), static_cast<int32>(Settings->Get_VisibilityMode()));
    }

    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkEntityVisualizer_PmgTransformGizmo_ComposesRetainedChildren,
    "Ck.EntityVisualizer.TransformGizmo.PmgComposesRetainedChildren",
    ck_tests_entity_visualizer::kTestFlags)

bool FCkEntityVisualizer_PmgTransformGizmo_ComposesRetainedChildren::RunTest(const FString& Parameters)
{
    auto EcsWorld = ck::FEcsWorld{};
    auto& Registry = EcsWorld.Get_Registry();
    auto Root = FCk_Handle{Registry.Get_TransientEntity(), Registry.Get_RegistryHandle()};
    auto Source = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Root, {});
    auto SourceTransform = UCk_Utils_Transform_UE::Add(
        Source, FTransform::Identity, ECk_Replication::DoesNotReplicate);

    const auto Visuals = UCk_Utils_EntityVisualizer_UE::Create_TransformGizmo_Pmg(SourceTransform);

    TestEqual(TEXT("PMG gizmo creates one retained arrow per axis"), Visuals.Num(), 3);
    TestEqual(TEXT("all PMG gizmo children are visualizer-owned"),
        ck_tests_entity_visualizer::CountVisuals(Registry), 3);

    for (const auto& Visual : Visuals)
    {
        const auto Handle = Visual.ConvertToHandle();
        TestTrue(TEXT("PMG gizmo child is valid"), ck::IsValid(Visual));
        TestTrue(TEXT("PMG gizmo child has persistent-duration exclusion"),
            Handle.Has<ck::FTag_Pmg_DebugShape_PersistentDuration>());
        TestTrue(TEXT("PMG gizmo child is tagged and SceneNode-attached to its source"),
            ck_tests_entity_visualizer::HasExpectedAttachment(Handle, SourceTransform));
    }

    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkEntityVisualizer_TransformGizmo_InvalidDimensionsFailWithoutChildren,
    "Ck.EntityVisualizer.TransformGizmo.InvalidDimensionsFailWithoutChildren",
    ck_tests_entity_visualizer::kTestFlags)

bool FCkEntityVisualizer_TransformGizmo_InvalidDimensionsFailWithoutChildren::RunTest(const FString& Parameters)
{
    auto EcsWorld = ck::FEcsWorld{};
    auto& Registry = EcsWorld.Get_Registry();
    auto Root = FCk_Handle{Registry.Get_TransientEntity(), Registry.Get_RegistryHandle()};
    auto Source = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Root, {});
    auto SourceTransform = UCk_Utils_Transform_UE::Add(
        Source, FTransform::Identity, ECk_Replication::DoesNotReplicate);

    auto InvalidParams = FCk_EntityVisualizer_TransformGizmoParams{};
    InvalidParams.Set_AxisLength(10.0f);
    InvalidParams.Set_ArrowHeadLength(11.0f);

    AddExpectedError(
        TEXT("Unable to create an ISM transform gizmo with invalid dimensions"),
        EAutomationExpectedErrorFlags::Contains, /*Occurrences=*/-1);
    const auto IsmVisuals = UCk_Utils_EntityVisualizer_UE::Create_TransformGizmo_Ism(
        SourceTransform, InvalidParams);

    AddExpectedError(
        TEXT("Unable to create a PMG transform gizmo with invalid dimensions"),
        EAutomationExpectedErrorFlags::Contains, /*Occurrences=*/-1);
    const auto PmgVisuals = UCk_Utils_EntityVisualizer_UE::Create_TransformGizmo_Pmg(
        SourceTransform, InvalidParams);

    TestTrue(TEXT("invalid ISM dimensions produce no child handles"), IsmVisuals.IsEmpty());
    TestTrue(TEXT("invalid PMG dimensions produce no child handles"), PmgVisuals.IsEmpty());
    TestEqual(TEXT("invalid dimensions create no partial visual children"),
        ck_tests_entity_visualizer::CountVisuals(Registry), 0);
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkEntityVisualizer_IsmTransformGizmo_ComposesRetainedChildren,
    "Ck.EntityVisualizer.TransformGizmo.IsmComposesRetainedChildren",
    ck_tests_entity_visualizer::kTestFlags)

bool FCkEntityVisualizer_IsmTransformGizmo_ComposesRetainedChildren::RunTest(const FString& Parameters)
{
    auto CreatedCount = MakeShared<int32>(0);
    auto AllChildrenAttached = MakeShared<bool>(false);

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(1, TEXT("/Engine/Maps/Entry")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(1, 30.0f));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda(
            [CreatedCount, AllChildrenAttached](UWorld* InWorld) -> void
            {
                auto Source = UCk_Utils_EntityLifetime_UE::Request_CreateEntity_TransientOwner(InWorld);
                auto SourceTransform = UCk_Utils_Transform_UE::Add(
                    Source, FTransform::Identity, ECk_Replication::DoesNotReplicate);
                const auto Visuals = UCk_Utils_EntityVisualizer_UE::Create_TransformGizmo_Ism(SourceTransform);

                *CreatedCount = Visuals.Num();
                *AllChildrenAttached = Visuals.Num() == 6;
                for (const auto& Visual : Visuals)
                {
                    *AllChildrenAttached = *AllChildrenAttached &&
                        ck_tests_entity_visualizer::HasExpectedAttachment(
                            Visual.ConvertToHandle(), SourceTransform);
                }
            })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda(
            [this, CreatedCount, AllChildrenAttached]() -> bool
            {
                TestEqual(TEXT("ISM gizmo creates a shaft and arrowhead for each axis"), *CreatedCount, 6);
                TestTrue(TEXT("ISM gizmo children are visualizer-tagged and SceneNode-attached"),
                    *AllChildrenAttached);
                return true;
            }),
        TEXT("ISM gizmo creates retained children")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkEntityVisualizer_IsmTransformGizmo_ThousandSourcesShareTwoBatches,
    "Ck.EntityVisualizer.TransformGizmo.IsmThousandSourcesShareTwoBatches",
    ck_tests_entity_visualizer::kTestFlags)

bool FCkEntityVisualizer_IsmTransformGizmo_ThousandSourcesShareTwoBatches::RunTest(const FString& Parameters)
{
    auto CreatedCount = MakeShared<int32>(0);
    auto UniqueRendererCount = MakeShared<int32>(0);
    auto AllChildrenAttached = MakeShared<bool>(true);

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(1, TEXT("/Engine/Maps/Entry")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(1, 30.0f));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda(
            [CreatedCount, UniqueRendererCount, AllChildrenAttached](UWorld* InWorld) -> void
            {
                auto UniqueRenderers = TSet<const UCk_IsmRenderer_Data*>{};
                for (auto SourceIndex = 0;
                    SourceIndex < ck_tests_entity_visualizer::kHighCountIsmSourceCount;
                    ++SourceIndex)
                {
                    auto Source = UCk_Utils_EntityLifetime_UE::Request_CreateEntity_TransientOwner(InWorld);
                    auto SourceTransform = UCk_Utils_Transform_UE::Add(
                        Source,
                        FTransform{FVector{static_cast<double>(SourceIndex) * 100.0, 0.0, 0.0}},
                        ECk_Replication::DoesNotReplicate);
                    const auto Visuals = UCk_Utils_EntityVisualizer_UE::Create_TransformGizmo_Ism(SourceTransform);

                    *CreatedCount += Visuals.Num();
                    *AllChildrenAttached = *AllChildrenAttached && Visuals.Num() == 6;
                    for (const auto& Visual : Visuals)
                    {
                        const auto Handle = Visual.ConvertToHandle();
                        *AllChildrenAttached = *AllChildrenAttached &&
                            ck_tests_entity_visualizer::HasExpectedAttachment(Handle, SourceTransform);
                        UniqueRenderers.Add(
                            Handle.Get<ck::FFragment_IsmProxy_Params>().Get_IsmRenderer().Get());
                    }
                }
                *UniqueRendererCount = UniqueRenderers.Num();
            })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda(
            [this, CreatedCount, UniqueRendererCount, AllChildrenAttached]() -> bool
            {
                TestEqual(TEXT("1024 ISM gizmos create six instances per source"),
                    *CreatedCount, ck_tests_entity_visualizer::kHighCountIsmSourceCount * 6);
                TestEqual(TEXT("all shafts and heads share two world-scoped renderer batches"),
                    *UniqueRendererCount, 2);
                TestTrue(TEXT("all high-count gizmo children stay attached to their source"),
                    *AllChildrenAttached);
                return true;
            }),
        TEXT("ISM gizmos retain two batch keys across 1024 sources")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
    return true;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
