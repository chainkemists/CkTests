// --------------------------------------------------------------------------------------------------------------------
// Obstacle wall actor for any gym that needs a nav-blocking surface (LOS/path
// trace tests, navmesh hole demonstrations, etc.).
//
// Construction-script wires a /Engine/BasicShapes/Cube static mesh with collision
// + nav settings so Recast carves a hole around it. The owning gym spawns this and
// SetActorScale3D's it to the wall footprint they want.
//
// To preserve nav obstruction the wall must extend high enough above the floor
// that the agent capsule cannot step over it; the navmesh bake will then mark
// tiles inside the wall as unwalkable. Z scale ~3.0 (300cm) is a safe default.
// --------------------------------------------------------------------------------------------------------------------

class ACk_Gym_ObstacleWall : AActor
{
    UPROPERTY(DefaultComponent, RootComponent)
    UStaticMeshComponent WallMesh;

    default WallMesh.Mobility = EComponentMobility::Movable;

    UFUNCTION(BlueprintOverride)
    void ConstructionScript()
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto CubeMesh = Cast<UStaticMesh>(LoadObject(this, "/Engine/BasicShapes/Cube.Cube"));
        if (CubeMesh != nullptr)
        {
            WallMesh.SetStaticMesh(CubeMesh);
        }

        auto WallMaterial = Cast<UMaterialInterface>(LoadObject(this, "/Engine/BasicShapes/BasicShapeMaterial.BasicShapeMaterial"));
        if (WallMaterial != nullptr)
        {
            WallMesh.SetMaterial(0, WallMaterial);
        }

        WallMesh.SetCollisionEnabled(ECollisionEnabled::QueryAndPhysics);
        WallMesh.SetCollisionObjectType(ECollisionChannel::ECC_WorldStatic);
        WallMesh.SetCollisionResponseToAllChannels(ECollisionResponse::ECR_Block);
        WallMesh.bCanEverAffectNavigation = true;
    }
}
