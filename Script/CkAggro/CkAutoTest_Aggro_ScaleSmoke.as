// Language=angelscript
//
// CK AGGRO - AUTOMATION TEST: the pipeline holds at scale
// 30 owners x 5 spatially-distributed targets (150 tracked targets) run the full pacer -> evaluate -> select
// pipeline for several seconds; the sample owner ends with a selected active target and its targets intact.
// (Scale/no-crash validation of the SERIAL Evaluate; the FPS/Insights perf pass is a separate manual step.)

class UCk_AutoTest_Aggro_ScaleSmoke : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 20.0f;

    private FCk_Handle_Aggro _Sample;
    private float            _Elapsed = 0.0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();

        auto EvalParams = FCk_Aggro_EvaluationParams();
        EvalParams.Set_EvaluationInterval(FCk_Time(0.1)).Set_EvaluationJitter(FCk_Time(0.05));
        auto OwnerParams = FCk_Fragment_Aggro_ParamsData();
        OwnerParams.Set_EvaluationParams(EvalParams);

        for (int o = 0; o < 30; o++)
        {
            auto Owner = utils_entity_lifetime::Request_CreateEntity(InHandle);
            utils_transform::Add(Owner, FTransform::Identity, ECk_Replication::DoesNotReplicate);
            _Sample = utils_aggro::Add(Owner, OwnerParams);

            for (int t = 0; t < 5; t++)
            {
                auto Tracked = utils_entity_lifetime::Request_CreateEntity(InHandle);
                utils_transform::Add(Tracked, FTransform(FRotator::ZeroRotator, FVector(100.0 * (t + 1), 0.0, 0.0)),
                    ECk_Replication::DoesNotReplicate);

                auto ThreatParams = FCk_AggroTarget_ThreatParams();
                ThreatParams.Set_InitialThreat(10.0 - t);
                auto Overrides = FCk_AggroTarget_ParamOverrides();
                Overrides.Set_OverrideThreat(true);
                Overrides.Set_ThreatParams(ThreatParams);
                _Sample.CreateTarget_WithParams(Tracked, Overrides);
            }
        }

        utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        _Elapsed += InDeltaT.Get_Seconds();
        if (_Elapsed < 3.0) { return; }

        Assert_True(ck::IsValid(_Sample.Get_ActiveTarget()),
            "At scale, the sample owner should have selected an active target");
        Assert_True(_Sample.Get_NumTrackedTargets() >= 1,
            "The sample owner should still track its targets after several evaluation cycles");

        FinishSuccess();
    }
}
