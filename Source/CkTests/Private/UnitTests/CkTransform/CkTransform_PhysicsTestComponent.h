#pragma once

#include <Components/SphereComponent.h>

#include "CkTransform_PhysicsTestComponent.generated.h"

// --------------------------------------------------------------------------------------------------------------------

struct FCk_Transform_PhysicsMoveObservation
{
    FVector Delta = FVector::ZeroVector;
    FQuat Rotation = FQuat::Identity;
    ETeleportType Teleport = ETeleportType::None;
    bool bSimulatingPhysics = false;
};

struct FCk_Transform_PhysicsUpdateObservation
{
    FVector ComponentLocation = FVector::ZeroVector;
    FVector AfterBodyLocation = FVector::ZeroVector;
    ETeleportType Teleport = ETeleportType::None;
    EUpdateTransformFlags Flags = EUpdateTransformFlags::None;
};

// --------------------------------------------------------------------------------------------------------------------

UCLASS()
class UCk_Transform_PhysicsTestComponent : public USphereComponent
{
    GENERATED_BODY()

public:
    auto Get_MoveObservations() const -> const TArray<FCk_Transform_PhysicsMoveObservation>&;
    auto Get_UpdateObservations() const -> const TArray<FCk_Transform_PhysicsUpdateObservation>&;
    auto Reset_MoveObservations() -> void;

protected:
    auto MoveComponentImpl(
        const FVector& Delta,
        const FQuat& NewRotation,
        bool bSweep,
        FHitResult* OutHit,
        EMoveComponentFlags MoveFlags,
        ETeleportType Teleport) -> bool override;
    auto OnUpdateTransform(EUpdateTransformFlags UpdateTransformFlags, ETeleportType Teleport) -> void override;

private:
    TArray<FCk_Transform_PhysicsMoveObservation> _MoveObservations;
    TArray<FCk_Transform_PhysicsUpdateObservation> _UpdateObservations;
};
