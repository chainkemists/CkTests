// Language=angelscript

//============================================================================
// CK LABEL — AUTOMATION TEST: Record lookup + destroy-driven index cleanup
//============================================================================
//
// Pins two related CkLabel audit-gap contracts that share a setup:
//
//   AUDIT GAP — Label_RecordOfLabeled_Entries_Lookup:
//   Cross-record lookup via Get_EntityOrRecordEntry_WithFragmentAndLabel
//   returns the labeled record entry. Exercised through CkAttribute's
//   utils_float_attribute::TryGet(owner, name) — the public-facing
//   wrapper around the EcsExt label-keyed Record query template.
//
//   AUDIT GAP — Label_DestroyLabeledEntity_RemovesFromIndex:
//   Destroying a labeled entity removes it from label lookups in the
//   next tick. Verified by Request_DestroyEntity → WaitOneFrame → TryGet
//   returns invalid for the destroyed entity's label, while a sibling
//   labeled entry remains findable (no collateral cleanup).
//
// Mechanism: Get_EntityOrRecordEntry_WithFragmentAndLabel iterates the
// Record entries on each call (no separate label index — see CkLabel
// CLAUDE.md "label-based lookup in Records" pattern). When an entry
// entity is destroyed, the Record's processor invalidates the slot in
// its next pass, so the next lookup misses. The "next tick" in the audit
// row name refers to the deferred Request_DestroyEntity → record-cleanup
// pipeline.
//============================================================================

class UCk_AutoTest_Label_RecordLookupAndDestroyCleanup : UCk_AutoTest_Base
{
    private FCk_Handle _Owner;
    private FGameplayTag _TagAlpha;
    private FGameplayTag _TagBeta;
    private FGameplayTag _TagGamma_Unused;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;
        _Owner = utils_entity_lifetime::Request_CreateEntity(LocalHandle);

        _TagAlpha = utils_gameplay_tag::ResolveGameplayTag(n"FloatAttribute.AutoTest_RecordLookup_Alpha");
        _TagBeta  = utils_gameplay_tag::ResolveGameplayTag(n"FloatAttribute.AutoTest_RecordLookup_Beta");
        _TagGamma_Unused = utils_gameplay_tag::ResolveGameplayTag(n"FloatAttribute.AutoTest_RecordLookup_Gamma_Unused");

        auto AlphaParams = FCk_FloatAttribute_Spec(_TagAlpha, 50.0f);
        auto BetaParams  = FCk_FloatAttribute_Spec(_TagBeta,  75.0f);

        auto AlphaAttr = utils_float_attribute::Add(_Owner, AlphaParams);
        auto BetaAttr  = utils_float_attribute::Add(_Owner, BetaParams);

        Assert_True(ck::IsValid(AlphaAttr),
            "Add of labeled float attribute Alpha must return a valid handle");
        Assert_True(ck::IsValid(BetaAttr),
            "Add of labeled float attribute Beta must return a valid handle");

        // GAP 1 — label-keyed Record lookup returns the right entry.
        auto FoundAlpha = utils_float_attribute::TryGet(_Owner, _TagAlpha);
        Assert_True(ck::IsValid(FoundAlpha),
            "TryGet(_Owner, TagAlpha) must find the labeled Alpha entry via Get_EntityOrRecordEntry_WithFragmentAndLabel");
        Assert_True(utils_float_attribute::Get_BaseValue(FoundAlpha) == 50.0f,
            "Lookup-by-label must return the Alpha entry specifically (BaseValue 50), not Beta");

        auto FoundBeta = utils_float_attribute::TryGet(_Owner, _TagBeta);
        Assert_True(ck::IsValid(FoundBeta),
            "TryGet(_Owner, TagBeta) must find the labeled Beta entry");
        Assert_True(utils_float_attribute::Get_BaseValue(FoundBeta) == 75.0f,
            "Lookup-by-label must return the Beta entry specifically (BaseValue 75)");

        // Unused label — no match.
        auto FoundGamma = utils_float_attribute::TryGet(_Owner, _TagGamma_Unused);
        Assert_True(ck::Is_NOT_Valid(FoundGamma),
            "TryGet with an unused label must return an invalid handle (record contains no entry with that label)");

        // GAP 2 — destroy Alpha and verify the next-tick lookup misses,
        // while Beta still resolves.
        utils_entity_lifetime::Request_DestroyEntity(FoundAlpha);

        WaitUntil(n"Check_AlphaGone", n"OnAfterDestroyAlpha");
    }

    // Alpha resolves before the destroy, so this goes true only once the record is pruned.
    UFUNCTION()
    private void Check_AlphaGone(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(ck::Is_NOT_Valid(utils_float_attribute::TryGet(_Owner, _TagAlpha)));
    }

    UFUNCTION()
    private void OnAfterDestroyAlpha(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto AlphaAfterDestroy = utils_float_attribute::TryGet(_Owner, _TagAlpha);
        Assert_True(ck::Is_NOT_Valid(AlphaAfterDestroy),
            "After Request_DestroyEntity + one frame, TryGet(_Owner, TagAlpha) must return an invalid handle — the Record entry has been pruned");

        auto BetaAfterDestroy = utils_float_attribute::TryGet(_Owner, _TagBeta);
        Assert_True(ck::IsValid(BetaAfterDestroy),
            "Destroying the Alpha entry must NOT affect Beta — sibling Record entries remain findable");
        Assert_True(utils_float_attribute::Get_BaseValue(BetaAfterDestroy) == 75.0f,
            "Beta entry's BaseValue must be unchanged after Alpha's destruction (no collateral state change)");

        FinishSuccess();
    }
}
