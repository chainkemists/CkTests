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
        auto Aggro = utils_aggro::Add(Owner, FCk_Fragment_Aggro_ParamsData());

        auto Tracked = utils_entity_lifetime::Request_CreateEntity(InHandle);
        _Target = Aggro.CreateTarget(FCk_Fragment_AggroTarget_ParamsData(Tracked));

        _Target.Request_MarkPerceived(FCk_Request_AggroTarget_MarkPerceived());
        _Target.Request_MarkPerceived(FCk_Request_AggroTarget_MarkPerceived());

        WaitOneFrame(n"OnStage1");
    }

    UFUNCTION()
    private void OnStage1(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        Assert_True(_Target.Get_IsPerceived(), "After 2x MarkPerceived the target should be perceived");

        _Target.Request_MarkUnperceived();
        WaitOneFrame(n"OnStage2");
    }

    UFUNCTION()
    private void OnStage2(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        Assert_True(_Target.Get_IsPerceived(), "After 2x perceive + 1x unperceive the target should STILL be perceived");

        _Target.Request_MarkUnperceived();
        WaitOneFrame(n"OnStage3");
    }

    UFUNCTION()
    private void OnStage3(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        Assert_True(_Target.Get_IsPerceived() == false, "After the second MarkUnperceived the target should no longer be perceived");

        FinishSuccess();
    }
}
