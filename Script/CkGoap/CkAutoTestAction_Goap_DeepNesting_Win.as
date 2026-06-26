// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST ACTION: WIN (DeepNesting test)
//============================================================================
//
// Atomic finishing-move under Alive. Precondition: EnemyAttacked=true.
// Effect: EnemyDead=true. Cost 1.0. Cannot be selected as Plan[0] until
// the chain produces EnemyAttacked=true via Engage's subtree. The regressive
// planner sequences this as Plan[1] in Alive's plan = [Engage, Win].
//============================================================================

class UCk_AutoTestAction_Goap_DeepNesting_Win : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        auto _CkPerfScope = ck::ScopedStat();
        AddPrecondition(utils_gameplay_tag::ResolveGameplayTag(
            n"AutoTest.Goap.DeepNesting.WS.EnemyAttacked"), true);
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"AutoTest.Goap.DeepNesting.WS.EnemyDead"), true);
        SetCost(1.0);
    }
}
