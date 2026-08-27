// Language=angelscript

//============================================================================
// CK GOAP - AUTOMATION TEST ACTION: ROOT (AtomicLeaf test)
//============================================================================
//
// Root action for the AtomicLeaf test. Exists only as a class reference
// for the Planner; its CDO effects (Ready=true) are used as the
// _InitialGoal_RootOnly target. No preconditions - root is always eligible.
//============================================================================

class UCk_AutoTestAction_Goap_ActionSet_Root_AtomicLeaf : UCk_GoapAction_EntityScript
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
