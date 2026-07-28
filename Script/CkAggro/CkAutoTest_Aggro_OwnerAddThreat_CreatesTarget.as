// Language=angelscript
//
// CK AGGRO — AUTOMATION TEST: owner-level AddThreat creates the target on demand
// The DamageResolution one-liner: Request_AddThreat on the owner with CreateIfMissing (default) for an untracked
// entity creates the tracked target and routes the threat onto it.

class UCk_AutoTest_Aggro_OwnerAddThreat_CreatesTarget : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 5.0f;

    private FCk_Handle_Aggro _Aggro;
    private FCk_Handle       _Tracked;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();

        auto Owner = utils_entity_lifetime::Request_CreateEntity(InHandle);
        utils_transform::Add(Owner, FTransform::Identity, ECk_Replication::DoesNotReplicate);
        _Aggro = utils_aggro::Add(Owner, FCk_Fragment_Aggro_ParamsData());

        _Tracked = utils_entity_lifetime::Request_CreateEntity(InHandle);

        _Aggro.Request_AddThreat(FCk_Request_Aggro_AddThreat(_Tracked, 7.0));

        WaitUntil(n"Check_ThreatRouted", n"OnStage2");
    }

    // Waits for the ROUTED threat to land, not merely for the target to exist.
    // Target creation is the FIRST stage of a create -> Setup -> threat-drain
    // cascade: the target is born carrying _InitialThreat (1.0) and the routed
    // 7.0 arrives on a later pass. Gating on existence alone reads 1.0 and fails
    // the > 5.0 contract. Safe to wait on the value because _ThreatDecayRate
    // defaults to 0 and this test uses default params, so threat is monotonic
    // here — it cannot rise past the threshold and fall back.
    UFUNCTION()
    private void Check_ThreatRouted(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Target = _Aggro.TryGet_Target_ByTrackedEntity(_Tracked);

        auto Res = OutResult;
        Res.Set(ck::IsValid(Target) && Target.Get_Threat() > 5.0);
    }

    UFUNCTION()
    private void OnStage2(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        Assert_Equals_Int(_Aggro.Get_NumTrackedTargets(), 1,
            "Owner AddThreat with CreateIfMissing should have created exactly one tracked target");

        auto Target = _Aggro.TryGet_Target_ByTrackedEntity(_Tracked);
        Assert_True(ck::IsValid(Target), "The created target should be findable by its tracked entity");

        if (ck::IsValid(Target))
        {
            Assert_True(Target.Get_Threat() > 5.0,
                f"The routed threat should have landed on the created target, got {Target.Get_Threat()}");
        }

        FinishSuccess();
    }
}
