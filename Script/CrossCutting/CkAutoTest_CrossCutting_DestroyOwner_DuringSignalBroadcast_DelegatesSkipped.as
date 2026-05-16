// Language=angelscript

//============================================================================
// CK CROSS-CUTTING — AUTOMATION TEST: SELF-DESTRUCT DURING SIGNAL BROADCAST
//============================================================================
//
// Pins the contract that destroying an entity from inside one of its own
// signal handlers must not crash, and that no further broadcast-handler
// reentrancy happens after self-destruct. This is the high-traffic "entity
// self-destructs on first event" gameplay pattern (one-shot pickups,
// expiring buffs, etc.).
//
// NOTE on broadcast targeting: broadcasting on a destroyed entity is an
// ensure-fail in the framework (the entity's signal-fragment storage is
// torn down with the entity). This test does NOT attempt a follow-up
// broadcast on the dead entity — that would be an illegal call. Instead
// it verifies the GA-flow contract: the handler fires exactly once for
// the legitimate broadcast, the entity is invalid afterward, and no
// internal callbacks reentrant on the dying entity fire.
//
// Setup:
//   - Create a child entity E.
//   - Bind a Ping handler on E whose body calls Request_DestroyEntity(E).
//   - Broadcast Ping to E.
//   - WaitOneFrame to let destruction settle.
//
// Pass: handler invoked exactly once; E invalid afterward; no crash from
//   self-destruct during the broadcast traversal.
//============================================================================

class UCk_AutoTest_CrossCutting_DestroyOwner_DuringSignalBroadcast_DelegatesSkipped : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    private FCk_Handle _Child;
    private int32 _PingCount = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;

        _Child = utils_entity_lifetime::Request_CreateEntity(LocalHandle);

        utils_messaging::BindTo_OnBroadcast(
            _Child,
            FCk_Message_MessagingGym_Ping,
            FCk_Delegate_Messaging_OnBroadcast(this, n"OnPingHandler"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);

        // Broadcast — handler will self-destruct the child entity.
        utils_messaging::Broadcast(_Child,
            FCk_Message_MessagingGym_Ping("Trigger", 1));

        WaitOneFrame(n"OnSettled");
    }

    UFUNCTION()
    private void OnPingHandler(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        _PingCount++;
        // Self-destruct from inside the broadcast handler — must not crash.
        utils_entity_lifetime::Request_DestroyEntity(_Child);
    }

    UFUNCTION()
    private void OnSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_PingCount, 1,
            "Self-destructing handler should fire exactly once; no reentrant fires after destroy mid-broadcast");
        Assert_True(!utils_handle::Get_IsValid(_Child),
            "Child entity should be invalid after self-destruct from inside the broadcast handler");

        FinishSuccess();
    }
}
