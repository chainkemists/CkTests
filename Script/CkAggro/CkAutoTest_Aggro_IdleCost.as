// Language=angelscript
//
// CK AGGRO — AUTOMATION TEST: idle is cheap, disabled is frozen
// Many enabled target-less owners keep pacing (their debug counter advances) while tracking nothing; disabled
// owners are fully excluded (counter never moves). Verifies the zero-cost-idle + counted-Disable design.

class UCk_AutoTest_Aggro_IdleCost : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;

    private FCk_Handle_Aggro _Enabled;
    private FCk_Handle_Aggro _Disabled;
    private float            _Elapsed = 0.0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();

        auto EvalParams = FCk_Aggro_EvaluationParams();
        EvalParams.Set_EvaluationInterval(FCk_Time(0.1)).Set_EvaluationJitter(FCk_Time(0.0));
        auto OwnerParams = FCk_Aggro_Spec();
        OwnerParams.Set_EvaluationParams(EvalParams);

        for (int i = 0; i < 40; i++)
        {
            auto Enabled = utils_entity_lifetime::Request_CreateEntity(InHandle);
            utils_transform::Add(Enabled, FTransform::Identity, ECk_Replication::DoesNotReplicate);
            _Enabled = utils_aggro::Add(Enabled, OwnerParams);

            auto Disabled = utils_entity_lifetime::Request_CreateEntity(InHandle);
            utils_transform::Add(Disabled, FTransform::Identity, ECk_Replication::DoesNotReplicate);
            _Disabled = utils_aggro::Add(Disabled, OwnerParams);
            _Disabled.Request_EnableDisable(ECk_EnableDisable::Disable);
        }

        utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        _Elapsed += InDeltaT.Get_Seconds();
        if (_Elapsed < 1.5) { return; }   // several 0.1s eval intervals

        Assert_True(_Enabled.Get_Debug_EvaluationCount() > 0, "An enabled target-less owner's pacer should advance");
        Assert_Equals_Int(_Enabled.Get_NumTrackedTargets(), 0, "A target-less owner tracks nothing");
        Assert_True(_Disabled.Get_Debug_EvaluationCount() == 0, "A disabled owner's pacer must stay frozen");
        Assert_Equals_Int(_Disabled.Get_NumTrackedTargets(), 0, "A disabled owner tracks nothing");

        FinishSuccess();
    }
}
