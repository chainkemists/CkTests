// Language=angelscript

//============================================================================
// CK ATTRIBUTE — NET AUTOMATION TEST: INTEGER MODIFIER-ADD REPLICATES
//============================================================================
//
// Integer parity with the C++ Float_ModifierAdd_Replicates spec. The modifier
// entity is server-side only; the recomputed FinalValue is what replicates via
// the templated FCk_RepData_IntegerAttributes container. Default NetSubject
// adds an IntegerAttribute.Health at initial 13 on both worlds; the server
// applies a revocable +100 Add modifier and the client polls for the
// replicated post-modifier FinalValue (113).
//============================================================================

class UCk_AutoTest_Net_Integer_ModifierAddReplicates : UCk_AutoTest_NetBase
{
    private FName _AttributeTagName = n"IntegerAttribute.Health";
    private int _ExpectedValue = 113; // subject initial 13 + revocable Add 100

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
            // Modifier index reuses the attribute tag (separate index from the attribute
            // name within CkAttribute), so no new tag registration is needed.
            auto ModParams = FCk_Fragment_IntegerAttributeModifier_ParamsData();
            ModParams.Set_ModifierDelta(100);
            utils_integer_attribute_modifier::Add_Revocable(
                Attribute,
                Tag,
                ECk_AttributeModifier_Operation::Add,
                ModParams);
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
