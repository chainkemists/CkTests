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

class UCk_EntityScript_AttributeGym_BasicAttributes : UCk_EntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    UPROPERTY(ExposeOnSpawn)
    FString StationName = "BasicAttributes";

    // Attribute handles for different types
    FCk_Handle_FloatAttribute HealthAttribute;
    FCk_Handle_ByteAttribute ArmorAttribute;
    FCk_Handle_VectorAttribute VelocityAttribute;

    // Test values
    float32 CurrentTestValue = 50.0f;
    bool IsIncreasing = true;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        // Add transform component so entity has a position
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::Replicates);

        // Add entity tag so we can find this entity later
        utils_entity_tag::Add(InHandle, n"TAG_AttributeGym_BasicAttributes");

        // Timer for display updates (every frame)
        auto DisplayTimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.0f));
        DisplayTimerParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        auto DisplayTimer = utils_timer::Add(InHandle, DisplayTimerParams);
        DisplayTimer.BindTo_OnUpdate(FCk_Delegate_Timer(this, n"DisplayTick"));

        // Timer for value updates (every 1.5 seconds)
        auto UpdateTimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(1.5f));
        UpdateTimerParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        auto UpdateTimer = utils_timer::Add(InHandle, UpdateTimerParams);
        UpdateTimer.BindTo_OnDone(FCk_Delegate_Timer(this, n"UpdateTick"));

        //------------------------------------------------------------------------
        // Attribute Setup
        //------------------------------------------------------------------------

        // Create Float Attribute (Health: 0-100)
        auto HealthParams = FCk_Fragment_FloatAttribute_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"Attribute.Health"),
            100.0f
        );
        HealthParams.Set_MinMax(ECk_MinMax::MinMax);
        HealthParams.Set_MinValue(0.0f);
        HealthParams.Set_MaxValue(100.0f);

        HealthAttribute = utils_float_attribute::Add(InHandle, HealthParams);

        // Create Byte Attribute (Armor: 0-255)
        auto ArmorParams = FCk_Fragment_ByteAttribute_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"Attribute.Armor"),
            150
        );
        ArmorParams.Set_MinMax(ECk_MinMax::MinMax);
        ArmorParams.Set_MinValue(0);
        ArmorParams.Set_MaxValue(255);

        ArmorAttribute = utils_byte_attribute::Add(InHandle, ArmorParams);

        // Create Vector Attribute (Velocity: unclamped)
        auto VelocityParams = FCk_Fragment_VectorAttribute_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"Attribute.Velocity"),
            FVector(100.0f, 50.0f, 0.0f)
        );

        VelocityAttribute = utils_vector_attribute::Add(InHandle, VelocityParams);

        // Bind to messages
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_AttributeGym_ResetAttributes, FCk_Delegate_Messaging_OnBroadcast(this, n"OnResetAttributes"));
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_AttributeGym_UpdateAttributes, FCk_Delegate_Messaging_OnBroadcast(this, n"OnUpdateAttributes"));

        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    // Timer callback for display updates (every frame)
    UFUNCTION()
    private void DisplayTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        DisplayCurrentValues();
    }

    // Timer callback for value updates (every 1.5 seconds)
    UFUNCTION()
    private void UpdateTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        utils_messaging::Broadcast(InHandle, FCk_Message_AttributeGym_UpdateAttributes());
    }

    UFUNCTION()
    private void OnUpdateAttributes(FCk_Handle InHandle, FGameplayTag InMessageName,
                                   FInstancedStruct InPayload)
    {
        if (ck::Is_NOT_Valid(HealthAttribute))
        { return; }

        // Cycle test value
        if (IsIncreasing)
        {
            CurrentTestValue += 10.0f;
            if (CurrentTestValue >= 120.0f) // Test clamping
            {
                IsIncreasing = false;
            }
        }
        else
        {
            CurrentTestValue -= 15.0f;
            if (CurrentTestValue <= -10.0f) // Test clamping
            {
                IsIncreasing = true;
            }
        }

        // Update all attributes
        utils_float_attribute::Request_Override(HealthAttribute, CurrentTestValue);

        auto ArmorValue = uint8(Math::Clamp(CurrentTestValue * 2.0f, 0.0f, 255.0f));
        utils_byte_attribute::Request_Override(ArmorAttribute, ArmorValue);

        auto VelocityValue = FVector(CurrentTestValue, CurrentTestValue * 0.5f, Math::Sin(CurrentTestValue * 0.1f) * 50.0f);
        utils_vector_attribute::Request_Override(VelocityAttribute, VelocityValue);
    }

    UFUNCTION()
    private void OnResetAttributes(FCk_Handle InHandle, FGameplayTag InMessageName,
                                   FInstancedStruct InPayload)
    {
        CurrentTestValue = 50.0f;
        IsIncreasing = true;

        if (ck::IsValid(HealthAttribute))
        {
            utils_float_attribute::Request_Override(HealthAttribute, 100.0f);
        }
        if (ck::IsValid(ArmorAttribute))
        {
            utils_byte_attribute::Request_Override(ArmorAttribute, 150);
        }
        if (ck::IsValid(VelocityAttribute))
        {
            utils_vector_attribute::Request_Override(VelocityAttribute, FVector(100.0f, 50.0f, 0.0f));
        }
    }

    void DisplayCurrentValues()
    {
        auto SelfEntity = ck::ToEntity(this);
        auto TransformHandle = SelfEntity.As_Transform();

        if (ck::Ensure(ck::IsValid(TransformHandle), "TransformHandle should be valid in gym") == false)
        {
            return;
        }

        auto TitleText = "BASIC ATTRIBUTES - AUTO CLAMPING";
        auto DisplayText = "";

        DisplayText = f"{DisplayText}Testing automatic min/max clamping behavior\n";
        DisplayText = f"{DisplayText}Values update every 1.5s, cycling through boundaries\n\n";

        DisplayText = f"{DisplayText}TEST INPUT: {CurrentTestValue} (Direction: " + (IsIncreasing ? "UP" : "DOWN") + ")\n\n";

        if (ck::IsValid(HealthAttribute))
        {
            auto HealthValue = utils_float_attribute::Get_FinalValue(HealthAttribute);
            auto HealthBar = CkGym_Attribute::Create_ProgressBar(HealthValue, 100.0f, 20);
            auto ClampSuffix = CkGym_Attribute::Get_ClampingSuffix(HealthValue, CurrentTestValue);
            DisplayText = f"{DisplayText}FLOAT Health: {HealthValue}/100\n";
            DisplayText = f"{DisplayText}[{HealthBar}]{ClampSuffix}\n\n";
        }

        if (ck::IsValid(ArmorAttribute))
        {
            auto ArmorValue = utils_byte_attribute::Get_FinalValue(ArmorAttribute);
            auto TestArmorValue = Math::Clamp(CurrentTestValue * 2.0f, 0.0f, 255.0f);
            auto ArmorBar = CkGym_Attribute::Create_ProgressBar(float32(ArmorValue), 255.0f, 20, ECk_ASCII_ProgressBar_Style::HashTag_Symbol);
            auto ClampSuffix = CkGym_Attribute::Get_ClampingSuffix(float32(ArmorValue), TestArmorValue);
            DisplayText = f"{DisplayText}BYTE Armor: {ArmorValue}/255\n";
            DisplayText = f"{DisplayText}[{ArmorBar}]{ClampSuffix}\n\n";
        }

        if (ck::IsValid(VelocityAttribute))
        {
            auto VelocityValue = utils_vector_attribute::Get_FinalValue(VelocityAttribute);
            DisplayText = f"{DisplayText}VECTOR Velocity: {VelocityValue.ToString()}\n";
            DisplayText = f"{DisplayText}Speed: {VelocityValue.Size()} (No limits - unclamped)\n\n";
        }

        DisplayText = f"{DisplayText}===== Commands =====\n";
        DisplayText = f"{DisplayText}Ck_GymAttribute_UpdateBasicValues\n";
        DisplayText = f"{DisplayText}Ck_GymAttribute_ResetBasicValues";

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
    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Attribute.BasicAttributes");
            Station.Height = 7.0f;
            Station.Title = FText::FromString("BASIC ATTRIBUTES - AUTO CLAMPING");
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Tests float, byte, and vector attributes with auto-clamping."));
            Description.Add(FText::FromString("Values cycle through boundaries every 1.5s."));
            Description.Add(FText::FromString("Console: Ck_GymAttribute_UpdateBasicValues / ResetBasicValues"));
            Station.Description = Description;
            Stations.Add(Station);
        }

        return Stations;
    }

    void Request_StartGym() override
    {
        Request_StartBasicAttributes();
        ck::Trace("✅ Attribute System Testing Gym - Basic Attributes started");
    }

    void Request_StartBasicAttributes()
    {
        auto StationTransform = Get_StationTransform("Gym.Attribute.BasicAttributes");

        // Spawn the basic attributes testing entity at the station
        auto SpawnParams = FBasicAttributesSpawnParams(StationTransform, "BasicAttributes");

        auto SpawnRequest = utils_entity_script::Request_SpawnEntity(
            Get_StationHandle("Gym.Attribute.BasicAttributes"),
            UCk_EntityScript_AttributeGym_BasicAttributes,
            FInstancedStruct::Make(SpawnParams)
        );

        if (ck::IsValid(SpawnRequest))
        {
            ck::Trace("✅ Basic Attributes station started");
        }
        else
        {
            ck::Error("❌ Failed to spawn Basic Attributes entity");
        }
    }

    // Console Commands
    UFUNCTION(Exec, DisplayName="Attribute Gym - Update Basic Values")
    void Ck_GymAttribute_UpdateBasicValues()
    {
        auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_AttributeGym_BasicAttributes");

        for (auto Entity : Entities)
        {
            utils_messaging::Broadcast(Entity, FCk_Message_AttributeGym_UpdateAttributes());
        }
    }

    UFUNCTION(Exec, DisplayName="Attribute Gym - Reset Basic Values")
    void Ck_GymAttribute_ResetBasicValues()
    {
        auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_AttributeGym_BasicAttributes");

        for (auto Entity : Entities)
        {
            utils_messaging::Broadcast(Entity, FCk_Message_AttributeGym_ResetAttributes());
        }
    }
}

//============================================================================
// GAME MODE
//============================================================================

class ACk_AttributeGym_GameMode : ACk_Gym_Base_GameMode
{
    default PlayerControllerClass = ACk_AttributeGym_PlayerController;
    default DefaultPawnClass = ACk_Gym_Base_Pawn;
}
