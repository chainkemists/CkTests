// Language=angelscript

//============================================================================
// CK PROBE - AUTOMATION TEST: RIGID-BODY CONTACT DOES NOT MASQUERADE AS PROBE
//============================================================================
//
// A single entity may legitimately own both a JoltBody and a Probe. They share
// the entity id in Jolt user data, so the contact routers must still respect
// WHICH body actually made contact. This test makes that distinction visible:
//
//   1. Hybrid entity: a real kinematic JoltBody plus a Notify Probe which is
//      explicitly Disabled before the measurement begins.
//   2. Detector: an enabled Notify Probe at an isolated location.
//   3. Teleport only the JoltBody into the detector and prove its native
//      OnJoltBodyContactAdded signal names the detector.
//   4. Let queued contact handling drain. The disabled Probe must have emitted
//      no BeginOverlap and must still have no overlap membership.
//   5. Enable that sibling Probe. Its large sensor volume genuinely overlaps
//      the detector even after only the smaller JoltBody teleports away. The
//      JoltBody's ContactRemoved must not end the Probe's real overlap.
//
// This deliberately uses the production Jolt contact queue and Probe request
// processor, rather than synthesizing a BeginOverlap request. A regression
// here would let an ordinary rigid-body contact be attributed to the sibling
// Probe merely because both bodies share an owning entity.
//============================================================================

namespace ck_probe_rigidbody_contact_test
{
    asset Asset_ProbeRigidBodyContactTest_Tags of UCk_GameplayTags
    {
        GameplayTags.Add(n"CkTests.Probe.RigidBodyContact.DisabledProbe");
        GameplayTags.Add(n"CkTests.Probe.RigidBodyContact.Detector");
    }
}

class UCk_AutoTest_Probe_RigidBodyContactDoesNotMasqueradeAsProbe : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 12.0f;

    private FCk_Handle _SelfHandle;
    private FCk_Handle _DetectorEntity;
    private FCk_Handle_JoltBody _RigidBody;
    private FCk_Handle_Probe _DisabledProbe;
    private FCk_Handle_Probe _DetectorProbe;

    // Keep the hybrid pair far from the other CkTests physics fixtures.
    private const FVector _StartLocation = FVector(0.0, 72000.0, 300.0);
    private const FVector _DetectorLocation = FVector(1000.0, 72000.0, 300.0);

    private int32 _JoltContactAddedCount = 0;
    private int32 _JoltContactRemovedCount = 0;
    private int32 _DisabledProbeBeginCount = 0;
    private int32 _SiblingProbeEndCount = 0;
    private bool _JoltContactNamedDetector = false;
    private bool _JoltContactRemovalNamedDetector = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _SelfHandle = InHandle;

        auto DisabledProbeTag = utils_gameplay_tag::ResolveGameplayTag(
            n"CkTests.Probe.RigidBodyContact.DisabledProbe");
        auto DetectorTag = utils_gameplay_tag::ResolveGameplayTag(
            n"CkTests.Probe.RigidBodyContact.Detector");

        // ---- Hybrid: one real JoltBody and one intentionally disabled Probe ------------------
        auto HybridEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        HybridEntity.Request_OverrideToSelf();
        auto HybridTransform = utils_transform::Add(
            HybridEntity, FTransform(FRotator::ZeroRotator, _StartLocation), ECk_Replication::DoesNotReplicate);

        auto RigidShape = FCk_Jolt_ShapeDimensions(ECk_Jolt_ShapeType::Sphere);
        RigidShape.Set_Radius(100.0);
        auto RigidParams = FCk_Fragment_JoltBody_ParamsData(ECk_JoltBody_ShapeSource::ExplicitShape);
        RigidParams.Set_ShapeDimensions(RigidShape);
        RigidParams.Set_MotionType(ECk_MotionType::Kinematic);
        RigidParams.Set_CollisionProfileName(n"BlockAllDynamic");
        _RigidBody = utils_jolt_body::Add(HybridEntity, RigidParams);

        auto DisabledProbeParams = FCk_Fragment_Probe_ParamsData(DisabledProbeTag);
        DisabledProbeParams.Set_MotionType(ECk_MotionType::Kinematic);
        DisabledProbeParams.Set_ResponsePolicy(ECk_ProbeResponse_Policy::Notify);
        DisabledProbeParams.Set_StartingState(ECk_EnableDisable::Disable);

        auto DisabledProbeFilter = FGameplayTagContainer();
        DisabledProbeFilter.AddTag(DetectorTag);
        DisabledProbeParams.Set_Filter(DisabledProbeFilter);
        // The Probe starts disabled, so this large sensor cannot participate in the first (false
        // Added-route) phase. Its 1500uu radius keeps the later genuine Probe contact alive when
        // the 100uu JoltBody returns to StartLocation, 1000uu from the detector.
        _DisabledProbe = utils_probe::Add_Sphere(
            HybridTransform, 1500.0, DisabledProbeParams, FCk_Probe_DebugInfo());

        // ---- Enabled detector Probe ------------------------------------------------------------
        _DetectorEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        _DetectorEntity.Request_OverrideToSelf();
        auto DetectorTransform = utils_transform::Add(
            _DetectorEntity, FTransform(FRotator::ZeroRotator, _DetectorLocation), ECk_Replication::DoesNotReplicate);

        auto DetectorParams = FCk_Fragment_Probe_ParamsData(DetectorTag);
        DetectorParams.Set_MotionType(ECk_MotionType::Kinematic);
        DetectorParams.Set_ResponsePolicy(ECk_ProbeResponse_Policy::Notify);
        _DetectorProbe = utils_probe::Add_Sphere(
            DetectorTransform, 100.0, DetectorParams, FCk_Probe_DebugInfo());

        utils_jolt_body::BindTo_OnJoltBodyContactAdded(_RigidBody,
            FCk_Delegate_JoltBody_OnContact(this, n"OnRigidBodyContactAdded"));
        utils_jolt_body::BindTo_OnJoltBodyContactRemoved(_RigidBody,
            FCk_Delegate_JoltBody_OnContactRemoved(this, n"OnRigidBodyContactRemoved"));
        utils_probe::BindTo_OnBeginOverlap(_DisabledProbe,
            FCk_Delegate_Probe_OnBeginOverlap(this, n"OnDisabledProbeBeginOverlap"));
        utils_probe::BindTo_OnEndOverlap(_DisabledProbe,
            FCk_Delegate_Probe_OnEndOverlap(this, n"OnSiblingProbeEndOverlap"));

        // Do not teleport until both Jolt bodies are set up and the Probe's deferred Disable landed.
        WaitUntil(n"Check_SetupSettled", n"OnSetupSettled");
    }

    UFUNCTION()
    private void Check_SetupSettled(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(
            utils_jolt_body::Get_IsBodyAdded(_RigidBody)
            && utils_probe::Get_IsEnabledDisabled(_DisabledProbe) == ECk_EnableDisable::Disable
            && utils_probe::Get_IsEnabledDisabled(_DetectorProbe) == ECk_EnableDisable::Enable);
    }

    UFUNCTION()
    private void OnSetupSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        // The JoltBody readiness gate above proves its setup. Give the sibling Probe setup and
        // its Enable/Disable request a bounded drain window before moving the real body.
        WaitFrames(3, n"OnAllSetupDrained");
    }

    UFUNCTION()
    private void OnAllSetupDrained(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_DisabledProbeBeginCount, 0,
            "The disabled Probe must not receive setup-side BeginOverlap events");
        Assert_True(utils_probe::Get_CurrentOverlaps(_DisabledProbe).IsEmpty(),
            "The disabled Probe must have no setup-side overlap membership");

        auto Teleport = FCk_Request_JoltBody_Teleport(_DetectorLocation, FRotator::ZeroRotator);
        Teleport.Set_VelocityPolicy(ECk_Jolt_TeleportVelocityPolicy::ResetVelocity);
        utils_jolt_body::Request_Teleport(_RigidBody, Teleport);

        WaitUntil(n"Check_RigidBodyContact", n"OnRigidBodyContactObserved");
    }

    UFUNCTION()
    private void Check_RigidBodyContact(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(_JoltContactAddedCount > 0);
    }

    UFUNCTION()
    private void OnRigidBodyContactObserved(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_True(_JoltContactNamedDetector,
            "The JoltBody contact must identify the enabled detector Probe entity");

        // Contact routing reaches CkSpatialQuery through the same drained event batch. Let its
        // deferred Probe requests cross the next scheduler frames before asserting the negative.
        WaitFrames(3, n"OnProbeContactDrainSettled");
    }

    UFUNCTION()
    private void OnProbeContactDrainSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_DisabledProbeBeginCount, 0,
            "A JoltBody contact must not fire OnBeginOverlap on its disabled sibling Probe");
        Assert_True(utils_probe::Get_IsEnabledDisabled(_DisabledProbe) == ECk_EnableDisable::Disable,
            "The sibling Probe must still be disabled when the negative routing state is checked");
        Assert_True(utils_probe::Get_CurrentOverlaps(_DisabledProbe).IsEmpty(),
            "A disabled sibling Probe must not gain overlap membership from a JoltBody contact");
        Assert_True(utils_probe::Get_IsOverlapping(_DisabledProbe) == false,
            "A disabled sibling Probe must remain non-overlapping after the JoltBody contact");
        Assert_True(utils_probe::Get_IsOverlappingWith(_DisabledProbe, _DetectorEntity) == false,
            "A disabled sibling Probe must not report the detector as an overlap");

        utils_probe::Request_EnableDisable(_DisabledProbe,
            FCk_Request_Probe_EnableDisable(ECk_EnableDisable::Enable));
        WaitUntil(n"Check_SiblingProbeEnabled", n"OnSiblingProbeEnabled");
    }

    UFUNCTION()
    private void Check_SiblingProbeEnabled(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(utils_probe::Get_IsEnabledDisabled(_DisabledProbe) == ECk_EnableDisable::Enable);
    }

    UFUNCTION()
    private void OnSiblingProbeEnabled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        // Enabling re-adds the Probe body; let its first Jolt contact enter the Probe request path.
        WaitFrames(3, n"OnSiblingProbeContactDrainSettled");
    }

    UFUNCTION()
    private void OnSiblingProbeContactDrainSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        WaitUntil(n"Check_SiblingProbeGenuinelyOverlapping", n"OnSiblingProbeGenuinelyOverlapping");
    }

    UFUNCTION()
    private void Check_SiblingProbeGenuinelyOverlapping(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(utils_probe::Get_IsOverlappingWith(_DisabledProbe, _DetectorEntity));
    }

    UFUNCTION()
    private void OnSiblingProbeGenuinelyOverlapping(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_True(utils_probe::Get_IsOverlapping(_DisabledProbe),
            "The enabled sibling Probe must have a genuine detector overlap before the JoltBody separates");

        _SiblingProbeEndCount = 0;
        _JoltContactRemovedCount = 0;
        _JoltContactRemovalNamedDetector = false;

        auto Teleport = FCk_Request_JoltBody_Teleport(_StartLocation, FRotator::ZeroRotator);
        Teleport.Set_VelocityPolicy(ECk_Jolt_TeleportVelocityPolicy::ResetVelocity);
        utils_jolt_body::Request_Teleport(_RigidBody, Teleport);

        WaitUntil(n"Check_RigidBodyContactRemoved", n"OnRigidBodyContactRemovedObserved");
    }

    UFUNCTION()
    private void Check_RigidBodyContactRemoved(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(_JoltContactRemovedCount > 0);
    }

    UFUNCTION()
    private void OnRigidBodyContactRemovedObserved(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_True(_JoltContactRemovalNamedDetector,
            "The JoltBody ContactRemoved must identify the enabled detector Probe entity");

        // The removal event and its deferred Probe requests can cross scheduler frames separately.
        WaitFrames(3, n"OnRemovedContactDrainSettled");
    }

    UFUNCTION()
    private void OnRemovedContactDrainSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_SiblingProbeEndCount, 0,
            "The JoltBody ContactRemoved must not fire EndOverlap on the genuinely overlapping sibling Probe");
        Assert_True(utils_probe::Get_IsOverlapping(_DisabledProbe),
            "The genuine sibling Probe overlap must survive the JoltBody ContactRemoved");
        Assert_True(utils_probe::Get_IsOverlappingWith(_DisabledProbe, _DetectorEntity),
            "The genuine sibling Probe must still report the detector after the JoltBody separates");

        FinishSuccess();
    }

    UFUNCTION()
    private void OnRigidBodyContactAdded(FCk_Handle_JoltBody InHandle, FCk_JoltBody_Payload_OnContact InPayload)
    {
        if (IsFinished()) { return; }

        _JoltContactAddedCount++;
        if (InPayload.Get_OtherEntity() == _DetectorEntity)
        {
            _JoltContactNamedDetector = true;
        }
    }

    UFUNCTION()
    private void OnRigidBodyContactRemoved(FCk_Handle_JoltBody InHandle, FCk_JoltBody_Payload_OnContactRemoved InPayload)
    {
        if (IsFinished()) { return; }

        _JoltContactRemovedCount++;
        if (InPayload.Get_OtherEntity() == _DetectorEntity)
        {
            _JoltContactRemovalNamedDetector = true;
        }
    }

    UFUNCTION()
    private void OnDisabledProbeBeginOverlap(FCk_Handle_Probe InProbe, FCk_Probe_Payload_OnBeginOverlap InPayload)
    {
        if (IsFinished()) { return; }

        _DisabledProbeBeginCount++;
    }

    UFUNCTION()
    private void OnSiblingProbeEndOverlap(FCk_Handle_Probe InProbe, FCk_Probe_Payload_OnEndOverlap InPayload)
    {
        if (IsFinished()) { return; }

        _SiblingProbeEndCount++;
    }
}
