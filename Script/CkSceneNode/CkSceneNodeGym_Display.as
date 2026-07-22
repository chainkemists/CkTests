USTRUCT()
struct FSceneNodeGym_DisplaySpawnParams
{
	UPROPERTY()
	FTransform InitialTransform = FTransform::Identity;

	UPROPERTY()
	TWeakObjectPtr<ACk_SceneNodeGym_Cube> LinkedCube;
}

//============================================================================
// SCENE NODE GYM - DISPLAY ENTITY SCRIPT
// Reads cube actor state and updates station display text each frame.
//============================================================================

class UCk_EntityScript_SceneNodeGym_Display : UCk_GenericEntityScript_UE
{
	default _Replication = ECk_Replication::DoesNotReplicate;

	UPROPERTY(ExposeOnSpawn)
	FTransform InitialTransform = FTransform::Identity;

	UPROPERTY(ExposeOnSpawn)
	TWeakObjectPtr<ACk_SceneNodeGym_Cube> LinkedCube;

	UFUNCTION(BlueprintOverride)
	ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
	{
	    auto _CkPerfScope = ck::ScopedStat();
		utils_transform::Add(InHandle, InitialTransform, ECk_Replication::Replicates);
		utils_entity_tag::Add(InHandle, n"TAG_SceneNodeGym_Display");

		utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"DisplayTick"));

		return ECk_EntityScript_ConstructionFlow::Finished;
	}

	UFUNCTION()
	private void DisplayTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		auto Cube = LinkedCube.Get();
		if (ck::IsValid(Cube) == false)
		{ return; }

		auto SelfEntity = ck::ToEntity(this);
		auto Behavior = Cube.Behavior;

		auto TitleText = f"{Behavior}" + " (" + CkGym_Common::Get_NetworkRoleTitle(SelfEntity) + ")";
		auto DisplayText = "";
		auto Instructions = "";

		if (Behavior == ECk_SceneNodeGym_Behavior::ParentChild)
		{
			Display_ParentChild(Cube, DisplayText, Instructions);
		}
		else if (Behavior == ECk_SceneNodeGym_Behavior::OffsetUpdates)
		{
			Display_OffsetUpdates(Cube, DisplayText, Instructions);
		}
		else if (Behavior == ECk_SceneNodeGym_Behavior::MultipleChildren)
		{
			Display_MultipleChildren(Cube, DisplayText, Instructions);
		}
		else if (Behavior == ECk_SceneNodeGym_Behavior::Hierarchy)
		{
			Display_Hierarchy(Cube, DisplayText, Instructions);
		}

		CkGym_Common::Update_StationDisplay(SelfEntity, TitleText, DisplayText, Instructions);
	}

	private void Display_ParentChild(ACk_SceneNodeGym_Cube Cube, FString& OutDisplay, FString& OutInstructions)
	{
		auto ParentLoc = utils_transform::Get_EntityCurrentLocation(Cube.EcsEntity);
		auto ChildOffset = utils_scene_node::Get_Offset(Cube.ChildNode);
		auto ChildOffsetLoc = ChildOffset.GetLocation();

		OutDisplay = f"Parent Location:\n";
		OutDisplay = f"{OutDisplay}  X: {ParentLoc.X}  Y: {ParentLoc.Y}  Z: {ParentLoc.Z}\n\n";
		OutDisplay = f"{OutDisplay}Child Offset:\n";
		OutDisplay = f"{OutDisplay}  X: {ChildOffsetLoc.X}  Y: {ChildOffsetLoc.Y}  Z: {ChildOffsetLoc.Z}\n\n";
		OutDisplay = f"{OutDisplay}Orbit Radius: {Cube.OrbitRadius}\n";
		OutDisplay = f"{OutDisplay}Orbit Speed: {Cube.OrbitSpeed}";

		OutInstructions = "Child scene node orbits around\n"
			+ "parent entity.\n"
			+ "Uses utils_scene_node::Create()\n"
			+ "and Request_UpdateOffset_Location().\n"
			+ "Offset updated each frame with\n"
			+ "sin/cos circular path.";
	}

	private void Display_OffsetUpdates(ACk_SceneNodeGym_Cube Cube, FString& OutDisplay, FString& OutInstructions)
	{
		auto Offset = utils_scene_node::Get_Offset(Cube.OffsetNode);
		auto OffsetLoc = Offset.GetLocation();
		auto OffsetRot = Offset.GetRotation().Rotator();
		auto OffsetScale = Offset.GetScale3D();

		OutDisplay = f"Offset Location:\n";
		OutDisplay = f"{OutDisplay}  X: {OffsetLoc.X}  Y: {OffsetLoc.Y}  Z: {OffsetLoc.Z}\n\n";
		OutDisplay = f"{OutDisplay}Offset Rotation:\n";
		OutDisplay = f"{OutDisplay}  P: {OffsetRot.Pitch}  Y: {OffsetRot.Yaw}  R: {OffsetRot.Roll}\n\n";
		OutDisplay = f"{OutDisplay}Offset Scale:\n";
		OutDisplay = f"{OutDisplay}  X: {OffsetScale.X}  Y: {OffsetScale.Y}  Z: {OffsetScale.Z}";

		OutInstructions = "Animates location, rotation,\n"
			+ "and scale offsets simultaneously.\n"
			+ "Uses Request_UpdateOffset_Location\n"
			+ "/Rotation/Scale().\n"
			+ "All three components oscillate\n"
			+ "via sine wave.";
	}

	private void Display_MultipleChildren(ACk_SceneNodeGym_Cube Cube, FString& OutDisplay, FString& OutInstructions)
	{
		auto ParentRot = utils_transform::Get_EntityCurrentRotation(Cube.EcsEntity);

		OutDisplay = f"Parent Rotation:\n";
		OutDisplay = f"{OutDisplay}  Yaw: {ParentRot.Yaw}\n\n";
		OutDisplay = f"{OutDisplay}Children: {Cube.ChildNodes.Num()}\n\n";

		for (int32 Index = 0; Index < Cube.ChildNodes.Num(); ++Index)
		{
			auto ChildOffset = utils_scene_node::Get_Offset(Cube.ChildNodes[Index]);
			auto ChildLoc = ChildOffset.GetLocation();
			OutDisplay = f"{OutDisplay}Child {Index + 1}: ({ChildLoc.X}, {ChildLoc.Y}, {ChildLoc.Z})\n";
		}

		OutInstructions = "Parent rotates with 4 children\n"
			+ "at cardinal offsets.\n"
			+ "Children follow parent\n"
			+ "automatically via hierarchy.\n"
			+ "Rotation speed: " + f"{Cube.ParentRotationSpeed}" + " deg/s.";
	}

	private void Display_Hierarchy(ACk_SceneNodeGym_Cube Cube, FString& OutDisplay, FString& OutInstructions)
	{
		auto RootRot = utils_transform::Get_EntityCurrentRotation(Cube.EcsEntity);
		auto ChildOffset = utils_scene_node::Get_Offset(Cube.HierarchyChild);
		auto ChildRot = ChildOffset.GetRotation().Rotator();
		auto GrandchildOffset = utils_scene_node::Get_Offset(Cube.HierarchyGrandchild);
		auto GrandchildRot = GrandchildOffset.GetRotation().Rotator();

		OutDisplay = f"Root Yaw: {RootRot.Yaw}\n\n";
		OutDisplay = f"{OutDisplay}Child Offset Yaw: {ChildRot.Yaw}\n";
		OutDisplay = f"{OutDisplay}Child Offset X: {ChildOffset.GetLocation().X}\n\n";
		OutDisplay = f"{OutDisplay}Grandchild Offset Yaw: {GrandchildRot.Yaw}\n";
		OutDisplay = f"{OutDisplay}Grandchild Offset X: {GrandchildOffset.GetLocation().X}";

		OutInstructions = "Nested chain:\n"
			+ "root -> child -> grandchild (3 levels).\n"
			+ "Root rotates, child adds its own rotation,\n"
			+ "grandchild counter-rotates.\n"
			+ "Shows compounding transforms\n"
			+ "through hierarchy.";
	}
}
