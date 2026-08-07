// --------------------------------------------------------------------------------------------------------------------
// Shared judge scene for the "Stylize: Hand-Drawn" gym. ONE of these is spawned for the whole gym,
// because the effect is view-wide: the stations select which preset is applied, and every judgement is
// made against this one set of subjects.
//
// What each piece is FOR (a hand-drawn verdict needs all four, and none of them substitutes):
//   - architecture block : walls, pillars and a gable. Every piece is Movable mobility (runtime-created
//                          components have to be, to take a transform at all) but NOTHING here is ever
//                          moved — that stillness is the point. This is the only subject that can answer
//                          the load-bearing question: do world-attached strokes stay glued to the
//                          surface while the camera orbits? Strokes that swim here are a broken
//                          WorldPosition reconstruction, not a badly tuned pattern.
//   - spiked silhouette  : a sphere wearing a ring of cones. Ink thresholds are judged on contour
//                          DENSITY, and a smooth prop simply does not have enough edges to tell a
//                          working normal detector from a dead one.
//   - shade ramp spheres : dark / mid / bright albedo. Where the paint's colour-region count and the
//                          shadow-stroke threshold become readable — the hatching boundary has to land
//                          on the terminator, not on the albedo change.
//   - animated mover     : the screen-stable vs world-attached comparison. Screen-stable strokes must
//                          hold on it while it translates; world-attached ones will SLIDE, which is the
//                          documented limitation and not a defect to chase.
// The sky (or whatever fills the horizon in the gym map) is the fifth judge surface for free: with
// AffectSky off it must keep its own colours while still taking the paper grain and the horizon contour.
// --------------------------------------------------------------------------------------------------------------------

class ACk_UsfGym_StylizeHandDrawnJudgeScene : AActor
{
    UPROPERTY(DefaultComponent, RootComponent)
    USceneComponent Root;

    // The translating subject — assembled in BeginPlay along with everything else.
    private UStaticMeshComponent _Mover;
    private float _Elapsed = 0.0f;

    UFUNCTION(BlueprintOverride)
    void BeginPlay()
    {
        auto _CkPerfScope = ck::ScopedStat();

        Build_Architecture();
        Build_SpikedSilhouette();
        Build_ShadeRampSpheres();
        Build_Mover();
    }

    UFUNCTION(BlueprintOverride)
    void Tick(float InDeltaSeconds)
    {
        if (_Mover == nullptr)
        { return; }

        _Elapsed += InDeltaSeconds;

        // Both a rotation and a translation: rotation alone would leave the silhouette in place, and it
        // is the TRANSLATION that makes a world-attached pattern visibly slide across the surface.
        _Mover.SetRelativeRotation(FRotator(0.0f, _Elapsed * 45.0f, _Elapsed * 20.0f));
        _Mover.SetRelativeLocation(FVector(-500.0f, Math::Sin(_Elapsed * 0.7f) * 400.0f, 200.0f));
    }

    // A little building: back wall, two pillars, a lintel across them, and a floor slab. Deliberately
    // plain boxes — a hand-drawn look is judged on how its strokes sit on flat planes meeting at hard
    // corners, which is exactly where a triplanar projection is hardest.
    private void Build_Architecture()
    {
        auto CubeMesh = Cast<UStaticMesh>(LoadObject(this, "/Engine/BasicShapes/Cube.Cube"));
        auto Material = Cast<UMaterialInterface>(LoadObject(this, "/Engine/BasicShapes/BasicShapeMaterial.BasicShapeMaterial"));

        auto StoneColor = FLinearColor(0.42f, 0.40f, 0.37f, 1.0f);
        auto FloorColor = FLinearColor(0.28f, 0.27f, 0.26f, 1.0f);

        Spawn_Piece(CubeMesh, Material, FVector(600.0f, 0.0f, 300.0f), FVector(0.5f, 12.0f, 6.0f), StoneColor);

        Spawn_Piece(CubeMesh, Material, FVector(200.0f, -450.0f, 250.0f), FVector(1.5f, 1.5f, 5.0f), StoneColor);
        Spawn_Piece(CubeMesh, Material, FVector(200.0f,  450.0f, 250.0f), FVector(1.5f, 1.5f, 5.0f), StoneColor);
        Spawn_Piece(CubeMesh, Material, FVector(200.0f,    0.0f, 540.0f), FVector(1.5f, 10.5f, 0.8f), StoneColor);

        Spawn_Piece(CubeMesh, Material, FVector(250.0f, 0.0f, -10.0f), FVector(9.0f, 12.0f, 0.2f), FloorColor);

        // Two boxes rotated into a shallow gable over the lintel: sloped planes are where a triplanar
        // blend has to hand off between axes, and where a badly weighted one smears.
        Spawn_RotatedPiece(CubeMesh, Material, FVector(200.0f, -220.0f, 640.0f),
            FRotator(35.0f, 0.0f, 0.0f), FVector(4.5f, 1.2f, 0.3f), StoneColor);
        Spawn_RotatedPiece(CubeMesh, Material, FVector(200.0f,  220.0f, 640.0f),
            FRotator(-35.0f, 0.0f, 0.0f), FVector(4.5f, 1.2f, 0.3f), StoneColor);
    }

    // A sphere wearing a ring of outward-pointing cones. Every cone contributes two silhouette edges and
    // a normal discontinuity where it meets the sphere, so the three ink detectors each have something to
    // find that the other two do not.
    private void Build_SpikedSilhouette()
    {
        auto SphereMesh = Cast<UStaticMesh>(LoadObject(this, "/Engine/BasicShapes/Sphere.Sphere"));
        auto ConeMesh = Cast<UStaticMesh>(LoadObject(this, "/Engine/BasicShapes/Cone.Cone"));
        auto Material = Cast<UMaterialInterface>(LoadObject(this, "/Engine/BasicShapes/BasicShapeMaterial.BasicShapeMaterial"));

        auto Center = FVector(-100.0f, 700.0f, 260.0f);
        auto BodyColor = FLinearColor(0.55f, 0.50f, 0.45f, 1.0f);

        Spawn_Piece(SphereMesh, Material, Center, FVector(1.6f, 1.6f, 1.6f), BodyColor);

        const int32 SpikeCount = 12;
        const float SpikeRadius = 110.0f;

        for (int32 i = 0; i < SpikeCount; i++)
        {
            auto Angle = float(i) / float(SpikeCount) * 360.0f;
            auto Direction = FRotator(0.0f, Angle, 0.0f).ForwardVector;

            // Rolled 90 degrees so the cone's axis lies along the outward direction instead of pointing
            // at the sky — a ring of upright cones would give the detectors one repeated edge, not a
            // silhouette.
            Spawn_RotatedPiece(ConeMesh, Material, Center + Direction * SpikeRadius,
                FRotator(0.0f, Angle, 90.0f), FVector(0.55f, 0.55f, 1.1f), BodyColor);
        }
    }

    private void Build_ShadeRampSpheres()
    {
        auto SphereMesh = Cast<UStaticMesh>(LoadObject(this, "/Engine/BasicShapes/Sphere.Sphere"));
        auto Material = Cast<UMaterialInterface>(LoadObject(this, "/Engine/BasicShapes/BasicShapeMaterial.BasicShapeMaterial"));

        Spawn_Piece(SphereMesh, Material, FVector(-250.0f, -700.0f, 160.0f), FVector(2.0f, 2.0f, 2.0f),
            FLinearColor(0.05f, 0.05f, 0.055f, 1.0f));
        Spawn_Piece(SphereMesh, Material, FVector(-250.0f, -400.0f, 160.0f), FVector(2.0f, 2.0f, 2.0f),
            FLinearColor(0.18f, 0.18f, 0.18f, 1.0f));
        Spawn_Piece(SphereMesh, Material, FVector(-250.0f, -100.0f, 160.0f), FVector(2.0f, 2.0f, 2.0f),
            FLinearColor(0.82f, 0.80f, 0.74f, 1.0f));
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
        _Mover.SetRelativeScale3D(FVector(1.6f, 1.6f, 1.6f));

        if (Material != nullptr)
        {
            auto Mid = _Mover.CreateDynamicMaterialInstance(0, Material);
            if (Mid != nullptr)
            { Mid.SetVectorParameterValue(n"Color", FLinearColor(0.60f, 0.32f, 0.20f, 1.0f)); }
        }
    }

    // Named for what it places, not what shape it places: the architecture uses cubes, the silhouette
    // uses a sphere and cones, and all of them are the same axis-aligned spawn.
    private UStaticMeshComponent Spawn_Piece(UStaticMesh InMesh, UMaterialInterface InMaterial,
        FVector InLocation, FVector InScale, FLinearColor InColor)
    {
        return Spawn_RotatedPiece(InMesh, InMaterial, InLocation, FRotator::ZeroRotator, InScale, InColor);
    }

    private UStaticMeshComponent Spawn_RotatedPiece(UStaticMesh InMesh, UMaterialInterface InMaterial,
        FVector InLocation, FRotator InRotation, FVector InScale, FLinearColor InColor)
    {
        auto Piece = UStaticMeshComponent::Create(this);
        if (Piece == nullptr)
        { return nullptr; }

        if (InMesh != nullptr) { Piece.SetStaticMesh(InMesh); }
        Piece.SetMobility(EComponentMobility::Movable);
        Piece.SetCollisionEnabled(ECollisionEnabled::NoCollision);
        Piece.SetRelativeLocation(InLocation);
        Piece.SetRelativeRotation(InRotation);
        Piece.SetRelativeScale3D(InScale);

        if (InMaterial != nullptr)
        {
            auto Mid = Piece.CreateDynamicMaterialInstance(0, InMaterial);
            if (Mid != nullptr)
            { Mid.SetVectorParameterValue(n"Color", InColor); }
        }

        return Piece;
    }
}
