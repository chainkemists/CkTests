// --------------------------------------------------------------------------------------------------------------------
// Showcase for a multi-pass (render-texture) effect: a UCkUsf_MultiPassRenderer component drives the
// Smoke feedback definition into render targets each frame; this sphere blits the output RT.
// Proves the render-to-texture pipeline capability end-to-end.
// --------------------------------------------------------------------------------------------------------------------

class ACk_UsfGym_MultiPassShowcase : AActor
{
    UPROPERTY(DefaultComponent, RootComponent)
    UStaticMeshComponent Mesh;

    default Mesh.Mobility = EComponentMobility::Movable;

    UPROPERTY(DefaultComponent)
    UCkUsf_MultiPassRenderer Renderer;

    // Assign the multi-pass definition at construction so the component's BeginPlay (which runs
    // before this actor's BeginPlay) sets up its render targets.
    default Renderer._Definition = CkUsf::Smoke;

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
        // Component BeginPlay already ran -> output RT exists. Blit it onto the sphere.
        auto BlitMID = UCk_Utils_Usf_UE::Create_MID_ForLook(CkUsf::Blit, this);
        if (BlitMID != nullptr)
        {
            auto RT = Renderer.Get_OutputRenderTarget();
            if (RT != nullptr)
            {
                BlitMID.SetTextureParameterValue(n"iChannel0", RT);
            }
            Mesh.SetMaterial(0, BlitMID);
            ck::Trace("✅ CkUsf gym: multi-pass feedback showcase live");
        }
        else
        {
            ck::Warning("❌ CkUsf gym: Blit MID failed — run 'Generate Look Materials' first");
        }
    }
}
