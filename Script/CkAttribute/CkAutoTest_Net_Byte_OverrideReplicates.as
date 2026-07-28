// Language=angelscript

//============================================================================
// CK ATTRIBUTE — NET AUTOMATION TEST: BYTE OVERRIDE REPLICATES
//============================================================================
//
// Byte attributes ride the same templated container-replication path as Float
// (CkAttribute_Processor.inl.h → FCk_RepData_ByteAttributes). The default
// NetSubject's entity-script adds a ByteAttribute.Health on both worlds
// (symmetric setup); the server Request_Override's it and the client polls for
// the replicated value. Mirror of CkAutoTest_Net_Float_InitialValueReplicates.
//============================================================================

class UCk_AutoTest_Net_Byte_OverrideReplicates : UCk_AutoTest_NetBase
{
    private FName _AttributeTagName = n"ByteAttribute.Health";
    private uint8 _ExpectedValue = 200;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Subject = Get_SubjectEntity();
        if (ck::Is_NOT_Valid(Subject))
        { FinishFailure("subject entity not found"); return; }

        auto Tag = utils_gameplay_tag::ResolveGameplayTag(_AttributeTagName);
        auto Attribute = utils_byte_attribute::TryGet(Subject, Tag);
        if (ck::Is_NOT_Valid(Attribute))
        { FinishFailure("Byte attribute not found on subject — entity-script Construct didn't add it?"); return; }

        if (utils_net::Get_HasAuthority(Subject))
        {
            utils_byte_attribute::Request_Override(Attribute, _ExpectedValue, ECk_MinMaxCurrent::Current);
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
        auto Attribute = utils_byte_attribute::TryGet(Subject, Tag);
        if (ck::Is_NOT_Valid(Attribute))
        { WaitOneFrame(n"OnPollValue"); return; }

        if (utils_byte_attribute::Get_FinalValue(Attribute) == _ExpectedValue)
        {
            FinishSuccess();
            return;
        }

        WaitOneFrame(n"OnPollValue");
    }
}
