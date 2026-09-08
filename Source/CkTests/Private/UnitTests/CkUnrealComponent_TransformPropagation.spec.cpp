#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "CkCore/Validation/CkIsValid.h"
#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcsExt/Transform/CkTransform_Fragment.h"
#include "CkEcsExt/Transform/CkTransform_Utils.h"
#include "CkUnrealComponent/CkUnrealComponent_Fragment.h"
#include "CkUnrealComponent/CkUnrealComponent_Utils.h"
#include "CkProfile/Stats/CkCpuWork.h"

#include "CkTests/Net/CkNetAutomation_Common.h"

#include "Components/SceneComponent.h"
#include "HAL/IConsoleManager.h"

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
        IConsoleVariable* CpuWorkCVar = nullptr;
        FString CpuWorkPreviousValue;
        EConsoleVariableFlags CpuWorkPreviousPriority = ECVF_SetByConstructor;
        bool bCpuWorkOverrideActive = false;
        TOptional<bool> ExpectedCpuWorkEnabled;

        ~FTestState()
        { RestoreCpuWorkCVar(); }

        auto RestoreCpuWorkCVar() -> void
        {
            if (!bCpuWorkOverrideActive || CpuWorkCVar == nullptr)
            { return; }

            const auto CurrentPriority = static_cast<EConsoleVariableFlags>(
                CpuWorkCVar->GetFlags() & ECVF_SetByMask);
            CpuWorkCVar->Set(*CpuWorkPreviousValue, CurrentPriority);
            CpuWorkCVar->SetFlags(static_cast<EConsoleVariableFlags>(
                (CpuWorkCVar->GetFlags() & ~ECVF_SetByMask) | CpuWorkPreviousPriority));
            bCpuWorkOverrideActive = false;
            // Align the module's frame-latched flag with the restored CVar after a normal or aborted sequence.
            ck::cpu_work::BeginFrame();
        }
    };

    class FCk_Latent_RestoreCpuWorkCVar final : public IAutomationLatentCommand
    {
    public:
        explicit FCk_Latent_RestoreCpuWorkCVar(const TSharedRef<FTestState>& InState)
            : _State(InState)
        {
        }

        virtual auto Update() -> bool override
        {
            _State->RestoreCpuWorkCVar();
            return true;
        }

    private:
        TSharedRef<FTestState> _State;
    };
}

namespace ck_tests_unreal_component_transform
{
    auto QueueTransformPropagation(FAutomationTestBase* InTest, const TOptional<int32> InCpuWorkMode) -> void
    {
        auto State = MakeShared<FTestState>();
        if (InCpuWorkMode.IsSet())
        {
            State->CpuWorkCVar = IConsoleManager::Get().FindConsoleVariable(TEXT("ck.Perf.CpuWork"));
            if (State->CpuWorkCVar == nullptr)
            {
                InTest->AddError(TEXT("ck.Perf.CpuWork is not registered."));
            }
            else
            {
                State->CpuWorkPreviousValue = State->CpuWorkCVar->GetString();
                State->CpuWorkPreviousPriority = static_cast<EConsoleVariableFlags>(
                    State->CpuWorkCVar->GetFlags() & ECVF_SetByMask);
                State->CpuWorkCVar->Set(InCpuWorkMode.GetValue(), ECVF_SetByConsole);
                State->bCpuWorkOverrideActive = true;
                State->ExpectedCpuWorkEnabled = InCpuWorkMode.GetValue() != 0;
            }
        }

        ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(1, TEXT("/Engine/Maps/Entry")));
        ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(1, 30.0f));

        ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
            FCk_NetAutoTest_ServerAction::CreateLambda([InTest, State](UWorld* InWorld) -> void
            {
                if (State->ExpectedCpuWorkEnabled.IsSet())
                {
                    ck::cpu_work::BeginFrame();
                    InTest->TestEqual(TEXT("CPU-work frame latch matches this propagation alias mode"),
                        ck::cpu_work::Get_Enabled(), State->ExpectedCpuWorkEnabled.GetValue());
                }

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
                { InTest->AddError(TEXT("failed to create transform owner")); }
                if (ck::Is_NOT_Valid(State->ComponentHandle))
                { InTest->AddError(TEXT("failed to create UnrealComponent handle")); }
            })));

        ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(5));

        ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
            FCk_NetAutoTest_ServerAction::CreateLambda([InTest, State](UWorld*) -> void
            {
                if (ck::Is_NOT_Valid(State->ComponentHandle))
                {
                    InTest->AddError(TEXT("UnrealComponent handle became invalid during setup"));
                    return;
                }

                auto* Component = Cast<USceneComponent>(
                    UCk_Utils_UnrealComponent_UE::Get_Component(State->ComponentHandle));
                if (ck::Is_NOT_Valid(Component))
                {
                    InTest->AddError(TEXT("setup did not create a scene component"));
                    return;
                }

                State->SceneComponent = Component;
                if (State->OwnerTransform.Has<ck::FTag_Transform_Updated>())
                { State->OwnerTransform.Remove<ck::FTag_Transform_Updated>(); }
                Component->SetWorldTransform(State->ExternalDrift);
            })));

        ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(2));

        ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(InTest,
            FCk_NetAutoTest_Assertion::CreateLambda([InTest, State]() -> bool
            {
                const auto* Component = State->SceneComponent.Get();
                const auto IsValidComponent = ck::IsValid(Component);
                InTest->TestTrue(TEXT("scene component remains valid for idle assertion"), IsValidComponent);
                if (NOT IsValidComponent)
                { return true; }

                InTest->TestTrue(TEXT("idle owner does not overwrite external component drift"),
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

        ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(InTest,
            FCk_NetAutoTest_Assertion::CreateLambda([InTest, State]() -> bool
            {
                const auto* Component = State->SceneComponent.Get();
                const auto IsValidComponent = ck::IsValid(Component);
                InTest->TestTrue(TEXT("scene component remains valid for dirty-owner assertion"), IsValidComponent);
                if (NOT IsValidComponent)
                { return true; }

                const auto EcsTransform =
                    UCk_Utils_Transform_UE::Get_EntityCurrentTransform(State->OwnerTransform);
                InTest->TestTrue(TEXT("transform request moved the ECS owner"),
                    EcsTransform.Equals(State->MovedTransform));
                InTest->TestTrue(TEXT("dirty owner pushes its current ECS transform to the scene component"),
                    Component->GetComponentTransform().Equals(EcsTransform));
                return true;
            }),
            TEXT("dirty transform owner pushes its scene component")));

        ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
            FCk_NetAutoTest_ServerAction::CreateLambda([InTest, State](UWorld*) -> void
            {
                auto* Component = State->SceneComponent.Get();
                if (ck::Is_NOT_Valid(Component))
                {
                    InTest->AddError(TEXT("scene component became invalid before second idle assertion"));
                    return;
                }

                if (State->OwnerTransform.Has<ck::FTag_Transform_Updated>())
                { State->OwnerTransform.Remove<ck::FTag_Transform_Updated>(); }
                Component->SetWorldTransform(State->ExternalDrift);
            })));
        ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(1));

        ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(InTest,
            FCk_NetAutoTest_Assertion::CreateLambda([InTest, State]() -> bool
            {
                const auto* Component = State->SceneComponent.Get();
                const auto IsValidComponent = ck::IsValid(Component);
                InTest->TestTrue(TEXT("scene component remains valid for second idle assertion"), IsValidComponent);
                if (NOT IsValidComponent)
                { return true; }

                InTest->TestTrue(TEXT("unchanged owner continues to preserve external drift"),
                    Component->GetComponentTransform().Equals(State->ExternalDrift));
                return true;
            }),
            TEXT("polling remains disabled")));

        ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
        if (State->bCpuWorkOverrideActive)
        { ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RestoreCpuWorkCVar(State)); }
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkUnrealComponent_TransformPropagation_DirtyOwnersOnly,
    "Ck.UnrealComponent.TransformPropagation.DirtyOwnersOnly",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkUnrealComponent_TransformPropagation_DirtyOwnersOnly::RunTest(const FString& Parameters)
{
    ck_tests_unreal_component_transform::QueueTransformPropagation(this, {});
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkUnrealComponent_CpuWork_ComponentPropagationOff,
    "CkTests.UnitTests.CkProfile.CpuWork.ComponentPropagationOff",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkUnrealComponent_CpuWork_ComponentPropagationOff::RunTest(const FString& Parameters)
{
    ck_tests_unreal_component_transform::QueueTransformPropagation(this, 0);
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkUnrealComponent_CpuWork_ComponentPropagationOn,
    "CkTests.UnitTests.CkProfile.CpuWork.ComponentPropagationOn",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkUnrealComponent_CpuWork_ComponentPropagationOn::RunTest(const FString& Parameters)
{
    ck_tests_unreal_component_transform::QueueTransformPropagation(this, 1);
    return true;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
