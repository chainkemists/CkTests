// Language=angelscript
//
// CK AGGRO — AUTOMATION TEST (P0): the highest-score target becomes active
// Two co-located targets seeded at threat 10 and 5. After an evaluation pass the higher-threat one
// (equal distance -> score tracks threat) is selected as the active target.

class UCk_AutoTest_Aggro_Selection_HighestScoreBecomesActive : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;

    private FCk_Handle_Aggro _Aggro;
    private FCk_Handle       _TrackedHigh;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();

        auto Owner = utils_entity_lifetime::Request_CreateEntity(InHandle);
        utils_transform::Add(Owner, FTransform::Identity, ECk_Replication::DoesNotReplicate);
        _Aggro = utils_aggro::Add(Owner, FCk_Fragment_Aggro_ParamsData());

        _TrackedHigh   = utils_entity_lifetime::Request_CreateEntity(InHandle);
        auto TrackedLow = utils_entity_lifetime::Request_CreateEntity(InHandle);

        MakeTarget(_TrackedHigh, 10.0);
        MakeTarget(TrackedLow, 5.0);

        utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    private void MakeTarget(FCk_Handle InTracked, float InThreat)
    {
        auto ThreatParams = FCk_AggroTarget_ThreatParams();
        ThreatParams.Set_InitialThreat(InThreat);
        auto Overrides = FCk_AggroTarget_ParamOverrides();
        Overrides.Set_OverrideThreat(true);
        Overrides.Set_ThreatParams(ThreatParams);
        _Aggro.CreateTarget_WithParams(InTracked, Overrides);
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto Active = _Aggro.Get_ActiveTarget();
        if (ck::Is_NOT_Valid(Active)) { return; }   // not selected yet — keep polling

        Assert_True(Active.Get_TrackedEntity() == _TrackedHigh,
            "The higher-threat target should be selected as the active target");
        FinishSuccess();
    }
}
