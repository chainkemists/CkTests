// --------------------------------------------------------------------------------------------------------------------
// Nav-only obstacle for the Crowd Pathing gym. Carves the navmesh (so crowd agents path AROUND it,
// which is what creates the lateral approach -> orbit), but ignores the player Pawn so the player
// can walk straight through it instead of getting stuck on it. Crowd agents have no physics body —
// they avoid obstacles via the carved navmesh, not collision — so ignoring the Pawn costs nothing.
// --------------------------------------------------------------------------------------------------------------------

class ACk_CrowdPathingGym_NavBox : AActor
{
    UPROPERTY(DefaultComponent, RootComponent)
    UStaticMeshComponent BoxMesh;

    default BoxMesh.Mobility = EComponentMobility::Movable;

    UFUNCTION(BlueprintOverride)
    void ConstructionScript()
    {
        auto CubeMesh = Cast<UStaticMesh>(LoadObject(this, "/Engine/BasicShapes/Cube.Cube"));
        if (CubeMesh != nullptr)
        {
            BoxMesh.SetStaticMesh(CubeMesh);
        }

        auto BoxMaterial = Cast<UMaterialInterface>(LoadObject(this, "/Engine/BasicShapes/BasicShapeMaterial.BasicShapeMaterial"));
        if (BoxMaterial != nullptr)
        {
            BoxMesh.SetMaterial(0, BoxMaterial);
        }

        BoxMesh.SetCollisionEnabled(ECollisionEnabled::QueryAndPhysics);
        BoxMesh.SetCollisionObjectType(ECollisionChannel::ECC_WorldStatic);
        BoxMesh.SetCollisionResponseToAllChannels(ECollisionResponse::ECR_Block);
        BoxMesh.SetCollisionResponseToChannel(ECollisionChannel::ECC_Pawn, ECollisionResponse::ECR_Ignore);
        BoxMesh.bCanEverAffectNavigation = true;
    }
}
