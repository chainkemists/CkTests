// Language=angelscript

//============================================================================
// CK LABEL — AUTOMATION TEST: HIERARCHICAL MATCHING
//============================================================================
//
// Verifies the distinction between hierarchical and exact gameplay-tag
// label matching:
//   1. Add label "AutoTest.Label.Audio.Track.BGM" to a child entity.
//   2. MatchesExact for the full tag → true.
//   3. MatchesExact for the parent tag "AutoTest.Label.Audio.Track" → false.
//   4. Matches (hierarchical) for the parent tag → true.
//   5. MatchesExact for an unrelated tag → false.
//
// Pins down the contract for label-based filtering. Misuse of Matches vs
// MatchesExact is a common bug class (over-matching with hierarchical
// when exact was intended).
//============================================================================

class UCk_AutoTest_Label_HierarchicalMatching : UCk_AutoTest_Base
{
    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto Child = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        auto FullTag = utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Label.Audio.Track.BGM");
        auto ParentTag = utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Label.Audio.Track");
        auto UnrelatedTag = utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Label.Visual.VFX");

        utils_gameplay_label::Add(Child, FullTag);

        Assert_True(utils_gameplay_label::MatchesExact(Child, FullTag),
            "MatchesExact for the exact added tag should return true");
        Assert_True(!utils_gameplay_label::MatchesExact(Child, ParentTag),
            "MatchesExact for the PARENT of the added tag should return false");
        Assert_True(utils_gameplay_label::Matches(Child, ParentTag),
            "Matches (hierarchical) for the parent tag should return true");
        Assert_True(!utils_gameplay_label::MatchesExact(Child, UnrelatedTag),
            "MatchesExact for an unrelated tag should return false");
        Assert_True(!utils_gameplay_label::Matches(Child, UnrelatedTag),
            "Matches for an unrelated tag should also return false");

        FinishSuccess();
    }
}
