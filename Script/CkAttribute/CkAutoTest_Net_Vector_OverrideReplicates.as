// Language=angelscript

//============================================================================
// CK ATTRIBUTE - NET AUTOMATION TEST: VECTOR OVERRIDE REPLICATES
//============================================================================
//
// Vector attributes ride the same templated container-replication path as
// Float (FCk_RepData_VectorAttributes). Default NetSubject adds a
// VectorAttribute.AutoTest_PerComponent on both worlds; server Request_Override's
// it, client polls for the replicated value (per-component tolerance compare).
//============================================================================

class UCk_AutoTest_Net_Vector_OverrideReplicates : UCk_AutoTest_NetBase
{
    private FName _AttributeTagName = n"VectorAttribute.AutoTest_PerComponent";
    private FVector _ExpectedValue = FVector(10.0, 20.0, 30.0);
    private float32 _Tolerance = 0.01f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Subject = Get_SubjectEntity();
        if (ck::Is_NOT_Valid(Subject))
        { FinishFailure("subject entity not found"); return; }

        auto Tag = utils_gameplay_tag::ResolveGameplayTag(_AttributeTagName);
        auto Attribute = utils_vector_attribute::TryGet(Subject, Tag);
        if (ck::Is_NOT_Valid(Attribute))
        { FinishFailure("Vector attribute not found on subject"); return; }

        if (utils_net::Get_HasAuthority(Subject))
        {
            utils_vector_attribute::Request_Override(Attribute, _ExpectedValue, ECk_MinMaxCurrent::Current);
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
        auto Attribute = utils_vector_attribute::TryGet(Subject, Tag);
        if (ck::Is_NOT_Valid(Attribute))
        { WaitOneFrame(n"OnPollValue"); return; }

        if (utils_vector_attribute::Get_FinalValue(Attribute).Equals(_ExpectedValue, _Tolerance))
        {
            FinishSuccess();
            return;
        }

        WaitOneFrame(n"OnPollValue");
    }
}
