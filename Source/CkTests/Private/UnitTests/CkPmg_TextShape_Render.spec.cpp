// CkPmg text shape render test — end-to-end smoke: spawns a DrawText entity on the server
// world, ticks ~5 frames, then asserts the returned handle has a non-empty
// FFragment_Pmg_DebugShape_Lines (the wireframe tier — the most accessible end-to-end signal).
//
// Uses the PIE latent-command harness from CkNetAutomation_Common.h (same pattern as
// Test_Snapshot_FloatAttribute_Gate.spec.cpp). NumClients=1 == 1 server window, no extra clients.
//
// Surface in Session Frontend: Ck.Pmg.TextShape.RendersWireframe

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/Subsystem/CkEcsWorld_Subsystem.h"

#include "CkPmg/CkPmg_Fragment.h"
#include "CkPmg/CkPmg_Utils_BasicShapes.h"
#include "CkPmg/CkPmg_Utils_TextShapes.h"

#include "CkTests/Net/CkNetAutomation_Common.h"

#include "Engine/World.h"
#include "ProceduralMeshComponent.h"

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkPmg_TextShape_RendersWireframe,
    "Ck.Pmg.TextShape.RendersWireframe",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkPmg_WorldTeardown_UnregistersDebugShapeMeshBeforeWorldCleanup,
    "Ck.PackagedEnsure.Pmg.WorldTeardown.UnregistersDebugShapeMeshBeforeWorldCleanup",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkEcs_WorldTeardown_RejectsLateEntityCreation,
    "Ck.PackagedEnsure.Ecs.WorldTeardown.RejectsLateEntityCreation",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkPmg_TextShape_RendersWireframe::RunTest(const FString& Parameters)
{
    auto Handle = MakeShared<FCk_Handle_Pmg_DebugShape>();

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(1, TEXT("/Engine/Maps/Entry")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(1, 30.0f));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this, Handle](UWorld* InWorld) -> void
        {
            *Handle = UCk_Utils_Pmg_TextShapes::DrawText(
                InWorld,
                FVector::ZeroVector,
                TEXT("Ag"),
                100.0f,
                FLinearColor::White,
                /*InDrawLines=*/true,
                /*InDrawFilled=*/true,
                2.0f,
                ECk_Pmg_TextAlign::Left,
                ECk_Plane_Axis::XZ,
                /*InFontOverride=*/nullptr,
                /*InDuration=*/-1.0f);

            if (ck::Is_NOT_Valid(*Handle))
            {
                AddError(TEXT("DrawText returned invalid handle"));
            }
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(5));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this, Handle]() -> bool
        {
            auto& H = *Handle;
            if (ck::Is_NOT_Valid(H))
            {
                AddError(TEXT("text entity handle is invalid at assertion time"));
                return true;
            }

            const bool bHasLines = H.Has<ck::FFragment_Pmg_DebugShape_Lines>();
            TestTrue(TEXT("text entity has Lines fragment"), bHasLines);
            if (bHasLines)
            {
                TestTrue(TEXT("wireframe produced segments"),
                    H.Get<ck::FFragment_Pmg_DebugShape_Lines>().Get_Lines().Num() > 0);
            }
            return true;
        }),
        TEXT("text renders wireframe segments")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

bool FCkPmg_WorldTeardown_UnregistersDebugShapeMeshBeforeWorldCleanup::RunTest(const FString& Parameters)
{
    struct FTeardownObservation
    {
        TWeakObjectPtr<UWorld> World;
        TWeakObjectPtr<UProceduralMeshComponent> MeshComponent;
        FDelegateHandle WorldCleanupHandle;
        bool ObservedWorldCleanup = false;
        bool WasUnregisteredAtWorldCleanup = false;
    };

    auto Shape = MakeShared<FCk_Handle_Pmg_DebugShape>();
    auto Observation = MakeShared<FTeardownObservation>();

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(1, TEXT("/Engine/Maps/Entry")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(1, 30.0f));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this, Shape, Observation](UWorld* InWorld) -> void
        {
            *Shape = UCk_Utils_Pmg_BasicShapes::DrawFilledBox(
                InWorld,
                FVector::ZeroVector,
                FVector{50.0f},
                FLinearColor::White,
                /*InDrawLines=*/true,
                2.0f,
                ECk_Plane_Axis::XY,
                /*InDuration=*/-1.0f);

            if (ck::Is_NOT_Valid(*Shape))
            { AddError(TEXT("DrawFilledBox returned invalid handle")); return; }

            Observation->World = InWorld;
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(5));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this, Shape, Observation]() -> bool
        {
            if (ck::Is_NOT_Valid(*Shape) || NOT Shape->Has<ck::FFragment_Pmg_DebugShape_Current>())
            { AddError(TEXT("PMG shape did not reach Current before world teardown")); return true; }

            Observation->MeshComponent =
                Shape->Get<ck::FFragment_Pmg_DebugShape_Current>().Get_MeshComponent();
            auto* MeshComponent = Observation->MeshComponent.Get();
            if (ck::Is_NOT_Valid(MeshComponent))
            { AddError(TEXT("PMG shape did not create a mesh component")); return true; }

            TestTrue(TEXT("PMG mesh is registered before EndPIE"), MeshComponent->IsRegistered());

            Observation->WorldCleanupHandle = FWorldDelegates::OnWorldCleanup.AddLambda(
                [Observation](UWorld* InWorld, bool, bool)
                {
                    if (InWorld != Observation->World.Get())
                    { return; }

                    Observation->ObservedWorldCleanup = true;
                    const auto* Component = Observation->MeshComponent.Get();
                    Observation->WasUnregisteredAtWorldCleanup =
                        Component == nullptr || NOT Component->IsRegistered();
                });
            return true;
        }),
        TEXT("PMG mesh is registered and cleanup observation is armed")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this, Observation]() -> bool
        {
            if (Observation->WorldCleanupHandle.IsValid())
            {
                FWorldDelegates::OnWorldCleanup.Remove(Observation->WorldCleanupHandle);
                Observation->WorldCleanupHandle.Reset();
            }

            TestTrue(TEXT("PIE world cleanup was observed"), Observation->ObservedWorldCleanup);
            TestTrue(TEXT("PMG mesh was destroyed or unregistered before OnWorldCleanup"),
                Observation->WasUnregisteredAtWorldCleanup);
            return true;
        }),
        TEXT("PMG component is gone before engine world component validation")));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

bool FCkEcs_WorldTeardown_RejectsLateEntityCreation::RunTest(const FString& Parameters)
{
    // One CK ensure can surface through more than one log route. The test requires the diagnostic, while the explicit
    // invalid-handle assertion below proves the ordinary fail-closed path does not depend on the ensure body.
    AddExpectedError(TEXT("Request_CreateEntity rejected new world population after ECS world teardown began"),
        EAutomationExpectedErrorFlags::Contains, 0);

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(1, TEXT("/Engine/Maps/Entry")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(1, 30.0f));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InWorld) -> void
        {
            auto* EcsWorld = InWorld->GetSubsystem<UCk_EcsWorld_Subsystem_UE>();
            if (ck::Is_NOT_Valid(EcsWorld))
            { AddError(TEXT("PIE world has no CkEcs world subsystem")); return; }

            EcsWorld->Set_LoadHold(ECk_EcsWorld_LoadHold::Teardown);
            const auto Rejected = UCk_Utils_EntityLifetime_UE::Request_CreateEntity_TransientOwner(InWorld);
            EcsWorld->Set_LoadHold(ECk_EcsWorld_LoadHold::None);

            TestFalse(TEXT("world teardown rejects late entity creation even when ensure bodies compile out"),
                Rejected.IsValid(ck::IsValid_Policy_IncludePendingKill{}));
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
