// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST ACTION: WSOverrideStack OpB
//============================================================================
//
// Operator B for the WSOverrideStack BasicPushPop test. Precondition KeyB=true,
// effect Goal=true, cost 1.0. Becomes the only viable plan step after Push_Override
// flips KeyA=false and KeyB=true in the override stack.
//============================================================================

class UCk_AutoTestAction_Goap_WSOverrideStack_OpB : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        auto _CkPerfScope = ck::ScopedStat();
        AddPrecondition(utils_gameplay_tag::ResolveGameplayTag(
            n"AutoTest.Goap.WSOverrideStack.KeyB"), true);
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"AutoTest.Goap.WSOverrideStack.Goal"), true);
        SetCost(1.0);
    }
}
