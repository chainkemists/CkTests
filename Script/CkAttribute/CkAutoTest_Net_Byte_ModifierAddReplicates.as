// Language=angelscript

//============================================================================
// CK ATTRIBUTE — NET AUTOMATION TEST: BYTE MODIFIER-ADD REPLICATES
//============================================================================
//
// Byte parity with the C++ Float_ModifierAdd_Replicates spec. The modifier
// entity is server-side only ("container replicates VALUES only"); what
// crosses the wire is the recomputed FinalValue carried by the templated
// FCk_RepData_ByteAttributes container. Default NetSubject adds a
// ByteAttribute.Health at initial 7 on both worlds; the server applies a
// revocable +25 Add modifier and the client polls for the replicated
// post-modifier FinalValue (32).
//============================================================================

class UCk_AutoTest_Net_Byte_ModifierAddReplicates : UCk_AutoTest_NetBase
{
    private FName _AttributeTagName = n"ByteAttribute.Health";
    private uint8 _ExpectedValue = 32; // subject initial 7 + revocable Add 25

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Subject = Get_SubjectEntity();
        if (ck::Is_NOT_Valid(Subject))
        { FinishFailure("subject entity not found"); return; }

        auto Tag = utils_gameplay_tag::ResolveGameplayTag(_AttributeTagName);
        auto Attribute = utils_byte_attribute::TryGet(Subject, Tag);
        if (ck::Is_NOT_Valid(Attribute))
        { FinishFailure("Byte attribute not found on subject"); return; }

        if (utils_net::Get_HasAuthority(Subject))
        {
            // Modifier index reuses the attribute tag — the modifier name is a separate
            // index from the attribute name within CkAttribute, so no new tag registration
            // is needed (mirrors the Float_ModifierAdd_Replicates C++ spec).
            auto ModParams = FCk_Fragment_ByteAttributeModifier_ParamsData();
            ModParams.Set_ModifierDelta(25);
            utils_byte_attribute_modifier::Add_Revocable(
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
