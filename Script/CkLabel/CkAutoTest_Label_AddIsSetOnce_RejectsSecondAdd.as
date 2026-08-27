// Language=angelscript

//============================================================================
// CK LABEL - AUTOMATION TEST: ADD IS SET-ONCE
//============================================================================
//
// Pins the actual contract of `Add`:
//
//   1. Second Add with the SAME tag is a silent no-op - Get_Label still
//      returns the original tag, no log spam.
//   2. Second Add with a DIFFERENT tag is rejected - the ORIGINAL label
//      survives. A Display-level log is emitted (not an ensure) so this
//      path is safe to exercise from tests.
//
// There is no re-labeling API by design. Labels identify an entity's role
// within its parent context (per the CkLabel docs) and that role is
// meant to be decided at construction time.
//============================================================================

class UCk_AutoTest_Label_AddIsSetOnce_RejectsSecondAdd : UCk_AutoTest_Base
{
    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;
        auto Entity = utils_entity_lifetime::Request_CreateEntity(LocalHandle);

        auto TagA = utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Label.SetOnceA");
        auto TagB = utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Label.SetOnceB");

        utils_gameplay_label::Add(Entity, TagA);
        Assert_True(utils_gameplay_label::Has(Entity),
            "After first Add, entity should have a label");
        Assert_True(utils_gameplay_label::MatchesExact(Entity, TagA),
            "After first Add, Get_Label should return TagA");

        // Same-tag re-add - silent no-op, original survives.
        utils_gameplay_label::Add(Entity, TagA);
        Assert_True(utils_gameplay_label::MatchesExact(Entity, TagA),
            "Second Add of the same tag must be a silent no-op - original label A survives");

        // Different-tag re-add - caller-attributable rejection. The original
        // label MUST survive; only a Display log is emitted (no ensure).
        utils_gameplay_label::Add(Entity, TagB);
        Assert_True(utils_gameplay_label::MatchesExact(Entity, TagA),
            "Second Add of a different tag B must NOT overwrite - original label A survives (set-once contract)");
        Assert_True(utils_gameplay_label::MatchesExact(Entity, TagB) == false,
            "After rejected second Add, the entity must NOT carry the new tag B");

        FinishSuccess();
    }
}
