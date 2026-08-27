// --------------------------------------------------------------------------------------------------------------------
// Floor actor for any gym that needs a navmesh-bakeable surface.
//
// Construction-script wires a /Engine/BasicShapes/Cube static mesh with collision
// + nav settings so Recast treats the top face as walkable. The owning gym spawns
// this and SetActorScale3D's it to whatever footprint it wants (typical scale =
// (60, 60, 0.5) -> 6000cm x 6000cm x 50cm).
//
// WALKABLE SURFACE IS AT THE ACTOR'S ORIGIN. Spawn the floor at the Z you want your
// agents to stand on - no manual half-thickness compensation. The mesh is offset down
// by half a cube (relative Z = -50) so the slab hangs BELOW the origin: the offset is
// scaled by the actor's Z scale exactly as the thickness is, so the top face lands on
// the origin for ANY Z scale, not just the usual 0.5.
//
// This used to be otherwise: the root WAS the centered cube, so the origin sat at the
// slab's MID-height and every gym that spawned at the obvious ZeroVector buried its
// agents by half the thickness (25cm at the standard 0.5 Z scale). That 25cm exactly
// equals CkCrowd's _WaypointArrivalRadius, and the waypoint-arrival test is 3D - so a
// buried agent could never retire a waypoint authored on the surface plane. Keeping the
// walkable surface ON the origin is what closes that trap for good.
//
// IMPORTANT: navmesh bake requires Z scale >= 0.5; thinner slabs silently bake
// to zero walkable tiles.
// --------------------------------------------------------------------------------------------------------------------

class ACk_Gym_Floor : AActor
{
    UPROPERTY(DefaultComponent, RootComponent)
    USceneComponent SceneRoot;

    default SceneRoot.Mobility = EComponentMobility::Movable;

    UPROPERTY(DefaultComponent, Attach = SceneRoot)
    UStaticMeshComponent FloorMesh;

    default FloorMesh.Mobility = EComponentMobility::Movable;
    default FloorMesh.RelativeLocation = FVector(0.0, 0.0, -50.0);

    UFUNCTION(BlueprintOverride)
    void ConstructionScript()
    {
        auto _CkPerfScope = ck::ScopedStat();
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
        // run at construct time - these must be runtime calls inside ConstructionScript.
        FloorMesh.SetCollisionEnabled(ECollisionEnabled::QueryAndPhysics);
        FloorMesh.SetCollisionObjectType(ECollisionChannel::ECC_WorldStatic);
        FloorMesh.SetCollisionResponseToAllChannels(ECollisionResponse::ECR_Block);
        FloorMesh.bCanEverAffectNavigation = true;
    }
}
