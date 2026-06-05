// --------------------------------------------------------------------------------------------------------------------
// Showcase actor for the CkUsf gym: a sphere whose material is a runtime MID created
// from the AngelScript-declared Hologram look (CkUsf::Hologram). Proves the full path:
//   text .ush + AS LookDefinition -> generated master -> MID -> rendered on a mesh.
//
// The generated master must exist on disk first (run "Generate Look Materials" from the
// CkUsf editor subsystem). If it doesn't, MID creation returns null and we log a warning.
// --------------------------------------------------------------------------------------------------------------------

class ACk_UsfGym_Showcase : AActor
{
    UPROPERTY(DefaultComponent, RootComponent)
    UStaticMeshComponent Mesh;

    default Mesh.Mobility = EComponentMobility::Movable;

    UFUNCTION(BlueprintOverride)
    void ConstructionScript()
    {
        auto SphereMesh = Cast<UStaticMesh>(LoadObject(this, "/Engine/BasicShapes/Sphere.Sphere"));
        if (SphereMesh != nullptr)
        {
            Mesh.SetStaticMesh(SphereMesh);
        }
    }

    UFUNCTION(BlueprintOverride)
    void BeginPlay()
    {
        auto MID = UCk_Utils_Usf_UE::Create_MID_ForLook(CkUsf::Hologram, this);
        if (MID != nullptr)
        {
            Mesh.SetMaterial(0, MID);
            ck::Trace("✅ CkUsf gym: Hologram MID applied to showcase mesh");
        }
        else
        {
            ck::Warning("❌ CkUsf gym: failed to create Hologram MID — run 'Generate Look Materials' first");
        }
    }
}
