USTRUCT()
struct FSceneNodeGym_DisplaySpawnParams
{
	UPROPERTY()
	FTransform InitialTransform = FTransform::Identity;

	UPROPERTY()
	ACk_SceneNodeGym_Cube LinkedCube;
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
	ACk_SceneNodeGym_Cube LinkedCube;

	UFUNCTION(BlueprintOverride)
	ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
	{
		utils_transform::Add(InHandle, InitialTransform, ECk_Replication::Replicates);
		utils_entity_tag::Add(InHandle, n"TAG_SceneNodeGym_Display");

		utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"DisplayTick"));

		return ECk_EntityScript_ConstructionFlow::Finished;
	}

	UFUNCTION()
	private void DisplayTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		if (ck::IsValid(LinkedCube) == false)
		{ return; }

		auto SelfEntity = ck::ToEntity(this);
		auto Behavior = LinkedCube.Behavior;

		auto TitleText = f"{Behavior}" + " (" + CkGym_Common::Get_NetworkRoleTitle(SelfEntity) + ")";
		auto DisplayText = "";
		auto Instructions = "";

		if (Behavior == ECk_SceneNodeGym_Behavior::ParentChild)
		{
			Display_ParentChild(DisplayText, Instructions);
		}
		else if (Behavior == ECk_SceneNodeGym_Behavior::OffsetUpdates)
		{
			Display_OffsetUpdates(DisplayText, Instructions);
		}
		else if (Behavior == ECk_SceneNodeGym_Behavior::MultipleChildren)
		{
			Display_MultipleChildren(DisplayText, Instructions);
		}
		else if (Behavior == ECk_SceneNodeGym_Behavior::Hierarchy)
		{
			Display_Hierarchy(DisplayText, Instructions);
		}

		CkGym_Common::Update_StationDisplay(SelfEntity, TitleText, DisplayText, Instructions);
	}

	private void Display_ParentChild(FString& OutDisplay, FString& OutInstructions)
	{
		auto ParentLoc = utils_transform::Get_EntityCurrentLocation(LinkedCube.EcsEntity);
		auto ChildOffset = utils_scene_node::Get_Offset(LinkedCube.ChildNode);
		auto ChildOffsetLoc = ChildOffset.GetLocation();

		OutDisplay = f"Parent Location:\n";
		OutDisplay = f"{OutDisplay}  X: {ParentLoc.X}  Y: {ParentLoc.Y}  Z: {ParentLoc.Z}\n\n";
		OutDisplay = f"{OutDisplay}Child Offset:\n";
		OutDisplay = f"{OutDisplay}  X: {ChildOffsetLoc.X}  Y: {ChildOffsetLoc.Y}  Z: {ChildOffsetLoc.Z}\n\n";
		OutDisplay = f"{OutDisplay}Orbit Radius: {LinkedCube.OrbitRadius}\n";
		OutDisplay = f"{OutDisplay}Orbit Speed: {LinkedCube.OrbitSpeed}";

		OutInstructions = "Child scene node orbits around parent entity.\n"
			+ "Uses utils_scene_node::Create() and Request_UpdateOffset_Location().\n"
			+ "Offset updated each frame with sin/cos circular path.";
	}

	private void Display_OffsetUpdates(FString& OutDisplay, FString& OutInstructions)
	{
		auto Offset = utils_scene_node::Get_Offset(LinkedCube.OffsetNode);
		auto OffsetLoc = Offset.GetLocation();
		auto OffsetRot = Offset.GetRotation().Rotator();
		auto OffsetScale = Offset.GetScale3D();

		OutDisplay = f"Offset Location:\n";
		OutDisplay = f"{OutDisplay}  X: {OffsetLoc.X}  Y: {OffsetLoc.Y}  Z: {OffsetLoc.Z}\n\n";
		OutDisplay = f"{OutDisplay}Offset Rotation:\n";
		OutDisplay = f"{OutDisplay}  P: {OffsetRot.Pitch}  Y: {OffsetRot.Yaw}  R: {OffsetRot.Roll}\n\n";
		OutDisplay = f"{OutDisplay}Offset Scale:\n";
		OutDisplay = f"{OutDisplay}  X: {OffsetScale.X}  Y: {OffsetScale.Y}  Z: {OffsetScale.Z}";

		OutInstructions = "Animates location, rotation, and scale offsets simultaneously.\n"
			+ "Uses Request_UpdateOffset_Location/Rotation/Scale().\n"
			+ "All three components oscillate via sine wave.";
	}

	private void Display_MultipleChildren(FString& OutDisplay, FString& OutInstructions)
	{
		auto ParentRot = utils_transform::Get_EntityCurrentRotation(LinkedCube.EcsEntity);

		OutDisplay = f"Parent Rotation:\n";
		OutDisplay = f"{OutDisplay}  Yaw: {ParentRot.Yaw}\n\n";
		OutDisplay = f"{OutDisplay}Children: {LinkedCube.ChildNodes.Num()}\n\n";

		for (int32 Index = 0; Index < LinkedCube.ChildNodes.Num(); ++Index)
		{
			auto ChildOffset = utils_scene_node::Get_Offset(LinkedCube.ChildNodes[Index]);
			auto ChildLoc = ChildOffset.GetLocation();
			OutDisplay = f"{OutDisplay}Child {Index + 1}: ({ChildLoc.X}, {ChildLoc.Y}, {ChildLoc.Z})\n";
		}

		OutInstructions = "Parent rotates with 4 children at cardinal offsets.\n"
			+ "Children follow parent automatically via hierarchy.\n"
			+ "Rotation speed: " + f"{LinkedCube.ParentRotationSpeed}" + " deg/s.";
	}

	private void Display_Hierarchy(FString& OutDisplay, FString& OutInstructions)
	{
		auto RootRot = utils_transform::Get_EntityCurrentRotation(LinkedCube.EcsEntity);
		auto ChildOffset = utils_scene_node::Get_Offset(LinkedCube.HierarchyChild);
		auto ChildRot = ChildOffset.GetRotation().Rotator();
		auto GrandchildOffset = utils_scene_node::Get_Offset(LinkedCube.HierarchyGrandchild);
		auto GrandchildRot = GrandchildOffset.GetRotation().Rotator();

		OutDisplay = f"Root Yaw: {RootRot.Yaw}\n\n";
		OutDisplay = f"{OutDisplay}Child Offset Yaw: {ChildRot.Yaw}\n";
		OutDisplay = f"{OutDisplay}Child Offset X: {ChildOffset.GetLocation().X}\n\n";
		OutDisplay = f"{OutDisplay}Grandchild Offset Yaw: {GrandchildRot.Yaw}\n";
		OutDisplay = f"{OutDisplay}Grandchild Offset X: {GrandchildOffset.GetLocation().X}";

		OutInstructions = "Nested chain: root -> child -> grandchild (3 levels).\n"
			+ "Root rotates, child adds its own rotation, grandchild counter-rotates.\n"
			+ "Shows compounding transforms through hierarchy.";
	}
}
