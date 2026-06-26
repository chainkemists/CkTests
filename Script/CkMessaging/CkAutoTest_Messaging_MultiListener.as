// Language=angelscript

//============================================================================
// CK MESSAGING — AUTOMATION TEST: MULTI-LISTENER FAN-OUT
//============================================================================
//
// Verifies that multiple delegates bound to the same message type on the
// same entity all fire on a single broadcast (not just the first one):
//   1. Bind 3 separate delegates (A/B/C) to FCk_Message_MessagingGym_Ping.
//   2. Broadcast a single Ping.
//   3. All 3 counters increment to 1.
//
// Mirrors CkMessagingGym_MultiListener.
//============================================================================

class UCk_AutoTest_Messaging_MultiListener : UCk_AutoTest_Base
{
    private int32 _CountA = 0;
    private int32 _CountB = 0;
    private int32 _CountC = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        utils_messaging::BindTo_OnBroadcast(LocalHandle, FCk_Message_MessagingGym_Ping,
            FCk_Delegate_Messaging_OnBroadcast(this, n"OnPing_A"));
        utils_messaging::BindTo_OnBroadcast(LocalHandle, FCk_Message_MessagingGym_Ping,
            FCk_Delegate_Messaging_OnBroadcast(this, n"OnPing_B"));
        utils_messaging::BindTo_OnBroadcast(LocalHandle, FCk_Message_MessagingGym_Ping,
            FCk_Delegate_Messaging_OnBroadcast(this, n"OnPing_C"));

        utils_messaging::Broadcast(LocalHandle,
            FCk_Message_MessagingGym_Ping("AutoTest", 1));

        utils_timer::Create_Tick(LocalHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnPing_A(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        _CountA++;
    }

    UFUNCTION()
    private void OnPing_B(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        _CountB++;
    }

    UFUNCTION()
    private void OnPing_C(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        _CountC++;
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        if (_CountA == 0 || _CountB == 0 || _CountC == 0) { return; }

        Assert_Equals_Int(_CountA, 1, "Listener A should have fired exactly once");
        Assert_Equals_Int(_CountB, 1, "Listener B should have fired exactly once");
        Assert_Equals_Int(_CountC, 1, "Listener C should have fired exactly once");
        FinishSuccess();
    }
}
