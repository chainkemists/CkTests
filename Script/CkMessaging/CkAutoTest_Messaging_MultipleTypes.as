// Language=angelscript

//============================================================================
// CK MESSAGING - AUTOMATION TEST: MULTIPLE MESSAGE TYPES
//============================================================================
//
// Verifies that distinct message types route to their own delegates and
// don't cross-fire:
//   1. Bind separate delegates for Ping, Pong, Alert.
//   2. Broadcast one of each.
//   3. Each callback fires exactly once with the correct payload type.
//
// Mirrors CkMessagingGym_MultiType.
//============================================================================

class UCk_AutoTest_Messaging_MultipleTypes : UCk_AutoTest_Base
{
    private int32 _PingCount = 0;
    private int32 _PongCount = 0;
    private int32 _AlertCount = 0;
    private FString _PingSender;
    private FString _PongResponder;
    private FString _AlertText;
    private int32 _AlertPriority = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        utils_messaging::BindTo_OnBroadcast(LocalHandle, FCk_Message_MessagingGym_Ping,
            FCk_Delegate_Messaging_OnBroadcast(this, n"OnPing"));
        utils_messaging::BindTo_OnBroadcast(LocalHandle, FCk_Message_MessagingGym_Pong,
            FCk_Delegate_Messaging_OnBroadcast(this, n"OnPong"));
        utils_messaging::BindTo_OnBroadcast(LocalHandle, FCk_Message_MessagingGym_Alert,
            FCk_Delegate_Messaging_OnBroadcast(this, n"OnAlert"));

        utils_messaging::Broadcast(LocalHandle,
            FCk_Message_MessagingGym_Ping("PingSender", 1));
        utils_messaging::Broadcast(LocalHandle,
            FCk_Message_MessagingGym_Pong("PongResponder", 2));
        utils_messaging::Broadcast(LocalHandle,
            FCk_Message_MessagingGym_Alert("AlertText", 7));

        utils_timer::Create_Tick(LocalHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnPing(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        auto Typed = InPayload.Get(FCk_Message_MessagingGym_Ping);
        _PingCount++;
        _PingSender = Typed.Sender;
    }

    UFUNCTION()
    private void OnPong(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        auto Typed = InPayload.Get(FCk_Message_MessagingGym_Pong);
        _PongCount++;
        _PongResponder = Typed.Responder;
    }

    UFUNCTION()
    private void OnAlert(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        auto Typed = InPayload.Get(FCk_Message_MessagingGym_Alert);
        _AlertCount++;
        _AlertText = Typed.AlertText;
        _AlertPriority = Typed.Priority;
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        if (_PingCount == 0 || _PongCount == 0 || _AlertCount == 0) { return; }

        Assert_Equals_Int(_PingCount, 1, "Ping callback should fire exactly once");
        Assert_Equals_Int(_PongCount, 1, "Pong callback should fire exactly once");
        Assert_Equals_Int(_AlertCount, 1, "Alert callback should fire exactly once");

        Assert_Equals_String(_PingSender, "PingSender",
            "Ping payload should reach the Ping handler intact");
        Assert_Equals_String(_PongResponder, "PongResponder",
            "Pong payload should reach the Pong handler intact");
        Assert_Equals_String(_AlertText, "AlertText",
            "Alert payload AlertText should reach the Alert handler intact");
        Assert_Equals_Int(_AlertPriority, 7,
            "Alert payload Priority should reach the Alert handler intact");

        FinishSuccess();
    }
}
