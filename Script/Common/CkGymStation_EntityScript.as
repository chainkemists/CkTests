//============================================================================
// CkGymStation_EntityScript
//
// Pure-ECS GymStation. The station entity is the root of a SceneNode hierarchy;
// every visible piece (body geometry, text, spotlight) and every anchor is its
// own child SceneNode entity, with a UActorComponent attached via CkUnrealComponent.
//
// No Actor is involved. SceneNode propagation flows the station's world
// transform through the hierarchy; CkUnrealComponent's PushTransform processor
// mirrors each child's world transform onto its component every tick. Moving
// the station via Request_SetTransform automatically propagates to every piece.
//
// Geometry conventions:
//   - Pivot at alcove centre on the ground (Z=0).
//   - Alcove opens toward +X (player approaches from world +X looking -X).
//   - Width along Y, Depth along X, Height along Z.
//   - Width / Depth / Height in 100×cm units (Width=6 → 600cm).
//   - WallThickness / FloorThickness / TrimDepth in cm.
//
// Pieces (lit + opaque, lit by /Engine/BasicShapes/Cube's BasicShapeMaterial):
//   - Back wall + floor stage (BodyColour)
//   - Four trim pieces framing the back wall (TrimColour)
//   - Title + description text on the back wall (UTextRenderComponent)
//   - Floor description text reading from above (Pitch=90)
//   - Spotlight illuminating the back wall (USpotLightComponent)
//
// Anchors:
//   - 7 anchor SceneNodes are always created — they are the canonical
//     world-position source for Get_*WorldLocation() getters. The getters
//     read the SceneNode's world transform via utils_transform.
//   - When ShowAnchors=true, each anchor SceneNode also gets a small PMG
//     sphere visual via Add_Sphere. Cyan for the 4 agent-spawn anchors,
//     magenta for the 3 panel/footprint anchors.
//
// Lifecycle:
//   - DoConstruct: build SceneNode hierarchy + attach all components + setup
//     anchor visuals if requested. Component setup is async — OnAdded
//     handlers configure each component once Setup processor instantiates it.
//   - DoEndPlay: nothing manual. SceneNode children cascade-destroy with the
//     station; each child entity's CkUnrealComponent EndPlay processor tears
//     down the component.
//
// Coexistence note: ACk_GymStation (the static-mesh actor in CkGymStation.as)
// remains in use by ACk_NavigationGym_GameMode::BeginPlay until that gym is
// migrated to spawn UCk_EntityScript_GymStation directly.
//============================================================================

// Where the floor description sits along the alcove's depth (X axis).
//   Front  → toward +X (the alcove opening)
//   Center → middle of the floor stage along X
//   Back   → toward -X (against the back wall)
// Y position is controlled by FloorTextAlignment, mirroring wall-text behaviour.
UENUM()
enum ECk_GymStation_FloorTextPlacement
{
	Front,
	Center,
	Back
}

USTRUCT()
struct FCk_GymStation_SpawnParams
{
	UPROPERTY()
	FTransform InitialTransform = FTransform::Identity;

	// Alcove dimensions — 100×cm units.
	UPROPERTY() double Width = 6.0;
	UPROPERTY() double Depth = 5.0;
	UPROPERTY() double Height = 5.0;

	// Wall thicknesses — cm.
	UPROPERTY() double WallThickness = 15.0;
	UPROPERTY() double FloorThickness = 15.0;

	// How far the trim pieces extend forward from the back wall — cm.
	UPROPERTY() double TrimDepth = 30.0;

	// How far past the alcove edge each agent-spawn anchor sits — cm.
	// 0 = anchor sits right on the alcove footprint edge. Increase for clearance
	// when spawning physical test agents that shouldn't clip the trim.
	UPROPERTY() double AgentSpawnOffset = 0.0;

	// Body colour for the back wall + floor stage.
	UPROPERTY() FLinearColor BodyColour = FLinearColor(0.02, 0.02, 0.02, 1.0);

	// Trim colour for the four frame pieces — lighter grey by default.
	UPROPERTY() FLinearColor TrimColour = FLinearColor(0.3, 0.3, 0.3, 1.0);

	// Title.
	UPROPERTY() FText TitleText = FText::FromString("Title");
	UPROPERTY() double TitleScale = 20.0;
	UPROPERTY() FColor TitleColour = FColor(255, 255, 255, 255);

	// Description (back wall).
	UPROPERTY() TArray<FText> DescriptionText;
	UPROPERTY() double DescriptionScale = 12.0;
	UPROPERTY() FColor DescriptionColour = FColor(255, 255, 255, 255);
	UPROPERTY() EHorizTextAligment TextAlignment = EHorizTextAligment::EHTA_Left;

	// Floor description (optional). Empty array = no floor text rendered.
	UPROPERTY() TArray<FText> FloorDescriptionText;
	UPROPERTY() double FloorDescriptionScale = 12.0;
	UPROPERTY() FColor FloorDescriptionColour = FColor(255, 255, 255, 255);
	UPROPERTY() EHorizTextAligment FloorTextAlignment = EHorizTextAligment::EHTA_Center;
	UPROPERTY() ECk_GymStation_FloorTextPlacement FloorTextPlacement = ECk_GymStation_FloorTextPlacement::Center;

	// Toggles.
	UPROPERTY() bool ShowSpotlight = true;
	UPROPERTY() bool ShowAnchors = false;
}

// ====================================================================================================================

class UCk_EntityScript_GymStation : UCk_GenericEntityScript_UE
{
	default _Replication = ECk_Replication::DoesNotReplicate;

	UPROPERTY(ExposeOnSpawn) FTransform InitialTransform = FTransform::Identity;

	UPROPERTY(ExposeOnSpawn) double Width = 6.0;
	UPROPERTY(ExposeOnSpawn) double Depth = 5.0;
	UPROPERTY(ExposeOnSpawn) double Height = 5.0;

	UPROPERTY(ExposeOnSpawn) double WallThickness = 15.0;
	UPROPERTY(ExposeOnSpawn) double FloorThickness = 15.0;

	UPROPERTY(ExposeOnSpawn) double TrimDepth = 30.0;
	UPROPERTY(ExposeOnSpawn) double AgentSpawnOffset = 0.0;

	UPROPERTY(ExposeOnSpawn) FLinearColor BodyColour = FLinearColor(0.02, 0.02, 0.02, 1.0);
	UPROPERTY(ExposeOnSpawn) FLinearColor TrimColour = FLinearColor(0.3, 0.3, 0.3, 1.0);

	UPROPERTY(ExposeOnSpawn) FText TitleText = FText::FromString("Title");
	UPROPERTY(ExposeOnSpawn) double TitleScale = 20.0;
	UPROPERTY(ExposeOnSpawn) FColor TitleColour = FColor(255, 255, 255, 255);

	UPROPERTY(ExposeOnSpawn) TArray<FText> DescriptionText;
	UPROPERTY(ExposeOnSpawn) double DescriptionScale = 12.0;
	UPROPERTY(ExposeOnSpawn) FColor DescriptionColour = FColor(255, 255, 255, 255);
	UPROPERTY(ExposeOnSpawn) EHorizTextAligment TextAlignment = EHorizTextAligment::EHTA_Left;

	UPROPERTY(ExposeOnSpawn) TArray<FText> FloorDescriptionText;
	UPROPERTY(ExposeOnSpawn) double FloorDescriptionScale = 12.0;
	UPROPERTY(ExposeOnSpawn) FColor FloorDescriptionColour = FColor(255, 255, 255, 255);
	UPROPERTY(ExposeOnSpawn) EHorizTextAligment FloorTextAlignment = EHorizTextAligment::EHTA_Center;
	UPROPERTY(ExposeOnSpawn) ECk_GymStation_FloorTextPlacement FloorTextPlacement = ECk_GymStation_FloorTextPlacement::Center;

	UPROPERTY(ExposeOnSpawn) bool ShowSpotlight = true;
	UPROPERTY(ExposeOnSpawn) bool ShowAnchors = false;

	// Body component handles — used by OnBodyMeshAdded/OnTrimMeshAdded to
	// disambiguate which piece fired the callback (since one handler serves
	// multiple pieces of the same type).
	private FCk_Handle_UnrealComponent _BackWallHandle;
	private FCk_Handle_UnrealComponent _FloorStageHandle;
	private FCk_Handle_UnrealComponent _LeftTrimHandle;
	private FCk_Handle_UnrealComponent _RightTrimHandle;
	private FCk_Handle_UnrealComponent _TopTrimHandle;
	private FCk_Handle_UnrealComponent _BottomTrimHandle;

	// Text + spotlight component handles.
	private FCk_Handle_UnrealComponent _TitleHandle;
	private FCk_Handle_UnrealComponent _DescriptionHandle;
	private FCk_Handle_UnrealComponent _FloorDescriptionHandle;
	private FCk_Handle_UnrealComponent _SpotlightHandle;

	// Anchor SceneNodes — always created; queried by Get_*WorldLocation getters.
	private FCk_Handle_SceneNode _AnchorFootprintCenter;
	private FCk_Handle_SceneNode _AnchorAgentSpawnFront;
	private FCk_Handle_SceneNode _AnchorAgentSpawnBack;
	private FCk_Handle_SceneNode _AnchorAgentSpawnLeft;
	private FCk_Handle_SceneNode _AnchorAgentSpawnRight;
	private FCk_Handle_SceneNode _AnchorPanelTopFront;
	private FCk_Handle_SceneNode _AnchorPanelCenter;

	//------------------------------------------------------------------------
	// Lifecycle
	//------------------------------------------------------------------------

	UFUNCTION(BlueprintOverride)
	ECk_EntityScript_ConstructionFlow
	DoConstruct(FCk_Handle& InHandle)
	{
		auto StationTH = utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);

		Build_Body(StationTH);
		Build_Text(StationTH);
		Build_Spotlight(StationTH);
		Build_Anchors(StationTH);

		if (ShowAnchors)
		{
			Build_AnchorVisuals(InHandle);
		}

		return ECk_EntityScript_ConstructionFlow::Finished;
	}

	// DoEndPlay intentionally omitted — SceneNode children cascade-destroy with
	// the station entity, and the CkUnrealComponent EndPlay processor tears down
	// each child's component when its entity dies.

	//========================================================================
	// Body — back wall, floor stage, four trims.
	//========================================================================

	private void Build_Body(FCk_Handle_Transform& InStationTH)
	{
		const auto W_cm = Width * 100.0;
		const auto D_cm = Depth * 100.0;
		const auto H_cm = Height * 100.0;

		const auto WT = WallThickness;
		const auto FT = FloorThickness;

		// Back wall: thin slab at -X end, full Width × full Height.
		_BackWallHandle = Spawn_StaticMeshPiece(InStationTH, n"BackWall", n"OnBodyMeshAdded",
			FVector(-D_cm * 0.5 + WT * 0.5, 0.0, H_cm * 0.5),
			FVector(WT / 100.0, Width, Height));

		// Floor stage at Z=0.
		_FloorStageHandle = Spawn_StaticMeshPiece(InStationTH, n"FloorStage", n"OnBodyMeshAdded",
			FVector(0.0, 0.0, FT * 0.5),
			FVector(Depth, Width, FT / 100.0));

		// Trim — picture-frame around the back wall, flush with the back wall's
		// front face, projecting forward by TrimDepth.
		const auto TrimCenterX = -D_cm * 0.5 + WT + TrimDepth * 0.5;

		_LeftTrimHandle = Spawn_StaticMeshPiece(InStationTH, n"LeftTrim", n"OnTrimMeshAdded",
			FVector(TrimCenterX, W_cm * 0.5 - WT * 0.5, H_cm * 0.5),
			FVector(TrimDepth / 100.0, WT / 100.0, Height));

		_RightTrimHandle = Spawn_StaticMeshPiece(InStationTH, n"RightTrim", n"OnTrimMeshAdded",
			FVector(TrimCenterX, -W_cm * 0.5 + WT * 0.5, H_cm * 0.5),
			FVector(TrimDepth / 100.0, WT / 100.0, Height));

		_TopTrimHandle = Spawn_StaticMeshPiece(InStationTH, n"TopTrim", n"OnTrimMeshAdded",
			FVector(TrimCenterX, 0.0, H_cm - WT * 0.5),
			FVector(TrimDepth / 100.0, Width, WT / 100.0));

		_BottomTrimHandle = Spawn_StaticMeshPiece(InStationTH, n"BottomTrim", n"OnTrimMeshAdded",
			FVector(TrimCenterX, 0.0, FT + WT * 0.5),
			FVector(TrimDepth / 100.0, Width, WT / 100.0));
	}

	private FCk_Handle_UnrealComponent Spawn_StaticMeshPiece(
		FCk_Handle_Transform& InStationTH,
		FName InDebugName,
		FName InOnAddedHandler,
		FVector InLocalLocation,
		FVector InLocalScale)
	{
		auto LocalTransform = FTransform(FRotator::ZeroRotator, InLocalLocation, InLocalScale);
		auto PieceSCN = utils_scene_node::Create(InStationTH, LocalTransform);
		auto PieceTH = PieceSCN.As_Transform();
		auto PieceEntity = FCk_Handle(PieceTH);

		auto Params = FCk_Fragment_UnrealComponent_ParamsData(UStaticMeshComponent);
		Params.Set_TickPolicy(ECk_UnrealComponent_TickPolicy::DoNotTick);
		Params.Set_DebugName(InDebugName);

		auto ComponentHandle = utils_unreal_component::Add(PieceEntity, Params);

		utils_unreal_component::BindTo_OnAdded(
			ComponentHandle,
			FCk_Delegate_UnrealComponent_OnAdded(this, InOnAddedHandler));

		return ComponentHandle;
	}

	UFUNCTION()
	private void OnBodyMeshAdded(FCk_Handle_UnrealComponent InHandle)
	{
		Configure_StaticMesh(InHandle, BodyColour);
	}

	UFUNCTION()
	private void OnTrimMeshAdded(FCk_Handle_UnrealComponent InHandle)
	{
		Configure_StaticMesh(InHandle, TrimColour);
	}

	private void Configure_StaticMesh(FCk_Handle_UnrealComponent InHandle, FLinearColor InColour)
	{
		auto Comp = utils_unreal_component::Get_Component(InHandle);
		auto Mesh = Cast<UStaticMeshComponent>(Comp);
		if (Mesh == nullptr) { return; }

		auto Cube = Cast<UStaticMesh>(LoadObject(this, "/Engine/BasicShapes/Cube.Cube"));
		if (Cube != nullptr) { Mesh.SetStaticMesh(Cube); }

		Mesh.SetCollisionEnabled(ECollisionEnabled::NoCollision);

		auto MID = Mesh.CreateDynamicMaterialInstance(0);
		if (MID != nullptr)
		{
			MID.SetVectorParameterValue(n"Color", InColour);
		}
	}

	//========================================================================
	// Text — title + description on back wall, optional floor description.
	//========================================================================

	private void Build_Text(FCk_Handle_Transform& InStationTH)
	{
		const auto BackWallInnerX = -Depth * 50.0 + WallThickness;
		const auto TextX = BackWallInnerX + 5.0;          // 5cm in front of inner face
		const auto PanelTopZ = Height * 100.0;
		const auto DescZ  = PanelTopZ - (TitleScale + 60.0);
		const auto TitleZ = PanelTopZ - (TitleScale + 60.0) / 2.0;
		const auto TextY = TextAlignmentOffset(TextAlignment, 1.0);

		_TitleHandle = Spawn_TextPiece(InStationTH, n"TitleText", n"OnTitleAdded",
			FVector(TextX, TextY, TitleZ),
			FRotator::ZeroRotator);

		_DescriptionHandle = Spawn_TextPiece(InStationTH, n"DescriptionText", n"OnDescriptionAdded",
			FVector(TextX, TextY, DescZ),
			FRotator::ZeroRotator);

		// Floor description is created unconditionally; the OnAdded handler hides
		// the component when FloorDescriptionText is empty.
		const auto FloorTopZ = FloorThickness + 2.0;
		const auto FloorX = FloorPlacementOffset(1.0);
		const auto FloorY = TextAlignmentOffset(FloorTextAlignment, 1.0);

		_FloorDescriptionHandle = Spawn_TextPiece(InStationTH, n"FloorDescriptionText", n"OnFloorDescriptionAdded",
			FVector(FloorX, FloorY, FloorTopZ),
			FRotator(90.0, 0.0, 0.0));
	}

	private FCk_Handle_UnrealComponent Spawn_TextPiece(
		FCk_Handle_Transform& InStationTH,
		FName InDebugName,
		FName InOnAddedHandler,
		FVector InLocalLocation,
		FRotator InLocalRotation)
	{
		auto LocalTransform = FTransform(InLocalRotation, InLocalLocation, FVector(1.0, 1.0, 1.0));
		auto PieceSCN = utils_scene_node::Create(InStationTH, LocalTransform);
		auto PieceTH = PieceSCN.As_Transform();
		auto PieceEntity = FCk_Handle(PieceTH);

		auto Params = FCk_Fragment_UnrealComponent_ParamsData(UTextRenderComponent);
		Params.Set_TickPolicy(ECk_UnrealComponent_TickPolicy::DoNotTick);
		Params.Set_DebugName(InDebugName);

		auto ComponentHandle = utils_unreal_component::Add(PieceEntity, Params);

		utils_unreal_component::BindTo_OnAdded(
			ComponentHandle,
			FCk_Delegate_UnrealComponent_OnAdded(this, InOnAddedHandler));

		return ComponentHandle;
	}

	UFUNCTION()
	private void OnTitleAdded(FCk_Handle_UnrealComponent InHandle)
	{
		auto Text = Cast<UTextRenderComponent>(utils_unreal_component::Get_Component(InHandle));
		if (Text == nullptr) { return; }

		Text.SetText(TitleText);
		Text.SetWorldSize(float(TitleScale));
		Text.SetTextRenderColor(TitleColour);
		Text.SetHorizontalAlignment(TextAlignment);
		Text.SetVerticalAlignment(EVerticalTextAligment::EVRTA_TextTop);
	}

	UFUNCTION()
	private void OnDescriptionAdded(FCk_Handle_UnrealComponent InHandle)
	{
		auto Text = Cast<UTextRenderComponent>(utils_unreal_component::Get_Component(InHandle));
		if (Text == nullptr) { return; }

		Text.SetText(Format_MultilineText(DescriptionText));
		Text.SetWorldSize(float(DescriptionScale));
		Text.SetTextRenderColor(DescriptionColour);
		Text.SetHorizontalAlignment(TextAlignment);
		Text.SetVerticalAlignment(EVerticalTextAligment::EVRTA_TextTop);
	}

	UFUNCTION()
	private void OnFloorDescriptionAdded(FCk_Handle_UnrealComponent InHandle)
	{
		auto Text = Cast<UTextRenderComponent>(utils_unreal_component::Get_Component(InHandle));
		if (Text == nullptr) { return; }

		const auto HasFloorText = FloorDescriptionText.Num() > 0;
		Text.SetVisibility(HasFloorText, false);
		if (HasFloorText == false) { return; }

		Text.SetText(Format_MultilineText(FloorDescriptionText));
		Text.SetWorldSize(float(FloorDescriptionScale));
		Text.SetTextRenderColor(FloorDescriptionColour);
		Text.SetHorizontalAlignment(FloorTextAlignment);
		Text.SetVerticalAlignment(EVerticalTextAligment::EVRTA_TextCenter);
	}

	// Y offset for text based on the given alignment + width adjustment.
	// EHTA_Left → +Y, EHTA_Right → -Y, Center → 0.
	private double TextAlignmentOffset(EHorizTextAligment InAlignment, double InWidthAdjustment)
	{
		const auto Magnitude = ((Width - InWidthAdjustment) * 0.5) * 100.0;

		if (InAlignment == EHorizTextAligment::EHTA_Center) { return 0.0; }
		if (InAlignment == EHorizTextAligment::EHTA_Left)   { return Magnitude; }
		return -Magnitude;
	}

	// X offset for the floor text based on FloorTextPlacement + depth adjustment.
	// Front → +X (toward opening), Back → -X (toward back wall), Center → 0.
	private double FloorPlacementOffset(double InDepthAdjustment)
	{
		const auto Magnitude = ((Depth - InDepthAdjustment) * 0.5) * 100.0;

		if (FloorTextPlacement == ECk_GymStation_FloorTextPlacement::Center) { return 0.0; }
		if (FloorTextPlacement == ECk_GymStation_FloorTextPlacement::Front)  { return Magnitude; }
		return -Magnitude;
	}

	private FText Format_MultilineText(TArray<FText> InLines)
	{
		auto Result = "";
		const auto LineCount = InLines.Num();

		for (int i = 0; i < LineCount; ++i)
		{
			Result = f"{Result}{InLines[i].ToString()}";
			if (i < LineCount - 1)
			{
				Result = f"{Result}\n";
			}
		}

		return FText::FromString(Result);
	}

	//========================================================================
	// Spotlight — illuminates the back wall from inside the alcove.
	//========================================================================

	private void Build_Spotlight(FCk_Handle_Transform& InStationTH)
	{
		const auto SpotX = Depth * 30.0;     // 30% of half-depth toward front opening
		const auto SpotZ = Height * 90.0;    // near the top of the alcove

		// Default spotlight aims +X. Yaw=180 flips to -X (toward back wall);
		// Pitch=-30 angles down a bit.
		auto LocalTransform = FTransform(FRotator(-30.0, 180.0, 0.0), FVector(SpotX, 0.0, SpotZ), FVector(1.0, 1.0, 1.0));
		auto PieceSCN = utils_scene_node::Create(InStationTH, LocalTransform);
		auto PieceTH = PieceSCN.As_Transform();
		auto PieceEntity = FCk_Handle(PieceTH);

		auto Params = FCk_Fragment_UnrealComponent_ParamsData(USpotLightComponent);
		Params.Set_TickPolicy(ECk_UnrealComponent_TickPolicy::DoNotTick);
		Params.Set_DebugName(n"Spotlight");

		_SpotlightHandle = utils_unreal_component::Add(PieceEntity, Params);

		utils_unreal_component::BindTo_OnAdded(
			_SpotlightHandle,
			FCk_Delegate_UnrealComponent_OnAdded(this, n"OnSpotlightAdded"));
	}

	UFUNCTION()
	private void OnSpotlightAdded(FCk_Handle_UnrealComponent InHandle)
	{
		auto Light = Cast<USpotLightComponent>(utils_unreal_component::Get_Component(InHandle));
		if (Light == nullptr) { return; }

		Light.SetVisibility(ShowSpotlight, false);
		if (ShowSpotlight == false) { return; }

		Light.SetIntensity(50000.0);
		Light.SetAttenuationRadius(2000.0);
		Light.SetInnerConeAngle(20.0);
		Light.SetOuterConeAngle(40.0);
	}

	//========================================================================
	// Anchors — 7 SceneNodes always created. They are the canonical
	// world-position source for Get_*WorldLocation() getters.
	//========================================================================

	private void Build_Anchors(FCk_Handle_Transform& InStationTH)
	{
		const auto W_cm = Width * 100.0;
		const auto D_cm = Depth * 100.0;
		const auto H_cm = Height * 100.0;

		_AnchorFootprintCenter  = Make_AnchorSCN(InStationTH, FVector(0.0, 0.0, 0.0));
		_AnchorAgentSpawnFront  = Make_AnchorSCN(InStationTH, FVector( D_cm * 0.5 + AgentSpawnOffset, 0.0, 0.0));
		_AnchorAgentSpawnBack   = Make_AnchorSCN(InStationTH, FVector(-D_cm * 0.5 - AgentSpawnOffset, 0.0, 0.0));
		_AnchorAgentSpawnLeft   = Make_AnchorSCN(InStationTH, FVector(0.0,  W_cm * 0.5 + AgentSpawnOffset, 0.0));
		_AnchorAgentSpawnRight  = Make_AnchorSCN(InStationTH, FVector(0.0, -W_cm * 0.5 - AgentSpawnOffset, 0.0));
		_AnchorPanelTopFront    = Make_AnchorSCN(InStationTH, FVector(D_cm * 0.5, 0.0, H_cm));
		_AnchorPanelCenter      = Make_AnchorSCN(InStationTH, FVector(0.0, 0.0, H_cm * 0.5));
	}

	private FCk_Handle_SceneNode Make_AnchorSCN(FCk_Handle_Transform& InStationTH, FVector InLocalLocation)
	{
		auto LocalTransform = FTransform(FRotator::ZeroRotator, InLocalLocation, FVector(1.0, 1.0, 1.0));
		return utils_scene_node::Create(InStationTH, LocalTransform);
	}

	// Spawns a small filled PMG sphere per anchor for in-world visualisation.
	// Cyan for the 4 agent-spawn anchors; magenta for footprint + panel anchors.
	//
	// We use Create_Sphere (spawns a fresh child entity owned by the station)
	// rather than Add_Sphere (which would ENSURE — Add_Sphere internally calls
	// utils_transform::Add, but the anchor SCNs already have Transform fragments
	// from utils_scene_node::Create).
	//
	// World transforms are computed manually from InitialTransform × LocalOffset
	// because at DoConstruct time the SceneNode propagation processor hasn't yet
	// written world transforms to the anchor SCNs — so Get_EntityCurrentLocation
	// would return stale values.
	//
	// Trade-off: spheres are positioned once and won't follow the station if it
	// moves later. Acceptable for a static showcase; revisit if stations become
	// mobile.
	private void Build_AnchorVisuals(FCk_Handle& InStation)
	{
		// PMG idiom: translucent fill (alpha 0.35) + wireframe overlay so the
		// underlying station geometry stays readable through the marker.
		const auto AgentColour = FLinearColor(0.0, 1.0, 1.0, 0.35);   // cyan
		const auto PanelColour = FLinearColor(1.0, 0.0, 1.0, 0.35);   // magenta
		const auto Radius = 20.0f;

		const auto W_cm = Width * 100.0;
		const auto D_cm = Depth * 100.0;
		const auto H_cm = Height * 100.0;

		Create_AnchorSphere(InStation, FVector( D_cm * 0.5 + AgentSpawnOffset, 0.0, 0.0), AgentColour, Radius);
		Create_AnchorSphere(InStation, FVector(-D_cm * 0.5 - AgentSpawnOffset, 0.0, 0.0), AgentColour, Radius);
		Create_AnchorSphere(InStation, FVector(0.0,  W_cm * 0.5 + AgentSpawnOffset, 0.0), AgentColour, Radius);
		Create_AnchorSphere(InStation, FVector(0.0, -W_cm * 0.5 - AgentSpawnOffset, 0.0), AgentColour, Radius);
		Create_AnchorSphere(InStation, FVector(0.0, 0.0, 0.0),                            PanelColour, Radius);
		Create_AnchorSphere(InStation, FVector(D_cm * 0.5, 0.0, H_cm),                    PanelColour, Radius);
		Create_AnchorSphere(InStation, FVector(0.0, 0.0, H_cm * 0.5),                     PanelColour, Radius);
	}

	private void Create_AnchorSphere(FCk_Handle& InOwner, FVector InLocalLocation, FLinearColor InColour, float InRadius)
	{
		const auto WorldLoc = InitialTransform.TransformPosition(InLocalLocation);
		const auto WorldRot = InitialTransform.Rotator();
		const auto WorldT = FTransform(WorldRot, WorldLoc, FVector(1.0, 1.0, 1.0));

		UCk_Utils_Pmg_BasicShapes::Create_Sphere(
			InOwner,
			WorldT,
			InRadius,
			16,                       // Segments
			16,                       // Rings
			ECk_Plane_Axis::XY,
			InColour,
			true,                     // InDrawLines = true — wireframe overlay (PMG idiom)
			2.0f,                     // InLineThickness
			-1.0f);                   // InDuration = -1.0f for persistent
	}

	//========================================================================
	// Anchor world-position getters — read each anchor SCN's current world
	// transform via the framework's transform util. SceneNode propagation
	// keeps these correct even if the station moves.
	//========================================================================

	UFUNCTION()
	FVector Get_FootprintCenterWorldLocation()
	{ return utils_transform::Get_EntityCurrentLocation(_AnchorFootprintCenter.As_Transform()); }

	UFUNCTION()
	FVector Get_AgentSpawnFrontWorldLocation()
	{ return utils_transform::Get_EntityCurrentLocation(_AnchorAgentSpawnFront.As_Transform()); }

	UFUNCTION()
	FVector Get_AgentSpawnBackWorldLocation()
	{ return utils_transform::Get_EntityCurrentLocation(_AnchorAgentSpawnBack.As_Transform()); }

	UFUNCTION()
	FVector Get_AgentSpawnLeftWorldLocation()
	{ return utils_transform::Get_EntityCurrentLocation(_AnchorAgentSpawnLeft.As_Transform()); }

	UFUNCTION()
	FVector Get_AgentSpawnRightWorldLocation()
	{ return utils_transform::Get_EntityCurrentLocation(_AnchorAgentSpawnRight.As_Transform()); }

	UFUNCTION()
	FVector Get_PanelTopFrontWorldLocation()
	{ return utils_transform::Get_EntityCurrentLocation(_AnchorPanelTopFront.As_Transform()); }

	UFUNCTION()
	FVector Get_PanelCenterWorldLocation()
	{ return utils_transform::Get_EntityCurrentLocation(_AnchorPanelCenter.As_Transform()); }
}
