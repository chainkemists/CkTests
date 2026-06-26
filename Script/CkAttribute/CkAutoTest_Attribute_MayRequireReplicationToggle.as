// Language=angelscript

//============================================================================
// CK ATTRIBUTE — AUTOMATION TEST: MayRequireReplicationThisFrame toggle
//============================================================================
//
// Pins the FTag_MayRequireReplication toggle contract:
//   1. A mutation on a replicated attribute sets the tag IMMEDIATELY —
//      Get_MayRequireReplicationThisFrame == true in the same script
//      pass as Request_Override.
//   2. The Replicate processor (FGroup_Replication) clears the tag on
//      its next pass — Get_MayRequireReplicationThisFrame == false
//      after one WaitOneFrame.
//   3. The same mutation on a DoesNotReplicate attribute NEVER sets the
//      tag — Request_TryReplicateAttribute early-returns when
//      FTag_ReplicatedAttribute is absent.
//
// Why this matters: the tag is the single source of truth for "this
// attribute has pending replication". Drift in either direction breaks
// replication scheduling — either pushing redundant data every frame, or
// missing pushes after a mutation. The Replicate processor body in
// CkAttribute_Processor.inl.h ends with InHandle.Remove<MarkedDirtyBy>(),
// so the tag's lifetime is exactly one processor pass from set to clear.
//============================================================================

class UCk_AutoTest_Attribute_MayRequireReplicationToggle : UCk_AutoTest_Base
{
    private FCk_Handle_FloatAttribute _Replicated;
    private FCk_Handle_FloatAttribute _NotReplicated;
    private int _SettleTries = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto ReplicatedParams = FCk_Fragment_FloatAttribute_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"FloatAttribute.AutoTest_RepFlag_Replicated"),
            100.0f);
        ReplicatedParams.Set_MinMax(ECk_MinMax::MinMax);
        ReplicatedParams.Set_MinValue(0.0f);
        ReplicatedParams.Set_MaxValue(100.0f);
        _Replicated = utils_float_attribute::Add(LocalHandle, ReplicatedParams,
            ECk_Replication::Replicates);

        auto NotRepParams = FCk_Fragment_FloatAttribute_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"FloatAttribute.AutoTest_RepFlag_NotReplicated"),
            100.0f);
        NotRepParams.Set_MinMax(ECk_MinMax::MinMax);
        NotRepParams.Set_MinValue(0.0f);
        NotRepParams.Set_MaxValue(100.0f);
        _NotReplicated = utils_float_attribute::Add(LocalHandle, NotRepParams,
            ECk_Replication::DoesNotReplicate);

        utils_float_attribute::Request_Override(_Replicated, 42.0f);
        utils_float_attribute::Request_Override(_NotReplicated, 42.0f);

        auto FlagReplicatedNow = utils_float_attribute::Get_MayRequireReplicationThisFrame(_Replicated);
        Assert_True(FlagReplicatedNow,
            "Replicated attribute must have MayRequireReplication set in the same frame as Request_Override (Request_TryReplicateAttribute adds the tag synchronously)");

        auto FlagNotReplicatedNow = utils_float_attribute::Get_MayRequireReplicationThisFrame(_NotReplicated);
        Assert_True(!FlagNotReplicatedNow,
            "Non-replicated attribute must NOT have MayRequireReplication set — Request_TryReplicateAttribute gates on FTag_ReplicatedAttribute and early-returns when absent");

        WaitOneFrame(n"OnAfterReplicateProcessor");
    }

    UFUNCTION()
    private void OnAfterReplicateProcessor(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        // The timer callback fires in FGroup_Gameplay_TimeDelta — BEFORE this frame's
        // FGroup_Replication slot — so a single fixed wait can observe the tag in the window
        // between the value settling (same-frame via pumps) and the next Replicate pass
        // consuming it. Poll until the Replicate pass has run; the assert below then pins
        // that the tag DID clear (a sticky tag fails via the bounded retry).
        if (utils_float_attribute::Get_MayRequireReplicationThisFrame(_Replicated) && _SettleTries < 40)
        {
            _SettleTries++;
            WaitOneFrame(n"OnAfterReplicateProcessor");
            return;
        }

        auto FlagReplicatedAfter = utils_float_attribute::Get_MayRequireReplicationThisFrame(_Replicated);
        Assert_True(!FlagReplicatedAfter,
            "Replicate processor (FGroup_Replication) must clear MayRequireReplication on the replicated attribute on its next pass");

        auto FlagNotReplicatedAfter = utils_float_attribute::Get_MayRequireReplicationThisFrame(_NotReplicated);
        Assert_True(!FlagNotReplicatedAfter,
            "Non-replicated attribute must remain without MayRequireReplication across frames");

        FinishSuccess();
    }
}
