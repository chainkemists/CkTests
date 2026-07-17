// Language=angelscript

//============================================================================
// CK JOLT — AUTOMATION TEST: FIVE-BOX STACK SETTLES AND STAYS STACKED
//============================================================================
//
// A stability check for contact resolution + sleep: five Dynamic JoltBody
// boxes dropped in a column onto a Static JoltBody floor must settle into a
// clean touching stack (center-to-center ~100uu for 50uu half-extents),
// preserve their bottom-to-top order, and stay put over a long hold window.
//
//   1. Static floor + five 50uu boxes stacked with 105uu spacing (small gaps).
//   2. Poll until every box's Z is stable across consecutive frames.
//   3. Assert order preserved and consecutive Z deltas ~= 100uu (+/-10).
//   4. Hold for a further 60 polls; the stack must not drift or collapse.
//
// Placed at an isolated Y so it never touches other autotests' physics bodies.
//============================================================================

class UCk_AutoTest_CkJolt_BoxStackOfFiveSettlesAndStays : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 25.0f;

    private FCk_Handle _SelfHandle;
    private TArray<FCk_Handle_Transform> _BoxTransforms;
    private TArray<float> _LastZ;
    private TArray<float> _SettledZ;

    private FVector _StackXY = FVector(0.0, 34000.0, 0.0);
    private int _BoxCount = 5;
    private float _BoxHalfExtent = 50.0;

    private int _Phase = 0;   // 0 = settling, 1 = holding
    private int _FramesWaited = 0;
    private int _StableFrames = 0;
    private int _HoldPolls = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _SelfHandle = InHandle;

        // ---- Static floor ---------------------------------------------------------------------
        auto FloorEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        FloorEntity.Request_OverrideToSelf();
        utils_transform::Add(FloorEntity, FTransform(FRotator::ZeroRotator, _StackXY),
            ECk_Replication::DoesNotReplicate);

        auto FloorShape = FCk_Jolt_ShapeDimensions(ECk_Jolt_ShapeType::Box);
        FloorShape.Set_HalfExtents(FVector(500.0, 500.0, 25.0));
        auto FloorParams = FCk_Fragment_JoltBody_ParamsData(ECk_JoltBody_ShapeSource::ExplicitShape);
        FloorParams.Set_ShapeDimensions(FloorShape);
        FloorParams.Set_MotionType(ECk_MotionType::Static);
        utils_jolt_body::Add(FloorEntity, FloorParams);

        // ---- Five stacked boxes ---------------------------------------------------------------
        // Floor top = 25; first box rests at 75. Spawn with wide 200uu gaps so the settled 100uu
        // spacing DIFFERS from the spawn spacing — a stack that never simulates (e.g. no gravity)
        // keeps its 200uu spacing and fails the "~100uu" assertion instead of trivially passing.
        for (int Index = 0; Index < _BoxCount; Index++)
        {
            auto BoxZ = 75.0 + float(Index) * 200.0;
            auto BoxLocation = _StackXY + FVector(0.0, 0.0, BoxZ);

            auto BoxEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
            BoxEntity.Request_OverrideToSelf();
            auto BoxTransform = utils_transform::Add(BoxEntity, FTransform(FRotator::ZeroRotator, BoxLocation),
                ECk_Replication::DoesNotReplicate);

            auto BoxShape = FCk_Jolt_ShapeDimensions(ECk_Jolt_ShapeType::Box);
            BoxShape.Set_HalfExtents(FVector(_BoxHalfExtent, _BoxHalfExtent, _BoxHalfExtent));
            auto BoxParams = FCk_Fragment_JoltBody_ParamsData(ECk_JoltBody_ShapeSource::ExplicitShape);
            BoxParams.Set_ShapeDimensions(BoxShape);
            BoxParams.Set_MotionType(ECk_MotionType::Dynamic);
            utils_jolt_body::Add(BoxEntity, BoxParams);

            _BoxTransforms.Add(BoxTransform);
            _LastZ.Add(BoxZ);
        }

        utils_timer::Create_Tick(_SelfHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    private float Get_MaxDelta()
    {
        float MaxDelta = 0.0;
        for (int Index = 0; Index < _BoxCount; Index++)
        {
            auto CurrentZ = utils_transform::Get_EntityCurrentLocation(_BoxTransforms[Index]).Z;
            auto Delta = Math::Abs(CurrentZ - _LastZ[Index]);
            if (Delta > MaxDelta)
            { MaxDelta = Delta; }
            _LastZ[Index] = CurrentZ;
        }
        return MaxDelta;
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        _FramesWaited++;
        auto MaxDelta = Get_MaxDelta();

        if (_Phase == 0)
        {
            if (MaxDelta < 0.1)
            { _StableFrames++; }
            else
            { _StableFrames = 0; }

            if (_StableFrames >= 15)
            {
                // Record the settled column and assert order + spacing.
                for (int Index = 0; Index < _BoxCount; Index++)
                { _SettledZ.Add(utils_transform::Get_EntityCurrentLocation(_BoxTransforms[Index]).Z); }

                for (int Index = 0; Index < _BoxCount - 1; Index++)
                {
                    auto Lower = _SettledZ[Index];
                    auto Upper = _SettledZ[Index + 1];
                    Assert_True(Upper > Lower,
                        f"Box {Index + 1} must sit above box {Index} (Z {Upper} vs {Lower})");
                    Assert_True(Math::Abs((Upper - Lower) - 100.0) <= 10.0,
                        f"Box {Index}->{Index + 1} spacing should be ~100uu (got {Upper - Lower})");
                }

                _Phase = 1;
            }

            if (_FramesWaited > 900)
            { FinishFailure(f"Stack never settled after {_FramesWaited} frames"); }

            return;
        }

        // Phase 1 — hold: the settled column must not drift or reorder.
        _HoldPolls++;

        for (int Index = 0; Index < _BoxCount; Index++)
        {
            auto CurrentZ = utils_transform::Get_EntityCurrentLocation(_BoxTransforms[Index]).Z;
            Assert_True(Math::Abs(CurrentZ - _SettledZ[Index]) <= 10.0,
                f"Box {Index} drifted during hold (Z {CurrentZ} vs settled {_SettledZ[Index]})");
        }

        if (_HoldPolls >= 60)
        { FinishSuccess(); }
    }
}
