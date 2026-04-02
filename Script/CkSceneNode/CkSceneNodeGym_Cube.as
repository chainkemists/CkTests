UENUM()
enum ECk_SceneNodeGym_Behavior
{
	ParentChild,
	OffsetUpdates,
	MultipleChildren,
	Hierarchy,
	ECk_MAX
}

UCLASS(Blueprintable)
class ACk_SceneNodeGym_Cube : AActor
{
	default bReplicates = true;
	default bAlwaysRelevant = true;
	default bReplicateMovement = true;

	UPROPERTY(DefaultComponent)
	UCk_EntityBridge_ActorComponent_UE EntityBridge;
	default EntityBridge._ConstructionScript = UCk_Entity_ConstructionScript_WithTransform_PDA;
	default EntityBridge._Replication = ECk_Replication::Replicates;

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

	UFUNCTION(BlueprintOverride)
	void BeginPlay()
	{
		TextRenderer.SetText(ck::Text(f"{Behavior}"));
	}

	UFUNCTION(BlueprintOverride)
	void ConstructionScript()
	{
		EntityBridge._OnReplicationComplete_MC.AddUFunction(this, n"OnReplicationComplete");
		EntityBridge._OnPreConstruct.AddUFunction(this, n"EcsConstructionScript");
	}

	UFUNCTION()
	private void EcsConstructionScript(FCk_Handle InEntity)
	{
		utils_transform::Add(InEntity, GetActorTransform());
	}

	UFUNCTION()
	private void OnReplicationComplete(FCk_Handle InEntity)
	{
		if (System::IsServer() == false)
		{ return; }

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
		auto ParentWorldTransform = utils_transform::Get_EntityCurrentTransform(EcsEntity);
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
		auto ChildLocalTransform = FTransform(FRotator(), FVector(120.0f, 0.0f, 0.0f), FVector(0.7f, 0.7f, 0.7f));
		HierarchyChild = utils_scene_node::Create(ParentTransform, ChildLocalTransform);
		HierarchyChildCube = SpawnChildCube("Child");

		auto GrandchildLocalTransform = FTransform(FRotator(), FVector(200.0f, 0.0f, 0.0f), FVector(0.4f, 0.4f, 0.4f));
		HierarchyGrandchild = utils_scene_node::Create(ParentTransform, GrandchildLocalTransform);
		HierarchyGrandchildCube = SpawnChildCube("Grandchild");
	}

	//------------------------------------------------------------------------
	// PER-FRAME TICK
	//------------------------------------------------------------------------

	UFUNCTION()
	private void OnFrameTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		auto DeltaSeconds = InDeltaT.Get_Seconds();
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
		// Rotate the parent — children follow automatically
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
}
