// Language=angelscript

//============================================================================
// CK LIVETUNE — AUTOMATION TEST: ATTRIBUTE PILOT (ViaRebuild ROUND TRIP)
//============================================================================
//
// The hardest re-apply tier, end to end on the framework's most decomposed
// feature: a FloatAttribute retune captures runtime state via the persistence
// Produce, destroys the attribute entity, re-Adds it with the FRESH params
// once the dying entity is actually gone (the record uses
// DisallowDuplicateNames — a same-named re-Add must never collide with the
// dying entry), and restores runtime state through the standard hydration
// dispatcher. Pinned here: the overridden current value survives the rebuild,
// the link survives the rebuild (a second retune works), and a fresh clamp
// cascades onto the restored value.
//============================================================================

class UCk_AutoTest_LiveTune_AttributeRebuild_RoundTrip : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;

    private UCk_LiveTuneTest_TuningAsset _Asset;
    private FCk_Handle _Owner;
    private FCk_Handle_FloatAttribute _OldAttr;
    private FGameplayTag _Tag;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Self = InHandle;
        _Asset = UCk_LiveTuneTest_Utils::Create_TuningAsset(0, 0);
        _Owner = utils_entity_lifetime::Request_CreateEntity(Self);
        _Tag = utils_gameplay_tag::ResolveGameplayTag(n"Attribute.Health");

        auto Params = FCk_Fragment_FloatAttribute_ParamsData(_Tag, 100.0f);
        Params.Set_MinMax(ECk_MinMax::MinMax);
        Params.Set_MinValue(0.0f);
        Params.Set_MaxValue(200.0f);
        _OldAttr = utils_float_attribute::Add(_Owner, Params);
        UCk_LiveTuneTest_Utils::Set_HealthParams(_Asset, Params);

        auto AttrBase = FCk_Handle(_OldAttr);
        UCk_LiveTuneTest_Utils::Link(AttrBase, _Asset, n"_HealthParams");

        utils_float_attribute::Request_Override(_OldAttr, 40.0f, ECk_MinMaxCurrent::Current);

        Add_Step_WaitUntil("the pre-rebuild override lands", n"Check_OverrideLanded");
        Add_Step("retune the max upward — no clamp effect on the current 40", n"Step_RetuneMaxUp");
        Add_Step_WaitUntil("the old attribute entity fully destroys", n"Check_OldAttrGone");
        Add_Step_WaitUntil("a same-named attribute exists again with its runtime state restored", n"Check_RuntimeStateRestored");
        Add_Step("the link survived the rebuild", n"Step_AssertRelinked");
        Add_Step("retune the max BELOW the restored value", n"Step_RetuneMaxDown");
        Add_Step_WaitUntil("the fresh clamp cascades onto the restored value", n"Check_ClampLanded");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Check_OverrideLanded(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_float_attribute::Get_FinalValue(_OldAttr, ECk_MinMaxCurrent::Current) == 40.0f);
    }

    UFUNCTION()
    private void Step_RetuneMaxUp(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Self = InHandle;
        auto Retuned = FCk_Fragment_FloatAttribute_ParamsData(_Tag, 100.0f);
        Retuned.Set_MinMax(ECk_MinMax::MinMax);
        Retuned.Set_MinValue(0.0f);
        Retuned.Set_MaxValue(300.0f);
        UCk_LiveTuneTest_Utils::Set_HealthParams(_Asset, Retuned);
        UCk_LiveTuneTest_Utils::SimulatePropertyChange(Self, _Asset, n"_HealthParams");
    }

    UFUNCTION()
    private void Check_OldAttrGone(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(ck::Is_NOT_Valid(_OldAttr));
    }

    UFUNCTION()
    private void Check_RuntimeStateRestored(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        auto NewAttr = utils_float_attribute::TryGet(_Owner, _Tag);
        Res.Set(ck::IsValid(NewAttr) &&
            utils_float_attribute::Get_FinalValue(NewAttr, ECk_MinMaxCurrent::Current) == 40.0f);
    }

    UFUNCTION()
    private void Step_AssertRelinked(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Self = InHandle;
        Assert_Equals_Int(UCk_LiveTuneTest_Utils::Get_LinkCount(Self, _Asset, n"_HealthParams"), 1,
            "the rebuilt attribute must be re-linked automatically");
    }

    UFUNCTION()
    private void Step_RetuneMaxDown(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Self = InHandle;
        auto Retuned = FCk_Fragment_FloatAttribute_ParamsData(_Tag, 100.0f);
        Retuned.Set_MinMax(ECk_MinMax::MinMax);
        Retuned.Set_MinValue(0.0f);
        Retuned.Set_MaxValue(25.0f);
        UCk_LiveTuneTest_Utils::Set_HealthParams(_Asset, Retuned);
        UCk_LiveTuneTest_Utils::SimulatePropertyChange(Self, _Asset, n"_HealthParams");
    }

    UFUNCTION()
    private void Check_ClampLanded(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        auto NewAttr = utils_float_attribute::TryGet(_Owner, _Tag);
        Res.Set(ck::IsValid(NewAttr) &&
            utils_float_attribute::Get_FinalValue(NewAttr, ECk_MinMaxCurrent::Current) == 25.0f);
    }
}
