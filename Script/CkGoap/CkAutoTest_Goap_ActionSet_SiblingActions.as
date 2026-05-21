// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST: ACTIONSET SIBLING ACTIONS
//============================================================================
//
// Validates utils_goap_action_set::AddAction_ToActionSet(ActionSet,
// ActionParams).
//
// Per spec §3.1: AddAction_ToActionSet adds a top-level Action as a sibling
// of the root — catalog-only, NOT inserted into the active chain. These
// siblings exist for Request_SetRootAction to pick from later (or for
// designers who want to register multiple top-level Actions).
//
// Setup:
//   - WS: Ready=true (so root plan trivially succeeds).
//   - Root = Simple action (effect Ready=true → goal already met).
//   - Wait for Root's OnPlanComplete to confirm chain is settled.
//
// Phase 2:
//   - Call AddAction_ToActionSet(ActionSet, SiblingParams) with the
//     AtomicLeaf root class (a distinct class from Root).
//   - Assert sibling handle is valid.
//   - Assert sibling is in the catalog: Find_ActionByClass returns the
//     sibling's handle.
//   - Assert sibling is NOT in the active chain: Get_ActiveChain still
//     contains only Root (length 1).
//   - Assert Get_RootAction is unchanged (still Root_A).
//============================================================================

class UCk_AutoTest_Goap_ActionSet_SiblingActions : UCk_AutoTest_Base
{
    private FCk_Handle_Goap_ActionSet _ActionSet;
    private FCk_Handle_Goap_Action _RootAction;
    private FCk_Handle_Goap_Action _SiblingAction;
    private bool _RootPlanReceived = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Local = InHandle;
        utils_transform::Add(Local, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        auto WS = utils_goap_world_state::Create(Local,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.WS"),
            FCk_Fragment_Goap_WorldState_ParamsData());
        utils_goap_world_state::Set_Value(WS,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.WS.Ready"),
            true);

        auto Goap = utils_goap::Add(Local, FCk_Fragment_Goap_RootParamsData());

        auto ActionSetParams = FCk_Fragment_Goap_ActionSetParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.Set"));
        _ActionSet = utils_goap_action_set::AddActionSet(Goap, ActionSetParams);
        Assert_True(ck::IsValid(_ActionSet), "AddActionSet should return a valid handle");

        // Root = Simple. Effect Ready=true IS the goal.
        auto RootParams = FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_ActionSet_Simple);
        _RootAction = utils_goap_action_set::SetRootAction(_ActionSet, RootParams, WS);
        Assert_True(ck::IsValid(_RootAction), "SetRootAction should return a valid handle");

        utils_goap_action::BindTo_OnPlanComplete(_RootAction,
            FCk_Delegate_Goap_OnActionPlanComplete(this, n"OnRootPlan"));
    }

    UFUNCTION()
    private void OnRootPlan(
        FCk_Handle_Goap_Action InAction,
        FCk_Goap_Payload_OnPlanComplete InPayload)
    {
        if (IsFinished()) { return; }
        if (_RootPlanReceived) { return; }
        _RootPlanReceived = true;

        // Chain settled at [Root].
        auto Chain = utils_goap_action_set::Get_ActiveChain(_ActionSet);
        Assert_True(Chain.Num() == 1,
            f"Chain should be [Root] before sibling Add (got {Chain.Num()})");

        // Add sibling top-level Action — different class so DoCreateOrFindActionEntity
        // creates a fresh entity rather than returning the existing Root.
        auto SiblingParams = FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_ActionSet_Root_AtomicLeaf);
        _SiblingAction = utils_goap_action_set::AddAction_ToActionSet(_ActionSet, SiblingParams);

        Assert_True(ck::IsValid(_SiblingAction),
            "AddAction_ToActionSet should return a valid handle for a sibling Action");

        Assert_True(_SiblingAction != _RootAction,
            "Sibling Action handle should differ from Root handle");

        // Sibling is in the catalog.
        auto FoundByClass = utils_goap_action_set::Find_ActionByClass(
            _ActionSet, UCk_AutoTestAction_Goap_ActionSet_Root_AtomicLeaf);
        Assert_True(ck::IsValid(FoundByClass),
            "Find_ActionByClass should locate the sibling in the catalog");
        Assert_True(FoundByClass == _SiblingAction,
            "Find_ActionByClass should return the sibling's handle");

        // Root is still findable by its class.
        auto FoundRootByClass = utils_goap_action_set::Find_ActionByClass(
            _ActionSet, UCk_AutoTestAction_Goap_ActionSet_Simple);
        Assert_True(FoundRootByClass == _RootAction,
            "Find_ActionByClass(Simple) should still return the Root handle");

        // Get_RootAction is unchanged — sibling Add did not promote the sibling.
        auto CurrentRoot = utils_goap_action_set::Get_RootAction(_ActionSet);
        Assert_True(CurrentRoot == _RootAction,
            "Get_RootAction should be unchanged after AddAction_ToActionSet");

        // Active chain should still be [Root] only — sibling is catalog-only.
        // ChainUpdate runs after the next tick, so wait one frame and assert.
        WaitOneFrame(n"OnVerifyChainAfterSiblingAdd");
    }

    UFUNCTION()
    private void OnVerifyChainAfterSiblingAdd(
        FCk_Handle_Timer InTimer,
        FCk_Chrono InChrono,
        FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto Chain = utils_goap_action_set::Get_ActiveChain(_ActionSet);
        Assert_True(Chain.Num() == 1,
            f"Chain should remain [Root] (length 1) after AddAction_ToActionSet — siblings are catalog-only (got {Chain.Num()})");

        if (Chain.Num() >= 1)
        {
            Assert_True(Chain[0] == _RootAction,
                "Chain[0] should still be Root after sibling Add");
        }

        FinishSuccess();
    }
}

//============================================================================
// HAND-AUTHORED WRAPPER ACTOR (skipped by auto-generator when present)
//============================================================================

class ACk_AutoTest_Goap_ActionSet_SiblingActions_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Goap_ActionSet_SiblingActions;
    default _TimeoutSeconds = 15.0f;
}
