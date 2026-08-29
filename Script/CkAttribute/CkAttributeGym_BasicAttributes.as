//============================================================================
// BASIC ATTRIBUTES ENTITY SCRIPT
//============================================================================

USTRUCT()
struct FBasicAttributesSpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    UPROPERTY()
    FString StationName = "";

    FBasicAttributesSpawnParams(FTransform InTransform, FString InStationName = "")
    {
        InitialTransform = InTransform;
        StationName = InStationName;
    }
}

class UCk_EntityScript_AttributeGym_BasicAttributes : UCk_GenericEntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    UPROPERTY(ExposeOnSpawn)
    FString StationName = "BasicAttributes";

    // Attribute handles
    FCk_Handle_FloatAttribute HealthAttribute;
    FCk_Handle_ByteAttribute ArmorAttribute;
    FCk_Handle_VectorAttribute VelocityAttribute;

    // Auto mode
    FCk_Handle_Timer AutoTimer;
    bool AutoRunning = true;
    int32 AutoStep = 0;
    FCkGym_AutoConfig AutoConfig;

    // Signal counters
    int32 HealthChangeCount = 0;
    int32 ArmorChangeCount = 0;
    int32 VelocityChangeCount = 0;
    int32 ClampedCount = 0;

    //------------------------------------------------------------------------
    // Construction & Initialization
    //------------------------------------------------------------------------

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        InHandle.Set_DebugName(n"BasicAttributes");
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::Replicates);
        utils_entity_tag::Add(InHandle, n"TAG_AttributeGym_BasicAttributes");

        // Display timer (every frame)
        auto DisplayTimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.0f));
        DisplayTimerParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        auto DisplayTimer = utils_timer::Add(InHandle, DisplayTimerParams);
        DisplayTimer.BindTo_OnUpdate(FCk_Delegate_Timer(this, n"DisplayTick"));

        // Auto timer (2s cycle)
        AutoTimer = gym_auto::Setup(InHandle, this, FCk_Time(2.0f));

        // Auto config
        AutoConfig.TotalSteps = 6;
        AutoConfig.Description = "Tests float, byte, and vector attributes with auto-clamping.";
        AutoConfig.GlobalAutoCommand = "panel [T] Auto-cycle phases";
        AutoConfig.PerStationAutoCommand = "panel [T] Auto-cycle phases";
        AutoConfig.Steps.Add(FCkGym_AutoStep("SetHealth 50, SetArmor 150, SetVelocity mid", 0, 0));
        AutoConfig.Steps.Add(FCkGym_AutoStep("SetHealth 95, SetArmor 245, SetVelocity high", 1, 1));
        AutoConfig.Steps.Add(FCkGym_AutoStep("TestBoundaries (push past max)", 2, 2));
        AutoConfig.Steps.Add(FCkGym_AutoStep("SetHealth 10, SetArmor 20, SetVelocity low", 3, 3));
        AutoConfig.Steps.Add(FCkGym_AutoStep("SetHealth -10, SetArmor 0 (push past min)", 4, 4));
        AutoConfig.Steps.Add(FCkGym_AutoStep("ResetBasicValues", 5, 5));
        AutoConfig.ManualCommands.Add("panel [1] Health preset · [2] Armor preset · [3] Velocity preset");
        AutoConfig.ManualCommands.Add("panel [B] Test boundaries · [R] Reset values");
        AutoConfig.ManualCommands.Add("console Ck_GymAttribute_SetVelocity [x] [y] [z] (free-range)");

        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        Request_SetupAttributes(InHandle);
        Request_BindSignals();
        Request_BindMessages(InHandle);
    }

    void Request_SetupAttributes(FCk_Handle InHandle)
    {
        // Float Attribute (Health: 0-100)
        auto HealthParams = FCk_Fragment_FloatAttribute_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"Attribute.Health"),
            100.0f
        );
        HealthParams.Set_MinMax(ECk_MinMax::MinMax);
        HealthParams.Set_MinValue(0.0f);
        HealthParams.Set_MaxValue(100.0f);
        HealthAttribute = utils_float_attribute::Add(InHandle, HealthParams);

        // Byte Attribute (Armor: 0-255)
        auto ArmorParams = FCk_Fragment_ByteAttribute_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"Attribute.Armor"),
            150
        );
        ArmorParams.Set_MinMax(ECk_MinMax::MinMax);
        ArmorParams.Set_MinValue(0);
        ArmorParams.Set_MaxValue(255);
        ArmorAttribute = utils_byte_attribute::Add(InHandle, ArmorParams);

        // Vector Attribute (Velocity: unclamped)
        auto VelocityParams = FCk_Fragment_VectorAttribute_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"Attribute.Velocity"),
            FVector(100.0f, 50.0f, 0.0f)
        );
        VelocityAttribute = utils_vector_attribute::Add(InHandle, VelocityParams);
    }

    void Request_BindSignals()
    {
        // Health signals
        utils_float_attribute::BindTo_OnValueChanged(HealthAttribute, ECk_MinMaxCurrent::Current,
            FCk_Delegate_FloatAttribute_OnValueChanged(this, n"OnHealthValueChanged"));
        utils_float_attribute::BindTo_OnMinClamped(HealthAttribute,
            FCk_Delegate_FloatAttribute_OnClamped(this, n"OnHealthClamped"));
        utils_float_attribute::BindTo_OnMaxClamped(HealthAttribute,
            FCk_Delegate_FloatAttribute_OnClamped(this, n"OnHealthClamped"));

        // Armor signals
        utils_byte_attribute::BindTo_OnValueChanged(ArmorAttribute, ECk_MinMaxCurrent::Current,
            FCk_Delegate_ByteAttribute_OnValueChanged(this, n"OnArmorValueChanged"));
        utils_byte_attribute::BindTo_OnMinClamped(ArmorAttribute,
            FCk_Delegate_ByteAttribute_OnClamped(this, n"OnArmorClamped"));
        utils_byte_attribute::BindTo_OnMaxClamped(ArmorAttribute,
            FCk_Delegate_ByteAttribute_OnClamped(this, n"OnArmorClamped"));

        // Velocity signals
        utils_vector_attribute::BindTo_OnValueChanged(VelocityAttribute, ECk_MinMaxCurrent::Current,
            FCk_Delegate_VectorAttribute_OnValueChanged(this, n"OnVelocityValueChanged"));
    }

    void Request_BindMessages(FCk_Handle InHandle)
    {
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_AttributeGym_SetHealth,
            FCk_Delegate_Messaging_OnBroadcast(this, n"OnSetHealth"));
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_AttributeGym_SetArmor,
            FCk_Delegate_Messaging_OnBroadcast(this, n"OnSetArmor"));
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_AttributeGym_SetVelocity,
            FCk_Delegate_Messaging_OnBroadcast(this, n"OnSetVelocity"));
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_AttributeGym_TestBoundaries,
            FCk_Delegate_Messaging_OnBroadcast(this, n"OnTestBoundaries"));
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_AttributeGym_ResetAttributes,
            FCk_Delegate_Messaging_OnBroadcast(this, n"OnResetAttributes"));
    }

    //------------------------------------------------------------------------
    // Signal Callbacks
    //------------------------------------------------------------------------

    UFUNCTION()
    void OnHealthValueChanged(FCk_Handle InAttributeOwnerEntity, FCk_Payload_FloatAttribute_OnValueChanged InPayload)
    {
        HealthChangeCount++;
    }

    UFUNCTION()
    void OnHealthClamped(FCk_Handle InAttributeOwnerEntity, FCk_Payload_FloatAttribute_OnClamped InPayload)
    {
        ClampedCount++;
    }

    UFUNCTION()
    void OnArmorValueChanged(FCk_Handle InAttributeOwnerEntity, FCk_Payload_ByteAttribute_OnValueChanged InPayload)
    {
        ArmorChangeCount++;
    }

    UFUNCTION()
    void OnArmorClamped(FCk_Handle InAttributeOwnerEntity, FCk_Payload_ByteAttribute_OnClamped InPayload)
    {
        ClampedCount++;
    }

    UFUNCTION()
    void OnVelocityValueChanged(FCk_Handle InAttributeOwnerEntity, FCk_Payload_VectorAttribute_OnValueChanged InPayload)
    {
        VelocityChangeCount++;
    }

    //------------------------------------------------------------------------
    // Message Handlers
    //------------------------------------------------------------------------

    UFUNCTION()
    private void OnSetHealth(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        gym_auto::StopAuto(AutoTimer, AutoRunning);
        auto Typed = InPayload.Get(FCk_Message_AttributeGym_SetHealth);
        utils_float_attribute::Request_Override(HealthAttribute, Typed.Value, ECk_MinMaxCurrent::Current);
    }

    UFUNCTION()
    private void OnSetArmor(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        gym_auto::StopAuto(AutoTimer, AutoRunning);
        auto Typed = InPayload.Get(FCk_Message_AttributeGym_SetArmor);
        utils_byte_attribute::Request_Override(ArmorAttribute, Typed.Value, ECk_MinMaxCurrent::Current);
    }

    UFUNCTION()
    private void OnSetVelocity(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        gym_auto::StopAuto(AutoTimer, AutoRunning);
        auto Typed = InPayload.Get(FCk_Message_AttributeGym_SetVelocity);
        utils_vector_attribute::Request_Override(VelocityAttribute, Typed.Value, ECk_MinMaxCurrent::Current);
    }

    UFUNCTION()
    private void OnTestBoundaries(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        gym_auto::StopAuto(AutoTimer, AutoRunning);
        Request_TestBoundariesMax();
    }

    UFUNCTION()
    private void OnResetAttributes(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        AutoStep = 0;
        HealthChangeCount = 0;
        ArmorChangeCount = 0;
        VelocityChangeCount = 0;
        ClampedCount = 0;

        Request_ResetToDefaults();

        // Restart auto mode
        AutoRunning = true;
        utils_timer::Request_Resume(AutoTimer);
    }

    UFUNCTION()
    private void OnAutoSet(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        gym_auto::HandleAutoSet(InPayload, AutoTimer, AutoRunning);
    }

    //------------------------------------------------------------------------
    // Auto Mode
    //------------------------------------------------------------------------

    UFUNCTION()
    private void AutoTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        auto Step = AutoStep % AutoConfig.TotalSteps;
        AutoStep++;

        switch (Step)
        {
            case 0: // SetHealth 50, SetArmor 150, SetVelocity mid
                Request_SetAllValues(50.0f, 150, FVector(100.0f, 50.0f, 0.0f));
                break;

            case 1: // SetHealth 95, SetArmor 245, SetVelocity high
                Request_SetAllValues(95.0f, 245, FVector(200.0f, 100.0f, 50.0f));
                break;

            case 2: // TestBoundaries - push past max
                Request_TestBoundariesMax();
                break;

            case 3: // SetHealth 10, SetArmor 20, SetVelocity low
                Request_SetAllValues(10.0f, 20, FVector(50.0f, 25.0f, -25.0f));
                break;

            case 4: // Push past min - SetHealth -10 (clamps to 0), SetArmor 0
                Request_SetAllValues(-10.0f, 0, FVector(-50.0f, -25.0f, -50.0f));
                break;

            case 5: // Reset to defaults
                Request_ResetToDefaults();
                break;
        }
    }

    // Shared operations used by both auto steps and manual message handlers
    void Request_SetAllValues(float32 InHealth, uint8 InArmor, FVector InVelocity)
    {
        utils_float_attribute::Request_Override(HealthAttribute, InHealth, ECk_MinMaxCurrent::Current);
        utils_byte_attribute::Request_Override(ArmorAttribute, InArmor, ECk_MinMaxCurrent::Current);
        utils_vector_attribute::Request_Override(VelocityAttribute, InVelocity, ECk_MinMaxCurrent::Current);
    }

    void Request_TestBoundariesMax()
    {
        utils_float_attribute::Request_Override(HealthAttribute, 120.0f, ECk_MinMaxCurrent::Current);
        utils_byte_attribute::Request_Override(ArmorAttribute, 255, ECk_MinMaxCurrent::Current);
        utils_vector_attribute::Request_Override(VelocityAttribute, FVector(500.0f, 250.0f, 100.0f), ECk_MinMaxCurrent::Current);
    }

    void Request_ResetToDefaults()
    {
        if (ck::IsValid(HealthAttribute))
        {
            utils_float_attribute::Request_Override(HealthAttribute, 100.0f, ECk_MinMaxCurrent::Current);
        }
        if (ck::IsValid(ArmorAttribute))
        {
            utils_byte_attribute::Request_Override(ArmorAttribute, 150, ECk_MinMaxCurrent::Current);
        }
        if (ck::IsValid(VelocityAttribute))
        {
            utils_vector_attribute::Request_Override(VelocityAttribute, FVector(100.0f, 50.0f, 0.0f), ECk_MinMaxCurrent::Current);
        }
    }

    //------------------------------------------------------------------------
    // Display
    //------------------------------------------------------------------------

    UFUNCTION()
    private void DisplayTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        DisplayCurrentValues();
    }

    void DisplayCurrentValues()
    {
        auto SelfEntity = ck::ToEntity(this);
        auto TransformHandle = SelfEntity.As_Transform();

        if (ck::Ensure(ck::IsValid(TransformHandle), "TransformHandle should be valid in gym") == false)
        {
            return;
        }

        auto NetworkRole = CkGym_Common::Get_NetworkRoleTitle(SelfEntity);
        auto TitleText = "BASIC ATTRIBUTES (" + NetworkRole + ")";

        auto DisplayText = gym_auto::FormatHeader(AutoConfig, AutoRunning);

        // Attribute values
        DisplayText = DisplayText + "===== Attribute Values =====\n";

        if (ck::IsValid(HealthAttribute))
        {
            auto HealthValue = utils_float_attribute::Get_FinalValue(HealthAttribute);
            auto HealthBar = CkGym_Attribute::Create_ProgressBar(HealthValue, 100.0f, 20);
            DisplayText = f"{DisplayText}FLOAT Health: {HealthValue}/100\n";
            DisplayText = f"{DisplayText}[{HealthBar}]\n\n";
        }

        if (ck::IsValid(ArmorAttribute))
        {
            auto ArmorValue = utils_byte_attribute::Get_FinalValue(ArmorAttribute);
            auto ArmorBar = CkGym_Attribute::Create_ProgressBar(float32(ArmorValue), 255.0f, 20, ECk_ASCII_ProgressBar_Style::HashTag_Symbol);
            DisplayText = f"{DisplayText}BYTE Armor: {ArmorValue}/255\n";
            DisplayText = f"{DisplayText}[{ArmorBar}]\n\n";
        }

        if (ck::IsValid(VelocityAttribute))
        {
            auto VelocityValue = utils_vector_attribute::Get_FinalValue(VelocityAttribute);
            DisplayText = f"{DisplayText}VECTOR Velocity: {VelocityValue.ToString()}\n";
            DisplayText = f"{DisplayText}Speed: {VelocityValue.Size()} (unclamped)\n\n";
        }

        auto TotalChanges = HealthChangeCount + ArmorChangeCount + VelocityChangeCount;
        DisplayText = f"{DisplayText}Changes: {TotalChanges} | Clamps: {ClampedCount}\n";

        DisplayText = DisplayText + gym_auto::FormatAutoAndCommands(AutoConfig, AutoStep, AutoRunning);

        auto Owner = utils_entity_lifetime::Get_LifetimeOwner(SelfEntity);
        auto& Fragment = Owner.AddOrGet_Fragment(FCkGym_Station_TitleAndDescription);
        Fragment.Title = FText::FromString(TitleText);
        Fragment.Description = FText::FromString(DisplayText);
    }
}

//============================================================================
// PLAYER CONTROLLER
//============================================================================

class ACk_AttributeGym_PlayerController : ACk_Gym_Base_PlayerController
{
    // Preset-ring positions for the panel rows; each press applies the NEXT value, chosen to
    // exercise the auto-clamping (over-max, negative) the station demonstrates.
    private int32 _HealthPresetIndex = -1;
    private int32 _ArmorPresetIndex = -1;
    private int32 _VelocityPresetIndex = -1;

    // Mirror of the station's auto-cycle state - it lives in the entity script behind a broadcast
    // message with no readback, so the panel mirrors it here (starts true: the station auto-runs).
    private bool _AutoEnabled = true;

    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Attribute.BasicAttributes");
            Station.AutoSize = true;
            Station.Title = FText::FromString("BASIC ATTRIBUTES - AUTO CLAMPING");
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Tests float, byte, and vector attributes with auto-clamping."));
            Description.Add(FText::FromString("Auto-cycles through 6 phases every 2s."));
            Description.Add(FText::FromString("All knobs are on the control panel; free-range velocity via console Ck_GymAttribute_SetVelocity X Y Z"));
            Station.Description = Description;
            Stations.Add(Station);
        }

        return Stations;
    }

    void Request_StartGym() override
    {
        Request_StartBasicAttributes();
        ck::Trace("[OK] Attribute System Testing Gym - Basic Attributes started");
    }

    void Request_StartBasicAttributes()
    {
        auto StationTransform = Get_StationAnchorTransform("Gym.Attribute.BasicAttributes", ECk_GymStation_Anchor::PanelCenter);
        auto SpawnParams = FBasicAttributesSpawnParams(StationTransform, "BasicAttributes");

        auto SpawnRequest = utils_entity_script::Request_SpawnEntity(
            Get_StationHandle("Gym.Attribute.BasicAttributes"),
            UCk_EntityScript_AttributeGym_BasicAttributes,
            FInstancedStruct::Make(SpawnParams)
        );

        if (ck::IsValid(SpawnRequest))
        {
            ck::Trace("[OK] Basic Attributes station started");
        }
        else
        {
            ck::Error("[FAIL] Failed to spawn Basic Attributes entity");
        }
    }

    //------------------------------------------------------------------------
    // Control panel
    //------------------------------------------------------------------------

    TArray<FCkGym_ControlRow> Get_ControlRows() override
    {
        auto Rows = TArray<FCkGym_ControlRow>();
        Rows.Add(CkGym_Control::Header("BASIC ATTRIBUTES"));
        Rows.Add(CkGym_Control::Toggle(EKeys::T, "T", "Auto-cycle phases", _AutoEnabled));
        Rows.Add(CkGym_Control::Cycle(EKeys::One,   "1", "Health preset",   DoGet_PresetLabel(_HealthPresetIndex,   "100 / 50 / 0 / -25 / 150")));
        Rows.Add(CkGym_Control::Cycle(EKeys::Two,   "2", "Armor preset",    DoGet_PresetLabel(_ArmorPresetIndex,    "0 / 64 / 128 / 255")));
        Rows.Add(CkGym_Control::Cycle(EKeys::Three, "3", "Velocity preset", DoGet_PresetLabel(_VelocityPresetIndex, "rings")));
        Rows.Add(CkGym_Control::Action(EKeys::B, "B", "Test boundaries"));
        Rows.Add(CkGym_Control::Action(EKeys::R, "R", "Reset values"));
        Rows.Add(CkGym_Control::Status("Free-range velocity", "console Ck_GymAttribute_SetVelocity X Y Z"));
        return Rows;
    }

    void Request_ControlActivated(int32 InRowIndex) override
    {
        if (InRowIndex == 1)
        {
            _AutoEnabled = !_AutoEnabled;
            DoBroadcastAutoSet(_AutoEnabled);
        }
        else if (InRowIndex == 2)
        {
            _HealthPresetIndex = (_HealthPresetIndex + 1) % 5;
            auto Values = TArray<float32>();
            Values.Add(100.0f); Values.Add(50.0f); Values.Add(0.0f); Values.Add(-25.0f); Values.Add(150.0f);
            DoBroadcastToStation(FCk_Message_AttributeGym_SetHealth(Values[_HealthPresetIndex]));
        }
        else if (InRowIndex == 3)
        {
            _ArmorPresetIndex = (_ArmorPresetIndex + 1) % 4;
            auto Values = TArray<uint8>();
            Values.Add(uint8(0)); Values.Add(uint8(64)); Values.Add(uint8(128)); Values.Add(uint8(255));
            DoBroadcastToStation(FCk_Message_AttributeGym_SetArmor(Values[_ArmorPresetIndex]));
        }
        else if (InRowIndex == 4)
        {
            _VelocityPresetIndex = (_VelocityPresetIndex + 1) % 4;
            auto Values = TArray<FVector>();
            Values.Add(FVector::ZeroVector);
            Values.Add(FVector(100.0, 0.0, 0.0));
            Values.Add(FVector(0.0, 500.0, 0.0));
            Values.Add(FVector(9999.0, 9999.0, 9999.0));
            DoBroadcastToStation(FCk_Message_AttributeGym_SetVelocity(Values[_VelocityPresetIndex]));
        }
        else if (InRowIndex == 5)
        {
            DoBroadcastToStation(FCk_Message_AttributeGym_TestBoundaries());
        }
        else if (InRowIndex == 6)
        {
            DoBroadcastToStation(FCk_Message_AttributeGym_ResetAttributes());
            _HealthPresetIndex = -1;
            _ArmorPresetIndex = -1;
            _VelocityPresetIndex = -1;
        }
    }

    private FString DoGet_PresetLabel(int32 InIndex, FString InRing)
    {
        return InIndex < 0 ? f"({InRing})" : f"step {InIndex + 1}";
    }

    private void DoBroadcastAutoSet(bool InEnabled)
    {
        auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_AttributeGym_BasicAttributes");
        for (auto Entity : Entities)
        {
            utils_messaging::Broadcast(Entity, FCk_Message_Gym_AutoSet(InEnabled));
        }
    }

    private void DoBroadcastToStation(FCk_Message_AttributeGym_SetHealth InMessage)
    {
        auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_AttributeGym_BasicAttributes");
        for (auto Entity : Entities)
        {
            utils_messaging::Broadcast(Entity, InMessage);
        }
    }

    private void DoBroadcastToStation(FCk_Message_AttributeGym_SetArmor InMessage)
    {
        auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_AttributeGym_BasicAttributes");
        for (auto Entity : Entities)
        {
            utils_messaging::Broadcast(Entity, InMessage);
        }
    }

    private void DoBroadcastToStation(FCk_Message_AttributeGym_SetVelocity InMessage)
    {
        auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_AttributeGym_BasicAttributes");
        for (auto Entity : Entities)
        {
            utils_messaging::Broadcast(Entity, InMessage);
        }
    }

    private void DoBroadcastToStation(FCk_Message_AttributeGym_TestBoundaries InMessage)
    {
        auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_AttributeGym_BasicAttributes");
        for (auto Entity : Entities)
        {
            utils_messaging::Broadcast(Entity, InMessage);
        }
    }

    private void DoBroadcastToStation(FCk_Message_AttributeGym_ResetAttributes InMessage)
    {
        auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_AttributeGym_BasicAttributes");
        for (auto Entity : Entities)
        {
            utils_messaging::Broadcast(Entity, InMessage);
        }
    }

    //------------------------------------------------------------------------
    // Console (free-range input the panel cannot express)
    //------------------------------------------------------------------------

    UFUNCTION(Exec, DisplayName="Attribute Gym - Set Velocity")
    void Ck_GymAttribute_SetVelocity(float32 InX, float32 InY, float32 InZ)
    {
        DoBroadcastToStation(FCk_Message_AttributeGym_SetVelocity(FVector(InX, InY, InZ)));
    }
}

//============================================================================
// GAME MODE
//============================================================================

class ACk_AttributeGym_GameMode : ACkTests_Gym_Base_GameMode
{
    default PlayerControllerClass = ACk_AttributeGym_PlayerController;
    default DefaultPawnClass = ACk_Gym_Base_Pawn;
}
