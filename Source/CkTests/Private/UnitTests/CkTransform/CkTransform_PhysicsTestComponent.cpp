#include "CkTransform_PhysicsTestComponent.h"

// --------------------------------------------------------------------------------------------------------------------

auto
    UCk_Transform_PhysicsTestComponent::
    Get_MoveObservations() const
    -> const TArray<FCk_Transform_PhysicsMoveObservation>&
{
    return _MoveObservations;
}

auto
    UCk_Transform_PhysicsTestComponent::
    Get_UpdateObservations() const
    -> const TArray<FCk_Transform_PhysicsUpdateObservation>&
{
    return _UpdateObservations;
}

auto
    UCk_Transform_PhysicsTestComponent::
    Reset_MoveObservations()
    -> void
{
    _MoveObservations.Reset();
    _UpdateObservations.Reset();
}

auto
    UCk_Transform_PhysicsTestComponent::
    MoveComponentImpl(
        const FVector& Delta,
        const FQuat& NewRotation,
        bool bSweep,
        FHitResult* OutHit,
        EMoveComponentFlags MoveFlags,
        ETeleportType Teleport)
    -> bool
{
    _MoveObservations.Add(FCk_Transform_PhysicsMoveObservation{
        Delta, NewRotation, Teleport, IsSimulatingPhysics()});
    return Super::MoveComponentImpl(Delta, NewRotation, bSweep, OutHit, MoveFlags, Teleport);
}

auto
    UCk_Transform_PhysicsTestComponent::
    OnUpdateTransform(
        EUpdateTransformFlags UpdateTransformFlags,
        ETeleportType Teleport)
    -> void
{
    Super::OnUpdateTransform(UpdateTransformFlags, Teleport);
    _UpdateObservations.Add(FCk_Transform_PhysicsUpdateObservation{
        GetComponentLocation(), BodyInstance.IsValidBodyInstance()
            ? BodyInstance.GetUnrealWorldTransform().GetLocation() : FVector::ZeroVector,
        Teleport, UpdateTransformFlags});
}
