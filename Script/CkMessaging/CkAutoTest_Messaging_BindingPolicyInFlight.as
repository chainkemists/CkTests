// Language=angelscript

//============================================================================
// CK MESSAGING — AUTOMATION TEST: BINDING POLICY (IN-FLIGHT PAYLOAD)
//============================================================================
//
// Verifies the BindingPolicy contract for messaging signals:
//   1. Broadcast a Ping FIRST, before any binds.
//   2. Bind a listener with FireIfPayloadInFlightThisFrame. Expect it
//      to fire immediately with the in-flight payload (count goes to 1).
//   3. Bind a second listener with IgnorePayloadInFlight. Expect it to
//      NOT fire — it should only respond to future broadcasts.
//   4. Wait several ticks; ignore-listener stays at 0; in-flight at 1.
//
// Pins down the policy distinction documented in CkSignal_Fragment_Data.h
// — gameplay code that needs to "react to events that already happened
// before I bound" relies on FireIfPayloadInFlight; code that explicitly
// wants to skip past events relies on IgnorePayloadInFlight.
//============================================================================

class UCk_AutoTest_Messaging_BindingPolicyInFlight : UCk_AutoTest_Base
{
    private FCk_Handle _SelfHandle;
    private int32 _InFlightCount = 0;
    private int32 _IgnoreCount = 0;
    private int32 _TicksSinceBind = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        _SelfHandle = InHandle;

        // Step 1: broadcast BEFORE any binds. The in-flight payload sits in
        // the signal's queue.
        utils_messaging::Broadcast(_SelfHandle,
            FCk_Message_MessagingGym_Ping("AutoTest", 1));

        // Step 2: bind with FireIfPayloadInFlightThisFrame — should fire
        // immediately on bind because a payload is in flight this frame.
        utils_messaging::BindTo_OnBroadcast(
            _SelfHandle,
            FCk_Message_MessagingGym_Ping,
            FCk_Delegate_Messaging_OnBroadcast(this, n"OnInFlightPing"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);

        // Step 3: bind with IgnorePayloadInFlight — should NOT fire on bind
        // for the in-flight payload, only on future broadcasts.
        utils_messaging::BindTo_OnBroadcast(
            _SelfHandle,
            FCk_Message_MessagingGym_Ping,
            FCk_Delegate_Messaging_OnBroadcast(this, n"OnIgnorePing"),
            ECk_Signal_BindingPolicy::IgnorePayloadInFlight,
            ECk_Signal_PostFireBehavior::DoNothing);

        utils_timer::Create_Tick(_SelfHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnInFlightPing(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        _InFlightCount++;
    }

    UFUNCTION()
    private void OnIgnorePing(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        _IgnoreCount++;
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        _TicksSinceBind++;
        if (_TicksSinceBind >= 5)
        {
            Assert_Equals_Int(_InFlightCount, 1,
                "FireIfPayloadInFlightThisFrame listener should fire once for the in-flight payload");
            Assert_Equals_Int(_IgnoreCount, 0,
                "IgnorePayloadInFlight listener should NOT fire for the in-flight payload");
            FinishSuccess();
        }
    }
}
