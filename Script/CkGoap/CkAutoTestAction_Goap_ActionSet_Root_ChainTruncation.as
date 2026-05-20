// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST ACTION: ROOT (ChainTruncation test)
//============================================================================
//
// Root action for the ChainTruncation test.
//
// CDO effects: AKey=true. _InitialGoal_RootOnly is set to {AKey=true}
// in the test so Root plans to achieve AKey=true.
// Mid_A (cost 1) and Mid_B (cost 2) both have effect AKey=true.
// Initially Root picks Mid_A (lower cost). After Request_SetActionCost
// bumps Mid_A's cost to 100, Root replans and picks Mid_B.
//============================================================================

class UCk_AutoTestAction_Goap_ActionSet_Root_ChainTruncation : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"AutoTest.Goap.ActionSet.WS.AKey"), true);
        SetCost(1.0);
    }
}
