// Language=angelscript

//============================================================================
// CK PROBE TRACE - AUTOMATION TEST: SILENT NOTIFY POLICY SUPPRESSES PINGS
//============================================================================
//
// The knob that exists because the game's weapon aim sweep could not use this
// API at all: the script-facing overloads always fired Begin/EndOverlap into
// every probe they hit, so an aim preview ran as a real hit.
//
//   1. Notify (the default): the probe receives its BeginOverlap ping.
//   2. Silent: the SAME trace still returns the hit, and the probe receives
//      nothing further. Suppressing the side-effect must not suppress the
//      result.
//============================================================================

namespace ck_probetrace_silent_test
{
    asset Asset_ProbeTraceSilent_Tags of UCk_GameplayTags
    {
        GameplayTags.Add(n"CkTests.ProbeTrace.Silent.Target");
    }
}

class UCk_AutoTest_ProbeTrace_OverlapNotify_SilentFiresNothing : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;

    private FCk_Handle _SelfHandle;
    private FCk_Handle _ProbeEntity;

    private int32 _BeginCount = 0;

    // Y-band 45000.
    private float _Band = 45000.0;
    private float _TraceZ = 300.0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _SelfHandle = InHandle;

        _ProbeEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        _ProbeEntity.Request_OverrideToSelf();

        auto ProbeTransform = utils_transform::Add(_ProbeEntity,
            FTransform(FRotator::ZeroRotator, FVector(500.0, _Band, _TraceZ)), ECk_Replication::DoesNotReplicate);

        auto ProbeParams = FCk_Fragment_Probe_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"CkTests.ProbeTrace.Silent.Target"));
        ProbeParams.Set_MotionType(ECk_MotionType::Static);
        ProbeParams.Set_ResponsePolicy(ECk_ProbeResponse_Policy::Notify);
        utils_probe::Add_Box(ProbeTransform, FVector(50.0, 50.0, 50.0), ProbeParams, FCk_Probe_DebugInfo());

        WaitUntil(n"Check_ProbeIsTraceable", n"OnSettled");
    }

    private FCk_Probe_RayCast_Settings Make_Settings() const
    {
        auto Filter = FGameplayTagContainer();
        Filter.AddTag(utils_gameplay_tag::ResolveGameplayTag(n"CkTests.ProbeTrace.Silent.Target"));

        return FCk_Probe_RayCast_Settings(
            FVector(0.0, _Band, _TraceZ), FVector(1000.0, _Band, _TraceZ), Filter);
    }

    UFUNCTION()
    private void Check_ProbeIsTraceable(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        // Silent, because this predicate re-traces EVERY poll: a Notify settle-trace enqueues a
        // deferred BeginOverlap that drains a tick later, landing after the bind below and
        // inflating the measured count.
        auto Settings = Make_Settings();
        Settings.Set_OverlapNotifyPolicy(ECk_ProbeResponse_Policy::Silent);

        auto Res = OutResult;
        Res.Set(utils_probe_trace::Request_MultiLineTrace(_SelfHandle, Settings).Num() == 1);
    }

    UFUNCTION()
    private void OnSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        // Bound after the settle traces so only the measured casts are counted.
        utils_probe::BindTo_OnBeginOverlap(utils_probe::DoCastChecked(_ProbeEntity),
            FCk_Delegate_Probe_OnBeginOverlap(this, n"OnBeginOverlap"));

        auto Notify = utils_probe_trace::Request_MultiLineTrace(_SelfHandle, Make_Settings());
        Assert_Equals_Int(Notify.Num(), 1, "The default (Notify) trace reports the probe");

        WaitUntil(n"Check_ProbeWasPinged", n"OnNotifyDrained");
    }

    UFUNCTION()
    private void Check_ProbeWasPinged(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_BeginCount > 0);
    }

    UFUNCTION()
    private void OnNotifyDrained(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_BeginCount, 1, "Notify is the default - the probe receives exactly one ping");

        auto Settings = Make_Settings();
        Settings.Set_OverlapNotifyPolicy(ECk_ProbeResponse_Policy::Silent);

        auto Silent = utils_probe_trace::Request_MultiLineTrace(_SelfHandle, Settings);
        Assert_Equals_Int(Silent.Num(), 1, "Silent still RETURNS the hit - only the side-effect is suppressed");

        // Nothing to wait for: the assertion is that no further ping arrives.
        WaitFrames(6, n"OnSilentDrained");
    }

    UFUNCTION()
    private void OnSilentDrained(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_BeginCount, 1, "A Silent trace must add no further BeginOverlap ping");

        FinishSuccess();
    }

    UFUNCTION()
    private void OnBeginOverlap(FCk_Handle_Probe InProbe, FCk_Probe_Payload_OnBeginOverlap InPayload)
    {
        _BeginCount++;
    }
}
