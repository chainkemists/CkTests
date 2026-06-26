// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST ACTION: MID (WSInheritance / WSOverride tests)
//============================================================================
//
// Child action used in the WSInheritance and WSOverride tests.
//
// CDO effects: AKey=true — satisfies Root's _InitialGoal_RootOnly={AKey=true}
// so Root's planner selects Mid as Plan[0].
//
// No children added in either test — Mid is treated as atomic for the
// purposes of these WS-resolution tests.
//============================================================================

class UCk_AutoTestAction_Goap_ActionSet_Mid_WSInheritance : UCk_GoapAction_EntityScript
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
