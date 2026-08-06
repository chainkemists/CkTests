// Language=angelscript
//
// CK AGGRO — AUTOMATION TEST: perception is a counted tag
// Two MarkPerceived need two MarkUnperceived to clear: after 2x perceive + 1x unperceive the target is still
// perceived; the second unperceive clears it.

class UCk_AutoTest_Aggro_Perception_CountedTagBalance : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 5.0f;

    private FCk_Handle_AggroTarget _Target;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();

        auto Owner = utils_entity_lifetime::Request_CreateEntity(InHandle);
        utils_transform::Add(Owner, FTransform::Identity, ECk_Replication::DoesNotReplicate);
        auto Aggro = utils_aggro::Add(Owner, FCk_Aggro_Spec());

        auto Tracked = utils_entity_lifetime::Request_CreateEntity(InHandle);
        _Target = Aggro.CreateTarget(Tracked);

        _Target.Request_MarkPerceived(FCk_Request_AggroTarget_MarkPerceived());
        _Target.Request_MarkPerceived(FCk_Request_AggroTarget_MarkPerceived());

        WaitUntil(n"Check_Perceived", n"OnStage1");
    }

    // Both MarkPerceived are queued in the same tick and drained in one processor pass,
    // so when this first goes true the counted tag stands at 2 — which is exactly what
    // stages 2 and 3 depend on.
    UFUNCTION()
    private void Check_Perceived(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_Target.Get_IsPerceived());
    }

    UFUNCTION()
    private void Check_NotPerceived(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_Target.Get_IsPerceived() == false);
    }

    UFUNCTION()
    private void OnStage1(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        Assert_True(_Target.Get_IsPerceived(), "After 2x MarkPerceived the target should be perceived");

        _Target.Request_MarkUnperceived();

        // MUST stay a settle. This is the one hop with nothing to wait on: the counted
        // tag drops 2 -> 1 and Get_IsPerceived stays TRUE across it, and the depth is
        // private to CK_DEFINE_ECS_TAG_COUNTED with no accessor. Waiting on
        // Check_Perceived here would release on its first poll before the unperceive was
        // even handled, and stage 2 would then assert "still perceived" about a request
        // that had not happened yet — passing for the wrong reason.
        WaitOneFrame(n"OnStage2");
    }

    UFUNCTION()
    private void OnStage2(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        Assert_True(_Target.Get_IsPerceived(), "After 2x perceive + 1x unperceive the target should STILL be perceived");

        _Target.Request_MarkUnperceived();
        WaitUntil(n"Check_NotPerceived", n"OnStage3");
    }

    UFUNCTION()
    private void OnStage3(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        Assert_True(_Target.Get_IsPerceived() == false, "After the second MarkUnperceived the target should no longer be perceived");

        FinishSuccess();
    }
}
