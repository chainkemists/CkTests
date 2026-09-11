// Language=angelscript

class UCk_AutoTest_Selection_FixtureComposition : UCk_AutoTest_Base
{
    private FCk_Handle _FixtureRoot;
    private FCk_Handle _DirectCandidate;
    private FCk_Handle _OrdinaryParent;
    private FCk_Handle _NestedCandidate;
    private FCk_Handle _OrdinaryTransformChild;
    private FCk_Handle _NoTransformDescendant;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _FixtureRoot = utils_entity_lifetime::Request_CreateEntity(InHandle);
        _FixtureRoot.Set_DebugName(n"AutoTest.Selection.FixtureRoot");

        _DirectCandidate = selection_gym::Create_Candidate(
            ck::TransientEntity(),
            n"AutoTest.Selection.Direct",
            FVector(100.0f, 0.0f, 0.0f));
        // This root is outside the runner-owned fixture tree. Register it before any
        // wait/assertion so FinishFailure and the cleanup watchdog destroy it on every exit path.
        Track_ForCleanup(_DirectCandidate);
        _OrdinaryParent = selection_gym::Create_OrdinaryChild(_FixtureRoot, n"AutoTest.Selection.OrdinaryParent");
        _NestedCandidate = selection_gym::Create_Candidate(
            _OrdinaryParent,
            n"AutoTest.Selection.NestedIndependent",
            FVector(200.0f, 0.0f, 0.0f));
        selection_gym::Create_CompositeCandidate(_FixtureRoot, FVector(300.0f, 0.0f, 0.0f));
        _OrdinaryTransformChild = selection_gym::Create_OrdinaryTransformChild(
            _OrdinaryParent,
            n"AutoTest.Selection.OrdinaryTransformChild",
            FVector(250.0f, 0.0f, 0.0f));
        _NoTransformDescendant = selection_gym::Create_OrdinaryChild(
            _OrdinaryTransformChild,
            n"AutoTest.Selection.NoTransformDescendant");

        WaitUntil(n"Check_ContextRootsSettled", n"OnContextRootsSettled");
    }

    UFUNCTION(BlueprintOverride)
    void DoEndPlay(FCk_Handle InHandle)
    {
        // Defensive teardown for runner/world shutdown paths that bypass normal completion.
        // Only validate the handle; never inspect its fragments or ownership during teardown.
        if (ck::IsValid(_DirectCandidate))
        { utils_entity_lifetime::Request_DestroyEntity(_DirectCandidate); }
        _DirectCandidate = FCk_Handle();
    }

    UFUNCTION()
    private void Check_ContextRootsSettled(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto DirectOwner = utils_context_owner::Get_ContextOwner(_DirectCandidate);
        auto NestedOwner = utils_context_owner::Get_ContextOwner(_NestedCandidate);
        auto DirectLifetimeOwner = utils_entity_lifetime::Get_LifetimeOwner(_DirectCandidate);
        auto NestedLifetimeOwner = utils_entity_lifetime::Get_LifetimeOwner(_NestedCandidate);
        auto TransformChildOwner = utils_entity_lifetime::Get_LifetimeOwner(_OrdinaryTransformChild);
        auto NoTransformOwner = utils_entity_lifetime::Get_LifetimeOwner(_NoTransformDescendant);
        auto Res = OutResult;
        Res.Set(utils_handle::IsEqual(DirectOwner, _DirectCandidate)
            && utils_handle::IsEqual(NestedOwner, _NestedCandidate)
            && utils_handle::IsEqual(DirectLifetimeOwner, ck::TransientEntity())
            && utils_handle::IsEqual(NestedLifetimeOwner, _OrdinaryParent)
            && utils_handle::IsEqual(TransformChildOwner, _OrdinaryParent)
            && utils_handle::IsEqual(NoTransformOwner, _OrdinaryTransformChild));
    }

    UFUNCTION()
    private void OnContextRootsSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_True(utils_gameplay_label::MatchesExact(_DirectCandidate, selection_gym::Get_RootLabel()),
            "A direct child of the transient root must carry the public selection-root gameplay label");
        Assert_True(utils_gameplay_label::MatchesExact(_NestedCandidate, selection_gym::Get_RootLabel()),
            "A candidate nested below an ordinary lifetime parent must carry the public selection-root gameplay label");
        Assert_True(utils_transform::Has(_DirectCandidate),
            "A positioned selection candidate must own a Transform");
        Assert_True(utils_transform::Has(_OrdinaryTransformChild),
            "An ordinary child can carry a Transform without becoming an independent labelled root");
        Assert_True(utils_transform::Has(_NoTransformDescendant) == false,
            "The no-transform descendant must remain an ordinary family member without a Transform");

        utils_entity_lifetime::Request_DestroyEntity(_FixtureRoot);
        utils_entity_lifetime::Request_DestroyEntity(_DirectCandidate);
        WaitUntil(n"Check_FixtureTreeDestroyed", n"OnFixtureTreeDestroyed");
    }

    UFUNCTION()
    private void Check_FixtureTreeDestroyed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(ck::Is_NOT_Valid(_DirectCandidate)
            && ck::Is_NOT_Valid(_NestedCandidate)
            && ck::Is_NOT_Valid(_OrdinaryTransformChild)
            && ck::Is_NOT_Valid(_NoTransformDescendant));
    }

    UFUNCTION()
    private void OnFixtureTreeDestroyed(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        FinishSuccess();
    }
}
