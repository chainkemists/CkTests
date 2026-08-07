// --------------------------------------------------------------------------------------------------------------------
// Shared judge scene for the "Stylize: Cel Shade" gym. ONE of these is spawned for the whole gym, because
// the effect is view-wide: the stations select which preset is applied, and every judgement is made
// against this one set of subjects.
//
// What each piece is FOR (a cel verdict needs all of them, and none substitutes for another):
//   - gradient ramp wall : 32 albedo slabs from black to white under one light. Bands and their spacing
//                          are readable here and almost nowhere else. It is ALSO the illumination test:
//                          the reconstruction divides SceneColor by BaseColor, so a correct one puts the
//                          SAME band boundaries across every slab; boundaries that follow the albedo ramp
//                          instead mean the reconstruction failed and QuantizeFinalColor is the fallback.
//   - dielectric spheres : dark / mid / bright albedo. Curved surfaces are where band SHAPE reads, and
//                          where "Off must restore the frame" is judged.
//   - LitMetal spheres   : the CkUsf LitMetal look — a checker of METAL vs DIELECTRIC squares at
//                          different roughness in one mesh. The coarse one is the Metallic group's
//                          subject (metals get their light from reflections, so the illumination
//                          reconstruction is worst there); the fine one is the stepped-specular subject
//                          (its smooth squares fall under the roughness cutoff, its rough ones do not).
//                          The ONE deliberate plugin-content dependency here: no engine material exposes
//                          Metallic or Roughness as parameters. Null-guarded — a missing master warns
//                          once and those spheres fall back to the default material.
//   - backlit figure     : a capsule with a bright light BEHIND it. Rim light is the one feature that
//                          cannot be judged on a front-lit subject at all.
//   - stencil row        : four cubes — an untagged control plus one at the suppress value, one at
//                          RoundDots and one at DiagonalLines. The per-object contract is a claim about
//                          neighbouring meshes differing, so it needs them side by side.
//   - translating mover  : the documented world-space limitation. A post-process pass has no frame
//                          history, so a world-anchored pattern SLIDES across a translating mesh; this
//                          is here to make that visible rather than to hide it.
// --------------------------------------------------------------------------------------------------------------------

class ACk_UsfGym_StylizeCelJudgeScene : AActor
{
    UPROPERTY(DefaultComponent, RootComponent)
    USceneComponent Root;

    private UStaticMeshComponent _Mover;
    private TArray<UStaticMeshComponent> _StencilMeshes;
    private float _Elapsed = 0.0f;

    UFUNCTION(BlueprintOverride)
    void BeginPlay()
    {
        auto _CkPerfScope = ck::ScopedStat();

        Build_GradientWall();
        Build_Spheres();
        Build_BacklitFigure();
        Build_StencilRow();
        Build_Mover();
    }

    UFUNCTION(BlueprintOverride)
    void Tick(float InDeltaSeconds)
    {
        if (_Mover == nullptr)
        { return; }

        _Elapsed += InDeltaSeconds;

        // Rotation alone would leave the silhouette in place; the sideways drift is what makes a
        // world-anchored pattern visibly slide across the surface.
        _Mover.SetRelativeRotation(FRotator(0.0f, _Elapsed * 45.0f, _Elapsed * 20.0f));
        _Mover.SetRelativeLocation(FVector(-400.0f, Math::Sin(_Elapsed * 0.7f) * 350.0f, 240.0f));
    }

    // The stencil values are resolved from the LIVE settings rather than hardcoded, so a preset that moves
    // the base keeps this row correct instead of silently tagging meshes with unrelated values.
    void Request_RefreshStencilRow()
    {
        auto Subsystem = UCkUsf_CelShadeSubsystem::Get_CelShadeSubsystem();
        if (Subsystem == nullptr || _StencilMeshes.Num() < 4)
        { return; }

        Apply_Stencil(_StencilMeshes[1], Subsystem.Get_StencilSuppressValue());
        Apply_Stencil(_StencilMeshes[2], Subsystem.Get_StencilValueFor(ECk_Usf_CelPattern::RoundDots));
        Apply_Stencil(_StencilMeshes[3], Subsystem.Get_StencilValueFor(ECk_Usf_CelPattern::DiagonalLines));
    }

    private void Apply_Stencil(UStaticMeshComponent InMesh, int32 InValue)
    {
        if (InMesh == nullptr)
        { return; }

        // 0 means the stencil contract is switched off in the current settings — writing it would tag the
        // mesh with the engine's "nothing here" value and read as if the row simply stopped working.
        if (InValue == 0)
        {
            InMesh.SetRenderCustomDepth(false);
            return;
        }

        InMesh.SetRenderCustomDepth(true);
        InMesh.SetCustomDepthStencilValue(InValue);
    }

    private void Build_GradientWall()
    {
        const int32 GradientSlabCount = 32;
        const float GradientSlabWidth = 40.0f;

        auto CubeMesh = Cast<UStaticMesh>(LoadObject(this, "/Engine/BasicShapes/Cube.Cube"));
        auto SlabMaterial = Cast<UMaterialInterface>(LoadObject(this, "/Engine/BasicShapes/BasicShapeMaterial.BasicShapeMaterial"));

        auto StartY = -(GradientSlabCount - 1) * GradientSlabWidth * 0.5f;

        for (int32 i = 0; i < GradientSlabCount; i++)
        {
            auto Slab = UStaticMeshComponent::Create(this);
            if (Slab == nullptr)
            { continue; }

            if (CubeMesh != nullptr) { Slab.SetStaticMesh(CubeMesh); }
            Slab.SetMobility(EComponentMobility::Movable);
            Slab.SetCollisionEnabled(ECollisionEnabled::NoCollision);
            Slab.SetRelativeLocation(FVector(0.0f, StartY + i * GradientSlabWidth, 250.0f));
            Slab.SetRelativeScale3D(FVector(0.15f, GradientSlabWidth / 100.0f, 5.0f));

            if (SlabMaterial != nullptr)
            {
                auto Mid = Slab.CreateDynamicMaterialInstance(0, SlabMaterial);
                if (Mid != nullptr)
                {
                    // Linear in ALBEDO. The whole point is that the light on this wall is uniform while
                    // the albedo is not — so a light-driven band boundary runs straight across it.
                    auto T = float(i) / float(GradientSlabCount - 1);
                    Mid.SetVectorParameterValue(n"Color", FLinearColor(T, T, T, 1.0f));
                }
            }
        }
    }

    private void Build_Spheres()
    {
        auto SphereMesh = Cast<UStaticMesh>(LoadObject(this, "/Engine/BasicShapes/Sphere.Sphere"));
        auto FlatMaterial = Cast<UMaterialInterface>(LoadObject(this, "/Engine/BasicShapes/BasicShapeMaterial.BasicShapeMaterial"));
        auto MetalMaster = Cast<UMaterialInterface>(
            LoadObject(this, "/CkFoundation/CkUsf/GeneratedLooks/M_CkUsf_Look_LitMetal.M_CkUsf_Look_LitMetal"));

        Spawn_FlatSphere(SphereMesh, FlatMaterial, -600.0f, FLinearColor(0.04f, 0.04f, 0.045f, 1.0f));
        Spawn_FlatSphere(SphereMesh, FlatMaterial, -300.0f, FLinearColor(0.18f, 0.18f, 0.18f, 1.0f));
        Spawn_FlatSphere(SphereMesh, FlatMaterial,    0.0f, FLinearColor(0.80f, 0.78f, 0.72f, 1.0f));

        Spawn_MetalSphere(SphereMesh, MetalMaster, 300.0f, 4.0f);
        Spawn_MetalSphere(SphereMesh, MetalMaster, 600.0f, 12.0f);

        if (MetalMaster == nullptr)
        {
            ck::Warning("Stylize Cel Gym: LitMetal master missing — the metallic/specular spheres render as default. Run the console command 'Ck_Usf_GenerateLooks' once.");
        }
    }

    private void Spawn_FlatSphere(UStaticMesh InMesh, UMaterialInterface InMaterial, float InY, FLinearColor InColor)
    {
        auto Sphere = Make_Sphere(InMesh, InY);
        if (Sphere == nullptr || InMaterial == nullptr)
        { return; }

        auto Mid = Sphere.CreateDynamicMaterialInstance(0, InMaterial);
        if (Mid != nullptr)
        { Mid.SetVectorParameterValue(n"Color", InColor); }
    }

    private void Spawn_MetalSphere(UStaticMesh InMesh, UMaterialInterface InMaster, float InY, float InTiles)
    {
        auto Sphere = Make_Sphere(InMesh, InY);
        if (Sphere == nullptr || InMaster == nullptr)
        { return; }

        auto Mid = Sphere.CreateDynamicMaterialInstance(0, InMaster);
        if (Mid != nullptr)
        { Mid.SetScalarParameterValue(n"Tiles", InTiles); }
    }

    private UStaticMeshComponent Make_Sphere(UStaticMesh InMesh, float InY)
    {
        auto Sphere = UStaticMeshComponent::Create(this);
        if (Sphere == nullptr)
        { return nullptr; }

        if (InMesh != nullptr) { Sphere.SetStaticMesh(InMesh); }
        Sphere.SetMobility(EComponentMobility::Movable);
        Sphere.SetCollisionEnabled(ECollisionEnabled::NoCollision);
        Sphere.SetRelativeLocation(FVector(-350.0f, InY, 120.0f));
        Sphere.SetRelativeScale3D(FVector(2.0f, 2.0f, 2.0f));
        return Sphere;
    }

    private void Build_BacklitFigure()
    {
        auto CylinderMesh = Cast<UStaticMesh>(LoadObject(this, "/Engine/BasicShapes/Cylinder.Cylinder"));
        auto Material = Cast<UMaterialInterface>(LoadObject(this, "/Engine/BasicShapes/BasicShapeMaterial.BasicShapeMaterial"));

        auto Figure = UStaticMeshComponent::Create(this);
        if (Figure == nullptr)
        { return; }

        if (CylinderMesh != nullptr) { Figure.SetStaticMesh(CylinderMesh); }
        Figure.SetMobility(EComponentMobility::Movable);
        Figure.SetCollisionEnabled(ECollisionEnabled::NoCollision);
        Figure.SetRelativeLocation(FVector(-750.0f, -900.0f, 200.0f));
        Figure.SetRelativeScale3D(FVector(1.2f, 1.2f, 3.5f));

        if (Material != nullptr)
        {
            auto Mid = Figure.CreateDynamicMaterialInstance(0, Material);
            if (Mid != nullptr)
            { Mid.SetVectorParameterValue(n"Color", FLinearColor(0.22f, 0.20f, 0.24f, 1.0f)); }
        }

        // BEHIND the figure relative to the station row, so the lit edge is a rim and not a key light.
        // Without this the rim-light controls have nothing to act on and every preset looks identical
        // in that respect.
        auto BackLight = UPointLightComponent::Create(this);
        if (BackLight == nullptr)
        { return; }

        BackLight.SetMobility(EComponentMobility::Movable);
        BackLight.SetRelativeLocation(FVector(-1400.0f, -900.0f, 300.0f));
        BackLight.SetIntensity(80000.0f);
        BackLight.SetAttenuationRadius(2500.0f);
        BackLight.SetLightColor(FLinearColor(1.0f, 0.92f, 0.78f, 1.0f));
    }

    private void Build_StencilRow()
    {
        auto CubeMesh = Cast<UStaticMesh>(LoadObject(this, "/Engine/BasicShapes/Cube.Cube"));
        auto Material = Cast<UMaterialInterface>(LoadObject(this, "/Engine/BasicShapes/BasicShapeMaterial.BasicShapeMaterial"));

        for (int32 i = 0; i < 4; i++)
        {
            auto Cube = UStaticMeshComponent::Create(this);
            if (Cube == nullptr)
            { continue; }

            if (CubeMesh != nullptr) { Cube.SetStaticMesh(CubeMesh); }
            Cube.SetMobility(EComponentMobility::Movable);
            Cube.SetCollisionEnabled(ECollisionEnabled::NoCollision);
            Cube.SetRelativeLocation(FVector(-700.0f, -300.0f + i * 300.0f, 130.0f));
            Cube.SetRelativeScale3D(FVector(2.0f, 2.0f, 2.0f));

            if (Material != nullptr)
            {
                auto Mid = Cube.CreateDynamicMaterialInstance(0, Material);
                if (Mid != nullptr)
                {
                    // All four share one albedo on purpose: any difference between them then comes from
                    // the stencil contract and from nothing else.
                    Mid.SetVectorParameterValue(n"Color", FLinearColor(0.45f, 0.45f, 0.48f, 1.0f));
                }
            }

            _StencilMeshes.Add(Cube);
        }

        Request_RefreshStencilRow();
    }

    private void Build_Mover()
    {
        auto CubeMesh = Cast<UStaticMesh>(LoadObject(this, "/Engine/BasicShapes/Cube.Cube"));
        auto Material = Cast<UMaterialInterface>(LoadObject(this, "/Engine/BasicShapes/BasicShapeMaterial.BasicShapeMaterial"));

        _Mover = UStaticMeshComponent::Create(this);
        if (_Mover == nullptr)
        { return; }

        if (CubeMesh != nullptr) { _Mover.SetStaticMesh(CubeMesh); }
        _Mover.SetMobility(EComponentMobility::Movable);
        _Mover.SetCollisionEnabled(ECollisionEnabled::NoCollision);
        _Mover.SetRelativeScale3D(FVector(1.4f, 1.4f, 1.4f));

        if (Material != nullptr)
        {
            auto Mid = _Mover.CreateDynamicMaterialInstance(0, Material);
            if (Mid != nullptr)
            { Mid.SetVectorParameterValue(n"Color", FLinearColor(0.75f, 0.42f, 0.20f, 1.0f)); }
        }
    }
}
