//============================================================================
// CLAMPING & SIGNALS - DUAL STATIONS (AUTO + MANUAL)
//============================================================================

USTRUCT()
struct FClampingSpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FClampingSpawnParams(FTransform InTransform)
    {
        InitialTransform = InTransform;
    }
}

//============================================================================
// AUTO CLAMPING ENTITY SCRIPT
//============================================================================

class UCk_EntityScript_AttributeGym_ClampingAuto : UCk_EntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    FCk_Handle_FloatAttribute ManaAttribute;
    FCk_Handle_ByteAttribute StaminaAttribute;

    int32 ValueChangeCount = 0;
    int32 ClampedCount = 0;

    // Auto-cycling test values
    float32 CurrentManaTest = 50.0f;
    uint8 CurrentStaminaTest = 128;
    bool ManaIncreasing = true;
    bool StaminaIncreasing = true;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        // Add transform component so entity has a position
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::Replicates);

        // Add entity tag so we can find this entity later
        utils_entity_tag::Add(InHandle, n"TAG_AttributeGym_ClampingAuto");

        // Timer for display updates (every frame)
        auto DisplayTimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.0f));
        DisplayTimerParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        auto DisplayTimer = utils_timer::Add(InHandle, DisplayTimerParams);
        DisplayTimer.BindTo_OnUpdate(ECk_Signal_BindingPolicy::FireIfPayloadInFlight, FCk_Delegate_Timer(this, n"DisplayTick"));

        // Timer for automatic value updates (every 2 seconds)
        auto UpdateTimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(2.0f));
        UpdateTimerParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        auto UpdateTimer = utils_timer::Add(InHandle, UpdateTimerParams);
        UpdateTimer.BindTo_OnDone(ECk_Signal_BindingPolicy::FireIfPayloadInFlight, FCk_Delegate_Timer(this, n"UpdateTick"));

        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto SelfEntity = InHandle;

        // Create clamped float attribute (Mana: 0-100)
        auto ManaParams = FCk_Fragment_FloatAttribute_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"Attribute.Mana"),
            50.0f
        );
        ManaParams.Set_MinMax(ECk_MinMax::MinMax);
        ManaParams.Set_MinValue(0.0f);
        ManaParams.Set_MaxValue(100.0f);

        ManaAttribute = utils_float_attribute::Add(SelfEntity, ManaParams);

        // Create clamped byte attribute (Stamina: 0-200)
        auto StaminaParams = FCk_Fragment_ByteAttribute_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"Attribute.Stamina"),
            128
        );
        StaminaParams.Set_MinMax(ECk_MinMax::MinMax);
        StaminaParams.Set_MinValue(0);
        StaminaParams.Set_MaxValue(200);

        StaminaAttribute = utils_byte_attribute::Add(SelfEntity, StaminaParams);

        // Bind to value change signals
        if (ck::IsValid(ManaAttribute))
        {
            auto ManaDelegate = FCk_Delegate_FloatAttribute_OnValueChanged(this, n"OnManaChanged");
            utils_float_attribute::BindTo_OnValueChanged(
                ManaAttribute,
                ECk_MinMaxCurrent::Current,
                ECk_Signal_BindingPolicy::FireIfPayloadInFlight,
                ECk_Signal_PostFireBehavior::DoNothing,
                ManaDelegate
            );

            // Bind to clamping signals
            auto ManaClampedDelegate = FCk_Delegate_FloatAttribute_OnClamped(this, n"OnManaClamped");
            utils_float_attribute::BindTo_OnMinClamped(
                ManaAttribute,
                ECk_Signal_BindingPolicy::FireIfPayloadInFlight,
                ECk_Signal_PostFireBehavior::DoNothing,
                ManaClampedDelegate
            );

            utils_float_attribute::BindTo_OnMaxClamped(
                ManaAttribute,
                ECk_Signal_BindingPolicy::FireIfPayloadInFlight,
                ECk_Signal_PostFireBehavior::DoNothing,
                ManaClampedDelegate
            );
        }

        if (ck::IsValid(StaminaAttribute))
        {
            auto StaminaDelegate = FCk_Delegate_ByteAttribute_OnValueChanged(this, n"OnStaminaChanged");
            utils_byte_attribute::BindTo_OnValueChanged(
                StaminaAttribute,
                ECk_MinMaxCurrent::Current,
                ECk_Signal_BindingPolicy::FireIfPayloadInFlight,
                ECk_Signal_PostFireBehavior::DoNothing,
                StaminaDelegate
            );

            // Bind to clamping signals
            auto StaminaClampedDelegate = FCk_Delegate_ByteAttribute_OnClamped(this, n"OnStaminaClamped");
            utils_byte_attribute::BindTo_OnMinClamped(
                StaminaAttribute,
                ECk_Signal_BindingPolicy::FireIfPayloadInFlight,
                ECk_Signal_PostFireBehavior::DoNothing,
                StaminaClampedDelegate
            );

            utils_byte_attribute::BindTo_OnMaxClamped(
                StaminaAttribute,
                ECk_Signal_BindingPolicy::FireIfPayloadInFlight,
                ECk_Signal_PostFireBehavior::DoNothing,
                StaminaClampedDelegate
            );
        }

        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_AttributeGym_ResetAttributes, FCk_Delegate_Messaging_OnBroadcast(this, n"OnResetAttributes"));
    }

    // Timer callbacks
    UFUNCTION()
    private void DisplayTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        DisplayStats();
    }

    UFUNCTION()
    private void UpdateTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        Request_AutoUpdateValues();
    }

    // Signal callbacks
    UFUNCTION()
    void OnManaChanged(FCk_Handle InAttributeOwnerEntity, FCk_Payload_FloatAttribute_OnValueChanged InPayload)
    {
        ValueChangeCount++;
    }

    UFUNCTION()
    void OnStaminaChanged(FCk_Handle InAttributeOwnerEntity, FCk_Payload_ByteAttribute_OnValueChanged InPayload)
    {
        ValueChangeCount++;
    }

    UFUNCTION()
    void OnManaClamped(FCk_Handle InAttributeOwnerEntity, FCk_Payload_FloatAttribute_OnClamped InPayload)
    {
        ClampedCount++;

        auto SelfEntity = ck::SelfEntity(this);
        auto TransformHandle = SelfEntity.To_FCk_Handle_Transform();
        if (ck::IsValid(TransformHandle))
        {
            auto Transform = utils_transform::Get_EntityCurrentTransform(TransformHandle);
            auto ClampPos = Transform.GetLocation() + FVector(0.0f, 100.0f, 150.0f);
            utils_debug_draw::DrawDebugSphere(ClampPos, 25.0f, 8, FLinearColor(1.0f, 0.0f, 0.0f, 1.0f), 2.0f, 3.0f);
        }
    }

    UFUNCTION()
    void OnStaminaClamped(FCk_Handle InAttributeOwnerEntity, FCk_Payload_ByteAttribute_OnClamped InPayload)
    {
        ClampedCount++;

        auto SelfEntity = ck::SelfEntity(this);
        auto TransformHandle = SelfEntity.To_FCk_Handle_Transform();
        if (ck::IsValid(TransformHandle))
        {
            auto Transform = utils_transform::Get_EntityCurrentTransform(TransformHandle);
            auto ClampPos = Transform.GetLocation() + FVector(0.0f, -100.0f, 150.0f);
            utils_debug_draw::DrawDebugSphere(ClampPos, 25.0f, 8, FLinearColor(1.0f, 0.5f, 0.0f, 1.0f), 2.0f, 3.0f);
        }
    }

    void Request_AutoUpdateValues()
    {
        if (ck::IsValid(ManaAttribute) == false) return;

        // Cycle mana value to test clamping
        if (ManaIncreasing)
        {
            CurrentManaTest += 15.0f;
            if (CurrentManaTest >= 120.0f)
            {
                ManaIncreasing = false;
            }
        }
        else
        {
            CurrentManaTest -= 20.0f;
            if (CurrentManaTest <= -15.0f)
            {
                ManaIncreasing = true;
            }
        }

        // Cycle stamina value to test clamping
        if (StaminaIncreasing)
        {
            CurrentStaminaTest = uint8(CurrentStaminaTest + 25);
            if (CurrentStaminaTest >= 240)
            {
                StaminaIncreasing = false;
            }
        }
        else
        {
            CurrentStaminaTest = uint8(CurrentStaminaTest - 35);
            if (CurrentStaminaTest <= 0)
            {
                StaminaIncreasing = true;
            }
        }

        // Apply the test values
        utils_float_attribute::Request_Override(ManaAttribute, CurrentManaTest);

        if (ck::IsValid(StaminaAttribute))
        {
            utils_byte_attribute::Request_Override(StaminaAttribute, CurrentStaminaTest);
        }
    }

    void DisplayStats()
    {
        auto SelfEntity = ck::SelfEntity(this);
        auto TransformHandle = SelfEntity.To_FCk_Handle_Transform();

        if (ck::IsValid(TransformHandle))
        {
            auto Transform = utils_transform::Get_EntityCurrentTransform(TransformHandle);

            // Get entity network mode using framework utils
            auto NetMode = utils_net::Get_EntityNetMode(SelfEntity);
            auto IsClient = (NetMode == ECk_Net_NetModeType::Client);
            auto IsHost = (NetMode == ECk_Net_NetModeType::Host);
            auto IsClientAndHost = (NetMode == ECk_Net_NetModeType::ClientAndHost);

            // Horizontal offset - HOST left, CLIENT right
            auto DisplayOffset = FVector(0.0f, 0.0f, 200.0f);
            if (IsHost)
            {
                DisplayOffset += FVector(-200.0f, 0.0f, 0.0f); // Host to the left
            }
            else if (IsClient)
            {
                DisplayOffset += FVector(200.0f, 0.0f, 0.0f);  // Client to the right
            }
            // ClientAndHost stays centered

            auto DisplayPos = Transform.GetLocation() + DisplayOffset;

            // Header based on network role
            auto TitleText = "";
            auto DisplayText = "";

            if (IsClientAndHost)
            {
                TitleText = "AUTO CLAMP (CLIENT+HOST)";
            }
            else if (IsHost)
            {
                TitleText = "AUTO CLAMP (HOST)";
            }
            else if (IsClient)
            {
                TitleText = "AUTO CLAMP (CLIENT)";
            }
            else
            {
                TitleText = "AUTO CLAMP (UNKNOWN)";
            }

            DisplayText = f"{DisplayText}Changes: {ValueChangeCount} | Clamps: {ClampedCount}\n\n";

            if (ck::IsValid(ManaAttribute))
            {
                auto ManaValue = utils_float_attribute::Get_FinalValue(ManaAttribute);
                auto ManaBar = utils_debug_draw::Create_ASCII_ProgressBar(
                    FCk_FloatRange_0to1(ManaValue / 100.0f), 20,
                    ECk_ForwardReverse::Forward,
                    ECk_ASCII_ProgressBar_Style::Equal_Symbol
                );
                auto ClampStatus = (ManaValue != CurrentManaTest) ? " [CLAMPED]" : " [NORMAL]";
                DisplayText = f"{DisplayText}Mana: {ManaValue}/100 (In: {CurrentManaTest})" + ClampStatus + "\n";
                DisplayText = f"{DisplayText}[{ManaBar}] Dir: " + (ManaIncreasing ? "UP" : "DOWN") + "\n";
            }

            if (ck::IsValid(StaminaAttribute))
            {
                auto StaminaValue = utils_byte_attribute::Get_FinalValue(StaminaAttribute);
                auto StaminaBar = utils_debug_draw::Create_ASCII_ProgressBar(
                    FCk_FloatRange_0to1(StaminaValue / 200.0f), 20,
                    ECk_ForwardReverse::Forward,
                    ECk_ASCII_ProgressBar_Style::HashTag_Symbol
                );
                auto ClampStatus = (StaminaValue != CurrentStaminaTest) ? " [CLAMPED]" : " [NORMAL]";
                DisplayText = f"{DisplayText}Stamina: {StaminaValue}/200 (In: {CurrentStaminaTest})" + ClampStatus + "\n";
                DisplayText = f"{DisplayText}[{StaminaBar}] Dir: " + (StaminaIncreasing ? "UP" : "DOWN");
            }

            auto Owner = utils_entity_lifetime::Get_LifetimeOwner(SelfEntity);
            auto& Fragment = UCk_Utils_DynamicFragment_UE::AddOrGet_Fragment(Owner, FCkGym_Station_TitleAndDescription);
            Fragment.Title = FText::FromString(TitleText);
            Fragment.Description = FText::FromString(DisplayText);
        }
    }

    UFUNCTION()
    private void OnResetAttributes(FCk_Handle InHandle, FGameplayTag InMessageName,
                                   FInstancedStruct InPayload)
    {
        ValueChangeCount = 0;
        ClampedCount = 0;
        CurrentManaTest = 50.0f;
        CurrentStaminaTest = 128;
        ManaIncreasing = true;
        StaminaIncreasing = true;

        if (ck::IsValid(ManaAttribute))
        {
            utils_float_attribute::Request_Override(ManaAttribute, 50.0f);
        }
        if (ck::IsValid(StaminaAttribute))
        {
            utils_byte_attribute::Request_Override(StaminaAttribute, 128);
        }
    }
}

//============================================================================
// MANUAL CLAMPING ENTITY SCRIPT
//============================================================================

class UCk_EntityScript_AttributeGym_ClampingManual : UCk_EntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    FCk_Handle_FloatAttribute ManaAttribute;
    FCk_Handle_ByteAttribute StaminaAttribute;

    int32 ValueChangeCount = 0;
    int32 ClampedCount = 0;

    // Last manually set values for display
    float LastManaInput = 50.0f;
    uint8 LastStaminaInput = 128;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::Replicates);
        utils_entity_tag::Add(InHandle, n"TAG_AttributeGym_ClampingManual");

        // Timer for display updates (every frame)
        auto DisplayTimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.0f));
        DisplayTimerParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        auto DisplayTimer = utils_timer::Add(InHandle, DisplayTimerParams);
        DisplayTimer.BindTo_OnUpdate(ECk_Signal_BindingPolicy::FireIfPayloadInFlight, FCk_Delegate_Timer(this, n"DisplayTick"));

        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto SelfEntity = InHandle;

        // Create clamped float attribute (Mana: 0-100)
        auto ManaParams = FCk_Fragment_FloatAttribute_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"Attribute.Mana"),
            50.0f
        );
        ManaParams.Set_MinMax(ECk_MinMax::MinMax);
        ManaParams.Set_MinValue(0.0f);
        ManaParams.Set_MaxValue(100.0f);

        ManaAttribute = utils_float_attribute::Add(SelfEntity, ManaParams);

        // Create clamped byte attribute (Stamina: 0-200)
        auto StaminaParams = FCk_Fragment_ByteAttribute_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"Attribute.Stamina"),
            128
        );
        StaminaParams.Set_MinMax(ECk_MinMax::MinMax);
        StaminaParams.Set_MinValue(0);
        StaminaParams.Set_MaxValue(200);

        StaminaAttribute = utils_byte_attribute::Add(SelfEntity, StaminaParams);

        // Bind signals
        if (ck::IsValid(ManaAttribute))
        {
            auto ManaDelegate = FCk_Delegate_FloatAttribute_OnValueChanged(this, n"OnManaChanged");
            utils_float_attribute::BindTo_OnValueChanged(
                ManaAttribute,
                ECk_MinMaxCurrent::Current,
                ECk_Signal_BindingPolicy::FireIfPayloadInFlight,
                ECk_Signal_PostFireBehavior::DoNothing,
                ManaDelegate
            );

            auto ManaClampedDelegate = FCk_Delegate_FloatAttribute_OnClamped(this, n"OnManaClamped");
            utils_float_attribute::BindTo_OnMinClamped(
                ManaAttribute,
                ECk_Signal_BindingPolicy::FireIfPayloadInFlight,
                ECk_Signal_PostFireBehavior::DoNothing,
                ManaClampedDelegate
            );

            utils_float_attribute::BindTo_OnMaxClamped(
                ManaAttribute,
                ECk_Signal_BindingPolicy::FireIfPayloadInFlight,
                ECk_Signal_PostFireBehavior::DoNothing,
                ManaClampedDelegate
            );
        }

        if (ck::IsValid(StaminaAttribute))
        {
            auto StaminaDelegate = FCk_Delegate_ByteAttribute_OnValueChanged(this, n"OnStaminaChanged");
            utils_byte_attribute::BindTo_OnValueChanged(
                StaminaAttribute,
                ECk_MinMaxCurrent::Current,
                ECk_Signal_BindingPolicy::FireIfPayloadInFlight,
                ECk_Signal_PostFireBehavior::DoNothing,
                StaminaDelegate
            );

            auto StaminaClampedDelegate = FCk_Delegate_ByteAttribute_OnClamped(this, n"OnStaminaClamped");
            utils_byte_attribute::BindTo_OnMinClamped(
                StaminaAttribute,
                ECk_Signal_BindingPolicy::FireIfPayloadInFlight,
                ECk_Signal_PostFireBehavior::DoNothing,
                StaminaClampedDelegate
            );

            utils_byte_attribute::BindTo_OnMaxClamped(
                StaminaAttribute,
                ECk_Signal_BindingPolicy::FireIfPayloadInFlight,
                ECk_Signal_PostFireBehavior::DoNothing,
                StaminaClampedDelegate
            );
        }

        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_AttributeGym_ResetAttributes, FCk_Delegate_Messaging_OnBroadcast(this, n"OnResetAttributes"));
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_AttributeGym_TestBoundaries, FCk_Delegate_Messaging_OnBroadcast(this, n"OnTestBoundaries"));
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_AttributeGym_SetStamina, FCk_Delegate_Messaging_OnBroadcast(this, n"OnSetStaminaAttribute"));
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_AttributeGym_SetMana, FCk_Delegate_Messaging_OnBroadcast(this, n"OnSetManaAttribute"));
    }

    UFUNCTION()
    private void DisplayTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        DisplayStats();
    }

    // Signal callbacks
    UFUNCTION()
    void OnManaChanged(FCk_Handle InAttributeOwnerEntity, FCk_Payload_FloatAttribute_OnValueChanged InPayload)
    {
        ValueChangeCount++;
    }

    UFUNCTION()
    void OnStaminaChanged(FCk_Handle InAttributeOwnerEntity, FCk_Payload_ByteAttribute_OnValueChanged InPayload)
    {
        ValueChangeCount++;
    }

    UFUNCTION()
    void OnManaClamped(FCk_Handle InAttributeOwnerEntity, FCk_Payload_FloatAttribute_OnClamped InPayload)
    {
        ClampedCount++;

        auto SelfEntity = ck::SelfEntity(this);
        auto TransformHandle = SelfEntity.To_FCk_Handle_Transform();
        if (ck::IsValid(TransformHandle))
        {
            auto Transform = utils_transform::Get_EntityCurrentTransform(TransformHandle);
            auto ClampPos = Transform.GetLocation() + FVector(0.0f, 100.0f, 150.0f);
            utils_debug_draw::DrawDebugSphere(ClampPos, 25.0f, 8, FLinearColor(1.0f, 0.0f, 0.0f, 1.0f), 2.0f, 3.0f);
        }
    }

    UFUNCTION()
    void OnStaminaClamped(FCk_Handle InAttributeOwnerEntity, FCk_Payload_ByteAttribute_OnClamped InPayload)
    {
        ClampedCount++;

        auto SelfEntity = ck::SelfEntity(this);
        auto TransformHandle = SelfEntity.To_FCk_Handle_Transform();
        if (ck::IsValid(TransformHandle))
        {
            auto Transform = utils_transform::Get_EntityCurrentTransform(TransformHandle);
            auto ClampPos = Transform.GetLocation() + FVector(0.0f, -100.0f, 150.0f);
            utils_debug_draw::DrawDebugSphere(ClampPos, 25.0f, 8, FLinearColor(1.0f, 0.5f, 0.0f, 1.0f), 2.0f, 3.0f);
        }
    }

    void DisplayStats()
    {
        auto SelfEntity = ck::SelfEntity(this);
        auto TransformHandle = SelfEntity.To_FCk_Handle_Transform();

        if (ck::IsValid(TransformHandle))
        {
            auto Transform = utils_transform::Get_EntityCurrentTransform(TransformHandle);

            // Get entity network mode using framework utils
            auto NetMode = utils_net::Get_EntityNetMode(SelfEntity);
            auto IsClient = (NetMode == ECk_Net_NetModeType::Client);
            auto IsHost = (NetMode == ECk_Net_NetModeType::Host);
            auto IsClientAndHost = (NetMode == ECk_Net_NetModeType::ClientAndHost);

            // Horizontal offset - HOST left, CLIENT right
            auto DisplayOffset = FVector(0.0f, 0.0f, 200.0f);
            if (IsHost)
            {
                DisplayOffset += FVector(-200.0f, 0.0f, 0.0f); // Host to the left
            }
            else if (IsClient)
            {
                DisplayOffset += FVector(200.0f, 0.0f, 0.0f);  // Client to the right
            }
            // ClientAndHost stays centered

            auto DisplayPos = Transform.GetLocation() + DisplayOffset;

            // Header and color based on network role
            auto TitleText = "";
            auto DisplayText = "";

            if (IsClientAndHost)
            {
                TitleText = "MANUAL CLAMP (CLIENT+HOST)";
            }
            else if (IsHost)
            {
                TitleText = "MANUAL CLAMP (HOST)";
            }
            else if (IsClient)
            {
                TitleText = "MANUAL CLAMP (CLIENT)";
            }
            else
            {
                TitleText = "MANUAL CLAMP (UNKNOWN)";
            }

            DisplayText = f"{DisplayText}Changes: {ValueChangeCount} | Clamps: {ClampedCount}\n\n";

            if (ck::IsValid(ManaAttribute))
            {
                auto ManaValue = utils_float_attribute::Get_FinalValue(ManaAttribute);
                auto ManaBar = utils_debug_draw::Create_ASCII_ProgressBar(
                    FCk_FloatRange_0to1(ManaValue / 100.0f), 20,
                    ECk_ForwardReverse::Forward,
                    ECk_ASCII_ProgressBar_Style::Equal_Symbol
                );
                auto ClampStatus = (ManaValue != LastManaInput) ? " [CLAMPED]" : " [NORMAL]";
                DisplayText = f"{DisplayText}Mana: {ManaValue}/100 (Last: {LastManaInput})" + ClampStatus + "\n";
                DisplayText = f"{DisplayText}[{ManaBar}]\n";
            }

            if (ck::IsValid(StaminaAttribute))
            {
                auto StaminaValue = utils_byte_attribute::Get_FinalValue(StaminaAttribute);
                auto StaminaBar = utils_debug_draw::Create_ASCII_ProgressBar(
                    FCk_FloatRange_0to1(StaminaValue / 200.0f), 20,
                    ECk_ForwardReverse::Forward,
                    ECk_ASCII_ProgressBar_Style::HashTag_Symbol
                );
                auto ClampStatus = (StaminaValue != LastStaminaInput) ? " [CLAMPED]" : " [NORMAL]";
                DisplayText = f"{DisplayText}Stamina: {StaminaValue}/200 (Last: {LastStaminaInput})" + ClampStatus + "\n";
                DisplayText = f"{DisplayText}[{StaminaBar}]\n";
            }

            DisplayText = f"{DisplayText}COMMANDS:\n";
            DisplayText = f"{DisplayText}Ck_GymAttribute_SetMana [value]\n";
            DisplayText = f"{DisplayText}Ck_GymAttribute_SetStamina [value]\n";
            DisplayText = f"{DisplayText}Ck_GymAttribute_TestBoundaries";


            auto Owner = utils_entity_lifetime::Get_LifetimeOwner(SelfEntity);
            auto& Fragment = UCk_Utils_DynamicFragment_UE::AddOrGet_Fragment(Owner, FCkGym_Station_TitleAndDescription);
            Fragment.Title = FText::FromString(TitleText);
            Fragment.Description = FText::FromString(DisplayText);
        }
    }

    UFUNCTION()
    private void OnSetManaAttribute(FCk_Handle InHandle, FGameplayTag InMessageName,
                                   FInstancedStruct InPayload)
    {
        // Only modify attributes on server/host - clients receive replicated updates
        auto SelfEntity = ck::SelfEntity(this);
        auto NetMode = utils_net::Get_EntityNetMode(SelfEntity);
        if (NetMode == ECk_Net_NetModeType::Client)
        {
            return; // Clients don't modify attributes
        }

        auto TypedPayload = InPayload.Get(FCk_Message_AttributeGym_SetMana);
        LastManaInput = TypedPayload.Value;
        if (ck::IsValid(ManaAttribute))
        {
            utils_float_attribute::Request_Override(ManaAttribute, TypedPayload.Value);
        }
    }

    UFUNCTION()
    private void OnSetStaminaAttribute(FCk_Handle InHandle, FGameplayTag InMessageName,
                                   FInstancedStruct InPayload)
    {
        // Only modify attributes on server/host - clients receive replicated updates
        auto SelfEntity = ck::SelfEntity(this);
        auto NetMode = utils_net::Get_EntityNetMode(SelfEntity);
        if (NetMode == ECk_Net_NetModeType::Client)
        {
            return; // Clients don't modify attributes
        }

        auto TypedPayload = InPayload.Get(FCk_Message_AttributeGym_SetStamina);
        LastStaminaInput = TypedPayload.Value;
        if (ck::IsValid(StaminaAttribute))
        {
            utils_byte_attribute::Request_Override(StaminaAttribute, TypedPayload.Value);
        }
    }

    UFUNCTION()
    private void OnTestBoundaries(FCk_Handle InHandle, FGameplayTag InMessageName,
                                   FInstancedStruct InPayload)
    {
        auto SelfEntity = ck::SelfEntity(this);
        auto TransformHandle = SelfEntity.To_FCk_Handle_Transform();
        if (ck::IsValid(TransformHandle))
        {
            auto Transform = utils_transform::Get_EntityCurrentTransform(TransformHandle);
            auto TestPos = Transform.GetLocation() + FVector(0.0f, 0.0f, 300.0f);
            utils_debug_draw::DrawDebugString(TestPos, "TESTING BOUNDARIES...", nullptr, FLinearColor(1.0f, 1.0f, 0.0f, 1.0f), 3.0f);
        }

        utils_messaging::Broadcast(InHandle, FCk_Message_AttributeGym_SetStamina(250));
        utils_messaging::Broadcast(InHandle, FCk_Message_AttributeGym_SetMana(150.0f));
    }

    UFUNCTION()
    private void OnResetAttributes(FCk_Handle InHandle, FGameplayTag InMessageName,
                                   FInstancedStruct InPayload)
    {
        ValueChangeCount = 0;
        ClampedCount = 0;
        LastManaInput = 50.0f;
        LastStaminaInput = 128;

        if (ck::IsValid(ManaAttribute))
        {
            utils_float_attribute::Request_Override(ManaAttribute, 50.0f);
        }
        if (ck::IsValid(StaminaAttribute))
        {
            utils_byte_attribute::Request_Override(StaminaAttribute, 128);
        }
    }
}

//============================================================================
// PLAYER CONTROLLER
//============================================================================

class ACk_AttributeGym_ClampingDual_PlayerController : ACk_Gym_Base_PlayerController
{
    FString Get_GymName() override
    {
        return "Attribute Clamping & Signals Gym (Dual)";
    }

    FString Get_GymDescription() override
    {
        return "Tests attribute clamping with both automatic cycling and manual control";
    }

    TArray<FString> Get_RequiredStationTags() override
    {
        auto RequiredTags = TArray<FString>();
        RequiredTags.Add("Gym.Attribute.ClampingAuto");
        RequiredTags.Add("Gym.Attribute.ClampingManual");
        return RequiredTags;
    }

    void Request_StartGym() override
    {
        Request_StartClampingAuto();
        Request_StartClampingManual();
        ck::Trace("✅ Dual Clamping Gym - Both stations started");
    }

    void Request_StartClampingAuto()
    {
        auto StationTransform = Get_StationTransform("Gym.Attribute.ClampingAuto");
        auto SpawnParams = FClampingSpawnParams(StationTransform);

        auto SpawnRequest = utils_entity_script::Request_SpawnEntity(
            Get_StationHandle("Gym.Attribute.ClampingAuto"),
            UCk_EntityScript_AttributeGym_ClampingAuto,
            FInstancedStruct::Make(SpawnParams)
        );

        if (ck::IsValid(SpawnRequest))
        {
            ck::Trace("✅ Auto Clamping entity spawned");
        }
        else
        {
            ck::Error("❌ Failed to spawn Auto Clamping entity");
        }
    }

    void Request_StartClampingManual()
    {
        auto StationTransform = Get_StationTransform("Gym.Attribute.ClampingManual");
        auto SpawnParams = FClampingSpawnParams(StationTransform);

        auto SpawnRequest = utils_entity_script::Request_SpawnEntity(
            Get_StationHandle("Gym.Attribute.ClampingManual"),
            UCk_EntityScript_AttributeGym_ClampingManual,
            FInstancedStruct::Make(SpawnParams)
        );

        if (ck::IsValid(SpawnRequest))
        {
            ck::Trace("✅ Manual Clamping entity spawned");
        }
        else
        {
            ck::Error("❌ Failed to spawn Manual Clamping entity");
        }
    }

    // Auto Station Commands
    UFUNCTION(Exec, DisplayName="Attribute Gym - Reset Auto Clamping")
    void Ck_GymAttribute_ResetAutoClamp()
    {
        auto Entities = utils_entity_tag::ForEach_Entity(ck::SelfEntity(this), n"TAG_AttributeGym_ClampingAuto");
        for (auto Entity : Entities)
        {
            utils_messaging::Broadcast(Entity, FCk_Message_AttributeGym_ResetAttributes());
        }
    }

    // Manual Station Commands
    UFUNCTION(Exec, DisplayName="Attribute Gym - Set Mana")
    void Ck_GymAttribute_SetMana(float32 InValue)
    {
        auto Entities = utils_entity_tag::ForEach_Entity(ck::SelfEntity(this), n"TAG_AttributeGym_ClampingManual");
        for (auto Entity : Entities)
        {
            utils_messaging::Broadcast(Entity, FCk_Message_AttributeGym_SetMana(InValue));
        }
    }

    UFUNCTION(Exec, DisplayName="Attribute Gym - Set Stamina")
    void Ck_GymAttribute_SetStamina(int32 InValue)
    {
        auto Entities = utils_entity_tag::ForEach_Entity(ck::SelfEntity(this), n"TAG_AttributeGym_ClampingManual");
        for (auto Entity : Entities)
        {
            utils_messaging::Broadcast(Entity, FCk_Message_AttributeGym_SetStamina(uint8(Math::Clamp(InValue, 0, 255))));
        }
    }

    UFUNCTION(Exec, DisplayName="Attribute Gym - Test Boundaries")
    void Ck_GymAttribute_TestBoundaries()
    {
        auto Entities = utils_entity_tag::ForEach_Entity(ck::SelfEntity(this), n"TAG_AttributeGym_ClampingManual");
        for (auto Entity : Entities)
        {
            utils_messaging::Broadcast(Entity, FCk_Message_AttributeGym_TestBoundaries());
        }
    }

    UFUNCTION(Exec, DisplayName="Attribute Gym - Reset Manual Clamping")
    void Ck_GymAttribute_ResetManualClamp()
    {
        auto Entities = utils_entity_tag::ForEach_Entity(ck::SelfEntity(this), n"TAG_AttributeGym_ClampingManual");
        for (auto Entity : Entities)
        {
            utils_messaging::Broadcast(Entity, FCk_Message_AttributeGym_ResetAttributes());
        }
    }
}

//============================================================================
// GAME MODE
//============================================================================

class ACk_AttributeGym_ClampingDual_GameMode : ACk_Gym_Base_GameMode
{
    default PlayerControllerClass = ACk_AttributeGym_ClampingDual_PlayerController;
    default DefaultPawnClass = ACk_Gym_Base_Pawn;

    FString Get_GymName() override
    {
        return "Attribute Clamping & Signals Gym (Dual)";
    }

    FString Get_GymDescription() override
    {
        return "Tests attribute clamping with both automatic cycling and manual control";
    }

    TArray<FString> Get_RequiredStationTags() override
    {
        auto RequiredTags = TArray<FString>();
        RequiredTags.Add("Gym.Attribute.ClampingAuto");
        RequiredTags.Add("Gym.Attribute.ClampingManual");
        return RequiredTags;
    }
}