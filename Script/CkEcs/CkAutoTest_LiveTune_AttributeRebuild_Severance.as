// Language=angelscript

//============================================================================
// CK LIVETUNE — AUTOMATION TEST: OBSERVER SEVERANCE ACROSS ViaRebuild
//============================================================================
//
// Pins the DOCUMENTED LIMITATION of the rebuild tier (design §10 risk #6,
// stance locked by the CTO review: accept + document): destroying and
// re-Adding the feature subtree changes entity identity, so a cached typesafe
// handle becomes a tombstone and a signal binding made against the old entity
// never fires again — nothing rebinds automatically. The rebuilt attribute
// itself keeps working. If a future rebind-assist changes this behavior, THIS
// test is the one that should fail.
//============================================================================

class UCk_AutoTest_LiveTune_AttributeRebuild_Severance : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;

    private UCk_LiveTuneTest_TuningAsset _Asset;
    private FCk_Handle _Owner;
    private FCk_Handle_FloatAttribute _OldAttr;
    private FGameplayTag _Tag;
    private int _OnChangedCount = 0;
    private int _CountAfterRebuild = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Self = InHandle;
        _Asset = UCk_LiveTuneTest_Utils::Create_TuningAsset(0, 0);
        _Owner = utils_entity_lifetime::Request_CreateEntity(Self);
        _Tag = utils_gameplay_tag::ResolveGameplayTag(n"Attribute.Health");

        auto Params = FCk_Fragment_FloatAttribute_ParamsData(_Tag, 100.0f);
        _OldAttr = utils_float_attribute::Add(_Owner, Params);
        UCk_LiveTuneTest_Utils::Set_HealthParams(_Asset, Params);

        auto AttrBase = FCk_Handle(_OldAttr);
        UCk_LiveTuneTest_Utils::Link(AttrBase, _Asset, n"_HealthParams");

        utils_float_attribute::BindTo_OnValueChanged(_OldAttr, ECk_MinMaxCurrent::Current,
            FCk_Delegate_FloatAttribute_OnValueChanged(this, n"OnOldBindingFired"));

        auto Retuned = FCk_Fragment_FloatAttribute_ParamsData(_Tag, 150.0f);
        UCk_LiveTuneTest_Utils::Set_HealthParams(_Asset, Retuned);
        UCk_LiveTuneTest_Utils::SimulatePropertyChange(Self, _Asset, n"_HealthParams");

        Add_Step_WaitUntil("the old attribute entity fully destroys", n"Check_OldGone");
        Add_Step_WaitUntil("the rebuilt attribute exists", n"Check_NewExists");
        Add_Step("snapshot the old binding's fire count", n"Step_Snapshot");
        Add_Step("mutate the rebuilt attribute", n"Step_MutateNew");
        Add_Step_WaitFrames("give a live binding every chance to fire", 10);
        Add_Step("the severed binding stayed silent; the new attribute works", n"Step_AssertSevered");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void OnOldBindingFired(FCk_Handle InAttributeOwnerEntity, FCk_Payload_FloatAttribute_OnValueChanged InPayload)
    {
        ++_OnChangedCount;
    }

    UFUNCTION()
    private void Check_OldGone(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(ck::Is_NOT_Valid(_OldAttr));
    }

    UFUNCTION()
    private void Check_NewExists(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(ck::IsValid(utils_float_attribute::TryGet(_Owner, _Tag)));
    }

    UFUNCTION()
    private void Step_Snapshot(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _CountAfterRebuild = _OnChangedCount;
    }

    UFUNCTION()
    private void Step_MutateNew(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto NewAttr = utils_float_attribute::TryGet(_Owner, _Tag);
        utils_float_attribute::Request_Override(NewAttr, 77.0f, ECk_MinMaxCurrent::Current);
    }

    UFUNCTION()
    private void Step_AssertSevered(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(ck::Is_NOT_Valid(_OldAttr),
            "a typesafe handle cached before the rebuild must be a tombstone after it");

        auto NewAttr = utils_float_attribute::TryGet(_Owner, _Tag);
        Assert_Equals_Float(utils_float_attribute::Get_FinalValue(NewAttr, ECk_MinMaxCurrent::Current), 77.0f, 0.01f,
            "the rebuilt attribute itself must keep working");

        Assert_Equals_Int(_OnChangedCount - _CountAfterRebuild, 0,
            "a binding made against the OLD entity must stay silent after the rebuild — the documented severance");
    }
}
