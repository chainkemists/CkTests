// Language=angelscript
//
// CK AGGRO — AUTOMATION TEST (P0): threat accumulates across AddThreat requests
// A target seeded at 0 threat, given +5 then +3, settles at 8 (default decay rate is 0).

class UCk_AutoTest_Aggro_AddThreat_Accumulates : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 4.0f;

    private FCk_Handle_AggroTarget _Target;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();

        auto Owner = utils_entity_lifetime::Request_CreateEntity(InHandle);
        utils_transform::Add(Owner, FTransform::Identity, ECk_Replication::DoesNotReplicate);
        auto Aggro = utils_aggro::Add(Owner, FCk_Fragment_Aggro_ParamsData());

        auto Tracked = utils_entity_lifetime::Request_CreateEntity(InHandle);

        auto ThreatParams = FCk_AggroTarget_ThreatParams();
        ThreatParams.Set_InitialThreat(0.0);
        auto Overrides = FCk_AggroTarget_ParamOverrides();
        Overrides.Set_OverrideThreat(true);
        Overrides.Set_ThreatParams(ThreatParams);
        _Target = Aggro.CreateTarget_WithParams(Tracked, Overrides);

        _Target.Request_AddThreat(5.0);
        _Target.Request_AddThreat(3.0);

        WaitOneFrame(n"OnSettled");
    }

    UFUNCTION()
    private void OnSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto Threat = _Target.Get_Threat();
        Assert_True(Math::Abs(Threat - 8.0) < 0.01, f"Threat should accumulate to 8, got {Threat}");

        FinishSuccess();
    }
}
