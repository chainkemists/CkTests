// Language=angelscript

//============================================================================
// CK GOAP - AUTOMATION TEST ACTION: ROOT (Toggle test)
//============================================================================
//
// Root action for the Toggle test.
//
// CDO effect: AKey=true. _InitialGoal_RootOnly is set to {BKey=true} in
// the test, so the planner searches for a child that achieves BKey. Mid
// (effect BKey=true, composite) is in the catalog as a child of Root,
// so Root's plan = [Mid]. When ChainUpdate is enabled, Mid is appended
// to the active chain.
//============================================================================

class UCk_AutoTestAction_Goap_ActionSet_Root_Toggle : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        auto _CkPerfScope = ck::ScopedStat();
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"AutoTest.Goap.ActionSet.WS.AKey"), true);
        SetCost(1.0);
    }
}
