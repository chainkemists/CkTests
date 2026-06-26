// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST ACTION: ADDREMOVE CHEAPER LEAF
//============================================================================
//
// Cheaper alternative leaf for the AddRemoveChildren test. Effect: Ready=true.
// Cost 0.5 — cheaper than AtomicChild (cost 1.0). When this leaf is added to
// a Planner that already has AtomicChild as a child, the next plan should
// prefer this leaf because of its lower cost.
//============================================================================

class UCk_AutoTestAction_Goap_AddRemove_Cheaper : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        auto _CkPerfScope = ck::ScopedStat();
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"AutoTest.Goap.ActionSet.WS.Ready"), true);
        SetCost(0.5);
    }
}
