// Language=angelscript

//============================================================================
// CK GOAP - AUTOMATION TEST ACTION: MAKE-A (GetPlanEntities test)
//============================================================================
//
// First step of the 2-step chain. Effect: AKey=true. No preconditions
// always eligible. Cost 1.0. Combined with MakeB (precondition AKey=true,
// effect BKey=true), this produces a 2-step plan when the goal is BKey=true.
//============================================================================

class UCk_AutoTestAction_Goap_GetPlanEntities_MakeA : UCk_GoapAction_EntityScript
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
