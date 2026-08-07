// --------------------------------------------------------------------------------------------------------------------
// Shared judge scene for the "Stylize: Cross Hatch" gym. ONE of these is spawned for the whole gym,
// because the effect is view-wide: the stations select which preset is applied, and every judgement is
// made against this one set of subjects.
//
// What each piece is FOR (a cross-hatch verdict needs all four, and none of them substitutes):
//   - curved forms      : a sphere, two cylinders and a cone. THE headline subject. Hatching is judged on
//                         whether the strokes WRAP the form — the projected normal turns continuously
//                         across a sphere, so the lines must sweep with it. A box cannot show this: its
//                         faces each have one constant normal, so any direction looks correct on them.
//   - flat wall + boxes : the control for the above. One normal per face means one hatch direction per
//                         face, and the discontinuity AT an edge must be a clean break rather than a
//                         smear — that is where a badly derived direction shows as noise.
//   - shade ramp row    : dark / mid / bright albedo spheres, where the LAYER stepping becomes readable.
//                         Each layer owns a slice of the darkness range, so the dark sphere must carry
//                         visibly more crossing stroke fields than the bright one.
//   - mask row          : two cubes hand-tagged with the project's effect-mask Custom-Stencil value.
//                         They are the reference the entity-API subjects (CkUsfStylizeCrossHatchGym_-
//                         EntityStations.as) must be INDISTINGUISHABLE from — both front doors write the
//                         same byte, so any difference between the two rows is a bug in one of them.
//                         Placed in FRONT of the control wall and clear of the floor slab's footprint,
//                         at the same X as the entity subjects the PlayerController spawns, so each
//                         hand-tagged cube and its entity twin sit side by side in one glance from the
//                         mask stations. A pair the judge has to walk between is a pair nobody compares
//                         — that is the Cel gym's contract for this row, and it is what makes the
//                         "indistinguishable" verdict cheap enough to actually be made.
// The sky is the fifth judge surface for free: with AffectSky off it must keep its own colours entirely,
// because a sky has no form for the hatch direction to follow.
// --------------------------------------------------------------------------------------------------------------------

class ACk_UsfGym_StylizeCrossHatchJudgeScene : AActor
{
    UPROPERTY(DefaultComponent, RootComponent)
    USceneComponent Root;

    UFUNCTION(BlueprintOverride)
    void BeginPlay()
    {
        auto _CkPerfScope = ck::ScopedStat();

        Build_CurvedForms();
        Build_FlatControl();
        Build_ShadeRamp();
        Build_MaskRow();
    }

    // The headline subjects. Every one of these has a normal that turns continuously across its
    // silhouette, which is the only thing that can show whether the hatch direction follows the form or
    // is a fixed screen-space angle wearing a costume.
    private void Build_CurvedForms()
    {
        auto SphereMesh = Cast<UStaticMesh>(LoadObject(this, "/Engine/BasicShapes/Sphere.Sphere"));
        auto CylinderMesh = Cast<UStaticMesh>(LoadObject(this, "/Engine/BasicShapes/Cylinder.Cylinder"));
        auto ConeMesh = Cast<UStaticMesh>(LoadObject(this, "/Engine/BasicShapes/Cone.Cone"));
        auto Material = Cast<UMaterialInterface>(LoadObject(this, "/Engine/BasicShapes/BasicShapeMaterial.BasicShapeMaterial"));

        auto BodyColor = FLinearColor(0.52f, 0.50f, 0.47f, 1.0f);

        Spawn_Piece(SphereMesh, Material, FVector(-100.0f, -300.0f, 260.0f), FVector(2.6f, 2.6f, 2.6f), BodyColor);
        Spawn_Piece(CylinderMesh, Material, FVector(-100.0f, 100.0f, 260.0f), FVector(1.8f, 1.8f, 2.6f), BodyColor);
        Spawn_Piece(ConeMesh, Material, FVector(-100.0f, 480.0f, 240.0f), FVector(2.2f, 2.2f, 2.4f), BodyColor);

        // Lying on its side, so its curvature runs across the screen rather than around it — the two
        // orientations exercise different halves of the projected normal.
        Spawn_RotatedPiece(CylinderMesh, Material, FVector(-100.0f, 850.0f, 200.0f),
            FRotator(90.0f, 0.0f, 0.0f), FVector(1.6f, 1.6f, 3.0f), BodyColor);
    }

    // Flat faces are the control: one normal per face means one direction per face. What is being judged
    // here is the EDGE between two faces — it must be a clean discontinuity, not a smeared band.
    private void Build_FlatControl()
    {
        auto CubeMesh = Cast<UStaticMesh>(LoadObject(this, "/Engine/BasicShapes/Cube.Cube"));
        auto Material = Cast<UMaterialInterface>(LoadObject(this, "/Engine/BasicShapes/BasicShapeMaterial.BasicShapeMaterial"));

        auto StoneColor = FLinearColor(0.44f, 0.43f, 0.40f, 1.0f);
        auto FloorColor = FLinearColor(0.30f, 0.29f, 0.28f, 1.0f);

        Spawn_Piece(CubeMesh, Material, FVector(700.0f, 0.0f, 320.0f), FVector(0.5f, 14.0f, 6.5f), StoneColor);
        Spawn_Piece(CubeMesh, Material, FVector(300.0f, 0.0f, -10.0f), FVector(10.0f, 14.0f, 0.2f), FloorColor);

        // Rotated boxes: their faces meet the light and the camera at angles nothing axis-aligned does,
        // which is where a direction derived in the wrong space stops looking plausible.
        Spawn_RotatedPiece(CubeMesh, Material, FVector(320.0f, -700.0f, 180.0f),
            FRotator(0.0f, 35.0f, 0.0f), FVector(2.0f, 2.0f, 3.5f), StoneColor);
        Spawn_RotatedPiece(CubeMesh, Material, FVector(320.0f, 700.0f, 180.0f),
            FRotator(25.0f, -20.0f, 0.0f), FVector(2.0f, 2.0f, 3.5f), StoneColor);
    }

    private void Build_ShadeRamp()
    {
        auto SphereMesh = Cast<UStaticMesh>(LoadObject(this, "/Engine/BasicShapes/Sphere.Sphere"));
        auto Material = Cast<UMaterialInterface>(LoadObject(this, "/Engine/BasicShapes/BasicShapeMaterial.BasicShapeMaterial"));

        Spawn_Piece(SphereMesh, Material, FVector(-450.0f, -700.0f, 150.0f), FVector(1.8f, 1.8f, 1.8f),
            FLinearColor(0.05f, 0.05f, 0.055f, 1.0f));
        Spawn_Piece(SphereMesh, Material, FVector(-450.0f, -420.0f, 150.0f), FVector(1.8f, 1.8f, 1.8f),
            FLinearColor(0.18f, 0.18f, 0.18f, 1.0f));
        Spawn_Piece(SphereMesh, Material, FVector(-450.0f, -140.0f, 150.0f), FVector(1.8f, 1.8f, 1.8f),
            FLinearColor(0.82f, 0.80f, 0.74f, 1.0f));
    }

    // Hand-tagged with the project's effect-mask stencil value — the same byte
    // UCk_Utils_Usf_StylizeMask_UE stamps through the entity API. Requires r.CustomDepth 3.
    private void Build_MaskRow()
    {
        auto CubeMesh = Cast<UStaticMesh>(LoadObject(this, "/Engine/BasicShapes/Cube.Cube"));
        auto Material = Cast<UMaterialInterface>(LoadObject(this, "/Engine/BasicShapes/BasicShapeMaterial.BasicShapeMaterial"));

        auto MaskStencil = UCk_Utils_Usf_Stylize_Settings_UE::Get_MaskStencilValue();
        auto SubjectColor = FLinearColor(0.45f, 0.45f, 0.48f, 1.0f);

        // Read the value from the project settings rather than restating 190: a project that moves the
        // reservation must move this row with it, or the gym silently stops demonstrating anything.
        // X = -900 puts these in FRONT of the control wall (X = 700) and clear of the floor slab, which
        // spans X 300 +- 500 — at X = -450 they sat inside that footprint and were occluded from the
        // mask stations. The entity twins spawn at the SAME X, offset only in Y, so each pair reads as
        // a pair rather than as two unrelated cubes.
        for (int32 i = 0; i < 2; i++)
        {
            auto Piece = Spawn_Piece(CubeMesh, Material,
                FVector(-900.0f, 250.0f + float(i) * 640.0f, 150.0f), FVector(2.0f, 2.0f, 2.0f), SubjectColor);

            if (Piece == nullptr)
            { continue; }

            Piece.SetRenderCustomDepth(true);
            Piece.SetCustomDepthStencilValue(MaskStencil);
        }
    }

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
