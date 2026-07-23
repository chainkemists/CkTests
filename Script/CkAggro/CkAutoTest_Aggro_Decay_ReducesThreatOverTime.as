// Language=angelscript
//
// CK AGGRO — AUTOMATION TEST (P0): threat decays over time
// With a non-zero owner decay rate, a target's analytic threat drops below its seeded value as time passes.

class UCk_AutoTest_Aggro_Decay_ReducesThreatOverTime : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;

    private FCk_Handle_AggroTarget _Target;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();

        auto Owner = utils_entity_lifetime::Request_CreateEntity(InHandle);
        utils_transform::Add(Owner, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        auto OwnerThreat = FCk_Aggro_ThreatParams();
        OwnerThreat.Set_ThreatDecayRate(5.0);
        auto OwnerParams = FCk_Fragment_Aggro_ParamsData();
        OwnerParams.Set_ThreatParams(OwnerThreat);
        auto Aggro = utils_aggro::Add(Owner, OwnerParams);

        auto Tracked = utils_entity_lifetime::Request_CreateEntity(InHandle);
        auto ThreatParams = FCk_AggroTarget_ThreatParams();
        ThreatParams.Set_InitialThreatMode(ECk_Aggro_OverridePolicy::Override).Set_InitialThreat(10.0);
        auto Params = FCk_Fragment_AggroTarget_ParamsData(Tracked);
        Params.Set_ThreatParams(ThreatParams);
        _Target = Aggro.CreateTarget(Params);

        utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        if (ck::Is_NOT_Valid(_Target)) { return; }

        if (_Target.Get_Threat() < 9.0)
        {
            Assert_True(_Target.Get_Threat() < 10.0, "Threat should decay below its initial value over time");
            FinishSuccess();
        }
    }
}
