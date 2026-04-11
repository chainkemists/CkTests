//============================================================================
// INTEGER CLAMPING & SIGNALS ENTITY SCRIPT
//============================================================================

class UCk_EntityScript_IntegerGym_Clamping : UCk_EntityScript_UE
{
	default _Replication = ECk_Replication::DoesNotReplicate;

	UPROPERTY(ExposeOnSpawn)
	FTransform InitialTransform = FTransform::Identity;

	FCk_Handle_IntegerAttribute ResourceAttribute;

	int32 MinClampCount = 0;
	int32 MaxClampCount = 0;
	int32 LastInputValue = 50;

	// Auto-cycling test values
	int32 CurrentTestValue = 50;
	bool IsIncreasing = true;

	UFUNCTION(BlueprintOverride)
	ECk_EntityScript_ConstructionFlow
	DoConstruct(
		FCk_Handle& InHandle)
	{
		utils_transform::Add(InHandle, InitialTransform, ECk_Replication::Replicates);
		utils_entity_tag::Add(InHandle, n"TAG_IntegerGym_Clamping");

		Request_SetupTimers(InHandle);
		return ECk_EntityScript_ConstructionFlow::Finished;
	}

	UFUNCTION(BlueprintOverride)
	void
	DoBeginPlay(
		FCk_Handle InHandle)
	{
		Request_SetupAttributes(InHandle);
		Request_BindSignals();

		utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_AttributeGym_ResetAttributes,
			FCk_Delegate_Messaging_OnBroadcast(this, n"OnResetAttributes"));
		utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_AttributeGym_TestBoundaries,
			FCk_Delegate_Messaging_OnBroadcast(this, n"OnTestBoundaries"));
	}

	void
	Request_SetupTimers(
		FCk_Handle InHandle)
	{
		auto DisplayTimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.0f));
		DisplayTimerParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
		auto DisplayTimer = utils_timer::Add(InHandle, DisplayTimerParams);
		DisplayTimer.BindTo_OnUpdate(FCk_Delegate_Timer(this, n"DisplayTick"));

		auto UpdateTimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(1.5f));
		UpdateTimerParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
		auto UpdateTimer = utils_timer::Add(InHandle, UpdateTimerParams);
		UpdateTimer.BindTo_OnDone(FCk_Delegate_Timer(this, n"UpdateTick"));
	}

	void
	Request_SetupAttributes(
		FCk_Handle InHandle)
	{
		auto ResourceParams = FCk_Fragment_IntegerAttribute_ParamsData(
			utils_gameplay_tag::ResolveGameplayTag(n"IntegerAttribute.Resource"),
			50);
		ResourceParams.Set_MinMax(ECk_MinMax::MinMax);
		ResourceParams.Set_MinValue(0);
		ResourceParams.Set_MaxValue(100);
		ResourceAttribute = utils_integer_attribute::Add(InHandle, ResourceParams);
	}

	void
	Request_BindSignals()
	{
		utils_integer_attribute::BindTo_OnMinClamped(ResourceAttribute,
			FCk_Delegate_IntegerAttribute_OnClamped(this, n"OnMinClamped"));
		utils_integer_attribute::BindTo_OnMaxClamped(ResourceAttribute,
			FCk_Delegate_IntegerAttribute_OnClamped(this, n"OnMaxClamped"));
	}

	UFUNCTION()
	private void
	UpdateTick(
		FCk_Handle_Timer InHandle,
		FCk_Chrono InChrono,
		FCk_Time InDeltaT)
	{
		Request_AutoUpdateValue();
	}

	void Request_AutoUpdateValue()
	{
		if (ck::Is_NOT_Valid(ResourceAttribute))
			return;

		// Cycle value to test clamping
		if (IsIncreasing)
		{
			CurrentTestValue += 20;
			if (CurrentTestValue >= 120)
			{
				IsIncreasing = false;
			}
		}
		else
		{
			CurrentTestValue -= 25;
			if (CurrentTestValue <= -20)
			{
				IsIncreasing = true;
			}
		}

		LastInputValue = CurrentTestValue;
		utils_integer_attribute::Request_Override(ResourceAttribute, CurrentTestValue);
	}

	UFUNCTION()
	private void
	DisplayTick(
		FCk_Handle_Timer InHandle,
		FCk_Chrono InChrono,
		FCk_Time InDeltaT)
	{
		Request_UpdateDisplay();
	}

	void
	Request_UpdateDisplay()
	{
		auto SelfEntity = ck::ToEntity(this);
		auto TitleText = "INTEGER CLAMPING (" + CkGym_Common::Get_NetworkRoleTitle(SelfEntity) + ")";
		auto DisplayText = f"Min Clamps: {MinClampCount} | Max Clamps: {MaxClampCount}\n\n";

		auto ResourceValue = utils_integer_attribute::Get_FinalValue(ResourceAttribute);
		auto ClampStatus = "";

		if (ResourceValue == 0 && LastInputValue < 0)
		{
			ClampStatus = " [MIN CLAMPED]";
		}
		else if (ResourceValue == 100 && LastInputValue > 100)
		{
			ClampStatus = " [MAX CLAMPED]";
		}
		else
		{
			ClampStatus = " [NORMAL]";
		}

		DisplayText = f"{DisplayText}Resource: {ResourceValue}/100\n";
		DisplayText = f"{DisplayText}Input Value: {LastInputValue}\n";
		DisplayText = f"{DisplayText}Status: " + ClampStatus + "\n";
		DisplayText = f"{DisplayText}Direction: " + (IsIncreasing ? "INCREASING" : "DECREASING") + "\n\n";

		// Visual representation
		auto ResourceBar = CkGym_Attribute::Create_ProgressBar(ResourceValue, 100.0f, 20);
		DisplayText = f"{DisplayText}[{ResourceBar}]";

		auto Instructions = "Tests automatic value clamping and signal callbacks.\n"
			+ "Auto-cycles values beyond min/max to trigger OnMinClamped and OnMaxClamped.\n"
			+ "Commands: Ck_GymInteger_TestBoundaries / Ck_GymInteger_ResetClamping";

		CkGym_Common::Update_StationDisplay(SelfEntity, TitleText, DisplayText, Instructions);
	}

	// Signal callbacks
	UFUNCTION()
	void OnMinClamped(FCk_Handle InAttributeOwnerEntity, FCk_Payload_IntegerAttribute_OnClamped InPayload)
	{
		MinClampCount++;
		auto SelfEntity = ck::ToEntity(this);
		CkGym_Attribute::Draw_ClampIndicator(SelfEntity, FVector(-50.0f, 0.0f, 150.0f), FLinearColor(0.0f, 0.0f, 1.0f, 1.0f));
	}

	UFUNCTION()
	void OnMaxClamped(FCk_Handle InAttributeOwnerEntity, FCk_Payload_IntegerAttribute_OnClamped InPayload)
	{
		MaxClampCount++;
		auto SelfEntity = ck::ToEntity(this);
		CkGym_Attribute::Draw_ClampIndicator(SelfEntity, FVector(50.0f, 0.0f, 150.0f), FLinearColor(1.0f, 0.0f, 0.0f, 1.0f));
	}

	// Message handlers
	UFUNCTION()
	private void OnTestBoundaries(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
	{
		auto SelfEntity = ck::ToEntity(this);
		CkGym_Common::Draw_DebugSphere(SelfEntity, FVector(0.0f, 0.0f, 250.0f), FLinearColor(1.0f, 1.0f, 0.0f, 1.0f), 25.0f, 3.0f, 2.0f);

		// Test extreme values
		utils_integer_attribute::Request_Override(ResourceAttribute, -50);
		utils_integer_attribute::Request_Override(ResourceAttribute, 150);
	}

	UFUNCTION()
	private void OnResetAttributes(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
	{
		MinClampCount = 0;
		MaxClampCount = 0;
		CurrentTestValue = 50;
		LastInputValue = 50;
		IsIncreasing = true;

		utils_integer_attribute::Request_Override(ResourceAttribute, 50);
	}
}
