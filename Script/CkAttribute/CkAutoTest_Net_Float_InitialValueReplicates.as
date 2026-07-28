// Language=angelscript

//============================================================================
// CK ATTRIBUTE — NET AUTOMATION TEST: FLOAT INITIAL-VALUE REPLICATES
//============================================================================
//
// AS-authored equivalent of the C++ spec `Ck.Attribute.Net.Float_InitialValue_Replicates`.
// Spawned on each PIE world by the harness's FCk_Latent_RunAsTestOnAllWorlds; server-side
// instance drives a Request_Override on the subject's Health attribute, client-side
// instance polls for the replicated value and FinishSuccess's once seen.
//
// The subject's entity-script (UCk_AutoTest_NetSubject_EntityScript_UE) adds the Health
// attribute on both worlds with initial value 42.5 — symmetric setup is mandatory for
// CkAttribute's container-fragment replication to deliver value updates (see the
// "CkAttribute replication is symmetric" memory note).
//============================================================================

class UCk_AutoTest_Net_Float_InitialValueReplicates : UCk_AutoTest_NetBase
{
    private FName _AttributeTagName = n"FloatAttribute.Health";
    private float32 _ExpectedValue = 100.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Subject = Get_SubjectEntity();
        if (ck::Is_NOT_Valid(Subject))
        {
            FinishFailure("subject entity not found — harness's NetSubject actor missing on this world");
            return;
        }

        auto Tag = utils_gameplay_tag::ResolveGameplayTag(_AttributeTagName);
        auto Attribute = utils_float_attribute::TryGet(Subject, Tag);
        if (ck::Is_NOT_Valid(Attribute))
        {
            FinishFailure("Health attribute not found on subject — entity-script Construct didn't add it on this world?");
            return;
        }

        if (utils_net::Get_HasAuthority(Subject))
        {
            // Server-side: drive the mutation. The post-Override value (100.0) propagates to
            // the client via the FCk_RepData_FloatAttributes container fragment.
            Attribute.Request_Override(_ExpectedValue, ECk_MinMaxCurrent::Current);
            FinishSuccess();
            return;
        }

        // Client-side: poll for the replicated value. WaitOneFrame schedules OnPollValue on the
        // next processor pass; OnPollValue re-arms itself until the value matches or the
        // harness times out.
        WaitOneFrame(n"OnPollValue");
    }

    UFUNCTION()
    private void OnPollValue(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto Subject = Get_SubjectEntity();
        if (ck::Is_NOT_Valid(Subject))
        {
            WaitOneFrame(n"OnPollValue");
            return;
        }

        auto Tag = utils_gameplay_tag::ResolveGameplayTag(_AttributeTagName);
        auto Attribute = utils_float_attribute::TryGet(Subject, Tag);
        if (ck::Is_NOT_Valid(Attribute))
        {
            WaitOneFrame(n"OnPollValue");
            return;
        }

        auto Value = utils_float_attribute::Get_FinalValue(Attribute, ECk_MinMaxCurrent::Current);
        if (Value == _ExpectedValue)
        {
            Assert_True(true, "client observed post-Override value via replication");
            FinishSuccess();
            return;
        }

        // Value hasn't arrived yet — try again next frame. The harness's per-test timeout
        // bounds this loop (see _TimeoutSeconds in the C++ spec stub); if the value never
        // arrives, the harness AddError's a timeout and the test fails.
        WaitOneFrame(n"OnPollValue");
    }
}
