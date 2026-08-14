// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST ACTION: PARENT-FALLBACK SUB-ACHIEVE
//============================================================================
//
// Child of the promoted host in the PromotedHostRoleSplit test: achieves the
// sub-planner's goal (Key.Local) in the SUB-WS index space.
//============================================================================

class UCk_AutoTestAction_Goap_ParentFallback_SubAchieve : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        auto _CkPerfScope = ck::ScopedStat();
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"AutoTest.Goap.ParentFallback.Key.Local"), true);
        SetCost(1.0);
    }
}
