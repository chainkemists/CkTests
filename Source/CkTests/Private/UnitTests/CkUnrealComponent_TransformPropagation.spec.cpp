#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "CkCore/Validation/CkIsValid.h"
#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcsExt/Transform/CkTransform_Fragment.h"
#include "CkEcsExt/Transform/CkTransform_Utils.h"
#include "CkUnrealComponent/CkUnrealComponent_Fragment.h"
#include "CkUnrealComponent/CkUnrealComponent_Utils.h"

#include "CkTests/Net/CkNetAutomation_Common.h"

#include "Components/SceneComponent.h"

namespace ck_tests_unreal_component_transform
{
    struct FTestState
    {
        FCk_Handle_Transform OwnerTransform;
        FCk_Handle_UnrealComponent ComponentHandle;
        TWeakObjectPtr<USceneComponent> SceneComponent;
        const FTransform DesiredTransform = FTransform{
            FRotator{10.0, 20.0, 30.0},
            FVector{100.0, 200.0, 300.0}};
        const FTransform ExternalDrift = FTransform{
            FRotator{-30.0, 40.0, 5.0},
            FVector{1000.0, -2000.0, 3000.0}};
        const FTransform MovedTransform = FTransform{
            FRotator{25.0, -35.0, 15.0},
            FVector{-400.0, 500.0, 600.0}};
    };
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkUnrealComponent_TransformPropagation_DirtyOwnersOnly,
    "Ck.UnrealComponent.TransformPropagation.DirtyOwnersOnly",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkUnrealComponent_TransformPropagation_DirtyOwnersOnly::RunTest(
    const FString& Parameters)
{
    using namespace ck_tests_unreal_component_transform;

    auto State = MakeShared<FTestState>();

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(1, TEXT("/Engine/Maps/Entry")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(1, 30.0f));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this, State](UWorld* InWorld) -> void
        {
            auto Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity_TransientOwner(InWorld);
            State->OwnerTransform = UCk_Utils_Transform_UE::Add(
                Owner,
                State->DesiredTransform,
                ECk_Replication::DoesNotReplicate);
            State->ComponentHandle = UCk_Utils_UnrealComponent_UE::Add(
                Owner,
                UCk_Utils_UnrealComponent_UE::Make_Params(
                    USceneComponent::StaticClass(),
                    ECk_UnrealComponent_TickPolicy::DoNotTick,
                    TEXT("TransformPropagationTest")));

            if (ck::Is_NOT_Valid(State->OwnerTransform))
            { AddError(TEXT("failed to create transform owner")); }
            if (ck::Is_NOT_Valid(State->ComponentHandle))
            { AddError(TEXT("failed to create UnrealComponent handle")); }
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(5));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this, State](UWorld*) -> void
        {
            if (ck::Is_NOT_Valid(State->ComponentHandle))
            {
                AddError(TEXT("UnrealComponent handle became invalid during setup"));
                return;
            }

            auto* Component = Cast<USceneComponent>(
                UCk_Utils_UnrealComponent_UE::Get_Component(State->ComponentHandle));
            if (ck::Is_NOT_Valid(Component))
            {
                AddError(TEXT("setup did not create a scene component"));
                return;
            }

            State->SceneComponent = Component;
            if (State->OwnerTransform.Has<ck::FTag_Transform_Updated>())
            { State->OwnerTransform.Remove<ck::FTag_Transform_Updated>(); }
            Component->SetWorldTransform(State->ExternalDrift);
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(2));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this, State]() -> bool
        {
            const auto* Component = State->SceneComponent.Get();
            const auto IsValidComponent = ck::IsValid(Component);
            TestTrue(TEXT("scene component remains valid for idle assertion"), IsValidComponent);
            if (NOT IsValidComponent)
            { return true; }

            TestTrue(TEXT("idle owner does not overwrite external component drift"),
                Component->GetComponentTransform().Equals(State->ExternalDrift));
            return true;
        }),
        TEXT("idle transform owner leaves its scene component untouched")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld*) -> void
        {
            UCk_Utils_Transform_UE::Request_SetTransform(
                State->OwnerTransform,
                FCk_Request_Transform_SetTransform{State->MovedTransform},
                {});
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(2));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this, State]() -> bool
        {
            const auto* Component = State->SceneComponent.Get();
            const auto IsValidComponent = ck::IsValid(Component);
            TestTrue(TEXT("scene component remains valid for dirty-owner assertion"), IsValidComponent);
            if (NOT IsValidComponent)
            { return true; }

            const auto EcsTransform =
                UCk_Utils_Transform_UE::Get_EntityCurrentTransform(State->OwnerTransform);
            TestTrue(TEXT("transform request moved the ECS owner"),
                EcsTransform.Equals(State->MovedTransform));
            TestTrue(TEXT("dirty owner pushes its current ECS transform to the scene component"),
                Component->GetComponentTransform().Equals(EcsTransform));
            return true;
        }),
        TEXT("dirty transform owner pushes its scene component")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this, State](UWorld*) -> void
        {
            auto* Component = State->SceneComponent.Get();
            if (ck::Is_NOT_Valid(Component))
            {
                AddError(TEXT("scene component became invalid before second idle assertion"));
                return;
            }

            if (State->OwnerTransform.Has<ck::FTag_Transform_Updated>())
            { State->OwnerTransform.Remove<ck::FTag_Transform_Updated>(); }
            Component->SetWorldTransform(State->ExternalDrift);
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(1));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this, State]() -> bool
        {
            const auto* Component = State->SceneComponent.Get();
            const auto IsValidComponent = ck::IsValid(Component);
            TestTrue(TEXT("scene component remains valid for second idle assertion"), IsValidComponent);
            if (NOT IsValidComponent)
            { return true; }

            TestTrue(TEXT("unchanged owner continues to preserve external drift"),
                Component->GetComponentTransform().Equals(State->ExternalDrift));
            return true;
        }),
        TEXT("polling remains disabled")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
    return true;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
