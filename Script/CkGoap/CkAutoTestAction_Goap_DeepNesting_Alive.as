// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST ACTION: ALIVE (DeepNesting test) — implicit root
//============================================================================
//
// Top-tier hosting Action for the DeepNesting test. Effect: EnemyDead=true.
// This is the implicit-root Action installed when AddAction is first called
// on the Alive Planner. It only exists to host the planner role; nothing
// picks Alive as an operator (no parent planner above it). The planner's
// real goal (EnemyDead=true) is set via PlannerParams._Goal.
//============================================================================

class UCk_AutoTestAction_Goap_DeepNesting_Alive : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        auto _CkPerfScope = ck::ScopedStat();
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"AutoTest.Goap.DeepNesting.WS.EnemyDead"), true);
        SetCost(0.0);
    }
}
