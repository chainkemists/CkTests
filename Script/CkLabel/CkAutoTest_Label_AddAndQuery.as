// Language=angelscript

//============================================================================
// CK LABEL — AUTOMATION TEST: ADD AND QUERY
//============================================================================
//
// Smoke test for the per-entity gameplay-label API:
//   1. Spawn a child entity.
//   2. Add a label tag to it via utils_gameplay_label::Add.
//   3. Has returns true.
//   4. Get_IsUnnamedLabel returns false (we set a real tag).
//   5. Get_Label returns the same tag we added.
//
// All operations resolve synchronously in DoBeginPlay.
//============================================================================

class UCk_AutoTest_Label_AddAndQuery : UCk_AutoTest_Base
{
    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto Child = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        auto LabelTag = utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Label.SomeRole");

        utils_gameplay_label::Add(Child, LabelTag);

        Assert_True(utils_gameplay_label::Has(Child),
            "Has should return true after Add");
        Assert_True(!utils_gameplay_label::Get_IsUnnamedLabel(Child),
            "Get_IsUnnamedLabel should return false for a non-empty label");

        auto Got = utils_gameplay_label::Get_Label(Child);
        Assert_True(Got == LabelTag,
            f"Get_Label should round-trip the added tag (got '{Got.ToString()}')");

        FinishSuccess();
    }
}
