// --------------------------------------------------------------------------------------------------------------------
// Drop-in demo for the CkUsf SOLID OUTLINE capability. Place this actor in a level, assign a Static Mesh to its
// Mesh component (and optionally pick a different Preset), then hit Play: the outline subsystem marks the mesh's
// custom depth/stencil and the SolidOutline post-process draws its silhouette. Move behind a wall to see the
// Normal preset hide and the SeeThrough/Masked presets persist. Capability lives in CkUsf; this is just a demo.
// --------------------------------------------------------------------------------------------------------------------

class ACk_UsfGym_OutlineShowcase : AActor
{
    UPROPERTY(DefaultComponent, RootComponent)
    UStaticMeshComponent Mesh;

    // Assign one of the sample presets (CkUsf::DA_Outline_Interactable / _SeeThrough / _MaskedObjective) or your own.
    UPROPERTY()
    UCkUsf_OutlinePreset Preset = CkUsf::DA_Outline_Interactable;

    UFUNCTION(BlueprintOverride)
    void BeginPlay()
    {
        auto Subsystem = UCkUsf_OutlineSubsystem::Get_OutlineSubsystem();
        if (Subsystem == nullptr)
        {
            ck::Trace("CkUsf outline showcase: subsystem unavailable");
            return;
        }

        Subsystem.Apply_Outline_To_Component(Mesh, Preset);
        ck::Trace("CkUsf outline showcase: applied solid outline to mesh");
    }
}
