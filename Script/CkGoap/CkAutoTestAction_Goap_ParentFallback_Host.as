// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST ACTION: PARENT-FALLBACK PROMOTED HOST
//============================================================================
//
// The dual-role entity of the PromotedHostRoleSplit test: a candidate in the
// top-level planner's search (precond Key.Shared, effect Key.New — both live
// in the PARENT WS's index space) that is promoted to a sub-planner carrying
// a _WorldStateSource_Override onto a sub-WS. The role split keeps these
// candidate keys out of the sub registry.
//============================================================================

class UCk_AutoTestAction_Goap_ParentFallback_Host : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        auto _CkPerfScope = ck::ScopedStat();
        AddPrecondition(utils_gameplay_tag::ResolveGameplayTag(
            n"AutoTest.Goap.ParentFallback.Key.Shared"), true);
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"AutoTest.Goap.ParentFallback.Key.New"), true);
        SetCost(1.0);
    }
}
