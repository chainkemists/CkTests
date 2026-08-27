//============================================================================
// CkGymStation
//
// Procedural alcove station - built from scaled /Engine/BasicShapes/Cube
// instances, no mesh-asset dependencies. Replaces BP_DemoDisplay's pre-baked
// tile system with code-driven geometry that's fully parametric.
//
// Visual structure (looking down at the alcove from above):
//
//        -X (back, where back wall is)
//         ^
//         |
//      +-------+
//      | back  |
//      | wall  |
//      |       |
//   +Y |       | -Y    (Width spans Y axis)
//   <- |       | ->
//      | floor |
//      +-------+
//        front opening
//         |
//         v
//        +X (front, where viewer + agents are)
//
// The alcove is an open-front "drive-in" structure:
//   - Back wall at -X end (deepest from viewer)
//   - Floor stage at Z=0 spanning the alcove
//   - Roof at Z=Height*100 spanning the alcove
//   - Side walls at Y=+/-Width*50 forming the left/right
//   - Open front at +X (viewer side)
//   - Optional base trim sitting in front of the alcove opening
//
// Pivot conventions:
//   - Actor pivot is at (0, 0, 0) - ground centre of the alcove footprint.
//   - Alcove extends from X=-Depth*50 (back wall) to X=+Depth*50 (front opening)
//     and from Y=-Width*50 to Y=+Width*50.
//   - All anchor components live in actor-local space.
//
// Why +X is "front": ACk_GymStation actors are typically placed deep in the
// scene (e.g., at world -X) and the player approaches from world +X looking
// toward -X. With the alcove opening toward +X relative to the actor, the
// player walks straight into the opening and sees the back wall.
//
// Width/Depth/Height are in 100xcm units (so Width=6 -> 600cm). Thickness
// parameters (WallThickness, RoofThickness, FloorThickness) are in cm.
//============================================================================

class ACk_GymStation : AActor
{
	default bReplicates = true;
	default bReplicateUsingRegisteredSubObjectList = true;
	default bAlwaysRelevant = true;

	//------------------------------------------------------------------------
	// Components
	//------------------------------------------------------------------------

	UPROPERTY(DefaultComponent, RootComponent)
	USceneComponent DefaultSceneRoot;

	// Alcove pieces - all default-component static-mesh instances using the engine Cube.
	// Their RelativeLocation/Rotation/Scale are computed in ConstructionScript.
	UPROPERTY(DefaultComponent, Attach = DefaultSceneRoot) UStaticMeshComponent BackWall;
	UPROPERTY(DefaultComponent, Attach = DefaultSceneRoot) UStaticMeshComponent LeftWall;
	UPROPERTY(DefaultComponent, Attach = DefaultSceneRoot) UStaticMeshComponent RightWall;
	UPROPERTY(DefaultComponent, Attach = DefaultSceneRoot) UStaticMeshComponent FloorStage;
	UPROPERTY(DefaultComponent, Attach = DefaultSceneRoot) UStaticMeshComponent Roof;
	UPROPERTY(DefaultComponent, Attach = DefaultSceneRoot) UStaticMeshComponent BaseTrim;

	// Text render - title + description on the alcove's back wall, facing +X (toward viewer).
	UPROPERTY(DefaultComponent, Attach = DefaultSceneRoot)
	UTextRenderComponent TitleText_Component;

	UPROPERTY(DefaultComponent, Attach = DefaultSceneRoot)
	UTextRenderComponent DescriptionText_Component;

	// Spotlight - optional, illuminates the alcove from inside.
	UPROPERTY(DefaultComponent, Attach = DefaultSceneRoot)
	USpotLightComponent Spotlight_Component;

	//------------------------------------------------------------------------
	// SceneNode anchors - public hooks for placement logic.
	// All in actor-local space. Read via .GetWorldLocation().
	//------------------------------------------------------------------------

	UPROPERTY(DefaultComponent, Attach = DefaultSceneRoot) USceneComponent FootprintCenterAnchor;
	UPROPERTY(DefaultComponent, Attach = DefaultSceneRoot) USceneComponent AgentSpawnFrontAnchor;
	UPROPERTY(DefaultComponent, Attach = DefaultSceneRoot) USceneComponent AgentSpawnLeftAnchor;
	UPROPERTY(DefaultComponent, Attach = DefaultSceneRoot) USceneComponent AgentSpawnRightAnchor;
	UPROPERTY(DefaultComponent, Attach = DefaultSceneRoot) USceneComponent AgentSpawnBackAnchor;
	UPROPERTY(DefaultComponent, Attach = DefaultSceneRoot) USceneComponent PanelTopFrontAnchor;
	UPROPERTY(DefaultComponent, Attach = DefaultSceneRoot) USceneComponent PanelCenterAnchor;

	//------------------------------------------------------------------------
	// Properties
	//------------------------------------------------------------------------

	// Alcove dimensions - 100xcm units.
	UPROPERTY(Category = "Alcove") double Width = 6.0;
	UPROPERTY(Category = "Alcove") double Depth = 5.0;
	UPROPERTY(Category = "Alcove") double Height = 5.0;

	// Wall thicknesses - cm.
	UPROPERTY(Category = "Alcove") double WallThickness = 15.0;
	UPROPERTY(Category = "Alcove") double FloorThickness = 15.0;
	UPROPERTY(Category = "Alcove") double RoofThickness = 25.0;

	// Base trim - small bar in front of the alcove opening.
	UPROPERTY(Category = "Alcove") double BaseTrimDepth = 50.0;        // cm; how deep the bar is along X
	UPROPERTY(Category = "Alcove") double BaseTrimWidth = 7.0;         // 100xcm units; usually slightly wider than alcove
	UPROPERTY(Category = "Alcove") double BaseTrimHeight = 30.0;       // cm; vertical thickness
	UPROPERTY(Category = "Alcove") double BaseTrimForwardOffset = 30.0; // cm; gap between alcove front and the trim

	// Spotlight + text-orientation toggles.
	UPROPERTY(Category = "Alcove") bool ShowSpotlight = true;
	UPROPERTY(Category = "Alcove") bool FloorText = false;

	// Title + description text.
	UPROPERTY(Category = "Title") FText TitleText = FText::FromString("Title");
	UPROPERTY(Category = "Title") double TitleScale = 20.0;
	UPROPERTY(Category = "Title") FColor TitleColour = FColor(255, 255, 255, 255);

	UPROPERTY(Category = "Description") TArray<FText> DescriptionText;
	UPROPERTY(Category = "Description") double DescriptionScale = 12.0;
	UPROPERTY(Category = "Description") FColor DescriptionColour = FColor(255, 255, 255, 255);
	UPROPERTY(Category = "Description") int32 LinesBetweenParagraphs = 1;
	UPROPERTY(Category = "Description") int32 SpacesBetweenLines = 0;
	UPROPERTY(Category = "Description") EHorizTextAligment TextAlignment = EHorizTextAligment::EHTA_Left;

	//------------------------------------------------------------------------
	// ConstructionScript - entry point. Re-runs in editor on every property
	// change AND at runtime spawn time.
	//------------------------------------------------------------------------

	UFUNCTION(BlueprintOverride)
	void ConstructionScript()
	{
	    auto _CkPerfScope = ck::ScopedStat();
		if (DescriptionText.IsEmpty())
		{
			DescriptionText.Add(FText::FromString("Example paragraph line 1"));
			DescriptionText.Add(FText::FromString("Example paragraph line 2"));
		}

		Setup_Cubes();
		Build_Alcove();
		Position_TextComponents();
		Apply_TextContent();
		Configure_Spotlight();
		Update_Anchors();
	}

	//------------------------------------------------------------------------
	// Update_Display - runtime API for gym scripts.
	//------------------------------------------------------------------------

	UFUNCTION()
	void Update_Display(FText InTitle, TArray<FText> InDescription)
	{
		TitleText = InTitle;
		DescriptionText = InDescription;
		Apply_TextContent();
	}

	//========================================================================
	// Internal helpers
	//========================================================================

	private void Setup_Cubes()
	{
		auto Cube = Cast<UStaticMesh>(LoadObject(this, "/Engine/BasicShapes/Cube.Cube"));
		if (Cube == nullptr) { return; }

		BackWall.SetStaticMesh(Cube);
		LeftWall.SetStaticMesh(Cube);
		RightWall.SetStaticMesh(Cube);
		FloorStage.SetStaticMesh(Cube);
		Roof.SetStaticMesh(Cube);
		BaseTrim.SetStaticMesh(Cube);
	}

	//------------------------------------------------------------------------
	// Build_Alcove - places the 6 box pieces according to the dimension params.
	//
	// Coordinate system (actor-local):
	//   - X: -Depth/2*100 (back wall) to +Depth/2*100 (front opening)
	//   - Y: -Width/2*100 to +Width/2*100
	//   - Z: 0 (floor) to +Height*100 (top of back wall / roof)
	//
	// Cube mesh is 100x100x100 cm centred at the component origin, so
	// scale_X = size_in_cm / 100, etc.
	//------------------------------------------------------------------------
	private void Build_Alcove()
	{
		const auto W_cm = Width * 100.0;
		const auto D_cm = Depth * 100.0;
		const auto H_cm = Height * 100.0;

		const auto WT = WallThickness;          // cm
		const auto FT = FloorThickness;
		const auto RT = RoofThickness;

		// Back wall: thin slab at -X end, full Width x full Height.
		BackWall.SetRelativeLocation(FVector(-D_cm * 0.5 + WT * 0.5, 0.0, H_cm * 0.5));
		BackWall.SetRelativeRotation(FRotator::ZeroRotator);
		BackWall.SetRelativeScale3D(FVector(WT / 100.0, Width, Height));

		// Left wall (+Y side): thin slab spanning full Depth x full Height.
		LeftWall.SetRelativeLocation(FVector(0.0, W_cm * 0.5 - WT * 0.5, H_cm * 0.5));
		LeftWall.SetRelativeRotation(FRotator::ZeroRotator);
		LeftWall.SetRelativeScale3D(FVector(Depth, WT / 100.0, Height));

		// Right wall (-Y side): mirror of LeftWall.
		RightWall.SetRelativeLocation(FVector(0.0, -W_cm * 0.5 + WT * 0.5, H_cm * 0.5));
		RightWall.SetRelativeRotation(FRotator::ZeroRotator);
		RightWall.SetRelativeScale3D(FVector(Depth, WT / 100.0, Height));

		// Floor stage: flat slab whose TOP face sits at actor-local Z=0, extending DOWN to Z=-FT.
		// This makes the actor's anchor coincide with the walkable surface - so when the gym
		// places the station at world Z=0 (DefaultStationGridZ), the floor's top is flush with
		// the world floor / navmesh height instead of poking up by FT cm and penetrating
		// path waypoints + agent capsules that ride on world Z=0.
		FloorStage.SetRelativeLocation(FVector(0.0, 0.0, -FT * 0.5));
		FloorStage.SetRelativeRotation(FRotator::ZeroRotator);
		FloorStage.SetRelativeScale3D(FVector(Depth, Width, FT / 100.0));

		// Roof: flat slab at Z=Height*100, full Width x full Depth.
		Roof.SetRelativeLocation(FVector(0.0, 0.0, H_cm - RT * 0.5));
		Roof.SetRelativeRotation(FRotator::ZeroRotator);
		Roof.SetRelativeScale3D(FVector(Depth, Width, RT / 100.0));

		// Base trim: small bar in front of the alcove opening (toward +X).
		const auto TrimCenterX = D_cm * 0.5 + BaseTrimForwardOffset + BaseTrimDepth * 0.5;
		BaseTrim.SetRelativeLocation(FVector(TrimCenterX, 0.0, BaseTrimHeight * 0.5));
		BaseTrim.SetRelativeRotation(FRotator::ZeroRotator);
		BaseTrim.SetRelativeScale3D(FVector(BaseTrimDepth / 100.0, BaseTrimWidth, BaseTrimHeight / 100.0));
	}

	//------------------------------------------------------------------------
	// Position_TextComponents - text sits on the back wall's inner face
	// (which faces +X, toward the viewer at the front opening).
	//
	// Back wall is at X = -Depth/2*100. Inner face (toward viewer) is at
	// X = -Depth/2*100 + WallThickness. Text is placed slightly in front
	// of that face (toward +X) to avoid z-fighting.
	//
	// Default UTextRender at rotation (0,0,0) already faces +X, which is
	// exactly what we want - no Yaw flip needed.
	//------------------------------------------------------------------------
	private void Position_TextComponents()
	{
		const auto IsFloorText = FloorText || Height < 2.0;

		const auto BackWallInnerX = -Depth * 50.0 + WallThickness;
		const auto TextX = BackWallInnerX + 5.0;   // 5cm into the alcove, toward viewer

		const auto PanelTopZ = (IsFloorText ? Depth : Height) * 100.0;
		const auto DescZ = PanelTopZ - (TitleScale + 60.0);
		const auto TitleZ = PanelTopZ - (TitleScale + 60.0) / 2.0;

		// Description.
		const auto DescY = TextAlignmentOffset(1.0, false);
		// Floor-text mode: text sits 5cm above the floor's top. With FloorStage relocated so its
		// top is at actor-local Z=0 (see Build_Alcove), 5cm above the surface is just Z=5 - no
		// FloorThickness component needed any more.
		const auto DescLocation = IsFloorText
			? FVector(0.0, DescY, 5.0)
			: FVector(TextX, DescY, DescZ);

		const auto DescRotation = IsFloorText
			? FRotator(90.0, 0.0, 0.0)
			: FRotator(0.0, 0.0, 0.0);

		DescriptionText_Component.SetRelativeLocation(DescLocation);
		DescriptionText_Component.SetRelativeRotation(DescRotation);
		DescriptionText_Component.HorizontalAlignment = TextAlignment;
		DescriptionText_Component.WorldSize = float(DescriptionScale);
		DescriptionText_Component.TextRenderColor = DescriptionColour;
		DescriptionText_Component.VerticalAlignment = IsFloorText
			? EVerticalTextAligment::EVRTA_TextBottom
			: EVerticalTextAligment::EVRTA_TextTop;

		// Title.
		const auto TitleLocation = IsFloorText
			? FVector(0.0, TextAlignmentOffset(1.0, false), 5.0)
			: FVector(TextX, TextAlignmentOffset(1.0, false), TitleZ);

		const auto TitleRotation = IsFloorText
			? FRotator(90.0, 0.0, 0.0)
			: FRotator(0.0, 0.0, 0.0);

		TitleText_Component.SetRelativeLocation(TitleLocation);
		TitleText_Component.SetRelativeRotation(TitleRotation);
		TitleText_Component.HorizontalAlignment = TextAlignment;
		TitleText_Component.WorldSize = float(TitleScale);
		TitleText_Component.TextRenderColor = TitleColour;
		TitleText_Component.VerticalAlignment = EVerticalTextAligment::EVRTA_TextTop;
	}

	// Mirrors BP "Text Alignment Offset" macro - Y offset for text based on
	// alignment + width adjustment. EHTA_Left -> +Y, EHTA_Right -> -Y, Center -> 0.
	private double TextAlignmentOffset(double InWidthAdjustment, bool InForceCenter)
	{
		const auto Effective = InForceCenter ? EHorizTextAligment::EHTA_Center : TextAlignment;
		const auto Magnitude = ((Width - InWidthAdjustment) * 0.5) * 100.0;

		if (Effective == EHorizTextAligment::EHTA_Center) { return 0.0; }
		if (Effective == EHorizTextAligment::EHTA_Left)   { return Magnitude; }
		return -Magnitude;
	}

	private void Apply_TextContent()
	{
		TitleText_Component.SetText(TitleText);
		DescriptionText_Component.SetText(Format_DescriptionText());
	}

	private FText Format_DescriptionText()
	{
		auto Result = "";
		const auto LineCount = DescriptionText.Num();

		for (int i = 0; i < LineCount; ++i)
		{
			Result = f"{Result}{DescriptionText[i].ToString()}";

			const auto IsLast = (i == LineCount - 1);
			if (IsLast == false)
			{
				for (int p = 0; p < LinesBetweenParagraphs; ++p) { Result = f"{Result}\n"; }
				for (int s = 0; s < SpacesBetweenLines; ++s)     { Result = f"{Result} "; }
			}
		}

		return FText::FromString(Result);
	}

	//------------------------------------------------------------------------
	// Configure_Spotlight - illuminates the back wall from inside the alcove.
	//------------------------------------------------------------------------
	private void Configure_Spotlight()
	{
		Spotlight_Component.SetVisibility(ShowSpotlight, false);
		if (ShowSpotlight == false) { return; }

		// Position the spotlight near the front opening, aimed at the back wall.
		// Front opening is at +Depth*50; back wall at -Depth*50.
		const auto SpotX = Depth * 30.0;           // 30% of half-depth toward front opening
		const auto SpotZ = Height * 90.0;          // near the top of the alcove

		Spotlight_Component.SetRelativeLocation(FVector(SpotX, 0.0, SpotZ));

		// Aim toward -X (back wall) and slightly down. Default light aims +X, so
		// Yaw=180 flips it to -X; Pitch=-30 angles down a bit.
		Spotlight_Component.SetRelativeRotation(FRotator(-30.0, 180.0, 0.0));
	}

	//------------------------------------------------------------------------
	// Update_Anchors - recomputes RelativeLocation on each anchor based on the
	// current alcove dimensions. Anchors are in actor-local space.
	//------------------------------------------------------------------------
	private void Update_Anchors()
	{
		const auto W_cm = Width * 100.0;
		const auto D_cm = Depth * 100.0;
		const auto H_cm = Height * 100.0;

		// Footprint centre of the alcove on the ground.
		FootprintCenterAnchor.SetRelativeLocation(FVector(0.0, 0.0, 0.0));

		// Spawn anchors - ground level, 100cm beyond the alcove footprint edge.
		// "Front" = the alcove opening (+X). "Back" = behind the back wall (-X).
		AgentSpawnFrontAnchor.SetRelativeLocation(FVector( D_cm * 0.5 + 100.0, 0.0, 0.0));
		AgentSpawnBackAnchor.SetRelativeLocation(FVector(-D_cm * 0.5 - 100.0, 0.0, 0.0));
		AgentSpawnLeftAnchor.SetRelativeLocation(FVector(0.0,  W_cm * 0.5 + 100.0, 0.0));
		AgentSpawnRightAnchor.SetRelativeLocation(FVector(0.0, -W_cm * 0.5 - 100.0, 0.0));

		// Alcove face anchors. PanelTopFront is at the front opening's top edge.
		PanelTopFrontAnchor.SetRelativeLocation(FVector(D_cm * 0.5, 0.0, H_cm));
		PanelCenterAnchor.SetRelativeLocation(FVector(0.0, 0.0, H_cm * 0.5));
	}
}
