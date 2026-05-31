// Language=angelscript

//============================================================================
// CK CAMERA — GYM PROPS
//============================================================================
//
// Visual-only reference geometry for the Camera gym so the driven camera has something to frame, orbit
// around, and lock onto. Without these the camera works but renders only skybox.
//
//   - ACk_CameraGym_Beacon : the fixed lock-on / look-at target. A bright floating sphere (distinct from the
//     grey cube pillars) so it reads as "the thing the camera is tracking". No collision — it must not deflect
//     the camera's ECC_Camera collision whiskers.
//
// Reference pillars use the framework's ACk_Gym_ObstacleWall (grey cubes, block all channels incl. ECC_Camera),
// so orbiting puts a pillar between camera and pawn and you see the collision push-in.
//============================================================================

class ACk_CameraGym_Beacon : AActor
{
    UPROPERTY(DefaultComponent, RootComponent)
    UStaticMeshComponent BeaconMesh;

    default BeaconMesh.Mobility = EComponentMobility::Movable;

    UFUNCTION(BlueprintOverride)
    void ConstructionScript()
    {
        auto SphereMesh = Cast<UStaticMesh>(LoadObject(this, "/Engine/BasicShapes/Sphere.Sphere"));
        if (SphereMesh != nullptr)
        { BeaconMesh.SetStaticMesh(SphereMesh); }

        auto Material = Cast<UMaterialInterface>(LoadObject(this, "/Engine/BasicShapes/BasicShapeMaterial.BasicShapeMaterial"));
        if (Material != nullptr)
        {
            // A dynamic instance lets us tint the beacon if the material exposes a Color param; if it doesn't,
            // SetVectorParameterValue is a harmless no-op and the beacon stays neutral (still readable by shape).
            auto Dynamic = BeaconMesh.CreateDynamicMaterialInstance(0, Material);
            if (Dynamic != nullptr)
            { Dynamic.SetVectorParameterValue(n"Color", FLinearColor(1.0f, 0.35f, 0.1f, 1.0f)); }
        }

        // Visual marker only — must not block or deflect the camera's collision whiskers.
        BeaconMesh.SetCollisionEnabled(ECollisionEnabled::NoCollision);
    }
}
