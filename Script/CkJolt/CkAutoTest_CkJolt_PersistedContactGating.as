// Language=angelscript

//============================================================================
// CK JOLT — AUTOMATION TEST: PERSISTED-CONTACT INTEREST GATING
//============================================================================
//
// Persisted contact events are generated per manifold per physics sub-step on
// the Jolt worker threads (2 heap allocs + a lock each) and are DISCARDED
// unless some entity carries FTag_Probe_PersistContacts /
// FTag_JoltBody_PersistContacts. This pins the interest gate:
//
//   Stage A — two overlapping probes, nobody opted in     -> zero Persisted events
//   Stage B — BindTo_OnOverlapUpdated (implicit opt-in)   -> events flow, signal fires
//   Stage C — UnbindFrom_OnOverlapUpdated (opt-out)       -> back to zero
//
// The counter read is FJoltWorld::_Debug_NumPersistedContactEventsLastDrain,
// i.e. what the LAST drain consumed — a per-frame reading, not a total.
//
// The mover is nudged every tick: a kinematic body that stops moving falls
// asleep and stops producing contacts, which would make Stage A pass for the
// wrong reason.
//============================================================================

namespace ck_jolt_persistgate_test
{
    asset Asset_JoltPersistGateTest_Tags of UCk_GameplayTags
    {
        GameplayTags.Add(n"CkTests.Probe.PersistGate.Anchor");
        GameplayTags.Add(n"CkTests.Probe.PersistGate.Mover");
    }
}

class UCk_AutoTest_CkJolt_PersistedContactGating : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 20.0f;

    private FCk_Handle          _SelfHandle;
    private FCk_Handle_Probe    _AnchorProbe;
    private FCk_Handle_Transform _MoverTransform;

    private int32 _OverlapUpdatedCount = 0;
    private float _NudgeDir = 1.0;

    private FVector _Center = FVector(0.0, 0.0, 300.0);
    private float32 _ProbeRadius = 100.0f;

    // ~1s at 60fps; both probes stay overlapped the whole time.
    private int32 _SettleFrames = 60;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _SelfHandle = InHandle;

        auto AnchorTag = utils_gameplay_tag::ResolveGameplayTag(n"CkTests.Probe.PersistGate.Anchor");
        auto MoverTag  = utils_gameplay_tag::ResolveGameplayTag(n"CkTests.Probe.PersistGate.Mover");

        // ---- Anchor: kinematic sphere probe, filtered to the mover ----
        auto AnchorEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        AnchorEntity.Request_OverrideToSelf();
        auto AnchorTransform = utils_transform::Add(
            AnchorEntity, FTransform(FRotator::ZeroRotator, _Center), ECk_Replication::DoesNotReplicate);

        auto AnchorParams = FCk_Fragment_Probe_ParamsData(AnchorTag);
        AnchorParams.Set_MotionType(ECk_MotionType::Kinematic);
        AnchorParams.Set_ResponsePolicy(ECk_ProbeResponse_Policy::Notify);

        auto AnchorFilter = FGameplayTagContainer();
        AnchorFilter.AddTag(MoverTag);
        AnchorParams.Set_Filter(AnchorFilter);

        _AnchorProbe = utils_probe::Add_Sphere(AnchorTransform, _ProbeRadius, AnchorParams, FCk_Probe_DebugInfo());

        // ---- Mover: kinematic sphere probe at the same location, filtered to the anchor ----
        auto MoverEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        MoverEntity.Request_OverrideToSelf();
        _MoverTransform = utils_transform::Add(
            MoverEntity, FTransform(FRotator::ZeroRotator, _Center), ECk_Replication::DoesNotReplicate);

        auto MoverParams = FCk_Fragment_Probe_ParamsData(MoverTag);
        MoverParams.Set_MotionType(ECk_MotionType::Kinematic);
        MoverParams.Set_ResponsePolicy(ECk_ProbeResponse_Policy::Notify);

        auto MoverFilter = FGameplayTagContainer();
        MoverFilter.AddTag(AnchorTag);
        MoverParams.Set_Filter(MoverFilter);

        utils_probe::Add_Sphere(_MoverTransform, _ProbeRadius, MoverParams, FCk_Probe_DebugInfo());

        // Keeps the pair awake for the whole test. NOT bound to OnOverlapUpdated yet, and
        // Set_PersistContacts is never called — Stage A must observe zero interest.
        utils_timer::Create_Tick(_SelfHandle, FCk_Delegate_Timer(this, n"OnNudge"));

        WaitFrames(_SettleFrames, n"OnStageA");
    }

    UFUNCTION()
    private void OnNudge(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        _NudgeDir = -_NudgeDir;
        utils_transform::Request_AddLocationOffset(
            _MoverTransform, FVector(_NudgeDir, 0.0, 0.0), ECk_LocalWorld::World);
    }

    // ---- Stage A: nobody wants persisted contacts ----
    UFUNCTION()
    private void OnStageA(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto Count = UCk_Utils_Jolt_UE::Get_Debug_NumPersistedContactEventsLastDrain(_SelfHandle);
        Assert_Equals_Int(Count, 0,
            f"persisted events generated with zero interest — gate missing/broken (count={Count})");

        // Implicit opt-in: BindTo_OnOverlapUpdated adds FTag_Probe_PersistContacts.
        _AnchorProbe = utils_probe::BindTo_OnOverlapUpdated(_AnchorProbe,
            FCk_Delegate_Probe_OnOverlapUpdated(this, n"OnAnchorOverlapUpdated"));

        WaitFrames(_SettleFrames, n"OnStageB");
    }

    // ---- Stage B: opt-in re-enables generation end-to-end ----
    UFUNCTION()
    private void OnStageB(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_True(_OverlapUpdatedCount > 0,
            f"OnOverlapUpdated never fired after opting in — the probes are not overlapping (updates={_OverlapUpdatedCount})");

        auto Count = UCk_Utils_Jolt_UE::Get_Debug_NumPersistedContactEventsLastDrain(_SelfHandle);
        Assert_True(Count > 0,
            f"opting in did not restore persisted-contact generation (count={Count}, updates={_OverlapUpdatedCount})");

        _AnchorProbe = utils_probe::UnbindFrom_OnOverlapUpdated(_AnchorProbe,
            FCk_Delegate_Probe_OnOverlapUpdated(this, n"OnAnchorOverlapUpdated"));

        WaitFrames(_SettleFrames, n"OnStageC");
    }

    // ---- Stage C: last unbind opts back out ----
    UFUNCTION()
    private void OnStageC(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto Count = UCk_Utils_Jolt_UE::Get_Debug_NumPersistedContactEventsLastDrain(_SelfHandle);
        Assert_Equals_Int(Count, 0,
            f"unbinding the last OnOverlapUpdated listener did not stop persisted-contact generation (count={Count})");

        FinishSuccess();
    }

    UFUNCTION()
    private void OnAnchorOverlapUpdated(FCk_Handle_Probe InProbe, FCk_Probe_Payload_OnOverlapUpdated InPayload)
    {
        if (IsFinished()) { return; }

        _OverlapUpdatedCount++;
    }
}
