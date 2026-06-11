UENUM()
enum ECk_TransformGym_Behavior
{
	SetLocation,
	SetRotation,
	SetScale,
	AddLocationOffset,
	AddRotationOffset,
	DirectionalVectors,
	ECk_MAX
}

UCLASS(Blueprintable)
class ACk_TransformGym_Cube : AActor
{
	default bReplicates = true;
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
	ECk_TransformGym_Behavior Behavior = ECk_TransformGym_Behavior::SetLocation;

	// --- Shared state ---
	FCk_Handle EcsEntity;
	float32 ElapsedTime = 0.0f;

	// --- SetLocation state ---
	int32 CurrentCorner = 0;
	float32 CornerOffsetDistance = 100.0f;

	// --- SetRotation state ---
	int32 CurrentRotationStep = 0;

	// --- SetScale state ---
	float32 ScaleSpeed = 1.5f;
	float32 MinScale = 0.5f;
	float32 MaxScale = 2.0f;

	// --- AddLocationOffset state ---
	float32 CircleRadius = 100.0f;
	float32 CircleSpeed = 1.0f;
	float32 PreviousAngle = 0.0f;

	// --- AddRotationOffset / DirectionalVectors state ---
	float32 RotationSpeed = 45.0f;
	float32 VectorDrawLength = 150.0f;

	UFUNCTION(BlueprintOverride)
	void BeginPlay()
	{
		TextRenderer.SetText(ck::Text(f"{Behavior}"));

		if (Behavior == ECk_TransformGym_Behavior::DirectionalVectors)
		{
			RotationSpeed = 20.0f;
		}

		auto PendingEntity = utils_entity_script_with_actor::Request_SpawnEntityScript_OnActor(
			this, UCk_EntityScript_WithActor_UE);
		if (utils_pending_entity_script::Get_IsValid(PendingEntity))
		{
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

		// Set up timers based on behavior
		if (Behavior == ECk_TransformGym_Behavior::SetLocation || Behavior == ECk_TransformGym_Behavior::SetRotation)
		{
			// Step timer: cycle every 1.5 seconds
			auto StepParams = FCk_Fragment_Timer_ParamsData(FCk_Time(1.5f));
			StepParams.Set_StartingState(ECk_Timer_State::Running);
			StepParams.Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
			auto StepTimer = utils_timer::Add(InEntity, StepParams);
			StepTimer.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnStepTimer"));
		}

		// Per-frame tick for continuous behaviors
		utils_timer::Create_Tick(InEntity, FCk_Delegate_Timer(this, n"OnFrameTick"));
	}

	//------------------------------------------------------------------------
	// STEP TIMER (SetLocation / SetRotation)
	//------------------------------------------------------------------------

	UFUNCTION()
	private void OnStepTimer(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		if (Behavior == ECk_TransformGym_Behavior::SetLocation)
		{
			CurrentCorner = (CurrentCorner + 1) % 4;
			auto BaseLocation = GetActorLocation();
			auto Offsets = Get_CornerOffsets();
			// Set location relative to initial spawn position
			auto TargetLocation = GetActorTransform().GetLocation() + Offsets[CurrentCorner];
			utils_transform::Request_SetLocation(EcsEntity, TargetLocation, ECk_LocalWorld::World);
		}
		else if (Behavior == ECk_TransformGym_Behavior::SetRotation)
		{
			CurrentRotationStep = (CurrentRotationStep + 1) % 4;
			auto Rotations = Get_TargetRotations();
			utils_transform::Request_SetRotation(EcsEntity, Rotations[CurrentRotationStep], ECk_LocalWorld::World);
		}
	}

	TArray<FVector> Get_CornerOffsets()
	{
		auto Offsets = TArray<FVector>();
		Offsets.Add(FVector(CornerOffsetDistance, -CornerOffsetDistance, 0.0f));
		Offsets.Add(FVector(CornerOffsetDistance, CornerOffsetDistance, 0.0f));
		Offsets.Add(FVector(-CornerOffsetDistance, CornerOffsetDistance, 0.0f));
		Offsets.Add(FVector(-CornerOffsetDistance, -CornerOffsetDistance, 0.0f));
		return Offsets;
	}

	TArray<FRotator> Get_TargetRotations()
	{
		auto Rotations = TArray<FRotator>();
		Rotations.Add(FRotator(0.0f, 0.0f, 0.0f));
		Rotations.Add(FRotator(0.0f, 90.0f, 0.0f));
		Rotations.Add(FRotator(0.0f, 180.0f, 0.0f));
		Rotations.Add(FRotator(0.0f, 270.0f, 0.0f));
		return Rotations;
	}

	//------------------------------------------------------------------------
	// PER-FRAME TICK
	//------------------------------------------------------------------------

	UFUNCTION()
	private void OnFrameTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		auto DeltaSeconds = float32(InDeltaT.Get_Seconds());
		ElapsedTime = ElapsedTime + DeltaSeconds;

		if (Behavior == ECk_TransformGym_Behavior::SetScale)
		{
			Tick_SetScale(DeltaSeconds);
		}
		else if (Behavior == ECk_TransformGym_Behavior::AddLocationOffset)
		{
			Tick_AddLocationOffset(DeltaSeconds);
		}
		else if (Behavior == ECk_TransformGym_Behavior::AddRotationOffset)
		{
			Tick_AddRotationOffset(DeltaSeconds);
		}
		else if (Behavior == ECk_TransformGym_Behavior::DirectionalVectors)
		{
			Tick_DirectionalVectors(DeltaSeconds);
		}
	}

	private void Tick_SetScale(float32 DeltaSeconds)
	{
		auto SineValue = Math::Sin(ElapsedTime * ScaleSpeed);
		auto NormalizedValue = (SineValue + 1.0f) * 0.5f;
		auto CurrentScale = MinScale + (MaxScale - MinScale) * NormalizedValue;
		auto ScaleVector = FVector(CurrentScale, CurrentScale, CurrentScale);
		utils_transform::Request_SetScale(EcsEntity, ScaleVector, ECk_LocalWorld::World);
	}

	private void Tick_AddLocationOffset(float32 DeltaSeconds)
	{
		auto CurrentAngle = ElapsedTime * CircleSpeed;
		auto DeltaX = CircleRadius * (Math::Cos(CurrentAngle) - Math::Cos(PreviousAngle));
		auto DeltaY = CircleRadius * (Math::Sin(CurrentAngle) - Math::Sin(PreviousAngle));
		PreviousAngle = CurrentAngle;

		auto Offset = FVector(DeltaX, DeltaY, 0.0f);
		utils_transform::Request_AddLocationOffset(EcsEntity, Offset, ECk_LocalWorld::World);
	}

	private void Tick_AddRotationOffset(float32 DeltaSeconds)
	{
		auto DeltaYaw = RotationSpeed * DeltaSeconds;
		utils_transform::Request_AddRotationOffset(EcsEntity, FRotator(0.0f, DeltaYaw, 0.0f), ECk_LocalWorld::World);
	}

	private void Tick_DirectionalVectors(float32 DeltaSeconds)
	{
		auto DeltaYaw = RotationSpeed * DeltaSeconds;
		utils_transform::Request_AddRotationOffset(EcsEntity, FRotator(0.0f, DeltaYaw, 0.0f), ECk_LocalWorld::World);

		auto ForwardVec = utils_transform::Get_EntityForwardVector(EcsEntity);
		auto RightVec = utils_transform::Get_EntityRightVector(EcsEntity);
		auto UpVec = utils_transform::Get_EntityUpVector(EcsEntity);
		auto Origin = utils_transform::Get_EntityCurrentLocation(EcsEntity);

		auto RedColor = FLinearColor(1.0f, 0.0f, 0.0f, 1.0f);
		auto GreenColor = FLinearColor(0.0f, 1.0f, 0.0f, 1.0f);
		auto BlueColor = FLinearColor(0.0f, 0.0f, 1.0f, 1.0f);

		utils_debug_draw::DrawDebugLine(Origin, Origin + ForwardVec * VectorDrawLength, RedColor, 0.0f, 2.0f);
		utils_debug_draw::DrawDebugLine(Origin, Origin + RightVec * VectorDrawLength, GreenColor, 0.0f, 2.0f);
		utils_debug_draw::DrawDebugLine(Origin, Origin + UpVec * VectorDrawLength, BlueColor, 0.0f, 2.0f);

		utils_debug_draw::DrawDebugString(Origin + ForwardVec * VectorDrawLength, "FWD", RedColor, 0.0f);
		utils_debug_draw::DrawDebugString(Origin + RightVec * VectorDrawLength, "RIGHT", GreenColor, 0.0f);
		utils_debug_draw::DrawDebugString(Origin + UpVec * VectorDrawLength, "UP", BlueColor, 0.0f);
	}
}
