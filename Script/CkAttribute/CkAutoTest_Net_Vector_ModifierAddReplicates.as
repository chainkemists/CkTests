// Language=angelscript

//============================================================================
// CK ATTRIBUTE - NET AUTOMATION TEST: VECTOR MODIFIER-ADD REPLICATES
//============================================================================
//
// Vector parity with the C++ Float_ModifierAdd_Replicates spec. The modifier
// entity is server-side only; the recomputed per-component FinalValue
// replicates via the templated FCk_RepData_VectorAttributes container. Default
// NetSubject adds a VectorAttribute.AutoTest_PerComponent at initial (1,2,3) on
// both worlds; the server applies a revocable (25,10,5) Add modifier and the
// client polls for the replicated post-modifier FinalValue (26,12,8).
//============================================================================

class UCk_AutoTest_Net_Vector_ModifierAddReplicates : UCk_AutoTest_NetBase
{
    private FName _AttributeTagName = n"VectorAttribute.AutoTest_PerComponent";
    private FVector _ExpectedValue = FVector(26.0, 12.0, 8.0); // (1,2,3) + (25,10,5)
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
            // Modifier index reuses the attribute tag (separate index from the attribute
            // name within CkAttribute), so no new tag registration is needed.
            auto ModParams = FCk_Fragment_VectorAttributeModifier_ParamsData();
            ModParams.Set_ModifierDelta(FVector(25.0, 10.0, 5.0));
            utils_vector_attribute_modifier::Add_Revocable(
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
