// Language=angelscript

//============================================================================
// CK LABEL — AUTOMATION TEST: MATCHES ANY (FROM CONTAINER)
//============================================================================
//
// Pins MatchesAny against a tag container:
//   - Entity labeled `A`:
//     - MatchesAny({A, X}) -> true (A is present in the container)
//     - MatchesAny({X, Y}) -> false (neither matches)
//     - MatchesAnyExact({A, X}) -> true (exact match on A)
//
// Complements the existing AddAndQuery (single-tag query) + Matches
// hierarchical tests by covering the container-based query verb.
//============================================================================

class UCk_AutoTest_Label_MatchesAny_FromContainer : UCk_AutoTest_Base
{
    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;
        auto Entity = utils_entity_lifetime::Request_CreateEntity(LocalHandle);

        auto TagA = utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Label.MatchA");
        auto TagX = utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Label.MatchX");
        auto TagY = utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Label.MatchY");

        utils_gameplay_label::Add(Entity, TagA);

        auto AX = FGameplayTagContainer();
        AX.AddTag(TagA);
        AX.AddTag(TagX);
        Assert_True(utils_gameplay_label::MatchesAny(Entity, AX),
            "MatchesAny({A, X}) should be true — label A is in the container");
        Assert_True(utils_gameplay_label::MatchesAnyExact(Entity, AX),
            "MatchesAnyExact({A, X}) should be true — A matches exactly");

        auto XY = FGameplayTagContainer();
        XY.AddTag(TagX);
        XY.AddTag(TagY);
        Assert_True(utils_gameplay_label::MatchesAny(Entity, XY) == false,
            "MatchesAny({X, Y}) should be false — neither matches label A");
        Assert_True(utils_gameplay_label::MatchesAnyExact(Entity, XY) == false,
            "MatchesAnyExact({X, Y}) should be false — neither matches label A");

        FinishSuccess();
    }
}
