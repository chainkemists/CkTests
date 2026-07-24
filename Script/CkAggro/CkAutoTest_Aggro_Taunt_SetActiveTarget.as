// Language=angelscript
//
// CK AGGRO — AUTOMATION TEST: taunt forces the active target
// The higher-threat target is selected first; Request_SetActiveTarget then forces the OTHER target active,
// bypassing selection hysteresis.

class UCk_AutoTest_Aggro_Taunt_SetActiveTarget : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;

    private FCk_Handle_Aggro _Aggro;
    private FCk_Handle       _TrackedB;
    private bool             _Taunted = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();

        auto Owner = utils_entity_lifetime::Request_CreateEntity(InHandle);
        utils_transform::Add(Owner, FTransform::Identity, ECk_Replication::DoesNotReplicate);
        _Aggro = utils_aggro::Add(Owner, FCk_Fragment_Aggro_ParamsData());

        auto TrackedA = utils_entity_lifetime::Request_CreateEntity(InHandle);
        _TrackedB      = utils_entity_lifetime::Request_CreateEntity(InHandle);
        MakeTarget(TrackedA, 10.0);
        MakeTarget(_TrackedB, 5.0);

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
        if (ck::Is_NOT_Valid(Active)) { return; }   // wait for the first selection (the higher-threat target)

        if (_Taunted == false)
        {
            _Aggro.Request_SetActiveTarget(_TrackedB);
            _Taunted = true;
            return;
        }

        if (Active.Get_TrackedEntity() == _TrackedB)
        {
            Assert_True(true, "Taunt forced the active target to B");
            FinishSuccess();
        }
    }
}
