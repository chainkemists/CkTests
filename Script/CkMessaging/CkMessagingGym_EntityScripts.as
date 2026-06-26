// Language=angelscript

//============================================================================
// MESSAGING GYM - ENTITY SCRIPTS
//============================================================================

//============================================================================
// SPAWN PARAMETERS
//============================================================================

USTRUCT()
struct FMessagingGymSpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FMessagingGymSpawnParams(FTransform InTransform)
    {
        InitialTransform = InTransform;
    }
}

//============================================================================
// STATION 1: BASIC BROADCAST & LISTEN
//============================================================================

class UCk_EntityScript_MessagingGym_Basic : UCk_GenericEntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    int32 PingCount = 0;
    int32 LastSequence = -1;
    FString LastSender = "N/A";

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::Replicates);
        utils_entity_tag::Add(InHandle, n"TAG_MessagingGym_Basic");

        // Display timer
        auto DisplayTimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.0f));
        DisplayTimerParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        auto DisplayTimer = utils_timer::Add(InHandle, DisplayTimerParams);
        DisplayTimer.BindTo_OnUpdate(FCk_Delegate_Timer(this, n"DisplayTick"));

        // Bind to messages
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_MessagingGym_Ping, FCk_Delegate_Messaging_OnBroadcast(this, n"OnPing"));
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_MessagingGym_Reset, FCk_Delegate_Messaging_OnBroadcast(this, n"OnReset"));

        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    UFUNCTION()
    private void DisplayTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        auto SelfEntity = ck::ToEntity(this);
        auto TitleText = "BASIC BROADCAST & LISTEN";

        auto DisplayText = "";
        DisplayText = f"{DisplayText}Demonstrates basic message broadcast and listener binding.\n";
        DisplayText = f"{DisplayText}Tests payload extraction with sender and sequence data.\n\n";
        DisplayText = f"{DisplayText}===== Message Stats =====\n";
        DisplayText = f"{DisplayText}Pings Received: {PingCount}\n";
        DisplayText = f"{DisplayText}Last Sender: {LastSender}\n";
        DisplayText = f"{DisplayText}Last Sequence: {LastSequence}\n";

        auto Instructions = "";
        Instructions = f"{Instructions}Ck_GymMessaging_SendPing\n";
        Instructions = f"{Instructions}Ck_GymMessaging_ResetAll";

        CkGym_Common::Update_StationDisplay(SelfEntity, TitleText, DisplayText, Instructions);
    }

    UFUNCTION()
    private void OnPing(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        auto TypedPayload = InPayload.Get(FCk_Message_MessagingGym_Ping);
        PingCount++;
        LastSender = TypedPayload.Sender;
        LastSequence = TypedPayload.SequenceNumber;
        ck::Trace(f"📨 Basic: Ping #{TypedPayload.SequenceNumber} from {TypedPayload.Sender}");
    }

    UFUNCTION()
    private void OnReset(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        PingCount = 0;
        LastSequence = -1;
        LastSender = "N/A";
        ck::Trace("✅ Basic: Counters reset");
    }
}

//============================================================================
// STATION 2: MULTI-LISTENER FAN-OUT
//============================================================================

class UCk_EntityScript_MessagingGym_MultiListener : UCk_GenericEntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    int32 ListenerA_Count = 0;
    int32 ListenerB_Count = 0;
    int32 ListenerC_Count = 0;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::Replicates);
        utils_entity_tag::Add(InHandle, n"TAG_MessagingGym_MultiListener");

        // Display timer
        auto DisplayTimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.0f));
        DisplayTimerParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        auto DisplayTimer = utils_timer::Add(InHandle, DisplayTimerParams);
        DisplayTimer.BindTo_OnUpdate(FCk_Delegate_Timer(this, n"DisplayTick"));

        // Bind 3 separate delegates to the SAME message type
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_MessagingGym_Ping, FCk_Delegate_Messaging_OnBroadcast(this, n"OnPing_ListenerA"));
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_MessagingGym_Ping, FCk_Delegate_Messaging_OnBroadcast(this, n"OnPing_ListenerB"));
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_MessagingGym_Ping, FCk_Delegate_Messaging_OnBroadcast(this, n"OnPing_ListenerC"));
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_MessagingGym_Reset, FCk_Delegate_Messaging_OnBroadcast(this, n"OnReset"));

        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    UFUNCTION()
    private void DisplayTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        auto SelfEntity = ck::ToEntity(this);
        auto TitleText = "MULTI-LISTENER FAN-OUT";
        auto Total = ListenerA_Count + ListenerB_Count + ListenerC_Count;

        auto DisplayText = "";
        DisplayText = f"{DisplayText}Three delegates bound to the same message type on one entity.\n";
        DisplayText = f"{DisplayText}A single broadcast fires all three listeners simultaneously.\n\n";
        DisplayText = f"{DisplayText}===== Listener Counts =====\n";
        DisplayText = f"{DisplayText}Listener A: {ListenerA_Count}\n";
        DisplayText = f"{DisplayText}Listener B: {ListenerB_Count}\n";
        DisplayText = f"{DisplayText}Listener C: {ListenerC_Count}\n";
        DisplayText = f"{DisplayText}Total: {Total}\n";

        auto Instructions = "";
        Instructions = f"{Instructions}Ck_GymMessaging_FanOutPing\n";
        Instructions = f"{Instructions}Ck_GymMessaging_ResetAll";

        CkGym_Common::Update_StationDisplay(SelfEntity, TitleText, DisplayText, Instructions);
    }

    UFUNCTION()
    private void OnPing_ListenerA(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        ListenerA_Count++;
    }

    UFUNCTION()
    private void OnPing_ListenerB(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        ListenerB_Count++;
    }

    UFUNCTION()
    private void OnPing_ListenerC(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        ListenerC_Count++;
    }

    UFUNCTION()
    private void OnReset(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        ListenerA_Count = 0;
        ListenerB_Count = 0;
        ListenerC_Count = 0;
        ck::Trace("✅ MultiListener: Counters reset");
    }
}

//============================================================================
// STATION 3: ONE-SHOT LISTENER
//============================================================================

class UCk_EntityScript_MessagingGym_OneShot : UCk_GenericEntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    int32 PingCount = 0;
    bool IsListening = true;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::Replicates);
        utils_entity_tag::Add(InHandle, n"TAG_MessagingGym_OneShot");

        // Display timer
        auto DisplayTimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.0f));
        DisplayTimerParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        auto DisplayTimer = utils_timer::Add(InHandle, DisplayTimerParams);
        DisplayTimer.BindTo_OnUpdate(FCk_Delegate_Timer(this, n"DisplayTick"));

        // One-shot: auto-unbinds after first fire
        Request_BindOneShot(InHandle);

        // Reset is always persistent
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_MessagingGym_Reset, FCk_Delegate_Messaging_OnBroadcast(this, n"OnReset"));

        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    void Request_BindOneShot(FCk_Handle InHandle)
    {
        utils_messaging::BindTo_OnBroadcast(
            InHandle,
            FCk_Message_MessagingGym_Ping,
            FCk_Delegate_Messaging_OnBroadcast(this, n"OnPing"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::Unbind
        );
        IsListening = true;
    }

    UFUNCTION()
    private void DisplayTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        auto SelfEntity = ck::ToEntity(this);
        auto TitleText = "ONE-SHOT LISTENER";
        auto ListeningStatus = IsListening ? "LISTENING" : "NOT LISTENING";

        auto DisplayText = "";
        DisplayText = f"{DisplayText}Listener auto-unbinds after first fire using PostFireBehavior::Unbind.\n";
        DisplayText = f"{DisplayText}Subsequent broadcasts are ignored until reset re-arms the listener.\n\n";
        DisplayText = f"{DisplayText}===== One-Shot Status =====\n";
        DisplayText = f"{DisplayText}Status: {ListeningStatus}\n";
        DisplayText = f"{DisplayText}Pings Received: {PingCount}\n";

        auto Instructions = "";
        Instructions = f"{Instructions}Ck_GymMessaging_FireOneShot\n";
        Instructions = f"{Instructions}Ck_GymMessaging_ResetAll";

        CkGym_Common::Update_StationDisplay(SelfEntity, TitleText, DisplayText, Instructions);
    }

    UFUNCTION()
    private void OnPing(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        PingCount++;
        IsListening = false;
        ck::Trace(f"📨 OneShot: Ping received (count: {PingCount}), listener now unbound");
    }

    UFUNCTION()
    private void OnReset(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        PingCount = 0;
        Request_BindOneShot(ck::ToEntity(this));
        ck::Trace("✅ OneShot: Reset and re-armed");
    }
}

//============================================================================
// STATION 4: DYNAMIC BIND / UNBIND
//============================================================================

class UCk_EntityScript_MessagingGym_DynamicBind : UCk_GenericEntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    int32 PingCount = 0;
    bool IsBound = true;
    int32 BindCount = 1;
    int32 UnbindCount = 0;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::Replicates);
        utils_entity_tag::Add(InHandle, n"TAG_MessagingGym_DynamicBind");

        // Display timer
        auto DisplayTimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.0f));
        DisplayTimerParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        auto DisplayTimer = utils_timer::Add(InHandle, DisplayTimerParams);
        DisplayTimer.BindTo_OnUpdate(FCk_Delegate_Timer(this, n"DisplayTick"));

        // Start bound to Ping
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_MessagingGym_Ping, FCk_Delegate_Messaging_OnBroadcast(this, n"OnPing"));

        // ToggleBind and Reset are always bound
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_MessagingGym_ToggleBind, FCk_Delegate_Messaging_OnBroadcast(this, n"OnToggleBind"));
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_MessagingGym_Reset, FCk_Delegate_Messaging_OnBroadcast(this, n"OnReset"));

        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    UFUNCTION()
    private void DisplayTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        auto SelfEntity = ck::ToEntity(this);
        auto TitleText = "DYNAMIC BIND / UNBIND";
        auto BoundStatus = IsBound ? "BOUND" : "UNBOUND";

        auto DisplayText = "";
        DisplayText = f"{DisplayText}Runtime bind and unbind of message listeners via console commands.\n";
        DisplayText = f"{DisplayText}Tests UnbindFrom_OnBroadcast and re-binding at runtime.\n\n";
        DisplayText = f"{DisplayText}===== Bind Status =====\n";
        DisplayText = f"{DisplayText}Ping Listener: {BoundStatus}\n";
        DisplayText = f"{DisplayText}Pings Received: {PingCount}\n\n";
        DisplayText = f"{DisplayText}===== Bind History =====\n";
        DisplayText = f"{DisplayText}Bind Count: {BindCount}\n";
        DisplayText = f"{DisplayText}Unbind Count: {UnbindCount}\n";

        auto Instructions = "";
        Instructions = f"{Instructions}Ck_GymMessaging_ToggleBind\n";
        Instructions = f"{Instructions}Ck_GymMessaging_SendPingToDynamic\n";
        Instructions = f"{Instructions}Ck_GymMessaging_ResetAll";

        CkGym_Common::Update_StationDisplay(SelfEntity, TitleText, DisplayText, Instructions);
    }

    UFUNCTION()
    private void OnPing(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        PingCount++;
        ck::Trace(f"📨 DynamicBind: Ping received (count: {PingCount})");
    }

    UFUNCTION()
    private void OnToggleBind(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        auto SelfEntity = ck::ToEntity(this);

        if (IsBound)
        {
            utils_messaging::UnbindFrom_OnBroadcast(SelfEntity, FCk_Message_MessagingGym_Ping, FCk_Delegate_Messaging_OnBroadcast(this, n"OnPing"));
            IsBound = false;
            UnbindCount++;
            ck::Trace("🔓 DynamicBind: Ping listener UNBOUND");
        }
        else
        {
            utils_messaging::BindTo_OnBroadcast(SelfEntity, FCk_Message_MessagingGym_Ping, FCk_Delegate_Messaging_OnBroadcast(this, n"OnPing"));
            IsBound = true;
            BindCount++;
            ck::Trace("🔒 DynamicBind: Ping listener BOUND");
        }
    }

    UFUNCTION()
    private void OnReset(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        auto SelfEntity = ck::ToEntity(this);

        if (IsBound == false)
        {
            utils_messaging::BindTo_OnBroadcast(SelfEntity, FCk_Message_MessagingGym_Ping, FCk_Delegate_Messaging_OnBroadcast(this, n"OnPing"));
            IsBound = true;
        }

        PingCount = 0;
        BindCount = 1;
        UnbindCount = 0;
        ck::Trace("✅ DynamicBind: Reset and rebound");
    }
}

//============================================================================
// STATION 5: MULTIPLE MESSAGE TYPES
//============================================================================

class UCk_EntityScript_MessagingGym_MultiType : UCk_GenericEntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    int32 PingCount = 0;
    int32 PongCount = 0;
    int32 AlertCount = 0;

    FString LastPingSender = "N/A";
    FString LastPongResponder = "N/A";
    FString LastAlertText = "N/A";
    int32 LastAlertPriority = 0;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::Replicates);
        utils_entity_tag::Add(InHandle, n"TAG_MessagingGym_MultiType");

        // Display timer
        auto DisplayTimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.0f));
        DisplayTimerParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        auto DisplayTimer = utils_timer::Add(InHandle, DisplayTimerParams);
        DisplayTimer.BindTo_OnUpdate(FCk_Delegate_Timer(this, n"DisplayTick"));

        // Bind to 3 different message types
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_MessagingGym_Ping, FCk_Delegate_Messaging_OnBroadcast(this, n"OnPing"));
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_MessagingGym_Pong, FCk_Delegate_Messaging_OnBroadcast(this, n"OnPong"));
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_MessagingGym_Alert, FCk_Delegate_Messaging_OnBroadcast(this, n"OnAlert"));
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_MessagingGym_Reset, FCk_Delegate_Messaging_OnBroadcast(this, n"OnReset"));

        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    UFUNCTION()
    private void DisplayTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        auto SelfEntity = ck::ToEntity(this);
        auto TitleText = "MULTIPLE MESSAGE TYPES";

        auto DisplayText = "";
        DisplayText = f"{DisplayText}Single entity listening to three different message types.\n";
        DisplayText = f"{DisplayText}Ping, Pong, and Alert messages tracked independently.\n\n";
        DisplayText = f"{DisplayText}===== Ping =====\n";
        DisplayText = f"{DisplayText}Count: {PingCount}  Sender: {LastPingSender}\n\n";
        DisplayText = f"{DisplayText}===== Pong =====\n";
        DisplayText = f"{DisplayText}Count: {PongCount}  Responder: {LastPongResponder}\n\n";
        DisplayText = f"{DisplayText}===== Alert =====\n";
        DisplayText = f"{DisplayText}Count: {AlertCount}  Last: {LastAlertText} (P{LastAlertPriority})\n";

        auto Instructions = "";
        Instructions = f"{Instructions}Ck_GymMessaging_SendAllTypes\n";
        Instructions = f"{Instructions}Ck_GymMessaging_SendPong\n";
        Instructions = f"{Instructions}Ck_GymMessaging_SendAlert [priority]\n";
        Instructions = f"{Instructions}Ck_GymMessaging_ResetAll";

        CkGym_Common::Update_StationDisplay(SelfEntity, TitleText, DisplayText, Instructions);
    }

    UFUNCTION()
    private void OnPing(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        auto TypedPayload = InPayload.Get(FCk_Message_MessagingGym_Ping);
        PingCount++;
        LastPingSender = TypedPayload.Sender;
        ck::Trace(f"📨 MultiType: Ping from {TypedPayload.Sender}");
    }

    UFUNCTION()
    private void OnPong(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        auto TypedPayload = InPayload.Get(FCk_Message_MessagingGym_Pong);
        PongCount++;
        LastPongResponder = TypedPayload.Responder;
        ck::Trace(f"📨 MultiType: Pong from {TypedPayload.Responder}");
    }

    UFUNCTION()
    private void OnAlert(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        auto TypedPayload = InPayload.Get(FCk_Message_MessagingGym_Alert);
        AlertCount++;
        LastAlertText = TypedPayload.AlertText;
        LastAlertPriority = TypedPayload.Priority;
        ck::Trace(f"📨 MultiType: Alert '{TypedPayload.AlertText}' P{TypedPayload.Priority}");
    }

    UFUNCTION()
    private void OnReset(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        PingCount = 0;
        PongCount = 0;
        AlertCount = 0;
        LastPingSender = "N/A";
        LastPongResponder = "N/A";
        LastAlertText = "N/A";
        LastAlertPriority = 0;
        ck::Trace("✅ MultiType: All counters reset");
    }
}
