// Language=angelscript

//============================================================================
// CK JOLT — AUTOMATION TEST: CONTACT SIGNALS FIRE ON IMPACT (ADD + REMOVE)
//============================================================================
//
// A dropped Dynamic box hitting a Static floor must raise OnJoltBodyContactAdded
// with a well-formed payload, and OnJoltBodyContactRemoved when the contact is
// broken (box teleported away after settling):
//
//   1. Static floor (a LIVE entity) + a Dynamic box dropped onto it.
//   2. On ContactAdded assert: _OtherEntity == the floor entity; _RelativeNormalSpeed
//      > 0 (positive-when-closing convention); _ContactNormal roughly +Z on the box's
//      surface (dot with +Z > 0.7 — the box's contact face points up away from the floor).
//   3. Let it settle, then Teleport the box far away -> OnJoltBodyContactRemoved fires.
//
// Placed at an isolated Y so it never touches other autotests' physics bodies.
//============================================================================

class UCk_AutoTest_CkJolt_ContactSignalsFireOnImpact : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 20.0f;

    private FCk_Handle _SelfHandle;
    private FCk_Handle _FloorEntity;
    private FCk_Handle_JoltBody _Body;
    private FCk_Handle_Transform _BoxTransform;

    private FVector _FloorCenter = FVector(0.0, 51000.0, 0.0);

    private int _Phase = 0;   // 0 = waiting for contact, 1 = settling then teleport away, 2 = waiting for removal
    private int _FramesWaited = 0;
    private int _FramesSinceContact = 0;
    private bool _ContactAdded = false;
    private bool _ContactRemoved = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _SelfHandle = InHandle;

        // ---- Static floor (kept as a live entity so contact _OtherEntity is assertable) -------
        _FloorEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        _FloorEntity.Request_OverrideToSelf();
        utils_transform::Add(_FloorEntity, FTransform(FRotator::ZeroRotator, _FloorCenter),
            ECk_Replication::DoesNotReplicate);

        auto FloorShape = FCk_Jolt_ShapeDimensions(ECk_Jolt_ShapeType::Box);
        FloorShape.Set_HalfExtents(FVector(500.0, 500.0, 25.0));
        auto FloorParams = FCk_Fragment_JoltBody_ParamsData(ECk_JoltBody_ShapeSource::ExplicitShape);
        FloorParams.Set_ShapeDimensions(FloorShape);
        FloorParams.Set_MotionType(ECk_MotionType::Static);
        utils_jolt_body::Add(_FloorEntity, FloorParams);

        // ---- Dynamic box dropped onto the floor -----------------------------------------------
        auto BoxStart = _FloorCenter + FVector(0.0, 0.0, 250.0);
        auto BoxEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        BoxEntity.Request_OverrideToSelf();
        _BoxTransform = utils_transform::Add(BoxEntity, FTransform(FRotator::ZeroRotator, BoxStart),
            ECk_Replication::DoesNotReplicate);

        auto BoxShape = FCk_Jolt_ShapeDimensions(ECk_Jolt_ShapeType::Box);
        BoxShape.Set_HalfExtents(FVector(50.0, 50.0, 50.0));
        auto BoxParams = FCk_Fragment_JoltBody_ParamsData(ECk_JoltBody_ShapeSource::ExplicitShape);
        BoxParams.Set_ShapeDimensions(BoxShape);
        BoxParams.Set_MotionType(ECk_MotionType::Dynamic);
        _Body = utils_jolt_body::Add(BoxEntity, BoxParams);

        utils_jolt_body::BindTo_OnJoltBodyContactAdded(_Body,
            FCk_Delegate_JoltBody_OnContact(this, n"OnContactAdded"));
        utils_jolt_body::BindTo_OnJoltBodyContactRemoved(_Body,
            FCk_Delegate_JoltBody_OnContactRemoved(this, n"OnContactRemoved"));

        utils_timer::Create_Tick(_SelfHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnContactAdded(FCk_Handle_JoltBody InHandle, FCk_JoltBody_Payload_OnContact InPayload)
    {
        if (IsFinished()) { return; }
        if (_ContactAdded) { return; }   // pin the FIRST contact (box vs floor)

        _ContactAdded = true;

        Assert_True(InPayload.Get_OtherEntity() == _FloorEntity,
            "ContactAdded _OtherEntity should be the floor entity");
        Assert_True(InPayload.Get_RelativeNormalSpeed() > 0.0,
            f"ContactAdded closing speed should be positive at impact (got {InPayload.Get_RelativeNormalSpeed()})");
        Assert_True(InPayload.Get_ContactNormal().Z > 0.7,
            f"ContactAdded normal on the box should point up (+Z), got {InPayload.Get_ContactNormal()}");
    }

    UFUNCTION()
    private void OnContactRemoved(FCk_Handle_JoltBody InHandle, FCk_JoltBody_Payload_OnContactRemoved InPayload)
    {
        if (IsFinished()) { return; }
        _ContactRemoved = true;
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        _FramesWaited++;

        if (_Phase == 0)
        {
            if (_ContactAdded)
            {
                _Phase = 1;
                _FramesSinceContact = 0;
                return;
            }

            if (_FramesWaited > 600)
            { FinishFailure("OnJoltBodyContactAdded never fired within the drop budget"); }

            return;
        }

        if (_Phase == 1)
        {
            // Let the box settle firmly on the floor, then teleport it far away to break contact.
            _FramesSinceContact++;
            if (_FramesSinceContact >= 40)
            {
                auto FarTarget = _FloorCenter + FVector(0.0, 0.0, 5000.0);
                auto Request = FCk_Request_JoltBody_Teleport(FarTarget, FRotator::ZeroRotator);
                Request.Set_VelocityPolicy(ECk_Jolt_TeleportVelocityPolicy::ResetVelocity);
                utils_jolt_body::Request_Teleport(_Body, Request);
                _Phase = 2;
                _FramesSinceContact = 0;
            }
            return;
        }

        // Phase 2 — the broken contact must raise OnJoltBodyContactRemoved.
        _FramesSinceContact++;
        if (_ContactRemoved)
        {
            FinishSuccess();
            return;
        }

        if (_FramesSinceContact > 300)
        { FinishFailure("OnJoltBodyContactRemoved never fired after the box was teleported away"); }
    }
}
