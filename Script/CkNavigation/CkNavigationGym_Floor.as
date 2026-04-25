//============================================================================
// Floor actor for the Navigation gym. A simple movable cube scaled wide+thin
// so the navmesh has something to bake on. Movable mobility is required so
// the GameMode can scale at runtime via SetActorScale3D.
//============================================================================

class ACk_NavigationGym_Floor : AActor
{
	UPROPERTY(DefaultComponent, RootComponent)
	UStaticMeshComponent FloorMesh;

	default FloorMesh.Mobility = EComponentMobility::Movable;

	UFUNCTION(BlueprintOverride)
	void ConstructionScript()
	{
		// Static mesh
		auto CubeMesh = Cast<UStaticMesh>(LoadObject(this, "/Engine/BasicShapes/Cube.Cube"));
		if (CubeMesh != nullptr)
		{
			FloorMesh.SetStaticMesh(CubeMesh);
		}

		// Collision: must block static channel + be marked WorldStatic for Recast to treat
		// the surface as nav-walkable. AS `default Component.SetXxx(...)` syntax doesn't
		// actually call methods at construct — these have to be runtime calls.
		FloorMesh.SetCollisionEnabled(ECollisionEnabled::QueryAndPhysics);
		FloorMesh.SetCollisionObjectType(ECollisionChannel::ECC_WorldStatic);
		FloorMesh.SetCollisionResponseToAllChannels(ECollisionResponse::ECR_Block);
		FloorMesh.bCanEverAffectNavigation = true;
	}
}
