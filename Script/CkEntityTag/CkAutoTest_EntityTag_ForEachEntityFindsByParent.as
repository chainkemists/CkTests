// Language=angelscript

//============================================================================
// CK ENTITY TAG — AUTOMATION TEST: FOR_EACH_ENTITY FINDS BY PARENT
//============================================================================
//
// Three child entities are tagged with sibling/cousin gameplay tags:
//   childA -> AutoTestEt.A.B.C
//   childB -> AutoTestEt.A.B.D
//   childX -> AutoTestEt.X.Y
//
// ForEach_Entity(n"AutoTestEt.A.B") must return childA and childB but NOT
// childX. This pins the parent-flattening contract at the lookup level.
//============================================================================

class UCk_AutoTest_EntityTag_ForEachEntityFindsByParent : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;

        auto ChildA = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        auto ChildB = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        auto ChildX = utils_entity_lifetime::Request_CreateEntity(LocalHandle);

        utils_entity_tag::Add_UsingGameplayTag(ChildA,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTestEt.A.B.C"));
        utils_entity_tag::Add_UsingGameplayTag(ChildB,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTestEt.A.B.D"));
        utils_entity_tag::Add_UsingGameplayTag(ChildX,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTestEt.X.Y"));

        auto Found = utils_entity_tag::ForEach_Entity(LocalHandle, n"AutoTestEt.A.B");
        Assert_Equals_Int(Found.Num(), 2,
            f"ForEach_Entity(A.B) must return exactly the two A.B.* children (got {Found.Num()})");

        // Verify by entity id — neither side of the swap-vector ordering matters.
        auto FoundA = false;
        auto FoundB = false;
        for (auto i = 0; i < Found.Num(); ++i)
        {
            if (Found[i] == ChildA) { FoundA = true; }
            if (Found[i] == ChildB) { FoundB = true; }
            Assert_True(Found[i] != ChildX,
                "ChildX (X.Y) must not appear in ForEach_Entity(A.B)");
        }
        Assert_True(FoundA, "ChildA (A.B.C) must appear in ForEach_Entity(A.B)");
        Assert_True(FoundB, "ChildB (A.B.D) must appear in ForEach_Entity(A.B)");

        FinishSuccess();
    }
}
