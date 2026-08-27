UENUM()
enum ECk_SceneNodeGym_Behavior
{
	ParentChild,
	OffsetUpdates,
	MultipleChildren,
	Hierarchy,
	PropagateOnly,
	AnchorOffset,
	ECk_MAX
}

UCLASS(Blueprintable)
class ACk_SceneNodeGym_Cube : AActor
{
	default bReplicates = true;
	default bReplicateUsingRegisteredSubObjectList = true;
	default bAlwaysRelevant = true;
	default bReplicateMovement = true;

	UPROPERTY(DefaultComponent)
	UStaticMeshComponent Mesh;
	default Mesh.StaticMesh = Cast<UStaticMesh>(utils_i_o::LoadAssetByName("Cube1", ECk_AssetSearchScope::Engine, ECk_AssetSearchStrategy::ExactOnly)._Asset);
	default Mesh.CollisionEnabled = ECollisionEnabled::NoCollision;

	UPROPERTY(DefaultComponent)
	UTextRenderComponent TextRenderer;
	default TextRenderer.RelativeLocation = FVector(0.0f, 0.0f, 75.0f);
	default TextRenderer.SetHorizontalAlignment(EHorizTextAligment::EHTA_Center);
	default TextRenderer.WorldSize = 40.0f;
	default TextRenderer.TextRenderColor = FColor::Orange;

	UPROPERTY(ExposeOnSpawn)
	ECk_SceneNodeGym_Behavior Behavior = ECk_SceneNodeGym_Behavior::ParentChild;

	// --- Shared state ---
	FCk_Handle EcsEntity;
	FCk_Handle_Transform ParentTransform;
	float32 ElapsedTime = 0.0f;

	// --- ParentChild state ---
	FCk_Handle_SceneNode ChildNode;
	ACk_SceneNodeGym_ChildCube ChildCubeActor;
	float32 OrbitRadius = 150.0f;
	float32 OrbitSpeed = 1.5f;

	// --- OffsetUpdates state ---
	FCk_Handle_SceneNode OffsetNode;
	ACk_SceneNodeGym_ChildCube OffsetCubeActor;
	float32 AnimSpeed = 1.0f;

	// --- MultipleChildren state ---
	TArray<FCk_Handle_SceneNode> ChildNodes;
	TArray<ACk_SceneNodeGym_ChildCube> ChildCubeActors;
	float32 ParentRotationSpeed = 30.0f;

	// --- Hierarchy state ---
	FCk_Handle_SceneNode HierarchyChild;
	FCk_Handle_SceneNode HierarchyGrandchild;
	ACk_SceneNodeGym_ChildCube HierarchyChildCube;
	ACk_SceneNodeGym_ChildCube HierarchyGrandchildCube;
	float32 RootRotationSpeed = 25.0f;
	float32 ChildRotationSpeed = 45.0f;

	// --- PropagateOnly state ---
	// Solar-system style: only the root rotates. Planet + moon have static
	// local offsets and no per-frame updates, so if scene-node transform
	// propagation works, planet should orbit root and moon should orbit
	// planet via parent motion alone. If propagation is broken, planet
	// and moon stay frozen at their initial world positions.
	FCk_Handle_SceneNode PropagatePlanet;
	FCk_Handle_SceneNode PropagateMoon;
	ACk_SceneNodeGym_ChildCube PropagatePlanetCube;
	ACk_SceneNodeGym_ChildCube PropagateMoonCube;
	float32 PropagateRootRotationSpeed = 40.0f;
	float32 PropagatePlanetOrbitRadius = 160.0f;
	float32 PropagateMoonOrbitRadius = 80.0f;

	// --- AnchorOffset state ---
	// The cube's own Mesh (a moving USceneComponent) is the anchor. A SceneNode
	// follows it at a fixed relative offset via CreateAndAttachToUnrealComponent;
	// rotating the actor moves the mesh in world so the follower tracks it, and
	// the offset height is animated each frame to show runtime-mutable offsets.
	FCk_Handle_SceneNode AnchorNode;
	ACk_SceneNodeGym_ChildCube AnchorCubeActor;
	float32 AnchorRotationSpeed = 35.0f;
	FVector AnchorBaseOffset = FVector(180.0f, 0.0f, 40.0f);

	UFUNCTION(BlueprintOverride)
	void BeginPlay()
	{
	    auto _CkPerfScope = ck::ScopedStat();
		TextRenderer.SetText(ck::Text(f"{Behavior}"));

		if (HasAuthority())
		{
			auto SpawnParams = FCk_EntityScript_WithActor_SpawnParams();
			SpawnParams._OwningActor = this;
			auto PendingEntity = utils_entity_script::Request_SpawnEntity(
				ck::TransientEntity(), UCk_EntityScript_WithActor_UE, SpawnParams);
			utils_pending_entity_script::Promise_OnConstructed(
				PendingEntity, FCk_Delegate_EntityScript_Constructed(this, n"OnEntityConstructed"));
		}
	}

	UFUNCTION()
	private void OnEntityConstructed(FCk_Handle_EntityScript InEntityScriptHandle)
	{
		if (System::IsServer() == false)
		{ return; }

		auto InEntity = FCk_Handle(InEntityScriptHandle);
		InEntity.Set_DebugName(FName(f"Cube_{Behavior}"));
		EcsEntity = InEntity;
		ParentTransform = InEntity.As_Transform();

		if (Behavior == ECk_SceneNodeGym_Behavior::ParentChild)
		{
			Setup_ParentChild();
		}
		else if (Behavior == ECk_SceneNodeGym_Behavior::OffsetUpdates)
		{
			Setup_OffsetUpdates();
		}
		else if (Behavior == ECk_SceneNodeGym_Behavior::MultipleChildren)
		{
			Setup_MultipleChildren();
		}
		else if (Behavior == ECk_SceneNodeGym_Behavior::Hierarchy)
		{
			Setup_Hierarchy();
		}
		else if (Behavior == ECk_SceneNodeGym_Behavior::PropagateOnly)
		{
			Setup_PropagateOnly();
		}
		else if (Behavior == ECk_SceneNodeGym_Behavior::AnchorOffset)
		{
			Setup_AnchorOffset();
		}

		// Per-frame tick
		utils_timer::Create_Tick(InEntity, FCk_Delegate_Timer(this, n"OnFrameTick"));
	}

	//------------------------------------------------------------------------
	// HELPERS
	//------------------------------------------------------------------------

	private ACk_SceneNodeGym_ChildCube SpawnChildCube(FString InLabel)
	{
		auto SpawnedChild = Cast<ACk_SceneNodeGym_ChildCube>(
			SpawnActor(ACk_SceneNodeGym_ChildCube, GetActorLocation(), FRotator()));
		SpawnedChild.Set_Label(InLabel);
		return SpawnedChild;
	}

	FTransform Get_SceneNodeWorldTransform(FCk_Handle_SceneNode InNode)
	{
		// Get the parent transform handle that this scene node is attached to
		auto ParentHandle = utils_scene_node::Get_Parent(InNode);
		auto ParentWorldTransform = utils_transform::Get_EntityCurrentTransform(ParentHandle);
		auto LocalOffset = utils_scene_node::Get_Offset(InNode);
		// Compose: parent world * local offset
		return LocalOffset * ParentWorldTransform;
	}

	private void SyncChildCube(ACk_SceneNodeGym_ChildCube InCube, FCk_Handle_SceneNode InNode)
	{
		if (ck::IsValid(InCube) == false)
		{ return; }

		auto WorldTransform = Get_SceneNodeWorldTransform(InNode);
		InCube.SetActorLocationAndRotation(WorldTransform.GetLocation(), WorldTransform.GetRotation().Rotator());
		InCube.SetActorScale3D(WorldTransform.GetScale3D());
	}

	//------------------------------------------------------------------------
	// SETUP FUNCTIONS
	//------------------------------------------------------------------------

	private void Setup_ParentChild()
	{
		auto ChildLocalTransform = FTransform(FRotator(), FVector(OrbitRadius, 0.0f, 0.0f), FVector(0.5f, 0.5f, 0.5f));
		ChildNode = utils_scene_node::Create(ParentTransform, ChildLocalTransform);
		ChildCubeActor = SpawnChildCube("Child");
	}

	private void Setup_OffsetUpdates()
	{
		auto ChildLocalTransform = FTransform(FRotator(), FVector(100.0f, 0.0f, 50.0f), FVector(0.5f, 0.5f, 0.5f));
		OffsetNode = utils_scene_node::Create(ParentTransform, ChildLocalTransform);
		OffsetCubeActor = SpawnChildCube("Offset");
	}

	private void Setup_MultipleChildren()
	{
		auto Offsets = TArray<FVector>();
		Offsets.Add(FVector(120.0f, 0.0f, 0.0f));
		Offsets.Add(FVector(0.0f, 120.0f, 0.0f));
		Offsets.Add(FVector(-120.0f, 0.0f, 0.0f));
		Offsets.Add(FVector(0.0f, -120.0f, 0.0f));

		for (int32 Index = 0; Index < 4; ++Index)
		{
			auto ChildLocalTransform = FTransform(FRotator(), Offsets[Index], FVector(0.4f, 0.4f, 0.4f));
			auto Node = utils_scene_node::Create(ParentTransform, ChildLocalTransform);
			ChildNodes.Add(Node);
			ChildCubeActors.Add(SpawnChildCube(f"Child {Index + 1}"));
		}
	}

	private void Setup_Hierarchy()
	{
		// Root -> Child
		auto ChildLocalTransform = FTransform(FRotator(), FVector(120.0f, 0.0f, 0.0f), FVector(0.7f, 0.7f, 0.7f));
		HierarchyChild = utils_scene_node::Create(ParentTransform, ChildLocalTransform);
		HierarchyChildCube = SpawnChildCube("Child");

		// Child -> Grandchild (parented to child's transform, not root)
		auto ChildTransformHandle = HierarchyChild.As_Transform();
		auto GrandchildLocalTransform = FTransform(FRotator(), FVector(100.0f, 0.0f, 0.0f), FVector(0.6f, 0.6f, 0.6f));
		HierarchyGrandchild = utils_scene_node::Create(ChildTransformHandle, GrandchildLocalTransform);
		HierarchyGrandchildCube = SpawnChildCube("Grandchild");
	}

	private void Setup_PropagateOnly()
	{
		// Sun (root) is the rotating parent this actor is attached to. The
		// planet and moon have static local offsets and NO per-frame updates
		// of their own - purely relying on scene-node transform propagation
		// to inherit the root's rotation.
		auto PlanetLocalTransform = FTransform(FRotator(), FVector(PropagatePlanetOrbitRadius, 0.0f, 0.0f), FVector(0.6f, 0.6f, 0.6f));
		PropagatePlanet = utils_scene_node::Create(ParentTransform, PlanetLocalTransform);
		PropagatePlanetCube = SpawnChildCube("Planet");

		auto PlanetTransformHandle = PropagatePlanet.As_Transform();
		auto MoonLocalTransform = FTransform(FRotator(), FVector(PropagateMoonOrbitRadius, 0.0f, 0.0f), FVector(0.4f, 0.4f, 0.4f));
		PropagateMoon = utils_scene_node::Create(PlanetTransformHandle, MoonLocalTransform);
		PropagateMoonCube = SpawnChildCube("Moon");
	}

	private void Setup_AnchorOffset()
	{
		// Attach a SceneNode to this actor's Mesh component (a foreign USceneComponent)
		// at a fixed relative offset. The node follows the mesh's world at that offset
		// it never drives the mesh back (read-only follower).
		auto Offset = FTransform(FRotator(), AnchorBaseOffset, FVector(0.5f, 0.5f, 0.5f));
		AnchorNode = utils_scene_node::CreateAndAttachToUnrealComponent(ParentTransform, Mesh, Offset);
		AnchorCubeActor = SpawnChildCube("Anchored");
	}

	//------------------------------------------------------------------------
	// PER-FRAME TICK
	//------------------------------------------------------------------------

	UFUNCTION()
	private void OnFrameTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		auto DeltaSeconds = float32(InDeltaT.Get_Seconds());
		ElapsedTime = ElapsedTime + DeltaSeconds;

		if (Behavior == ECk_SceneNodeGym_Behavior::ParentChild)
		{
			Tick_ParentChild(DeltaSeconds);
		}
		else if (Behavior == ECk_SceneNodeGym_Behavior::OffsetUpdates)
		{
			Tick_OffsetUpdates(DeltaSeconds);
		}
		else if (Behavior == ECk_SceneNodeGym_Behavior::MultipleChildren)
		{
			Tick_MultipleChildren(DeltaSeconds);
		}
		else if (Behavior == ECk_SceneNodeGym_Behavior::Hierarchy)
		{
			Tick_Hierarchy(DeltaSeconds);
		}
		else if (Behavior == ECk_SceneNodeGym_Behavior::PropagateOnly)
		{
			Tick_PropagateOnly(DeltaSeconds);
		}
		else if (Behavior == ECk_SceneNodeGym_Behavior::AnchorOffset)
		{
			Tick_AnchorOffset(DeltaSeconds);
		}
	}

	private void Tick_ParentChild(float32 DeltaSeconds)
	{
		// Orbit child around parent using offset updates
		auto Angle = ElapsedTime * OrbitSpeed;
		auto OffsetX = OrbitRadius * Math::Cos(Angle);
		auto OffsetY = OrbitRadius * Math::Sin(Angle);

		utils_scene_node::Request_UpdateOffset_Location(ChildNode, FVector(OffsetX, OffsetY, 0.0f), ECk_RelativeAbsolute::Absolute);
		SyncChildCube(ChildCubeActor, ChildNode);
	}

	private void Tick_OffsetUpdates(float32 DeltaSeconds)
	{
		// Animate all three offset components simultaneously
		auto SineVal = Math::Sin(ElapsedTime * AnimSpeed);
		auto CosVal = Math::Cos(ElapsedTime * AnimSpeed);

		// Location: oscillate along X
		auto LocationOffset = FVector(100.0f + SineVal * 80.0f, CosVal * 50.0f, 50.0f + SineVal * 30.0f);
		utils_scene_node::Request_UpdateOffset_Location(OffsetNode, LocationOffset, ECk_RelativeAbsolute::Absolute);

		// Rotation: oscillate yaw
		auto RotationOffset = FRotator(0.0f, SineVal * 45.0f, 0.0f);
		utils_scene_node::Request_UpdateOffset_Rotation(OffsetNode, RotationOffset, ECk_RelativeAbsolute::Absolute);

		// Scale: pulse between 0.3 and 0.7
		auto ScaleVal = 0.5f + SineVal * 0.2f;
		utils_scene_node::Request_UpdateOffset_Scale(OffsetNode, FVector(ScaleVal, ScaleVal, ScaleVal), ECk_RelativeAbsolute::Absolute);

		SyncChildCube(OffsetCubeActor, OffsetNode);
	}

	private void Tick_MultipleChildren(float32 DeltaSeconds)
	{
		// Rotate the parent - children follow automatically
		utils_transform::Request_AddRotationOffset(EcsEntity, FRotator(0.0f, ParentRotationSpeed * DeltaSeconds, 0.0f), ECk_LocalWorld::World);

		for (int32 Index = 0; Index < ChildNodes.Num(); ++Index)
		{
			SyncChildCube(ChildCubeActors[Index], ChildNodes[Index]);
		}
	}

	private void Tick_Hierarchy(float32 DeltaSeconds)
	{
		// Rotate root
		utils_transform::Request_AddRotationOffset(EcsEntity, FRotator(0.0f, RootRotationSpeed * DeltaSeconds, 0.0f), ECk_LocalWorld::World);

		// Rotate child's offset
		auto ChildRotation = FRotator(0.0f, ChildRotationSpeed * DeltaSeconds, 0.0f);
		utils_scene_node::Request_UpdateOffset_Rotation(HierarchyChild, ChildRotation, ECk_RelativeAbsolute::Relative);

		// Grandchild gets its own slow counter-rotation
		auto GrandchildRotation = FRotator(0.0f, -ChildRotationSpeed * 0.5f * DeltaSeconds, 0.0f);
		utils_scene_node::Request_UpdateOffset_Rotation(HierarchyGrandchild, GrandchildRotation, ECk_RelativeAbsolute::Relative);

		SyncChildCube(HierarchyChildCube, HierarchyChild);
		SyncChildCube(HierarchyGrandchildCube, HierarchyGrandchild);
	}

	private void Tick_PropagateOnly(float32 DeltaSeconds)
	{
		// ONLY the root rotates. Planet and Moon have their offsets locked in
		// at setup and are never touched again - so their world transforms
		// depend entirely on scene-node transform propagation picking up the
		// root's rotation change each frame.
		utils_transform::Request_AddRotationOffset(EcsEntity, FRotator(0.0f, PropagateRootRotationSpeed * DeltaSeconds, 0.0f), ECk_LocalWorld::World);

		SyncChildCube(PropagatePlanetCube, PropagatePlanet);
		SyncChildCube(PropagateMoonCube, PropagateMoon);
	}

	private void Tick_AnchorOffset(float32 DeltaSeconds)
	{
		// Rotate the whole actor - its Mesh (the anchor component) moves in world,
		// so the follower node tracks it at the offset.
		utils_transform::Request_AddRotationOffset(EcsEntity, FRotator(0.0f, AnchorRotationSpeed * DeltaSeconds, 0.0f), ECk_LocalWorld::World);

		// Animate the offset height to show the anchor offset is runtime-mutable
		// Request_UpdateOffset now sticks for anchor-follow nodes (was a no-op before).
		auto BobbedOffset = AnchorBaseOffset + FVector(0.0f, 0.0f, Math::Sin(ElapsedTime * 1.5f) * 60.0f);
		utils_scene_node::Request_UpdateOffset_Location(AnchorNode, BobbedOffset, ECk_RelativeAbsolute::Absolute);

		SyncAnchorCube();
	}

	private void SyncAnchorCube()
	{
		if (ck::IsValid(AnchorCubeActor) == false)
		{ return; }

		// Read the node's OWN composed world (offset * mesh world), not the structural-
		// parent composition - the Unreal anchor drives this node directly.
		auto NodeWorld = utils_transform::Get_EntityCurrentTransform(AnchorNode.As_Transform());
		AnchorCubeActor.SetActorLocationAndRotation(NodeWorld.GetLocation(), NodeWorld.GetRotation().Rotator());
		AnchorCubeActor.SetActorScale3D(NodeWorld.GetScale3D());
	}
}
