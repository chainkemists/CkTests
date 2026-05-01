// Language=angelscript

//============================================================================
// CK MESSAGING — AUTOMATION TEST: EXPLICIT UNBIND
//============================================================================
//
// Verifies UnbindFrom_OnBroadcast removes a listener:
//   1. Bind delegate, broadcast Ping → callback fires (count=1).
//   2. UnbindFrom_OnBroadcast.
//   3. Broadcast another Ping.
//   4. Wait several ticks; callback count should remain 1 (no second fire).
//
// Mirrors the bind/unbind toggle behavior in CkMessagingGym_DynamicBind.
//============================================================================

class UCk_AutoTest_Messaging_Unbind : UCk_AutoTest_Base
{
    private FCk_Handle _SelfHandle;
    private int32 _PingCount = 0;
    private bool _UnbindIssued = false;
    private int32 _TicksAfterSecondBroadcast = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _SelfHandle = InHandle;

        utils_messaging::BindTo_OnBroadcast(_SelfHandle, FCk_Message_MessagingGym_Ping,
            FCk_Delegate_Messaging_OnBroadcast(this, n"OnPing"));

        // First broadcast — should fire.
        utils_messaging::Broadcast(_SelfHandle,
            FCk_Message_MessagingGym_Ping("First", 1));

        utils_timer::Create_Tick(_SelfHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnPing(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        _PingCount++;
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        if (!_UnbindIssued)
        {
            // Wait for first ping, then unbind and broadcast again.
            if (_PingCount == 0) { return; }
            Assert_Equals_Int(_PingCount, 1, "First broadcast should fire callback once");

            utils_messaging::UnbindFrom_OnBroadcast(_SelfHandle, FCk_Message_MessagingGym_Ping,
                FCk_Delegate_Messaging_OnBroadcast(this, n"OnPing"));

            utils_messaging::Broadcast(_SelfHandle,
                FCk_Message_MessagingGym_Ping("Second", 2));

            _UnbindIssued = true;
            return;
        }

        // After unbind + second broadcast, give the system a few ticks to
        // confirm no late callback fires.
        _TicksAfterSecondBroadcast++;
        if (_TicksAfterSecondBroadcast >= 5)
        {
            Assert_Equals_Int(_PingCount, 1,
                "Callback should not fire after UnbindFrom_OnBroadcast");
            FinishSuccess();
        }
    }
}
