// Language=angelscript

//============================================================================
// CK JOLT — AUTOMATION TEST: CONSTRAINT REAPS ITSELF WHEN THE OTHER BODY DIES
//============================================================================
//
// A JPH constraint referencing a freed body is undefined behavior, so the
// liveness reaper must remove the constraint the same frame either referenced
// body begins destruction — and then destroy the now-inert constraint entity.
// Here two Dynamic balls are linked by a Distance constraint hosted on ball A;
// destroying ball B's ENTITY must (a) not crash the step, and (b) leave the
// constraint handle invalid within a few frames. Ball A must survive.
//
// Placed at an isolated Y so it never touches other autotests' physics bodies.
//============================================================================

class UCk_AutoTest_CkJolt_Constraint_ReapsWhenOtherBodyDies : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 15.0f;

    private FCk_Handle _SelfHandle;
    private FCk_Handle _BallAEntity;
    private FCk_Handle _BallBEntity;
    private FCk_Handle_JoltConstraint _Link;

    private FVector _Origin = FVector(0.0, 84000.0, 300.0);
    private int32 _FramesAfterKill = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _SelfHandle = InHandle;

        _BallAEntity = DoSpawnBall(_Origin, n"ReapTest.BallA");
        _BallBEntity = DoSpawnBall(_Origin + FVector(120.0, 0.0, 0.0), n"ReapTest.BallB");

        auto BallABody = utils_jolt_body::DoCastChecked(_BallAEntity);

        auto ConstraintParams = FCk_Fragment_JoltConstraint_ParamsData(ECk_JoltConstraint_Type::Distance);
        ConstraintParams.Set_OtherBody(_BallBEntity);
        ConstraintParams.Set_WorldAnchorA(_Origin);
        ConstraintParams.Set_WorldAnchorB(_Origin + FVector(120.0, 0.0, 0.0));
        _Link = utils_jolt_constraint::Create(BallABody, ConstraintParams);

        Assert_True(ck::IsValid(_Link), "Constraint Create should return a valid handle");

        utils_timer::Create_Tick(_SelfHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    private FCk_Handle DoSpawnBall(FVector InCenter, FName InDebugName)
    {
        auto Entity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        Entity.Request_OverrideToSelf();
        utils_handle::Set_DebugName(Entity, InDebugName);
        utils_transform::Add(Entity, FTransform(FRotator::ZeroRotator, InCenter),
            ECk_Replication::DoesNotReplicate);

        auto Shape = FCk_Jolt_ShapeDimensions(ECk_Jolt_ShapeType::Sphere);
        Shape.Set_Radius(20.0);
        auto Params = FCk_Fragment_JoltBody_ParamsData(ECk_JoltBody_ShapeSource::ExplicitShape);
        Params.Set_ShapeDimensions(Shape);
        Params.Set_MotionType(ECk_MotionType::Dynamic);
        Params.Set_GravityFactor(0.0);   // free-floating pair — the test is lifecycle, not dynamics
        utils_jolt_body::Add(Entity, Params);

        return Entity;
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        // Phase 1: wait for the constraint to actually exist Jolt-side, then kill ball B.
        if (_FramesAfterKill == 0)
        {
            if (!utils_jolt_constraint::Get_IsConstraintAdded(_Link))
            { return; }

            utils_entity_lifetime::Request_DestroyEntity(_BallBEntity);
            _FramesAfterKill = 1;
            return;
        }

        // Phase 2: within a few frames the reaper must have removed + destroyed the constraint entity.
        _FramesAfterKill++;

        if (ck::Is_NOT_Valid(_Link))
        {
            Assert_True(ck::IsValid(_BallAEntity), "Ball A must survive its partner's death");
            FinishSuccess();
            return;
        }

        if (_FramesAfterKill > 10)
        {
            FinishFailure("Constraint entity still alive 10 frames after its other body died — the liveness reap did not fire");
        }
    }
}
