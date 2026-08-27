// Language=angelscript

//============================================================================
// CK MESSAGING - AUTOMATION TEST: POST-FIRE UNBIND (ONE-SHOT)
//============================================================================
//
// Verifies that binding with PostFireBehavior::Unbind makes the listener
// auto-detach after the first fire:
//   1. Bind delegate with ECk_Signal_PostFireBehavior::Unbind.
//   2. Broadcast Ping -> callback fires (count=1).
//   3. Broadcast Ping again -> callback should NOT fire (auto-unbound).
//
// Mirrors CkMessagingGym_OneShot.
//============================================================================

class UCk_AutoTest_Messaging_PostFireUnbind : UCk_AutoTest_Base
{
    private FCk_Handle _SelfHandle;
    private int32 _PingCount = 0;
    private bool _SecondBroadcastIssued = false;
    private int32 _TicksAfterSecondBroadcast = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        _SelfHandle = InHandle;

        utils_messaging::BindTo_OnBroadcast(
            _SelfHandle,
            FCk_Message_MessagingGym_Ping,
            FCk_Delegate_Messaging_OnBroadcast(this, n"OnPing"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::Unbind);

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

        if (!_SecondBroadcastIssued)
        {
            if (_PingCount == 0) { return; }
            Assert_Equals_Int(_PingCount, 1,
                "One-shot listener should fire on first broadcast");

            utils_messaging::Broadcast(_SelfHandle,
                FCk_Message_MessagingGym_Ping("Second", 2));
            _SecondBroadcastIssued = true;
            return;
        }

        _TicksAfterSecondBroadcast++;
        if (_TicksAfterSecondBroadcast >= 5)
        {
            Assert_Equals_Int(_PingCount, 1,
                "One-shot listener should NOT fire on second broadcast (auto-unbound)");
            FinishSuccess();
        }
    }
}
