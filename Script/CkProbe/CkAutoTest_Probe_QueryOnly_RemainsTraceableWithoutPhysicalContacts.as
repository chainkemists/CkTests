// Language=angelscript

//============================================================================
// CK PROBE - AUTOMATION TEST: QUERY-ONLY REMAINS TRACEABLE WITHOUT CONTACTS
//============================================================================
//
// QueryOnly is deliberately not Silent: it removes a Probe from the physical
// contact graph while retaining its Jolt query body. This production-path test
// moves a QueryOnly target into a Notify receiver which would otherwise admit
// it, then proves both sides of that contract across an enable round-trip:
//
//   1. a real transform request moves the Kinematic target into the Static
//      Notify receiver;
//   2. the receiver has neither BeginOverlap nor overlap membership after the
//      normal deferred contact path has had a bounded drain window; and
//   3. an explicit ProbeTrace returns that same target before and after its
//      Disable/Enable request round-trip.
//============================================================================

namespace ck_probe_query_only_test
{
    asset Asset_ProbeQueryOnly_Tags of UCk_GameplayTags
    {
        GameplayTags.Add(n"CkTests.Probe.QueryOnly.Target");
        GameplayTags.Add(n"CkTests.Probe.QueryOnly.Receiver");
    }
}

class UCk_AutoTest_Probe_QueryOnly_RemainsTraceableWithoutPhysicalContacts : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 12.0f;

    private FCk_Handle _SelfHandle;
    private FCk_Handle _TargetEntity;
    private FCk_Handle_Transform _TargetTransform;
    private FCk_Handle_Probe _TargetProbe;
    private FCk_Handle_Probe _ReceiverProbe;

    // Keep this real Jolt pair isolated from the shared CkTests world.
    private const FVector _ReceiverLocation = FVector(0.0, 78000.0, 300.0);
    private const FVector _SeparatedTargetLocation = FVector(1000.0, 78000.0, 300.0);

    private int32 _ReceiverBeginOverlapCount = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _SelfHandle = InHandle;

        auto TargetTag = utils_gameplay_tag::ResolveGameplayTag(n"CkTests.Probe.QueryOnly.Target");
        auto ReceiverTag = utils_gameplay_tag::ResolveGameplayTag(n"CkTests.Probe.QueryOnly.Receiver");

        auto ReceiverEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        ReceiverEntity.Request_OverrideToSelf();
        auto ReceiverTransform = utils_transform::Add(ReceiverEntity,
            FTransform(FRotator::ZeroRotator, _ReceiverLocation), ECk_Replication::DoesNotReplicate);

        auto ReceiverParams = FCk_Fragment_Probe_ParamsData(ReceiverTag);
        ReceiverParams.Set_MotionType(ECk_MotionType::Static);
        ReceiverParams.Set_ResponsePolicy(ECk_ProbeResponse_Policy::Notify);
        auto ReceiverFilter = FGameplayTagContainer();
        ReceiverFilter.AddTag(TargetTag);
        ReceiverParams.Set_Filter(ReceiverFilter);
        _ReceiverProbe = utils_probe::Add_Box(ReceiverTransform, FVector(100.0, 100.0, 100.0),
            ReceiverParams, FCk_Probe_DebugInfo());

        _TargetEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        _TargetEntity.Request_OverrideToSelf();
        _TargetTransform = utils_transform::Add(_TargetEntity,
            FTransform(FRotator::ZeroRotator, _SeparatedTargetLocation), ECk_Replication::DoesNotReplicate);

        auto TargetParams = FCk_Fragment_Probe_ParamsData(TargetTag);
        TargetParams.Set_MotionType(ECk_MotionType::Kinematic);
        TargetParams.Set_ResponsePolicy(ECk_ProbeResponse_Policy::Notify);
        TargetParams.Set_ContactParticipation(ECk_Probe_ContactParticipation::QueryOnly);
        _TargetProbe = utils_probe::Add_Box(_TargetTransform, FVector(100.0, 100.0, 100.0),
            TargetParams, FCk_Probe_DebugInfo());

        utils_probe::BindTo_OnBeginOverlap(_ReceiverProbe,
            FCk_Delegate_Probe_OnBeginOverlap(this, n"OnReceiverBeginOverlap"));

        WaitUntil(n"Check_SetupReady", n"OnSetupReady");
    }

    UFUNCTION()
    private void Check_SetupReady(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(
            utils_probe::Get_IsEnabledDisabled(_ReceiverProbe) == ECk_EnableDisable::Enable
            && utils_probe::Get_IsEnabledDisabled(_TargetProbe) == ECk_EnableDisable::Enable);
    }

    UFUNCTION()
    private void OnSetupReady(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        // The initial separation is a control: no pre-existing pair may make the later
        // zero-contact assertion ambiguous. The bounded window drains setup requests.
        WaitFrames(3, n"OnInitialDrainSettled");
    }

    UFUNCTION()
    private void OnInitialDrainSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_NoPhysicalReceiverContact("The initially separated receiver must start without physical contact");

        utils_transform::Request_SetLocation(_TargetTransform,
            FCk_Request_Transform_SetLocation(_ReceiverLocation));
        WaitUntil(n"Check_TargetMovedAndTraceable", n"OnTargetMovedAndTraceable");
    }

    UFUNCTION()
    private void Check_TargetMovedAndTraceable(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(utils_transform::Get_EntityCurrentLocation(_TargetTransform).Equals(_ReceiverLocation, 1.0f)
            && Trace_ReturnsTarget());
    }

    UFUNCTION()
    private void OnTargetMovedAndTraceable(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        // Trace success proves the actual query body moved. Let physical contact callbacks and
        // their deferred requests drain before proving that QueryOnly admitted none of them.
        WaitFrames(3, n"OnMovedContactDrainSettled");
    }

    UFUNCTION()
    private void OnMovedContactDrainSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_True(Trace_ReturnsTarget(), "The moved QueryOnly target must be returned by ProbeTrace");
        Assert_NoPhysicalReceiverContact("QueryOnly must reject every physical contact with its Notify receiver");

        utils_probe::Request_EnableDisable(_TargetProbe,
            FCk_Request_Probe_EnableDisable(ECk_EnableDisable::Disable));
        WaitUntil(n"Check_TargetDisabled", n"OnTargetDisabled");
    }

    UFUNCTION()
    private void Check_TargetDisabled(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(utils_probe::Get_IsEnabledDisabled(_TargetProbe) == ECk_EnableDisable::Disable);
    }

    UFUNCTION()
    private void OnTargetDisabled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        utils_probe::Request_EnableDisable(_TargetProbe,
            FCk_Request_Probe_EnableDisable(ECk_EnableDisable::Enable));
        WaitUntil(n"Check_TargetReEnabled", n"OnTargetReEnabled");
    }

    UFUNCTION()
    private void Check_TargetReEnabled(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(utils_probe::Get_IsEnabledDisabled(_TargetProbe) == ECk_EnableDisable::Enable);
    }

    UFUNCTION()
    private void OnTargetReEnabled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        WaitUntil(n"Check_ReenabledTargetTraceable", n"OnReenabledTargetTraceable");
    }

    UFUNCTION()
    private void Check_ReenabledTargetTraceable(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(Trace_ReturnsTarget());
    }

    UFUNCTION()
    private void OnReenabledTargetTraceable(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        // Re-adding the Jolt body can produce contact work on a later scheduler pass too.
        WaitFrames(3, n"OnReenabledContactDrainSettled");
    }

    UFUNCTION()
    private void OnReenabledContactDrainSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_True(Trace_ReturnsTarget(), "The re-enabled QueryOnly target must remain returned by ProbeTrace");
        Assert_NoPhysicalReceiverContact("Re-enabling QueryOnly must not restore physical Probe contact participation");
        FinishSuccess();
    }

    private bool Trace_ReturnsTarget()
    {
        auto Filter = FGameplayTagContainer();
        Filter.AddTag(utils_gameplay_tag::ResolveGameplayTag(n"CkTests.Probe.QueryOnly.Target"));
        // This segment crosses the receiver location but excludes the target's original
        // X=1000 position, so a hit proves that the inactive Jolt transform was applied.
        auto Settings = FCk_Probe_RayCast_Settings(
            FVector(-250.0, 78000.0, 300.0), FVector(250.0, 78000.0, 300.0), Filter);
        Settings.Set_OverlapNotifyPolicy(ECk_ProbeResponse_Policy::Silent);
        auto Hits = utils_probe_trace::Request_MultiLineTrace(_SelfHandle, Settings);
        for (auto Hit : Hits)
        {
            if (Hit.Get_HitKind() == ECk_ProbeTrace_HitKind::Probe && Hit.Get_HitEntity() == _TargetEntity)
            {
                return true;
            }
        }
        return false;
    }

    private void Assert_NoPhysicalReceiverContact(const FString &in InMessage)
    {
        Assert_Equals_Int(_ReceiverBeginOverlapCount, 0, InMessage + ": OnBeginOverlap must not fire");
        Assert_True(utils_probe::Get_CurrentOverlaps(_ReceiverProbe).IsEmpty(),
            InMessage + ": the receiver must have no overlap membership");
        Assert_True(utils_probe::Get_IsOverlapping(_ReceiverProbe) == false,
            InMessage + ": the receiver must report non-overlapping");
        Assert_True(utils_probe::Get_IsOverlappingWith(_ReceiverProbe, _TargetEntity) == false,
            InMessage + ": the receiver must not report the QueryOnly target");
    }

    UFUNCTION()
    private void OnReceiverBeginOverlap(FCk_Handle_Probe InProbe, FCk_Probe_Payload_OnBeginOverlap InPayload)
    {
        if (IsFinished()) { return; }
        _ReceiverBeginOverlapCount++;
    }
}
