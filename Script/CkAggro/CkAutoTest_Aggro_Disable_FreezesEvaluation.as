// Language=angelscript
//
// CK AGGRO — AUTOMATION TEST: a disabled Aggro's pacer freezes
// Disabling an Aggro excludes it from the evaluation pacer, so its debug evaluation counter stops advancing.

class UCk_AutoTest_Aggro_Disable_FreezesEvaluation : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 5.0f;

    private FCk_Handle_Aggro _Aggro;
    private int64            _CountAtDisable = -1;
    private float            _ElapsedSinceDisable = 0.0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();

        auto Owner = utils_entity_lifetime::Request_CreateEntity(InHandle);
        utils_transform::Add(Owner, FTransform::Identity, ECk_Replication::DoesNotReplicate);
        // Short interval so the pacer WOULD tick often if it were enabled.
        auto EvalParams = FCk_Aggro_EvaluationParams();
        EvalParams.Set_EvaluationInterval(FCk_Time(0.1));
        EvalParams.Set_EvaluationJitter(FCk_Time(0.0));
        auto OwnerParams = FCk_Aggro_Spec();
        OwnerParams.Set_EvaluationParams(EvalParams);
        _Aggro = utils_aggro::Add(Owner, OwnerParams);

        _Aggro.Request_EnableDisable(ECk_EnableDisable::Disable);

        utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        if (_CountAtDisable < 0)
        { _CountAtDisable = _Aggro.Get_Debug_EvaluationCount(); return; }

        _ElapsedSinceDisable += InDeltaT.Get_Seconds();
        if (_ElapsedSinceDisable > 1.0)   // well past several 0.1s eval intervals
        {
            Assert_True(_Aggro.Get_Debug_EvaluationCount() == _CountAtDisable,
                "A disabled Aggro's evaluation counter must not advance");
            FinishSuccess();
        }
    }
}
