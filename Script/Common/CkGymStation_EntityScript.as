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

// Named anchor positions on a GymStation. Pass one to Get_AnchorWorldLocation
// (on the EntityScript) or to ACk_Gym_Base_PlayerController::Get_StationAnchorLocation
// (cross-gym helper) to retrieve the corresponding world position.
//
// Quick guide for picking one:
//   - FootprintCenter — alcove pivot on the floor (Z=0). Use for nav/physics/spatial
//     tests where elements need to sit on the navmesh.
//   - PanelCenter     — geometric centre of the alcove at mid-height. Use for
//     debug-shape tests so visual elements sit inside the alcove without
//     intersecting back wall / floor / trim. Default for most gyms.
//   - PanelTopFront   — top edge of the front opening. Marker / banner attach point.
//   - AgentSpawn{Front,Back,Left,Right} — perimeter anchors that respect AgentSpawnOffset.
UENUM()
enum ECk_GymStation_Anchor
{
	FootprintCenter,
	AgentSpawnFront,
	AgentSpawnBack,
	AgentSpawnLeft,
	AgentSpawnRight,
	PanelTopFront,
	PanelCenter
}

// Snapshot of all seven anchor world positions, populated by the GymStation
// EntityScript in DoConstruct. Lives on the station entity so any gym script
// can read the positions via Handle.Get_Fragment(FCkGym_Station_Anchors)
// without needing access to the EntityScript instance.
//
// Note: snapshot is computed at construction from InitialTransform × local
// offsets. If a station is moved at runtime, this fragment goes stale (the
// EntityScript's per-tick math via Get_EntityCurrentLocation stays correct,
// but the cross-gym fragment-based read does not). Acceptable for static
// stations, which is the current case for every gym.
USTRUCT()
struct FCkGym_Station_Anchors
{
	UPROPERTY() FVector FootprintCenter = FVector::ZeroVector;
	UPROPERTY() FVector AgentSpawnFront = FVector::ZeroVector;
	UPROPERTY() FVector AgentSpawnBack  = FVector::ZeroVector;
	UPROPERTY() FVector AgentSpawnLeft  = FVector::ZeroVector;
	UPROPERTY() FVector AgentSpawnRight = FVector::ZeroVector;
	UPROPERTY() FVector PanelTopFront   = FVector::ZeroVector;
	UPROPERTY() FVector PanelCenter     = FVector::ZeroVector;
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
	UPROPERTY() EHorizTextAligment FloorTextAlignment = EHorizTextAligment::EHTA_Left;
	UPROPERTY() ECk_GymStation_FloorTextPlacement FloorTextPlacement = ECk_GymStation_FloorTextPlacement::Front;

	// Toggles.
	UPROPERTY() bool ShowSpotlight = true;
	UPROPERTY() bool ShowAnchors = false;

	// Debug overlays — when true, draws a translucent wireframe PMG box at
	// each piece's *expected* world transform (computed from InitialTransform
	// + the local-offset math). If a piece's actual rendered geometry doesn't
	// match its overlay, the resize plumbing is broken for that piece.
	// Distinct colour per piece type.
	UPROPERTY() bool ShowDebugOverlays = false;

	// When true, Width and Height are computed from the title + description
	// text content at spawn AND grown at runtime if a fragment update via
	// CkGym_Common::Update_StationDisplay would overflow the alcove. The
	// Width / Height fields above are ignored when AutoSize=true. Grow-only:
	// the alcove never shrinks, eliminating frame-to-frame "pulsing".
	UPROPERTY() bool AutoSize = false;

	// Tags to apply to the spawned station entity (via utils_entity_tag::Add)
	// so the base PC's Get_StationHandle / Get_StationTransform can find it
	// later by tag. Set by CkGym_Common::Request_SpawnNewStation when
	// translating from FCkGym_Station_SpawnParams_Payload; you don't normally
	// set this directly.
	UPROPERTY() TArray<FName> StationTags;
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
	UPROPERTY(ExposeOnSpawn) EHorizTextAligment FloorTextAlignment = EHorizTextAligment::EHTA_Left;
	UPROPERTY(ExposeOnSpawn) ECk_GymStation_FloorTextPlacement FloorTextPlacement = ECk_GymStation_FloorTextPlacement::Front;

	UPROPERTY(ExposeOnSpawn) bool ShowSpotlight = true;
	UPROPERTY(ExposeOnSpawn) bool ShowAnchors = false;
	UPROPERTY(ExposeOnSpawn) bool ShowDebugOverlays = false;
	UPROPERTY(ExposeOnSpawn) bool AutoSize = false;
	UPROPERTY(ExposeOnSpawn) TArray<FName> StationTags;

	// Cached fragment values for the display watcher. Compared each tick
	// against the FCkGym_Station_TitleAndDescription fragment on this entity;
	// when a field changes, the corresponding text component is re-applied.
	private FText _CachedTitle;
	private FText _CachedDescription;
	private FText _CachedInstructions;

	// Body component handles — used by OnBodyMeshAdded/OnTrimMeshAdded to
	// disambiguate which piece fired the callback (since one handler serves
	// multiple pieces of the same type).
	private FCk_Handle_UnrealComponent _BackWallHandle;
	private FCk_Handle_UnrealComponent _FloorStageHandle;
	private FCk_Handle_UnrealComponent _LeftTrimHandle;
	private FCk_Handle_UnrealComponent _RightTrimHandle;
	private FCk_Handle_UnrealComponent _TopTrimHandle;
	private FCk_Handle_UnrealComponent _BottomTrimHandle;

	// Body SceneNode handles — stored directly so resize updates the right
	// SCN every time. (Get_OwningEntity → As_SceneNode chain proved unreliable
	// during runtime resizes — partial-update bugs that left the floor at
	// the new size while the back wall stayed at the old.)
	private FCk_Handle_SceneNode _BackWallSCN;
	private FCk_Handle_SceneNode _FloorStageSCN;
	private FCk_Handle_SceneNode _LeftTrimSCN;
	private FCk_Handle_SceneNode _RightTrimSCN;
	private FCk_Handle_SceneNode _TopTrimSCN;
	private FCk_Handle_SceneNode _BottomTrimSCN;

	// Text + spotlight component handles + their SceneNodes.
	private FCk_Handle_UnrealComponent _TitleHandle;
	private FCk_Handle_UnrealComponent _DescriptionHandle;
	private FCk_Handle_UnrealComponent _FloorDescriptionHandle;
	private FCk_Handle_UnrealComponent _SpotlightHandle;
	private FCk_Handle_SceneNode _TitleSCN;
	private FCk_Handle_SceneNode _DescriptionSCN;
	private FCk_Handle_SceneNode _FloorDescriptionSCN;
	private FCk_Handle_SceneNode _SpotlightSCN;

	// PMG handles for debug overlays (when ShowDebugOverlays=true).
	private TArray<FCk_Handle_Pmg_DebugShape> _DebugOverlays;

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
		// Compute auto-size from spawn-params text BEFORE building geometry,
		// so Width/Height reflect the content from frame zero.
		if (AutoSize)
		{
			Apply_AutoSize_FromSpawnParams();
		}

		auto StationTH = utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);

		Build_Body(StationTH);
		Build_Text(StationTH);
		Build_Spotlight(StationTH);
		Build_Anchors(StationTH);
		Populate_AnchorsFragment(InHandle);

		if (ShowAnchors)
		{
			Build_AnchorVisuals(InHandle);
		}

		if (ShowDebugOverlays)
		{
			Build_DebugOverlays(InHandle);
		}

		// Tag the station entity so the base PC's Get_StationHandle /
		// Get_StationTransform can find it later by tag.
		for (auto Tag : StationTags)
		{
			utils_entity_tag::Add(InHandle, Tag);
		}

		// Watch the FCkGym_Station_TitleAndDescription fragment so directors
		// calling CkGym_Common::Update_StationDisplay get reflected in the
		// text components.
		utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"OnDisplayTick"));

		return ECk_EntityScript_ConstructionFlow::Finished;
	}

	// Snapshot the seven anchor world positions into a fragment on the station
	// entity so other gym scripts can read them via Handle.Get_Fragment.
	// Computed from InitialTransform × local offset (matches the Build_Anchors
	// math). Static stations only — moving stations would need this re-run.
	private void Populate_AnchorsFragment(FCk_Handle& InHandle)
	{
		const auto W_cm = Width * 100.0;
		const auto D_cm = Depth * 100.0;
		const auto H_cm = Height * 100.0;

		auto& Fragment = InHandle.AddOrGet_Fragment(FCkGym_Station_Anchors);
		Fragment.FootprintCenter = InitialTransform.TransformPosition(FVector(0.0, 0.0, 0.0));
		Fragment.AgentSpawnFront = InitialTransform.TransformPosition(FVector( D_cm * 0.5 + AgentSpawnOffset, 0.0, 0.0));
		Fragment.AgentSpawnBack  = InitialTransform.TransformPosition(FVector(-D_cm * 0.5 - AgentSpawnOffset, 0.0, 0.0));
		Fragment.AgentSpawnLeft  = InitialTransform.TransformPosition(FVector(0.0,  W_cm * 0.5 + AgentSpawnOffset, 0.0));
		Fragment.AgentSpawnRight = InitialTransform.TransformPosition(FVector(0.0, -W_cm * 0.5 - AgentSpawnOffset, 0.0));
		Fragment.PanelTopFront   = InitialTransform.TransformPosition(FVector(D_cm * 0.5, 0.0, H_cm));
		Fragment.PanelCenter     = InitialTransform.TransformPosition(FVector(0.0, 0.0, H_cm * 0.5));
	}

	//------------------------------------------------------------------------
	// Fragment-driven display updates — directors push live status text via
	// CkGym_Common::Update_StationDisplay, which writes the fragment on this
	// entity. We poll the fragment each tick and re-apply text components
	// when any field changes.
	//------------------------------------------------------------------------
	UFUNCTION()
	private void OnDisplayTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		auto SelfEntity = ck::ToEntity(this);
		auto& Fragment = SelfEntity.AddOrGet_Fragment(FCkGym_Station_TitleAndDescription);

		if (!Fragment.Title.EqualTo(_CachedTitle))
		{
			_CachedTitle = Fragment.Title;
			Apply_TitleText(Fragment.Title);
		}
		if (!Fragment.Description.EqualTo(_CachedDescription))
		{
			_CachedDescription = Fragment.Description;
			Apply_DescriptionText(Fragment.Description);
		}
		if (!Fragment.Instructions.EqualTo(_CachedInstructions))
		{
			_CachedInstructions = Fragment.Instructions;
			Apply_FloorDescriptionText(Fragment.Instructions);
		}

		// Grow-only resize from actual rendered text bounds (read after
		// Apply_*Text() has called SetText). Avoids per-tick pulsing because
		// the resize only fires when measured bounds exceed current alcove.
		if (AutoSize)
		{
			Refit_FromMeasuredBounds();
		}
	}

	private void Apply_TitleText(FText InText)
	{
		auto Comp = utils_unreal_component::Get_Component(_TitleHandle);
		auto Text = Cast<UTextRenderComponent>(Comp);
		if (Text == nullptr) { return; }
		Text.SetText(InText);
	}

	private void Apply_DescriptionText(FText InText)
	{
		auto Comp = utils_unreal_component::Get_Component(_DescriptionHandle);
		auto Text = Cast<UTextRenderComponent>(Comp);
		if (Text == nullptr) { return; }
		Text.SetText(InText);
	}

	private void Apply_FloorDescriptionText(FText InText)
	{
		auto Comp = utils_unreal_component::Get_Component(_FloorDescriptionHandle);
		auto Text = Cast<UTextRenderComponent>(Comp);
		if (Text == nullptr) { return; }

		// Toggle visibility based on whether the fragment carries text.
		const auto HasText = !InText.IsEmpty();
		Text.SetVisibility(HasText, false);
		if (HasText) { Text.SetText(InText); }
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
			FVector(WT / 100.0, Width, Height),
			_BackWallSCN);

		// Floor stage at Z=0.
		_FloorStageHandle = Spawn_StaticMeshPiece(InStationTH, n"FloorStage", n"OnBodyMeshAdded",
			FVector(0.0, 0.0, FT * 0.5),
			FVector(Depth, Width, FT / 100.0),
			_FloorStageSCN);

		// Trim — picture-frame around the back wall, flush with the back wall's
		// front face, projecting forward by TrimDepth.
		const auto TrimCenterX = -D_cm * 0.5 + WT + TrimDepth * 0.5;

		_LeftTrimHandle = Spawn_StaticMeshPiece(InStationTH, n"LeftTrim", n"OnTrimMeshAdded",
			FVector(TrimCenterX, W_cm * 0.5 - WT * 0.5, H_cm * 0.5),
			FVector(TrimDepth / 100.0, WT / 100.0, Height),
			_LeftTrimSCN);

		_RightTrimHandle = Spawn_StaticMeshPiece(InStationTH, n"RightTrim", n"OnTrimMeshAdded",
			FVector(TrimCenterX, -W_cm * 0.5 + WT * 0.5, H_cm * 0.5),
			FVector(TrimDepth / 100.0, WT / 100.0, Height),
			_RightTrimSCN);

		_TopTrimHandle = Spawn_StaticMeshPiece(InStationTH, n"TopTrim", n"OnTrimMeshAdded",
			FVector(TrimCenterX, 0.0, H_cm - WT * 0.5),
			FVector(TrimDepth / 100.0, Width, WT / 100.0),
			_TopTrimSCN);

		_BottomTrimHandle = Spawn_StaticMeshPiece(InStationTH, n"BottomTrim", n"OnTrimMeshAdded",
			FVector(TrimCenterX, 0.0, FT + WT * 0.5),
			FVector(TrimDepth / 100.0, Width, WT / 100.0),
			_BottomTrimSCN);
	}

	private FCk_Handle_UnrealComponent Spawn_StaticMeshPiece(
		FCk_Handle_Transform& InStationTH,
		FName InDebugName,
		FName InOnAddedHandler,
		FVector InLocalLocation,
		FVector InLocalScale,
		FCk_Handle_SceneNode& OutSCN)
	{
		auto LocalTransform = FTransform(FRotator::ZeroRotator, InLocalLocation, InLocalScale);
		OutSCN = utils_scene_node::Create(InStationTH, LocalTransform);

		auto PieceTH = OutSCN.As_Transform();
		auto PieceEntity = FCk_Handle(PieceTH);

		const auto Params = utils_unreal_component::Make_Params(UStaticMeshComponent, ECk_UnrealComponent_TickPolicy::DoNotTick, InDebugName);
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
			FRotator::ZeroRotator,
			_TitleSCN);

		_DescriptionHandle = Spawn_TextPiece(InStationTH, n"DescriptionText", n"OnDescriptionAdded",
			FVector(TextX, TextY, DescZ),
			FRotator::ZeroRotator,
			_DescriptionSCN);

		// Floor description is created unconditionally; the OnAdded handler hides
		// the component when FloorDescriptionText is empty.
		const auto FloorTopZ = FloorThickness + 2.0;
		const auto FloorX = FloorPlacementOffset(1.0);
		const auto FloorY = TextAlignmentOffset(FloorTextAlignment, 1.0);

		_FloorDescriptionHandle = Spawn_TextPiece(InStationTH, n"FloorDescriptionText", n"OnFloorDescriptionAdded",
			FVector(FloorX, FloorY, FloorTopZ),
			FRotator(90.0, 0.0, 0.0),
			_FloorDescriptionSCN);
	}

	private FCk_Handle_UnrealComponent Spawn_TextPiece(
		FCk_Handle_Transform& InStationTH,
		FName InDebugName,
		FName InOnAddedHandler,
		FVector InLocalLocation,
		FRotator InLocalRotation,
		FCk_Handle_SceneNode& OutSCN)
	{
		auto LocalTransform = FTransform(InLocalRotation, InLocalLocation, FVector(1.0, 1.0, 1.0));
		OutSCN = utils_scene_node::Create(InStationTH, LocalTransform);

		auto PieceTH = OutSCN.As_Transform();
		auto PieceEntity = FCk_Handle(PieceTH);

		const auto Params = utils_unreal_component::Make_Params(UTextRenderComponent, ECk_UnrealComponent_TickPolicy::DoNotTick, InDebugName);

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

		// First chance to measure; description component may not be ready yet
		// (Refit_FromMeasuredBounds early-outs in that case).
		if (AutoSize) { Refit_FromMeasuredBounds(); }
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

		if (AutoSize) { Refit_FromMeasuredBounds(); }
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
		_SpotlightSCN = utils_scene_node::Create(InStationTH, LocalTransform);
		auto PieceTH = _SpotlightSCN.As_Transform();
		auto PieceEntity = FCk_Handle(PieceTH);

		const auto Params = utils_unreal_component::Make_Params(USpotLightComponent, ECk_UnrealComponent_TickPolicy::DoNotTick, n"Spotlight");

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
	// Anchor world-position getter — reads the named anchor SCN's current
	// world transform via the framework's transform util. SceneNode
	// propagation keeps this correct even if the station moves (which the
	// FCkGym_Station_Anchors fragment snapshot doesn't).
	//
	// External gym scripts can either:
	//   (a) Call ACk_Gym_Base_PlayerController::Get_StationAnchorLocation(InTag, EAnchor),
	//       which uses the snapshot fragment — fine for static stations.
	//   (b) Call this getter directly — needs the EntityScript instance.
	//========================================================================

	UFUNCTION()
	FVector Get_AnchorWorldLocation(ECk_GymStation_Anchor InAnchor)
	{
		auto SCN = Get_AnchorSCN(InAnchor);
		return utils_transform::Get_EntityCurrentLocation(SCN.As_Transform());
	}

	private FCk_Handle_SceneNode Get_AnchorSCN(ECk_GymStation_Anchor InAnchor)
	{
		if (InAnchor == ECk_GymStation_Anchor::FootprintCenter) { return _AnchorFootprintCenter; }
		if (InAnchor == ECk_GymStation_Anchor::AgentSpawnFront) { return _AnchorAgentSpawnFront; }
		if (InAnchor == ECk_GymStation_Anchor::AgentSpawnBack)  { return _AnchorAgentSpawnBack; }
		if (InAnchor == ECk_GymStation_Anchor::AgentSpawnLeft)  { return _AnchorAgentSpawnLeft; }
		if (InAnchor == ECk_GymStation_Anchor::AgentSpawnRight) { return _AnchorAgentSpawnRight; }
		if (InAnchor == ECk_GymStation_Anchor::PanelTopFront)   { return _AnchorPanelTopFront; }
		return _AnchorPanelCenter;
	}

	//========================================================================
	// Auto-sizing — heuristic Width/Height from text content.
	//
	// Spawn-time: walk the spawn-params Title + DescriptionText (TArray<FText>)
	// to find longest line + line count. Override Width/Height before geometry
	// is built. Exact since the array gives us per-line counts.
	//
	// Runtime: when Update_StationDisplay writes the fragment, recompute
	// required size from Fragment.Title + Fragment.Description (which may
	// contain "\n" for multi-line). Grow-only — Width/Height only ever
	// increase. Avoids pulsing as live-status text fluctuates.
	//
	// Heuristic uses approximate char-width (0.6 × DescriptionScale) and
	// line-height (1.5 × DescriptionScale). Imprecise but safely over-sizes
	// rather than truncating.
	//========================================================================

	private double Compute_AutoWidth(int32 InLongestLineChars)
	{
		const auto Padding_cm = 60.0;
		const auto CharWidthFactor = 0.6;        // approx world-cm per char per scale unit
		const auto MinWidth_units = 3.0;
		const auto TextWidth_cm = double(InLongestLineChars) * DescriptionScale * CharWidthFactor;
		return Math::Max(MinWidth_units, (TextWidth_cm + 2.0 * Padding_cm) / 100.0);
	}

	private double Compute_AutoHeight(int32 InDescLineCount)
	{
		const auto Padding_cm = 60.0;
		const auto LineHeightFactor = 1.5;
		const auto MinHeight_units = 2.0;
		const auto TextHeight_cm = TitleScale + double(InDescLineCount) * DescriptionScale * LineHeightFactor;
		return Math::Max(MinHeight_units, (TextHeight_cm + 2.0 * Padding_cm) / 100.0);
	}

	private void Apply_AutoSize_FromSpawnParams()
	{
		int32 LongestChars = TitleText.ToString().Len();
		for (auto Line : DescriptionText)
		{
			const auto Len = Line.ToString().Len();
			if (Len > LongestChars) { LongestChars = Len; }
		}

		Width  = Compute_AutoWidth(LongestChars);
		Height = Compute_AutoHeight(DescriptionText.Num());
	}

	// Grow-only resize using the actual rendered bounds from the
	// UTextRenderComponents. Called after every SetText (in OnTitleAdded,
	// OnDescriptionAdded, Apply_TitleText, Apply_DescriptionText) so the
	// alcove tracks the high-water mark of measured text size.
	//
	// GetTextLocalSize returns the local bounding box of the rendered text
	// quad: Y = horizontal width (text reading direction), Z = vertical
	// height (line stack). X is the quad's normal and is always 0.
	private void Refit_FromMeasuredBounds()
	{
		auto TitleComp = Cast<UTextRenderComponent>(utils_unreal_component::Get_Component(_TitleHandle));
		auto DescComp  = Cast<UTextRenderComponent>(utils_unreal_component::Get_Component(_DescriptionHandle));

		// Both components must exist for the measurement; this method is
		// called from each Apply_*Text handler so it may be invoked before
		// the other component is ready — early out and we'll catch up next call.
		if (TitleComp == nullptr || DescComp == nullptr) { return; }

		const auto TitleSize = TitleComp.GetTextLocalSize();
		const auto DescSize  = DescComp.GetTextLocalSize();

		const auto MaxWidth_cm    = Math::Max(TitleSize.Y, DescSize.Y);
		const auto TotalHeight_cm = TitleSize.Z + DescSize.Z;

		const auto Padding_cm    = 60.0;
		const auto GapBetween_cm = 30.0;
		const auto MinW_units    = 3.0;
		const auto MinH_units    = 2.0;

		const auto RequiredW = Math::Max(MinW_units, (MaxWidth_cm + 2.0 * Padding_cm) / 100.0);
		const auto RequiredH = Math::Max(MinH_units, (TotalHeight_cm + GapBetween_cm + 2.0 * Padding_cm) / 100.0);

		const auto NeedsGrow = (RequiredW > Width) || (RequiredH > Height);

		if (ShowDebugOverlays)
		{
			Print(f"[GymStation Refit] TitleSize={TitleSize}  DescSize={DescSize}  Required=({RequiredW :.2}, {RequiredH :.2})  Current=({Width :.2}, {Height :.2})  NeedsGrow={NeedsGrow}");
		}

		if (NeedsGrow == false) { return; }

		Width  = Math::Max(Width,  RequiredW);
		Height = Math::Max(Height, RequiredH);

		Resize_Alcove();
	}

	//========================================================================
	// Resize — re-applies local transforms to all SCNs based on current
	// Width / Depth / Height. Used by Refit_IfOverflow on grow.
	//========================================================================

	private void Resize_Alcove()
	{
		Update_BodyTransforms();
		Update_TextTransforms();
		Update_SpotlightTransform();
		Update_AnchorTransforms();

		// Populate_AnchorsFragment takes FCk_Handle& (non-const ref) so it
		// can call AddOrGet_Fragment. ck::ToEntity(this) returns a temporary,
		// so stash it in a local first.
		auto SelfEntity = ck::ToEntity(this);
		Populate_AnchorsFragment(SelfEntity);
	}

	private void Update_BodyTransforms()
	{
		const auto W_cm = Width * 100.0;
		const auto D_cm = Depth * 100.0;
		const auto H_cm = Height * 100.0;
		const auto WT = WallThickness;
		const auto FT = FloorThickness;
		const auto TrimCenterX = -D_cm * 0.5 + WT + TrimDepth * 0.5;

		if (ShowDebugOverlays)
		{
			Print(f"[GymStation Resize] Width={Width :.2}  Depth={Depth :.2}  Height={Height :.2}");
		}

		Update_PieceLocAndScale_Logged(_BackWallSCN, "BackWall",
			FVector(-D_cm * 0.5 + WT * 0.5, 0.0, H_cm * 0.5),
			FVector(WT / 100.0, Width, Height));

		Update_PieceLocAndScale_Logged(_FloorStageSCN, "FloorStage",
			FVector(0.0, 0.0, FT * 0.5),
			FVector(Depth, Width, FT / 100.0));

		Update_PieceLocAndScale_Logged(_LeftTrimSCN, "LeftTrim",
			FVector(TrimCenterX, W_cm * 0.5 - WT * 0.5, H_cm * 0.5),
			FVector(TrimDepth / 100.0, WT / 100.0, Height));

		Update_PieceLocAndScale_Logged(_RightTrimSCN, "RightTrim",
			FVector(TrimCenterX, -W_cm * 0.5 + WT * 0.5, H_cm * 0.5),
			FVector(TrimDepth / 100.0, WT / 100.0, Height));

		Update_PieceLocAndScale_Logged(_TopTrimSCN, "TopTrim",
			FVector(TrimCenterX, 0.0, H_cm - WT * 0.5),
			FVector(TrimDepth / 100.0, Width, WT / 100.0));

		Update_PieceLocAndScale_Logged(_BottomTrimSCN, "BottomTrim",
			FVector(TrimCenterX, 0.0, FT + WT * 0.5),
			FVector(TrimDepth / 100.0, Width, WT / 100.0));

		if (ShowDebugOverlays)
		{
			Rebuild_DebugOverlays();
		}
	}

	private void Update_PieceLocAndScale_Logged(FCk_Handle_SceneNode& InSCN, FString InName, FVector InLoc, FVector InScale)
	{
		if (ShowDebugOverlays)
		{
			Print(f"[GymStation Resize]   {InName}: loc={InLoc}  scale={InScale}");
		}
		Update_PieceLocAndScale(InSCN, InLoc, InScale);
	}

	private void Update_TextTransforms()
	{
		const auto BackWallInnerX = -Depth * 50.0 + WallThickness;
		const auto TextX = BackWallInnerX + 5.0;
		const auto PanelTopZ = Height * 100.0;
		const auto DescZ  = PanelTopZ - (TitleScale + 60.0);
		const auto TitleZ = PanelTopZ - (TitleScale + 60.0) / 2.0;
		const auto TextY = TextAlignmentOffset(TextAlignment, 1.0);

		Update_PieceLocAndRot(_TitleSCN,       FVector(TextX, TextY, TitleZ), FRotator::ZeroRotator);
		Update_PieceLocAndRot(_DescriptionSCN, FVector(TextX, TextY, DescZ),  FRotator::ZeroRotator);

		const auto FloorTopZ = FloorThickness + 2.0;
		const auto FloorX = FloorPlacementOffset(1.0);
		const auto FloorY = TextAlignmentOffset(FloorTextAlignment, 1.0);
		Update_PieceLocAndRot(_FloorDescriptionSCN, FVector(FloorX, FloorY, FloorTopZ), FRotator(90.0, 0.0, 0.0));
	}

	private void Update_SpotlightTransform()
	{
		const auto SpotX = Depth * 30.0;
		const auto SpotZ = Height * 90.0;
		Update_PieceLocAndRot(_SpotlightSCN, FVector(SpotX, 0.0, SpotZ), FRotator(-30.0, 180.0, 0.0));
	}

	private void Update_AnchorTransforms()
	{
		const auto W_cm = Width * 100.0;
		const auto D_cm = Depth * 100.0;
		const auto H_cm = Height * 100.0;

		Update_PieceLocOnly(_AnchorFootprintCenter,  FVector(0.0, 0.0, 0.0));
		Update_PieceLocOnly(_AnchorAgentSpawnFront,  FVector( D_cm * 0.5 + AgentSpawnOffset, 0.0, 0.0));
		Update_PieceLocOnly(_AnchorAgentSpawnBack,   FVector(-D_cm * 0.5 - AgentSpawnOffset, 0.0, 0.0));
		Update_PieceLocOnly(_AnchorAgentSpawnLeft,   FVector(0.0,  W_cm * 0.5 + AgentSpawnOffset, 0.0));
		Update_PieceLocOnly(_AnchorAgentSpawnRight,  FVector(0.0, -W_cm * 0.5 - AgentSpawnOffset, 0.0));
		Update_PieceLocOnly(_AnchorPanelTopFront,    FVector(D_cm * 0.5, 0.0, H_cm));
		Update_PieceLocOnly(_AnchorPanelCenter,      FVector(0.0, 0.0, H_cm * 0.5));
	}

	// Direct SCN updates — issued as a SINGLE full-transform request per piece.
	//
	// Why not the per-component Request_UpdateOffset_Location / _Rotation /
	// _Scale helpers: those each read the current offset, mutate one field,
	// and queue a full-transform request. SCN requests are processed in batch
	// later by FProcessor_SceneNode_HandleRequests, so issuing two helpers
	// in sequence means the second read sees the still-unmodified offset
	// (its mutation lands on stale values for the OTHER fields) and its
	// queued request clobbers the first when both run. Net effect during
	// runtime resize: only the *last* helper's mutated field survives;
	// everything else reverts to pre-resize values. Concretely with
	// Location-then-Scale, locations were dropped on every resize, leaving
	// pieces visually stuck at their initial Z while scales kept growing.
	//
	// Composing the full FTransform up front and submitting it once avoids
	// the round-trip entirely.
	private void Update_PieceLocAndScale(FCk_Handle_SceneNode& InSCN, FVector InLoc, FVector InScale)
	{
		auto NewOffset = utils_scene_node::Get_Offset(InSCN);
		NewOffset.SetLocation(InLoc);
		NewOffset.SetScale3D(InScale);
		utils_scene_node::Request_UpdateOffset(InSCN, FCk_Request_SceneNode_UpdateRelativeTransform(NewOffset));
	}

	private void Update_PieceLocAndRot(FCk_Handle_SceneNode& InSCN, FVector InLoc, FRotator InRot)
	{
		auto NewOffset = utils_scene_node::Get_Offset(InSCN);
		NewOffset.SetLocation(InLoc);
		NewOffset.SetRotation(InRot.Quaternion());
		utils_scene_node::Request_UpdateOffset(InSCN, FCk_Request_SceneNode_UpdateRelativeTransform(NewOffset));
	}

	private void Update_PieceLocOnly(FCk_Handle_SceneNode& InSCN, FVector InLoc)
	{
		auto NewOffset = utils_scene_node::Get_Offset(InSCN);
		NewOffset.SetLocation(InLoc);
		utils_scene_node::Request_UpdateOffset(InSCN, FCk_Request_SceneNode_UpdateRelativeTransform(NewOffset));
	}

	//========================================================================
	// Debug overlays — translucent wireframe PMG boxes drawn at each piece's
	// EXPECTED world transform. Useful for spotting a partial-resize bug:
	// if a piece's actual rendered geometry doesn't sit inside its overlay,
	// that piece's transform isn't tracking the latest dimensions.
	//
	// Colour key:
	//   Back wall  → red
	//   Floor      → blue
	//   Top trim   → yellow
	//   Bottom trim→ orange
	//   Left trim  → cyan
	//   Right trim → magenta
	//========================================================================

	private void Build_DebugOverlays(FCk_Handle& InOwner)
	{
		Destroy_DebugOverlays();
		Push_BodyOverlays(InOwner);
	}

	private void Rebuild_DebugOverlays()
	{
		auto SelfEntity = ck::ToEntity(this);
		Destroy_DebugOverlays();
		Push_BodyOverlays(SelfEntity);
	}

	private void Destroy_DebugOverlays()
	{
		for (auto Handle : _DebugOverlays)
		{
			utils_entity_lifetime::Request_DestroyEntity(Handle);
		}
		_DebugOverlays.Empty();
	}

	private void Push_BodyOverlays(FCk_Handle& InOwner)
	{
		const auto W_cm = Width * 100.0;
		const auto D_cm = Depth * 100.0;
		const auto H_cm = Height * 100.0;
		const auto WT = WallThickness;
		const auto FT = FloorThickness;
		const auto TrimCenterX = -D_cm * 0.5 + WT + TrimDepth * 0.5;

		// Back wall — red
		Push_OverlayBoxAt(InOwner,
			FVector(-D_cm * 0.5 + WT * 0.5, 0.0, H_cm * 0.5),
			FVector(WT * 0.5, W_cm * 0.5, H_cm * 0.5),
			FLinearColor(1.0, 0.0, 0.0, 0.25));

		// Floor — blue
		Push_OverlayBoxAt(InOwner,
			FVector(0.0, 0.0, FT * 0.5),
			FVector(D_cm * 0.5, W_cm * 0.5, FT * 0.5),
			FLinearColor(0.0, 0.4, 1.0, 0.25));

		// Left trim — cyan
		Push_OverlayBoxAt(InOwner,
			FVector(TrimCenterX, W_cm * 0.5 - WT * 0.5, H_cm * 0.5),
			FVector(TrimDepth * 0.5, WT * 0.5, H_cm * 0.5),
			FLinearColor(0.0, 1.0, 1.0, 0.25));

		// Right trim — magenta
		Push_OverlayBoxAt(InOwner,
			FVector(TrimCenterX, -W_cm * 0.5 + WT * 0.5, H_cm * 0.5),
			FVector(TrimDepth * 0.5, WT * 0.5, H_cm * 0.5),
			FLinearColor(1.0, 0.0, 1.0, 0.25));

		// Top trim — yellow
		Push_OverlayBoxAt(InOwner,
			FVector(TrimCenterX, 0.0, H_cm - WT * 0.5),
			FVector(TrimDepth * 0.5, W_cm * 0.5, WT * 0.5),
			FLinearColor(1.0, 1.0, 0.0, 0.25));

		// Bottom trim — orange
		Push_OverlayBoxAt(InOwner,
			FVector(TrimCenterX, 0.0, FT + WT * 0.5),
			FVector(TrimDepth * 0.5, W_cm * 0.5, WT * 0.5),
			FLinearColor(1.0, 0.5, 0.0, 0.25));
	}

	private void Push_OverlayBoxAt(FCk_Handle& InOwner, FVector InLocalLocation, FVector InHalfExtent, FLinearColor InColour)
	{
		const auto WorldLoc = InitialTransform.TransformPosition(InLocalLocation);
		const auto WorldRot = InitialTransform.Rotator();
		const auto BoxTransform = FTransform(WorldRot, WorldLoc, FVector(1.0, 1.0, 1.0));

		auto Box = UCk_Utils_Pmg_BasicShapes::Create_Box(
			InOwner,
			BoxTransform,
			InHalfExtent,
			ECk_Plane_Axis::XY,
			InColour,
			true,    // wireframe overlay
			3.0f,
			-1.0f);  // persistent

		_DebugOverlays.Add(Box);
	}
}
