// --------------------------------------------------------------------------------------------------------------------
// Shared judge scene for the "Stylize: Screen Dither" gym. ONE of these is spawned for the whole gym,
// because the effect is view-wide: the stations select which preset is applied, and every judgement is
// made against this one set of subjects.
//
// What each piece is FOR (a screen-dither verdict needs all four, and none of them substitutes):
//   - gradient ramp wall : 32 tinted slabs from black to white. This is where banding, palette size and
//                          dither texture are actually readable - a scene of lit props is not.
//   - dielectric spheres : dark / mid / bright albedo. Shows what the reduction does to plain surfaces
//                          at three exposures, which is where "Off must restore the frame" is judged.
//   - LitMetal spheres   : the CkUsf LitMetal look - a checker of METAL vs DIELECTRIC squares with
//                          different roughness in one mesh. Metals and smooth speculars are the first
//                          thing a palette reduction ruins, so they get their own subject.
//                          The ONE deliberate plugin-content dependency here (everything else is an
//                          engine basic shape + BasicShapeMaterial): no engine material exposes
//                          Metallic or Roughness as parameters, so without this look the scene simply
//                          cannot answer the metal question. Null-guarded - a missing master warns
//                          once and those two spheres fall back to the default material, degrading
//                          the scene rather than breaking it.
//   - rotating mover     : temporal stability. A static frame hides pattern crawl; this does not.
// The sky (or whatever fills the horizon in the gym map) is the fourth judge surface for free - a large
// smooth region is where an ordered pattern reads worst.
// --------------------------------------------------------------------------------------------------------------------

class ACk_UsfGym_StylizeDitherJudgeScene : AActor
{
    UPROPERTY(DefaultComponent, RootComponent)
    USceneComponent Root;

    // The rotating subject - assembled in BeginPlay along with everything else.
    private UStaticMeshComponent _Mover;
    private float _Elapsed = 0.0f;

    UFUNCTION(BlueprintOverride)
    void BeginPlay()
    {
        auto _CkPerfScope = ck::ScopedStat();

        Build_GradientWall();
        Build_Spheres();
        Build_Mover();
    }

    UFUNCTION(BlueprintOverride)
    void Tick(float InDeltaSeconds)
    {
        if (_Mover == nullptr)
        { return; }

        _Elapsed += InDeltaSeconds;

        // Rotation alone would leave the silhouette in place; the sideways drift is what makes a crawling
        // pixelation grid or a smearing pattern obvious.
        _Mover.SetRelativeRotation(FRotator(0.0f, _Elapsed * 60.0f, _Elapsed * 25.0f));
        _Mover.SetRelativeLocation(FVector(-400.0f, Math::Sin(_Elapsed * 0.8f) * 350.0f, 220.0f));
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
                    // Linear in albedo, not in perceived brightness: this ramp has to expose where the
                    // quantizer puts its steps, so it must not be pre-shaped by the scene author.
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

        // Two checker densities: the coarse one shows what the reduction does to a broad metal face, the
        // fine one shows whether it survives high-frequency roughness variation at all.
        Spawn_MetalSphere(SphereMesh, MetalMaster, 300.0f, 4.0f);
        Spawn_MetalSphere(SphereMesh, MetalMaster, 600.0f, 12.0f);

        if (MetalMaster == nullptr)
        {
            ck::Warning("Stylize Dither Gym: LitMetal master missing - metal/roughness spheres render as default. Run the console command 'Ck_Usf_GenerateLooks' once.");
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
        _Mover.SetRelativeScale3D(FVector(1.2f, 1.2f, 1.2f));

        if (Material != nullptr)
        {
            auto Mid = _Mover.CreateDynamicMaterialInstance(0, Material);
            if (Mid != nullptr)
            { Mid.SetVectorParameterValue(n"Color", FLinearColor(0.85f, 0.35f, 0.15f, 1.0f)); }
        }
    }
}
