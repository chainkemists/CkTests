// --------------------------------------------------------------------------------------------------------------------
// Showcase for the CkUsf SOLID OUTLINE capability. A sphere gets a runtime outline (custom depth/stencil + the
// SolidOutline post-process), plus an opaque wall partially in front of it (toward the player at world -X) so the
// occlusion difference is obvious: the Normal preset hides behind the wall, See-Through / Masked show through it.
//
// Used by the "Solid Outline" gym (one per preset). Also works as a drop-in: place it, pick a Preset, hit Play.
// The SolidOutline generated master must exist on disk (run "Generate Look Materials" if a fresh checkout).
// --------------------------------------------------------------------------------------------------------------------

class ACk_UsfGym_OutlineShowcase : AActor
{
    UPROPERTY(DefaultComponent, RootComponent)
    USceneComponent Root;

    UPROPERTY(DefaultComponent)
    UStaticMeshComponent Mesh;
    default Mesh.Mobility = EComponentMobility::Movable;
    default Mesh.RelativeScale3D = FVector(2.0, 2.0, 2.0);

    // Opaque occluder between the player (world -X) and the sphere - demonstrates configurable occlusion.
    UPROPERTY(DefaultComponent)
    UStaticMeshComponent Occluder;
    default Occluder.Mobility = EComponentMobility::Movable;
    default Occluder.RelativeLocation = FVector(-130.0, 0.0, 0.0);
    default Occluder.RelativeScale3D = FVector(0.3, 1.2, 2.5);

    // Assign one of the sample presets (CkUsf::DA_Outline_Interactable / _SeeThrough / _MaskedObjective) or your own.
    UPROPERTY()
    UCkUsf_OutlinePreset Preset = CkUsf::DA_Outline_Interactable;

    UFUNCTION(BlueprintOverride)
    void ConstructionScript()
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto SphereMesh = Cast<UStaticMesh>(LoadObject(this, "/Engine/BasicShapes/Sphere.Sphere"));
        if (SphereMesh != nullptr) { Mesh.SetStaticMesh(SphereMesh); }

        auto CubeMesh = Cast<UStaticMesh>(LoadObject(this, "/Engine/BasicShapes/Cube.Cube"));
        if (CubeMesh != nullptr) { Occluder.SetStaticMesh(CubeMesh); }
    }

    // The gym PlayerController calls this right after spawn to pick which preset this station demonstrates.
    void Request_SetPreset(UCkUsf_OutlinePreset InPreset)
    {
        Preset = InPreset;
        Apply_Outline();
    }

    UFUNCTION(BlueprintOverride)
    void BeginPlay()
    {
        auto _CkPerfScope = ck::ScopedStat();
        Apply_Outline();
    }

    private void Apply_Outline()
    {
        auto Subsystem = UCkUsf_OutlineSubsystem::Get_OutlineSubsystem();
        if (Subsystem == nullptr)
        {
            ck::Trace("CkUsf outline showcase: subsystem unavailable");
            return;
        }

        // Outline the sphere only (NOT the occluder).
        Subsystem.Apply_Outline_To_Component(Mesh, Preset);
    }
}
