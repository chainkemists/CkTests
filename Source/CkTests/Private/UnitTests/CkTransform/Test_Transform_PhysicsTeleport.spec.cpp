#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "CkCore/Validation/CkIsValid.h"
#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcsExt/Transform/CkTransform_Fragment.h"
#include "CkEcsExt/Transform/CkTransform_Utils.h"
#include "CkTests/Net/CkNetAutomation_Common.h"

#include "CkTransform_PhysicsTestComponent.h"

#include <GameFramework/Actor.h>

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_transform_physics_teleport
{
    struct FTestState
    {
        FCk_Handle_Transform InitiallyKinematic;
        FCk_Handle_Transform InitiallySimulating;
        TWeakObjectPtr<UCk_Transform_PhysicsTestComponent> BecameSimulating;
        TWeakObjectPtr<UCk_Transform_PhysicsTestComponent> BecameKinematic;
        FVector SimulatingLocationDelta = FVector::ZeroVector;
        FVector KinematicLocationDelta = FVector::ZeroVector;
        FVector SyncLocationDelta = FVector::ZeroVector;
    };

    auto CreateBoundRoot(
        FAutomationTestBase& InTest,
        UWorld& InWorld,
        bool bInitiallySimulating,
        TWeakObjectPtr<UCk_Transform_PhysicsTestComponent>& OutComponent)
        -> FCk_Handle_Transform
    {
        const auto Actor = TObjectPtr<AActor>{InWorld.SpawnActor<AActor>()};
        if (NOT InTest.TestTrue(TEXT("physics root actor spawned"), ck::IsValid(Actor)))
        { return {}; }

        const auto Component = TObjectPtr<UCk_Transform_PhysicsTestComponent>{
            NewObject<UCk_Transform_PhysicsTestComponent>(Actor.Get())};
        if (NOT InTest.TestTrue(TEXT("physics root component created"), ck::IsValid(Component)))
        { Actor->Destroy(); return {}; }

        Component->SetMobility(EComponentMobility::Movable);
        Component->SetSphereRadius(50.0f);
        Component->SetCollisionProfileName(TEXT("PhysicsActor"));
        Component->SetEnableGravity(false);
        Actor->SetRootComponent(Component.Get());
        Component->RegisterComponent();
        if (NOT InTest.TestTrue(TEXT("physics root registered"), Component->IsRegistered()))
        { Actor->Destroy(); return {}; }

        Component->SetWorldLocation(bInitiallySimulating
            ? FVector{0.0, 1000.0, 200.0}
            : FVector{0.0, -1000.0, 200.0});
        Component->SetSimulatePhysics(bInitiallySimulating);
        if (NOT InTest.TestEqual(TEXT("initial physics state applied"),
            Component->IsSimulatingPhysics(), bInitiallySimulating))
        { Actor->Destroy(); return {}; }

        auto Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity_TransientOwner(&InWorld);
        auto Transform = UCk_Utils_Transform_UE::AddAndAttachToUnrealComponent(
            Owner, Component.Get(), ECk_Replication::DoesNotReplicate);
        if (NOT InTest.TestTrue(TEXT("transform bound to registered physics root"), ck::IsValid(Transform)))
        {
            UCk_Utils_EntityLifetime_UE::Request_DestroyEntity(Owner);
            Actor->Destroy();
            return {};
        }

        OutComponent = Component;
        return Transform;
    }

    auto AssertObservedMove(
        FAutomationTestBase& InTest,
        const UCk_Transform_PhysicsTestComponent& InComponent,
        const FVector& InExpectedDelta,
        const FQuat& InExpectedRotation,
        ETeleportType InExpectedTeleport,
        bool bExpectedSimulating,
        const FString& InLabel)
        -> void
    {
        const auto& Observations = InComponent.Get_MoveObservations();
        const auto MatchingIndex = Observations.IndexOfByPredicate(
            [&](const FCk_Transform_PhysicsMoveObservation& InObservation)
            {
                return InObservation.Delta.Equals(InExpectedDelta, 5.0) &&
                    InObservation.Rotation.Equals(InExpectedRotation, 1.0e-3);
            });

        if (NOT InTest.TestTrue(*FString::Printf(TEXT("%s reached MoveComponentImpl"), *InLabel),
            MatchingIndex != INDEX_NONE))
        { return; }

        const auto& MatchingMove = Observations[MatchingIndex];
        InTest.TestTrue(*FString::Printf(TEXT("%s uses current physics teleport mode"), *InLabel),
            MatchingMove.Teleport == InExpectedTeleport);
        InTest.TestEqual(*FString::Printf(TEXT("%s observes current simulation state"), *InLabel),
            MatchingMove.bSimulatingPhysics, bExpectedSimulating);
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Transform_PhysicsTeleport_FollowsLiveSimulationState,
    "Ck.Transform.PhysicsTeleport.FollowsLiveSimulationState",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkTest_Transform_PhysicsTeleport_FollowsLiveSimulationState::RunTest(const FString& Parameters)
{
    using namespace ck_test_transform_physics_teleport;

    const auto State = MakeShared<FTestState>();
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(1, TEXT("/Engine/Maps/Entry")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(1, 30.0f));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this, State](UWorld* InWorld) -> void
        {
            State->InitiallyKinematic = CreateBoundRoot(
                *this, *InWorld, false, State->BecameSimulating);
            State->InitiallySimulating = CreateBoundRoot(
                *this, *InWorld, true, State->BecameKinematic);
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this, State](UWorld*) -> void
        {
            const auto BecameSimulating = TObjectPtr<UCk_Transform_PhysicsTestComponent>{State->BecameSimulating.Get()};
            const auto BecameKinematic = TObjectPtr<UCk_Transform_PhysicsTestComponent>{State->BecameKinematic.Get()};
            if (NOT TestTrue(TEXT("kinematic root remains available"), ck::IsValid(BecameSimulating)) ||
                NOT TestTrue(TEXT("simulating root remains available"), ck::IsValid(BecameKinematic)) ||
                NOT TestTrue(TEXT("kinematic transform remains valid"), ck::IsValid(State->InitiallyKinematic)) ||
                NOT TestTrue(TEXT("simulating transform remains valid"), ck::IsValid(State->InitiallySimulating)))
            { return; }

            BecameSimulating->SetSimulatePhysics(true);
            BecameKinematic->SetSimulatePhysics(false);
            TestTrue(TEXT("first root now simulates physics"), BecameSimulating->IsSimulatingPhysics());
            TestFalse(TEXT("second root no longer simulates physics"), BecameKinematic->IsSimulatingPhysics());

            const auto SimulatingDestination = FVector{1000.0, 100.0, 200.0};
            const auto KinematicDestination = FVector{-1000.0, -100.0, 200.0};
            State->SimulatingLocationDelta = SimulatingDestination - BecameSimulating->GetComponentLocation();
            State->KinematicLocationDelta = KinematicDestination - BecameKinematic->GetComponentLocation();
            BecameSimulating->Reset_MoveObservations();
            BecameKinematic->Reset_MoveObservations();
            UCk_Utils_Transform_UE::Request_SetLocation(State->InitiallyKinematic,
                FCk_Request_Transform_SetLocation{SimulatingDestination}, {});
            UCk_Utils_Transform_UE::Request_SetLocation(State->InitiallySimulating,
                FCk_Request_Transform_SetLocation{KinematicDestination}, {});
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(2));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this, State](UWorld*) -> void
        {
            const auto BecameSimulating = TObjectPtr<UCk_Transform_PhysicsTestComponent>{State->BecameSimulating.Get()};
            const auto BecameKinematic = TObjectPtr<UCk_Transform_PhysicsTestComponent>{State->BecameKinematic.Get()};
            if (ck::Is_NOT_Valid(BecameSimulating) || ck::Is_NOT_Valid(BecameKinematic))
            { AddError(TEXT("physics roots became invalid before location verification")); return; }

            AssertObservedMove(*this, *BecameSimulating, State->SimulatingLocationDelta,
                FQuat::Identity, ETeleportType::TeleportPhysics, true, TEXT("enabled-physics location request"));
            AssertObservedMove(*this, *BecameKinematic, State->KinematicLocationDelta,
                FQuat::Identity, ETeleportType::None, false, TEXT("disabled-physics location request"));
            // Physics may write back a solver pose later; verify the body write when the scoped move commits.
            const auto CommittedPhysicsMove = BecameSimulating->Get_UpdateObservations().IndexOfByPredicate(
                [&](const FCk_Transform_PhysicsUpdateObservation& InObservation)
                {
                    const auto Destination = FVector{1000.0, 100.0, 200.0};
                    return InObservation.ComponentLocation.Equals(Destination, 5.0)
                        && InObservation.AfterBodyLocation.Equals(Destination, 5.0)
                        && InObservation.Teleport == ETeleportType::TeleportPhysics
                        && InObservation.Flags == EUpdateTransformFlags::None;
                });
            TestTrue(TEXT("enabled-physics location request commits target pose to physics body"),
                CommittedPhysicsMove != INDEX_NONE);
            TestTrue(TEXT("disabled-physics location request reaches its target"),
                BecameKinematic->GetComponentLocation().Equals(FVector{-1000.0, -100.0, 200.0}, 5.0));

            const auto SimulatingRotation = FRotator{0.0, 42.0, 0.0};
            const auto KinematicRotation = FRotator{0.0, -37.0, 0.0};
            BecameSimulating->Reset_MoveObservations();
            BecameKinematic->Reset_MoveObservations();
            UCk_Utils_Transform_UE::Request_SetRotation(State->InitiallyKinematic,
                FCk_Request_Transform_SetRotation{SimulatingRotation}, {});
            UCk_Utils_Transform_UE::Request_SetRotation(State->InitiallySimulating,
                FCk_Request_Transform_SetRotation{KinematicRotation}, {});
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(2));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this, State](UWorld*) -> void
        {
            const auto BecameSimulating = TObjectPtr<UCk_Transform_PhysicsTestComponent>{State->BecameSimulating.Get()};
            const auto BecameKinematic = TObjectPtr<UCk_Transform_PhysicsTestComponent>{State->BecameKinematic.Get()};
            if (ck::Is_NOT_Valid(BecameSimulating) || ck::Is_NOT_Valid(BecameKinematic))
            { AddError(TEXT("physics roots became invalid before rotation verification")); return; }

            AssertObservedMove(*this, *BecameSimulating, FVector::ZeroVector,
                FRotator{0.0, 42.0, 0.0}.Quaternion(), ETeleportType::TeleportPhysics, true,
                TEXT("enabled-physics rotation request"));
            AssertObservedMove(*this, *BecameKinematic, FVector::ZeroVector,
                FRotator{0.0, -37.0, 0.0}.Quaternion(), ETeleportType::None, false,
                TEXT("disabled-physics rotation request"));
            TestTrue(TEXT("enabled-physics rotation request reaches its target"),
                BecameSimulating->GetComponentRotation().Equals(FRotator{0.0, 42.0, 0.0}, 1.0));
            TestTrue(TEXT("disabled-physics rotation request reaches its target"),
                BecameKinematic->GetComponentRotation().Equals(FRotator{0.0, -37.0, 0.0}, 1.0));

            State->InitiallyKinematic.AddOrGet<ck::FTag_Transform_ExternallyDriven>();
            const auto SyncDestination = FTransform{
                FRotator{0.0, 87.0, 0.0}, FVector{1600.0, 200.0, 300.0}};
            State->SyncLocationDelta = SyncDestination.GetLocation() - BecameSimulating->GetComponentLocation();
            auto& Transform = State->InitiallyKinematic.Get<ck::FFragment_Transform>();
            auto& Previous = State->InitiallyKinematic.Get<ck::FFragment_Transform_Previous>();
            UCk_Utils_Transform_UE::Apply_SetTransform_DirectWrite(Transform, Previous, SyncDestination);
            UCk_Utils_Transform_UE::Request_ForceRefresh(State->InitiallyKinematic, {});
            BecameSimulating->Reset_MoveObservations();
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(2));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this, State](UWorld*) -> void
        {
            const auto BecameSimulating = TObjectPtr<UCk_Transform_PhysicsTestComponent>{State->BecameSimulating.Get()};
            if (ck::Is_NOT_Valid(BecameSimulating))
            { AddError(TEXT("simulating root became invalid before sync verification")); return; }

            AssertObservedMove(*this, *BecameSimulating, State->SyncLocationDelta,
                FRotator{0.0, 87.0, 0.0}.Quaternion(), ETeleportType::TeleportPhysics, true,
                TEXT("enabled-physics SyncToActor"));
            TestTrue(TEXT("SyncToActor applies the authored world location"),
                BecameSimulating->GetComponentLocation().Equals(FVector{1600.0, 200.0, 300.0}, 5.0));
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
    return true;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
