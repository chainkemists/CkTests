// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST ACTION: ATOMIC CHILD (AtomicLeaf test)
//============================================================================
//
// Child of Root_AtomicLeaf. Effect: Ready=true. No grandchildren added in
// the test — this makes it atomic (leaf). The planner selects it as
// Plan[0] of Root, but ChainUpdate does NOT extend the active chain
// because it has no registered children.
//============================================================================

class UCk_AutoTestAction_Goap_ActionSet_AtomicChild : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        auto _CkPerfScope = ck::ScopedStat();
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"AutoTest.Goap.ActionSet.WS.Ready"), true);
        SetCost(1.0);
    }
}
