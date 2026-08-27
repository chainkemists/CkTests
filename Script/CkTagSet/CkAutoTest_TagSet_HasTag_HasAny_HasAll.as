// Language=angelscript

//============================================================================
// CK TAG SET - AUTOMATION TEST: HASTAG / HASANY / HASALL
//============================================================================
//
// Pins the three core query verbs on a TagSet seeded with {A, B, C}:
//   - HasTag(X)            -> true iff X is in the set
//   - HasAny(container)    -> true iff at least one tag in the container is in the set
//   - HasAll(container)    -> true iff every tag in the container is in the set
//
// Tests positive + negative cases for each verb.
//============================================================================

class UCk_AutoTest_TagSet_HasTag_HasAny_HasAll : UCk_AutoTest_Base
{
    private FCk_Handle_TagSet _TagSet;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto TagA = utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.TagSet.QueryA");
        auto TagB = utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.TagSet.QueryB");
        auto TagC = utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.TagSet.QueryC");
        auto TagX = utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.TagSet.QueryX");
        auto TagY = utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.TagSet.QueryY");

        auto Initial = FGameplayTagContainer();
        Initial.AddTag(TagA);
        Initial.AddTag(TagB);
        Initial.AddTag(TagC);
        _TagSet = utils_tag_set::Add(LocalHandle, Initial, ECk_Replication::DoesNotReplicate);

        // ---- HasTag ----
        Assert_True(utils_tag_set::HasTag(_TagSet, TagA),
            "HasTag(A) should be true - A is in the set");
        Assert_True(utils_tag_set::HasTag(_TagSet, TagB),
            "HasTag(B) should be true - B is in the set");
        Assert_True(utils_tag_set::HasTag(_TagSet, TagX) == false,
            "HasTag(X) should be false - X is NOT in the set");

        // ---- HasAny ----
        auto AnyAX = FGameplayTagContainer();
        AnyAX.AddTag(TagA);
        AnyAX.AddTag(TagX);
        Assert_True(utils_tag_set::HasAny(_TagSet, AnyAX),
            "HasAny({A, X}) should be true - A matches");

        auto AnyXY = FGameplayTagContainer();
        AnyXY.AddTag(TagX);
        AnyXY.AddTag(TagY);
        Assert_True(utils_tag_set::HasAny(_TagSet, AnyXY) == false,
            "HasAny({X, Y}) should be false - neither in the set");

        // ---- HasAll ----
        auto AllAB = FGameplayTagContainer();
        AllAB.AddTag(TagA);
        AllAB.AddTag(TagB);
        Assert_True(utils_tag_set::HasAll(_TagSet, AllAB),
            "HasAll({A, B}) should be true - both in the set");

        auto AllAX = FGameplayTagContainer();
        AllAX.AddTag(TagA);
        AllAX.AddTag(TagX);
        Assert_True(utils_tag_set::HasAll(_TagSet, AllAX) == false,
            "HasAll({A, X}) should be false - X is missing");

        FinishSuccess();
    }
}
