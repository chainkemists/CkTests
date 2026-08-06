// Language=angelscript
//
// CK AGGRO — AUTOMATION TEST (P0): a target is forgotten after its forget duration
// With a short ForgetDuration and no fresh threat/perception, a tracked target times out and is dropped
// (tracked count returns to 0).

class UCk_AutoTest_Aggro_Forget_AfterForgetDuration : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;

    private FCk_Handle_Aggro _Aggro;
    private bool             _SawTarget = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();

        auto Owner = utils_entity_lifetime::Request_CreateEntity(InHandle);
        utils_transform::Add(Owner, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        auto DefaultTargetThreat = FCk_AggroTarget_ThreatParams();
        DefaultTargetThreat.Set_InitialThreat(10.0);
        auto DefaultTargetForget = FCk_AggroTarget_ForgetParams();
        DefaultTargetForget.Set_ForgetDuration(FCk_Time(0.5));
        auto DefaultTargetParams = FCk_AggroTarget_Spec();
        DefaultTargetParams.Set_ThreatParams(DefaultTargetThreat);
        DefaultTargetParams.Set_ForgetParams(DefaultTargetForget);
        auto OwnerParams = FCk_Aggro_Spec();
        OwnerParams.Set_DefaultTargetParams(DefaultTargetParams);
        _Aggro = utils_aggro::Add(Owner, OwnerParams);

        auto Tracked = utils_entity_lifetime::Request_CreateEntity(InHandle);
        _Aggro.CreateTarget(Tracked);

        utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto Num = _Aggro.Get_NumTrackedTargets();
        if (Num >= 1)
        { _SawTarget = true; }
        else if (_SawTarget && Num == 0)
        {
            Assert_True(true, "Target was forgotten after its forget duration");
            FinishSuccess();
        }
    }
}
