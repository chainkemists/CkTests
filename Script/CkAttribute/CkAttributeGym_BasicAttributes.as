//============================================================================
// BASIC ATTRIBUTES ENTITY SCRIPT
//============================================================================

USTRUCT()
struct FBasicAttributesSpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FBasicAttributesSpawnParams(FTransform InTransform)
    {
        InitialTransform = InTransform;
    }
}

class UCk_EntityScript_AttributeGym_BasicAttributes : UCk_EntityScript_UE
{
    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

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
        DisplayTimer.BindTo_OnDone(ECk_Signal_BindingPolicy::FireIfPayloadInFlight, FCk_Delegate_Timer(this, n"DisplayTick"));

        // Timer for value updates (every 1.5 seconds)
        auto UpdateTimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(1.5f));
        UpdateTimerParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        auto UpdateTimer = utils_timer::Add(InHandle, UpdateTimerParams);
        UpdateTimer.BindTo_OnDone(ECk_Signal_BindingPolicy::FireIfPayloadInFlight, FCk_Delegate_Timer(this, n"UpdateTick"));

        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto SelfEntity = InHandle;

        // Create Float Attribute (Health: 0-100)
        auto HealthParams = FCk_Fragment_FloatAttribute_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"Attribute.Health"),
            100.0f
        );
        HealthParams.Set_MinMax(ECk_MinMax::MinMax);
        HealthParams.Set_MinValue(0.0f);
        HealthParams.Set_MaxValue(100.0f);

        HealthAttribute = utils_float_attribute::Add(SelfEntity, HealthParams);

        // Create Byte Attribute (Armor: 0-255)
        auto ArmorParams = FCk_Fragment_ByteAttribute_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"Attribute.Armor"),
            150
        );
        ArmorParams.Set_MinMax(ECk_MinMax::MinMax);
        ArmorParams.Set_MinValue(0);
        ArmorParams.Set_MaxValue(255);

        ArmorAttribute = utils_byte_attribute::Add(SelfEntity, ArmorParams);

        // Create Vector Attribute (Velocity: unclamped)
        auto VelocityParams = FCk_Fragment_VectorAttribute_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"Attribute.Velocity"),
            FVector(100.0f, 50.0f, 0.0f)
        );

        VelocityAttribute = utils_vector_attribute::Add(SelfEntity, VelocityParams);

        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_AttributeGym_ResetAttributes, FCk_Delegate_Messaging_OnBroadcast(this, n"OnResetAttributes"));
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_AttributeGym_UpdateAttributes, FCk_Delegate_Messaging_OnBroadcast(this, n"OnUpdateAttributes"));
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
        auto SelfEntity = ck::SelfEntity(this);
        auto TransformHandle = SelfEntity.To_FCk_Handle_Transform();

        if (ck::IsValid(TransformHandle))
        {
            auto Transform = utils_transform::Get_EntityCurrentTransform(TransformHandle);
            auto DisplayPos = Transform.GetLocation() + FVector(0.0f, 0.0f, 200.0f);

            auto DisplayText = "=== BASIC ATTRIBUTES - AUTO CLAMPING TEST ===\n";
            DisplayText = f"{DisplayText}Testing automatic min/max clamping behavior\n";
            DisplayText = f"{DisplayText}Values update every 1.5s, cycling through boundaries\n";
            DisplayText = f"{DisplayText}\n";

            DisplayText = f"{DisplayText}TEST INPUT: {CurrentTestValue} (Direction: " + (IsIncreasing ? "UP" : "DOWN") + ")\n";
            DisplayText = f"{DisplayText}\n";

            if (ck::IsValid(HealthAttribute))
            {
                auto HealthValue = utils_float_attribute::Get_FinalValue(HealthAttribute);
                auto HealthBase = utils_float_attribute::Get_BaseValue(HealthAttribute);
                auto ClampStatus = (HealthValue != CurrentTestValue) ? " [CLAMPED]" : " [NORMAL]";
                DisplayText = f"{DisplayText}FLOAT: Health = {HealthValue} (Limits: 0-100)" + ClampStatus + "\n";
            }

            if (ck::IsValid(ArmorAttribute))
            {
                auto ArmorValue = utils_byte_attribute::Get_FinalValue(ArmorAttribute);
                auto ArmorBase = utils_byte_attribute::Get_BaseValue(ArmorAttribute);
                auto TestArmorValue = uint8(Math::Clamp(CurrentTestValue * 2.0f, 0.0f, 255.0f));
                auto ClampStatus = (ArmorValue != TestArmorValue) ? " [CLAMPED]" : " [NORMAL]";
                DisplayText = f"{DisplayText}BYTE: Armor = {ArmorValue} (Limits: 0-255)" + ClampStatus + "\n";
            }

            if (ck::IsValid(VelocityAttribute))
            {
                auto VelocityValue = utils_vector_attribute::Get_FinalValue(VelocityAttribute);
                DisplayText = f"{DisplayText}VECTOR: Velocity = {VelocityValue.ToString()}\n";
                DisplayText = f"{DisplayText}  Speed: {VelocityValue.Size()} (No limits - unclamped)\n";
            }

            DisplayText = f"{DisplayText}\n";
            DisplayText = f"{DisplayText}WATCH FOR:\n";
            DisplayText = f"{DisplayText}- Health stops at 0 and 100 despite input going beyond\n";
            DisplayText = f"{DisplayText}- Armor (2x input) clamps at 0 and 255 boundaries\n";
            DisplayText = f"{DisplayText}- Velocity continues growing without limits\n";
            DisplayText = f"{DisplayText}- [CLAMPED] appears when limits are enforced";

            utils_debug_draw::DrawDebugString(DisplayPos, DisplayText, nullptr, FLinearColor::White, 0.0f);
        }
    }
}

//============================================================================
// PLAYER CONTROLLER
//============================================================================

class ACk_AttributeGym_PlayerController : ACk_Gym_Base_PlayerController
{
    FString Get_GymName() override
    {
        return "Attribute System Testing Gym";
    }

    FString Get_GymDescription() override
    {
        return "Tests Float, Byte, and Vector attributes with modifiers, clamping, and signals";
    }

    TArray<FString> Get_RequiredStationTags() override
    {
        auto RequiredTags = TArray<FString>();
        RequiredTags.Add("Gym.Attribute.BasicAttributes");
        return RequiredTags;
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
        auto SpawnParams = FBasicAttributesSpawnParams(StationTransform);

        auto SpawnRequest = utils_entity_script::Request_SpawnEntity(
            ck::SelfEntity(this),
            UCk_EntityScript_AttributeGym_BasicAttributes,
            FInstancedStruct::Make(SpawnParams)
        );

        if (ck::IsValid(SpawnRequest))
        {
            ck::Trace("✅ Basic Attributes entity spawned at station location");
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
        auto Entities = utils_entity_tag::ForEach_Entity(ck::SelfEntity(this), n"TAG_AttributeGym_BasicAttributes");

        for (auto Entity : Entities)
        {
            utils_messaging::Broadcast(Entity, FCk_Message_AttributeGym_UpdateAttributes());
        }
    }

    UFUNCTION(Exec, DisplayName="Attribute Gym - Reset Basic Values")
    void Ck_GymAttribute_ResetBasicValues()
    {
        auto Entities = utils_entity_tag::ForEach_Entity(ck::SelfEntity(this), n"TAG_AttributeGym_BasicAttributes");

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

    FString Get_GymName() override
    {
        return "Attribute System Testing Gym";
    }

    FString Get_GymDescription() override
    {
        return "Tests Float, Byte, and Vector attributes with modifiers, clamping, and signals";
    }

    TArray<FString> Get_RequiredStationTags() override
    {
        auto RequiredTags = TArray<FString>();
        RequiredTags.Add("Gym.Attribute.BasicAttributes");
        return RequiredTags;
    }
}