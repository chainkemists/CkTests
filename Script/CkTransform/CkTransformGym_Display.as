USTRUCT()
struct FTransformGym_DisplaySpawnParams
{
	UPROPERTY()
	FTransform InitialTransform = FTransform::Identity;

	UPROPERTY()
	TWeakObjectPtr<ACk_TransformGym_Cube> LinkedCube;
}

//============================================================================
// TRANSFORM GYM - DISPLAY ENTITY SCRIPT
// Reads cube actor state and updates station display text each frame.
//============================================================================

class UCk_EntityScript_TransformGym_Display : UCk_GenericEntityScript_UE
{
	default _Replication = ECk_Replication::DoesNotReplicate;

	UPROPERTY(ExposeOnSpawn)
	FTransform InitialTransform = FTransform::Identity;

	UPROPERTY(ExposeOnSpawn)
	TWeakObjectPtr<ACk_TransformGym_Cube> LinkedCube;

	UFUNCTION(BlueprintOverride)
	ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
	{
	    auto _CkPerfScope = ck::ScopedStat();
		utils_transform::Add(InHandle, InitialTransform, ECk_Replication::Replicates);
		utils_entity_tag::Add(InHandle, n"TAG_TransformGym_Display");

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
		auto CubeEntity = Cube.EcsEntity;
		auto Behavior = Cube.Behavior;

		auto TitleText = f"{Behavior}" + " (" + CkGym_Common::Get_NetworkRoleTitle(SelfEntity) + ")";
		auto DisplayText = "";
		auto Instructions = "";

		if (Behavior == ECk_TransformGym_Behavior::SetLocation)
		{
			auto CurrentLocation = utils_transform::Get_EntityCurrentLocation(CubeEntity);
			DisplayText = f"Corner: {Cube.CurrentCorner + 1} / 4\n\n";
			DisplayText = f"{DisplayText}Location X: {CurrentLocation.X}\n";
			DisplayText = f"{DisplayText}Location Y: {CurrentLocation.Y}\n";
			DisplayText = f"{DisplayText}Location Z: {CurrentLocation.Z}";

			Instructions = "Entity teleports between 4 corner positions.\n"
				+ "Uses Request_SetLocation() with ECk_LocalWorld::World.\n"
				+ "Steps every 1.5 seconds.";
		}
		else if (Behavior == ECk_TransformGym_Behavior::SetRotation)
		{
			auto CurrentRotation = utils_transform::Get_EntityCurrentRotation(CubeEntity);
			auto Rotations = Cube.Get_TargetRotations();
			auto TargetYaw = Rotations[Cube.CurrentRotationStep].Yaw;

			DisplayText = f"Step: {Cube.CurrentRotationStep + 1} / 4 (Target Yaw: {TargetYaw})\n\n";
			DisplayText = f"{DisplayText}Pitch: {CurrentRotation.Pitch}\n";
			DisplayText = f"{DisplayText}Yaw:   {CurrentRotation.Yaw}\n";
			DisplayText = f"{DisplayText}Roll:  {CurrentRotation.Roll}";

			Instructions = "Entity snaps to absolute yaw values (0, 90, 180, 270).\n"
				+ "Uses Request_SetRotation() with ECk_LocalWorld::World.\n"
				+ "Steps every 1.5 seconds.";
		}
		else if (Behavior == ECk_TransformGym_Behavior::SetScale)
		{
			auto ActualScale = utils_transform::Get_EntityCurrentScale(CubeEntity);

			DisplayText = f"Scale X: {ActualScale.X}\n";
			DisplayText = f"{DisplayText}Scale Y: {ActualScale.Y}\n";
			DisplayText = f"{DisplayText}Scale Z: {ActualScale.Z}\n\n";
			DisplayText = f"{DisplayText}Min: {Cube.MinScale}  Max: {Cube.MaxScale}\n";
			DisplayText = f"{DisplayText}Speed: {Cube.ScaleSpeed}";

			Instructions = "Entity pulses uniformly between 0.5x and 2.0x scale.\n"
				+ "Uses Request_SetScale() with a sine-wave oscillation.\n"
				+ "Updates every frame for smooth animation.";
		}
		else if (Behavior == ECk_TransformGym_Behavior::AddLocationOffset)
		{
			auto CurrentLocation = utils_transform::Get_EntityCurrentLocation(CubeEntity);

			DisplayText = f"Elapsed: {Cube.ElapsedTime}\n\n";
			DisplayText = f"{DisplayText}Location X: {CurrentLocation.X}\n";
			DisplayText = f"{DisplayText}Location Y: {CurrentLocation.Y}\n";
			DisplayText = f"{DisplayText}Location Z: {CurrentLocation.Z}\n\n";
			DisplayText = f"{DisplayText}Radius: {Cube.CircleRadius}  Speed: {Cube.CircleSpeed}";

			Instructions = "Entity traces a circular path using relative offsets.\n"
				+ "Uses Request_AddLocationOffset() each frame.\n"
				+ "Delta computed from angle difference (cos/sin).";
		}
		else if (Behavior == ECk_TransformGym_Behavior::AddRotationOffset)
		{
			auto CurrentRotation = utils_transform::Get_EntityCurrentRotation(CubeEntity);

			DisplayText = f"Speed: {Cube.RotationSpeed} deg/s\n\n";
			DisplayText = f"{DisplayText}Pitch: {CurrentRotation.Pitch}\n";
			DisplayText = f"{DisplayText}Yaw:   {CurrentRotation.Yaw}\n";
			DisplayText = f"{DisplayText}Roll:  {CurrentRotation.Roll}";

			Instructions = "Entity spins continuously via incremental yaw offsets.\n"
				+ "Uses Request_AddRotationOffset() each frame.\n"
				+ "Rotation speed: 45 degrees per second.";
		}
		else if (Behavior == ECk_TransformGym_Behavior::DirectionalVectors)
		{
			auto CurrentRotation = utils_transform::Get_EntityCurrentRotation(CubeEntity);
			auto ForwardVec = utils_transform::Get_EntityForwardVector(CubeEntity);
			auto RightVec = utils_transform::Get_EntityRightVector(CubeEntity);
			auto UpVec = utils_transform::Get_EntityUpVector(CubeEntity);

			DisplayText = f"Rotation Speed: {Cube.RotationSpeed} deg/s\n\n";
			DisplayText = f"{DisplayText}Current Yaw: {CurrentRotation.Yaw}\n\n";
			DisplayText = f"{DisplayText}Forward: ({ForwardVec.X}, {ForwardVec.Y}, {ForwardVec.Z})\n";
			DisplayText = f"{DisplayText}Right:   ({RightVec.X}, {RightVec.Y}, {RightVec.Z})\n";
			DisplayText = f"{DisplayText}Up:      ({UpVec.X}, {UpVec.Y}, {UpVec.Z})";

			Instructions = "Shows Forward (red), Right (green), Up (blue) vectors.\n"
				+ "Entity rotates slowly to visualize orientation changes.\n"
				+ "Uses Get_EntityForwardVector/RightVector/UpVector.";
		}

		CkGym_Common::Update_StationDisplay(SelfEntity, TitleText, DisplayText, Instructions);
	}
}
