// --------------------------------------------------------------------------------------------------------------------
// Floor actor for any CkCrowd gym that needs a navmesh.
//
// Construction-script wires a /Engine/BasicShapes/Cube static mesh with collision
// + nav settings so Recast treats the top face as walkable. The owning gym
// spawns this and SetActorScale3D's it to whatever footprint they want
// (default scale = (60, 60, 0.5) → 6000cm × 6000cm × 50cm with top face at Z=0
// when placed at Z=-25).
// --------------------------------------------------------------------------------------------------------------------

class ACk_CrowdGym_Floor : AActor
{
    UPROPERTY(DefaultComponent, RootComponent)
    UStaticMeshComponent FloorMesh;

    default FloorMesh.Mobility = EComponentMobility::Movable;

    UFUNCTION(BlueprintOverride)
    void ConstructionScript()
    {
        auto CubeMesh = Cast<UStaticMesh>(LoadObject(this, "/Engine/BasicShapes/Cube.Cube"));
        if (CubeMesh != nullptr)
        {
            FloorMesh.SetStaticMesh(CubeMesh);
        }

        // Replace the default WorldGridMaterial (which tiles infinitely + looks like a checkered
        // grid that visually overflows the mesh) with the engine's plain BasicShapeMaterial:
        // flat shaded, no tiling pattern, no grid. The mesh footprint becomes obvious.
        auto FloorMaterial = Cast<UMaterialInterface>(LoadObject(this, "/Engine/BasicShapes/BasicShapeMaterial.BasicShapeMaterial"));
        if (FloorMaterial != nullptr)
        {
            FloorMesh.SetMaterial(0, FloorMaterial);
        }

        // Collision must block the static channel + be WorldStatic for Recast to bake
        // the surface as nav-walkable. AS 'default Component.SetXxx(...)' syntax doesn't
        // run at construct time — these must be runtime calls inside ConstructionScript.
        FloorMesh.SetCollisionEnabled(ECollisionEnabled::QueryAndPhysics);
        FloorMesh.SetCollisionObjectType(ECollisionChannel::ECC_WorldStatic);
        FloorMesh.SetCollisionResponseToAllChannels(ECollisionResponse::ECR_Block);
        FloorMesh.bCanEverAffectNavigation = true;
    }
}
