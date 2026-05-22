// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST ACTION: MAKE-B (GetPlanEntities test)
//============================================================================
//
// Second step of the 2-step chain. Precondition: AKey=true. Effect: BKey=true.
// Cost 1.0. Cannot be selected until MakeA establishes AKey=true, so the
// regressive planner produces an ordered 2-step plan = [MakeA, MakeB] when
// the goal is BKey=true with both keys initially false.
//============================================================================

class UCk_AutoTestAction_Goap_GetPlanEntities_MakeB : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        AddPrecondition(utils_gameplay_tag::ResolveGameplayTag(
            n"AutoTest.Goap.ActionSet.WS.AKey"), true);
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"AutoTest.Goap.ActionSet.WS.BKey"), true);
        SetCost(1.0);
    }
}
