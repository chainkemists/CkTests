// Language=angelscript

//============================================================================
// CK MESSAGING — AUTOMATION TEST: BASIC BROADCAST
//============================================================================
//
// Smoke test for the messaging API:
//   1. Bind a delegate to FCk_Message_MessagingGym_Ping on self.
//   2. Broadcast a Ping with sender="AutoTest" and seq=42.
//   3. The delegate fires with a payload that round-trips both fields.
//
// Reuses the gym's Ping struct from CkMessagingGym_Messages.as — no need
// to declare test-only message structs.
//============================================================================

class UCk_AutoTest_Messaging_BasicBroadcast : UCk_AutoTest_Base
{
    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        utils_messaging::BindTo_OnBroadcast(
            LocalHandle,
            FCk_Message_MessagingGym_Ping,
            FCk_Delegate_Messaging_OnBroadcast(this, n"OnPing"));

        utils_messaging::Broadcast(
            LocalHandle,
            FCk_Message_MessagingGym_Ping("AutoTest", 42));
    }

    UFUNCTION()
    private void OnPing(
        FCk_Handle InHandle,
        FGameplayTag InMessageName,
        FInstancedStruct InPayload)
    {
        if (IsFinished()) { return; }

        auto Typed = InPayload.Get(FCk_Message_MessagingGym_Ping);
        Assert_Equals_String(Typed.Sender, "AutoTest",
            "Ping payload Sender should round-trip from Broadcast call");
        Assert_Equals_Int(Typed.SequenceNumber, 42,
            "Ping payload SequenceNumber should round-trip from Broadcast call");

        FinishSuccess();
    }
}
