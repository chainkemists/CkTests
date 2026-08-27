// Language=angelscript

//============================================================================
// CK ATTRIBUTE - NET AUTOMATION TEST: ALTERNATING BYTE OVERRIDE TRACKS ON CLIENT
//============================================================================
//
// Regression guard for the replicated-attribute modifier race. The server
// Request_Override's a replicated byte attribute TWICE with a settle gap so each
// value applies as its own client-side dispatch. The client must observe BOTH
// values in order.
//
// The bug: ApplyReplicatedByteAttributeEntry calls Request_ClearAllModifiers
// (which marks the prior EmptyTag Override modifier for DEFERRED destroy) then
// Request_Override, whose Add_NotRevocable coalesces the new base into that same
// doomed modifier - so the second override is silently lost and the client
// sticks at the first value. The single-override test
// (CkAutoTest_Net_Byte_OverrideReplicates) passes because the first override
// creates a fresh modifier; only the SECOND edge trips the race. Fixed by
// Add_NotRevocable skipping pending-destroy modifiers (CkAttribute_Utils.inl.h).
//============================================================================

class UCk_AutoTest_Net_Byte_AlternatingOverrideTracksOnClient : UCk_AutoTest_NetBase
{
    default _TimeoutSeconds = 12.0f;

    private FName  _AttributeTagName = n"ByteAttribute.Health";
    private uint8  _FirstValue       = 200;
    private uint8  _SecondValue      = 100;

    // Server: frames between the two overrides so the first replicates + applies
    // on the client as its own dispatch (separate dispatches are what trip the
    // race; a single coalesced net update would not).
    private int    _SettleFrames     = 25;
    private int    _ServerFrames     = 0;

    // Client: stage 0 waits for the first value, stage 1 for the second.
    private int    _ClientStage      = 0;
    private int    _ClientWaitFrames = 0;
    private int    _StuckDeadline    = 90;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Subject = Get_SubjectEntity();
        if (ck::Is_NOT_Valid(Subject))
        { FinishFailure("subject entity not found"); return; }

        auto Attribute = utils_byte_attribute::TryGet(Subject, utils_gameplay_tag::ResolveGameplayTag(_AttributeTagName));
        if (ck::Is_NOT_Valid(Attribute))
        { FinishFailure("Byte attribute not found on subject - entity-script Construct didn't add it?"); return; }

        if (utils_net::Get_HasAuthority(Subject))
        {
            utils_byte_attribute::Request_Override(Attribute, _FirstValue, ECk_MinMaxCurrent::Current);
            WaitOneFrame(n"OnServerSettle");
            return;
        }

        WaitOneFrame(n"OnClientPoll");
    }

    // Server: after the settle gap, fire the SECOND override and finish. The
    // assertion lives on the client; the server just drives the two edges.
    UFUNCTION()
    private void OnServerSettle(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        _ServerFrames += 1;
        if (_ServerFrames < _SettleFrames)
        { WaitOneFrame(n"OnServerSettle"); return; }

        auto Subject = Get_SubjectEntity();
        auto Attribute = utils_byte_attribute::TryGet(Subject, utils_gameplay_tag::ResolveGameplayTag(_AttributeTagName));
        if (ck::Is_NOT_Valid(Attribute))
        { FinishFailure("server: byte attribute vanished mid-test"); return; }

        utils_byte_attribute::Request_Override(Attribute, _SecondValue, ECk_MinMaxCurrent::Current);
        FinishSuccess();
    }

    // Client: observe the first value, then the second. Sticking at the first
    // past the deadline is the bug.
    UFUNCTION()
    private void OnClientPoll(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto Subject = Get_SubjectEntity();
        if (ck::Is_NOT_Valid(Subject))
        { WaitOneFrame(n"OnClientPoll"); return; }

        auto Attribute = utils_byte_attribute::TryGet(Subject, utils_gameplay_tag::ResolveGameplayTag(_AttributeTagName));
        if (ck::Is_NOT_Valid(Attribute))
        { WaitOneFrame(n"OnClientPoll"); return; }

        const auto Value = utils_byte_attribute::Get_FinalValue(Attribute);

        if (_ClientStage == 0)
        {
            if (Value == _FirstValue)
            { _ClientStage = 1; _ClientWaitFrames = 0; WaitOneFrame(n"OnClientPoll"); return; }

            _ClientWaitFrames += 1;
            if (_ClientWaitFrames > _StuckDeadline)
            { FinishFailure(f"client never observed the first override [{_FirstValue}] (value stuck at [{Value}])"); return; }

            WaitOneFrame(n"OnClientPoll");
            return;
        }

        // Stage 1: first value seen; the second override must now land on the client.
        if (Value == _SecondValue)
        { FinishSuccess(); return; }

        _ClientWaitFrames += 1;
        if (_ClientWaitFrames > _StuckDeadline)
        { FinishFailure(f"client stuck at [{_FirstValue}] - second Request_Override([{_SecondValue}]) never applied (replicated-attribute modifier race)"); return; }

        WaitOneFrame(n"OnClientPoll");
    }
}
