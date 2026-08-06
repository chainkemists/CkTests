// Language=angelscript
//
// CK AGGRO — AUTOMATION TEST: switching requires beating the hysteresis threshold
// With cooldown/min-duration removed (isolating the score gate), a challenger that only marginally beats the
// incumbent (11 vs 10) does NOT steal the active slot, but one well past bias*threshold (26) does.

class UCk_AutoTest_Aggro_Switch_ThresholdRequired : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;

    private FCk_Handle_Aggro       _Aggro;
    private FCk_Handle_AggroTarget _TargetB;
    private FCk_Handle             _TrackedA;
    private FCk_Handle             _TrackedB;
    private int                    _Stage = 0;
    private float                  _StageTime = 0.0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();

        auto Owner = utils_entity_lifetime::Request_CreateEntity(InHandle);
        utils_transform::Add(Owner, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        auto Selection = FCk_Aggro_SelectionParams();
        Selection.Set_TargetSwitchCooldown(FCk_Time(0.0)).Set_MinimumAggroDuration(FCk_Time(0.0));
        auto OwnerParams = FCk_Aggro_Spec();
        OwnerParams.Set_SelectionParams(Selection);
        _Aggro = utils_aggro::Add(Owner, OwnerParams);

        _TrackedA = utils_entity_lifetime::Request_CreateEntity(InHandle);
        _TrackedB = utils_entity_lifetime::Request_CreateEntity(InHandle);
        MakeTarget(_TrackedA, 10.0);
        _TargetB = MakeTarget(_TrackedB, 5.0);

        utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    private FCk_Handle_AggroTarget MakeTarget(FCk_Handle InTracked, float InThreat)
    {
        auto ThreatParams = FCk_AggroTarget_ThreatParams();
        ThreatParams.Set_InitialThreat(InThreat);
        auto Overrides = FCk_AggroTarget_ParamOverrides();
        Overrides.Set_OverrideThreat(true);
        Overrides.Set_ThreatParams(ThreatParams);
        return _Aggro.CreateTarget_WithParams(InTracked, Overrides);
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto Active = _Aggro.Get_ActiveTarget();

        if (_Stage == 0)
        {
            // Wait until the higher-threat target A is the active one.
            if (ck::Is_NOT_Valid(Active) || Active.Get_TrackedEntity() != _TrackedA) { return; }
            _TargetB.Request_AddThreat(6.0);   // B: 5 -> 11 (just above A's 10, below 10*1.2*1.15 = 13.8)
            _Stage = 1;
            _StageTime = 0.0;
            return;
        }

        if (_Stage == 1)
        {
            _StageTime += InDeltaT.Get_Seconds();
            if (_StageTime < 0.5) { return; }   // give the marginal challenger time to (not) win
            Assert_True(ck::IsValid(Active) && Active.Get_TrackedEntity() == _TrackedA,
                "A marginal challenger (11 vs 10) must not pass the switch threshold");
            _TargetB.Request_AddThreat(15.0);  // B: 11 -> 26 (well past the threshold)
            _Stage = 2;
            return;
        }

        // _Stage == 2 — the decisive challenger should now hold the active slot.
        if (ck::IsValid(Active) && Active.Get_TrackedEntity() == _TrackedB)
        {
            Assert_True(true, "A decisive challenger past bias*threshold takes the active slot");
            FinishSuccess();
        }
    }
}
