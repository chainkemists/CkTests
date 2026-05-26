// Language=angelscript

//============================================================================
// CK ENTITY TAG — AUTOMATION TEST: GET_ALL_TAGS_AS_CONTAINER IS EXPLICIT
//============================================================================
//
// Adding two gameplay tags A.B.C and X.Y registers parent FNames internally,
// but Get_AllTagsAsContainer must return ONLY the explicitly-added tags
// (A.B.C and X.Y) — not their parent-flattened ancestors.
//============================================================================

class UCk_AutoTest_EntityTag_GetAllTagsAsContainerIsExplicit : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 5.0f;

    private FCk_Handle _Entity;
    private FGameplayTag _TagABC;
    private FGameplayTag _TagXY;
    private FGameplayTag _TagAB;
    private FGameplayTag _TagA;
    private FGameplayTag _TagX;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _Entity = InHandle;
        _TagABC = utils_gameplay_tag::ResolveGameplayTag(n"AutoTestEt.A.B.C");
        _TagXY  = utils_gameplay_tag::ResolveGameplayTag(n"AutoTestEt.X.Y");
        _TagAB  = utils_gameplay_tag::ResolveGameplayTag(n"AutoTestEt.A.B");
        _TagA   = utils_gameplay_tag::ResolveGameplayTag(n"AutoTestEt.A");
        _TagX   = utils_gameplay_tag::ResolveGameplayTag(n"AutoTestEt.X");

        utils_entity_tag::Add_UsingGameplayTag(_Entity, _TagABC);
        utils_entity_tag::Add_UsingGameplayTag(_Entity, _TagXY);

        WaitOneFrame(n"AfterAdds");
    }

    UFUNCTION()
    private void AfterAdds(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto Container = utils_entity_tag::Get_AllTagsAsContainer(_Entity);

        Assert_True(Container.HasTagExact(_TagABC),
            "Container must contain explicitly-added A.B.C");
        Assert_True(Container.HasTagExact(_TagXY),
            "Container must contain explicitly-added X.Y");
        Assert_True(!Container.HasTagExact(_TagAB),
            "Container must NOT contain parent A.B (not explicitly added)");
        Assert_True(!Container.HasTagExact(_TagA),
            "Container must NOT contain parent A (not explicitly added)");
        Assert_True(!Container.HasTagExact(_TagX),
            "Container must NOT contain parent X (not explicitly added)");

        FinishSuccess();
    }
}
