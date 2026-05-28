// Language=angelscript

//============================================================================
// CK ATTRIBUTE — NET AUTOMATION TEST: INTEGER OVERRIDE REPLICATES
//============================================================================
//
// Integer attributes ride the same templated container-replication path as
// Float (FCk_RepData_IntegerAttributes). Default NetSubject adds an
// IntegerAttribute.Health on both worlds; server Request_Override's it, client
// polls for the replicated value.
//============================================================================

class UCk_AutoTest_Net_Integer_OverrideReplicates : UCk_AutoTest_NetBase
{
    private FName _AttributeTagName = n"IntegerAttribute.Health";
    private int _ExpectedValue = 999;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Subject = Get_SubjectEntity();
        if (ck::Is_NOT_Valid(Subject))
        { FinishFailure("subject entity not found"); return; }

        auto Tag = utils_gameplay_tag::ResolveGameplayTag(_AttributeTagName);
        auto Attribute = utils_integer_attribute::TryGet(Subject, Tag);
        if (ck::Is_NOT_Valid(Attribute))
        { FinishFailure("Integer attribute not found on subject"); return; }

        if (utils_net::Get_HasAuthority(Subject))
        {
            utils_integer_attribute::Request_Override(Attribute, _ExpectedValue);
            FinishSuccess();
            return;
        }

        WaitOneFrame(n"OnPollValue");
    }

    UFUNCTION()
    private void OnPollValue(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto Subject = Get_SubjectEntity();
        if (ck::Is_NOT_Valid(Subject))
        { WaitOneFrame(n"OnPollValue"); return; }

        auto Tag = utils_gameplay_tag::ResolveGameplayTag(_AttributeTagName);
        auto Attribute = utils_integer_attribute::TryGet(Subject, Tag);
        if (ck::Is_NOT_Valid(Attribute))
        { WaitOneFrame(n"OnPollValue"); return; }

        if (utils_integer_attribute::Get_FinalValue(Attribute) == _ExpectedValue)
        {
            FinishSuccess();
            return;
        }

        WaitOneFrame(n"OnPollValue");
    }
}
