// --------------------------------------------------------------------------------------------------------------------
// Showcase actor for the CkUsf gym: a sphere whose material is a runtime MID created
// from a USF-authored look. Proves the full path:
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

    // Called by the gym PlayerController right after spawn to pick which look to render.
    void Request_SetLook(UCkUsf_LookDefinition InLook)
    {
        auto MID = UCk_Utils_Usf_UE::Create_MID_ForLook(InLook, this);
        if (MID != nullptr)
        {
            Mesh.SetMaterial(0, MID);
            auto LookName = InLook.Get_EffectiveLookName();
            ck::Trace(f"✅ CkUsf gym: applied look [{LookName}]");
        }
        else
        {
            ck::Warning("❌ CkUsf gym: MID creation failed — run 'Generate Look Materials' first");
        }
    }
}
