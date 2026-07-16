// Language=angelscript

//============================================================================
// CK PROBE — AUTOMATION TEST: LINEARCAST BEGIN + END OVERLAP
//============================================================================
//
// Pins the LinearCast reconcile path (FProcessor_Probe_UpdateTransform_LinearCast):
//   1. Wall: static sphere probe (Notify, empty filter).
//   2. Mover: LinearCast kinematic sphere probe filtered to the wall's name,
//      stepped +X across the wall via Request_AddLocationOffset.
//   3. Sweeping INTO the wall fires OnProbeBeginOverlap exactly once (contact
//      persistence converts repeat hits into OverlapUpdated, not extra Begins).
//   4. Sweeping PAST the wall fires OnProbeEndOverlap (the lost-contact
//      reconcile ends the overlap on both probes).
//
// This is the behavior gate for any refactor of the LinearCast processor /
// ContactCastCollector — the ballistic-motion impact test covers Begin via a
// consumer, but nothing else covers EndOverlap on the probe itself.
//============================================================================

namespace ck_probe_linearcast_test
{
    asset Asset_ProbeLinearCastTest_Tags of UCk_GameplayTags
    {
        GameplayTags.Add(n"CkTests.Probe.LinearCast.Wall");
        GameplayTags.Add(n"CkTests.Probe.LinearCast.Mover");
    }
}

class UCk_AutoTest_Probe_LinearCast_BeginEndOverlap : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;

    private FCk_Handle _SelfHandle;
    private FCk_Handle _WallEntity;
    private FCk_Handle_Transform _MoverTransform;

    private int32 _BeginCount = 0;
    private int32 _EndCount = 0;
    private int32 _StepsTaken = 0;

    private FVector _WallCenter = FVector(600.0, 0.0, 300.0);
    private float32 _WallRadius = 150.0f;
    private float _StepDistance = 150.0;
    private int32 _MaxSteps = 40;   // 40 * 150 = 6000uu, far past the wall at X=600

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _SelfHandle = InHandle;

        // ---- Wall: static sphere probe, Notify, empty filter (receives from anything) ----
        _WallEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        _WallEntity.Request_OverrideToSelf();
        auto WallTransform = utils_transform::Add(
            _WallEntity, FTransform(FRotator::ZeroRotator, _WallCenter), ECk_Replication::DoesNotReplicate);

        auto WallProbeParams = FCk_Fragment_Probe_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"CkTests.Probe.LinearCast.Wall"));
        WallProbeParams.Set_MotionType(ECk_MotionType::Static);
        WallProbeParams.Set_ResponsePolicy(ECk_ProbeResponse_Policy::Notify);
        utils_probe::Add_Sphere(WallTransform, _WallRadius, WallProbeParams, FCk_Probe_DebugInfo());

        // ---- Mover: LinearCast kinematic sphere probe filtered to the wall ----
        auto Mover = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        Mover.Request_OverrideToSelf();
        _MoverTransform = utils_transform::Add(
            Mover, FTransform(FRotator::ZeroRotator, FVector(0.0, 0.0, 300.0)), ECk_Replication::DoesNotReplicate);

        auto MoverProbeParams = FCk_Fragment_Probe_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"CkTests.Probe.LinearCast.Mover"));
        MoverProbeParams.Set_MotionType(ECk_MotionType::Kinematic);
        MoverProbeParams.Set_MotionQuality(ECk_MotionQuality::LinearCast);
        MoverProbeParams.Set_ResponsePolicy(ECk_ProbeResponse_Policy::Notify);

        auto Filter = FGameplayTagContainer();
        Filter.AddTag(utils_gameplay_tag::ResolveGameplayTag(n"CkTests.Probe.LinearCast.Wall"));
        MoverProbeParams.Set_Filter(Filter);

        auto MoverProbe = utils_probe::Add_Sphere(_MoverTransform, 10.0, MoverProbeParams, FCk_Probe_DebugInfo());

        utils_probe::BindTo_OnBeginOverlap(MoverProbe,
            FCk_Delegate_Probe_OnBeginOverlap(this, n"OnMoverBeginOverlap"));
        utils_probe::BindTo_OnEndOverlap(MoverProbe,
            FCk_Delegate_Probe_OnEndOverlap(this, n"OnMoverEndOverlap"));

        // Let probe setup (Jolt body creation) settle, then sweep one step per tick.
        WaitOneFrame(n"OnSetupSettled");
    }

    UFUNCTION()
    private void OnSetupSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        utils_timer::Create_Tick(_SelfHandle, FCk_Delegate_Timer(this, n"OnStep"));
    }

    UFUNCTION()
    private void OnStep(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        _StepsTaken++;
        if (_StepsTaken > _MaxSteps)
        {
            FinishFailure(f"Mover swept {_MaxSteps} steps without completing the overlap cycle (begin={_BeginCount}, end={_EndCount})");
            return;
        }

        utils_transform::Request_AddLocationOffset(
            _MoverTransform, FVector(_StepDistance, 0.0, 0.0), ECk_LocalWorld::World);
    }

    UFUNCTION()
    private void OnMoverBeginOverlap(FCk_Handle_Probe InProbe, FCk_Probe_Payload_OnBeginOverlap InPayload)
    {
        if (IsFinished()) { return; }

        _BeginCount++;

        Assert_True(InPayload.Get_OtherEntity() == _WallEntity,
            "LinearCast BeginOverlap payload should reference the wall entity");
    }

    UFUNCTION()
    private void OnMoverEndOverlap(FCk_Handle_Probe InProbe, FCk_Probe_Payload_OnEndOverlap InPayload)
    {
        if (IsFinished()) { return; }

        _EndCount++;

        Assert_True(_BeginCount > 0, "EndOverlap should not fire before BeginOverlap");
        Assert_Equals_Int(_BeginCount, 1,
            "Persisted contact must convert repeat casts into OverlapUpdated — exactly one Begin expected");
        Assert_True(InPayload.Get_OtherEntity() == _WallEntity,
            "LinearCast EndOverlap payload should reference the wall entity");

        FinishSuccess();
    }
}
