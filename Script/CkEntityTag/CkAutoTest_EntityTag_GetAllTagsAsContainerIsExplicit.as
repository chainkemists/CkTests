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
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;
        auto TagABC = utils_gameplay_tag::ResolveGameplayTag(n"AutoTestEt.A.B.C");
        auto TagXY  = utils_gameplay_tag::ResolveGameplayTag(n"AutoTestEt.X.Y");
        auto TagAB  = utils_gameplay_tag::ResolveGameplayTag(n"AutoTestEt.A.B");
        auto TagA   = utils_gameplay_tag::ResolveGameplayTag(n"AutoTestEt.A");
        auto TagX   = utils_gameplay_tag::ResolveGameplayTag(n"AutoTestEt.X");

        utils_entity_tag::Add_UsingGameplayTag(LocalHandle, TagABC);
        utils_entity_tag::Add_UsingGameplayTag(LocalHandle, TagXY);

        auto Container = utils_entity_tag::Get_AllTagsAsContainer(LocalHandle);

        Assert_True(Container.HasTagExact(TagABC),
            "Container must contain explicitly-added A.B.C");
        Assert_True(Container.HasTagExact(TagXY),
            "Container must contain explicitly-added X.Y");
        Assert_True(!Container.HasTagExact(TagAB),
            "Container must NOT contain parent A.B (not explicitly added)");
        Assert_True(!Container.HasTagExact(TagA),
            "Container must NOT contain parent A (not explicitly added)");
        Assert_True(!Container.HasTagExact(TagX),
            "Container must NOT contain parent X (not explicitly added)");

        FinishSuccess();
    }
}
