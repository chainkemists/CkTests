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

        WaitOneFrame(n"OnStage1");
    }

    UFUNCTION()
    private void OnStage1(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        // A second settle frame: create -> Setup -> threat-drain is a multi-pass cascade.
        WaitOneFrame(n"OnStage2");
    }

    UFUNCTION()
    private void OnStage2(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

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
