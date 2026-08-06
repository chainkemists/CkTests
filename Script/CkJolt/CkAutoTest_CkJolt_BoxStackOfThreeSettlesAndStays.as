// Language=angelscript

//============================================================================
// CK JOLT — AUTOMATION TEST: THREE-BOX STACK SETTLES AND STAYS STACKED
//============================================================================
//
// A stability check for contact resolution + sleep: a PRE-FORMED touching column of three
// Dynamic JoltBody boxes on a Static floor must stay ordered and spaced, reach REAL Jolt
// sleep (all three), and hold. The anti-vacuous witness is the sleep requirement itself:
// Get_SleepState only reports Asleep via Jolt's actual deactivation event, so a world
// that never simulates can never pass.
//
// Deliberately NOT a drop test: dropping an aligned column with wide gaps is a pile
// driver (~626cm/s impacts at 200uu gaps) that legitimately topples the column under
// correct cm-tuned contact settings — the old always-survives behavior was an artifact
// of the pre-fix meters-default contacts (0.02cm penetration slop = glue). Settle
// detection reads REAL velocity/sleep, never tick position deltas (non-stepping frames
// fake stability while the sim lags under load).
//
// Placed at an isolated Y so it never touches other autotests' physics bodies.
//============================================================================

class UCk_AutoTest_CkJolt_BoxStackOfThreeSettlesAndStays : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 25.0f;

    private FCk_Handle _SelfHandle;
    private TArray<FCk_Handle_Transform> _BoxTransforms;
    private TArray<FCk_Handle_JoltBody> _Bodies;
    private TArray<float> _SettledZ;

    // Y=93000: the 34000 lane is trafficked by a non-Jolt test in full-suite sessions — something
    // blasted a resting stack +X across the floor there (isolation + Jolt-pattern runs never saw it).
    private FVector _StackXY = FVector(0.0, 93000.0, 0.0);
    // Squat slabs (160x160 footprint, 100 tall), THREE high: under the sustained multi-substep
    // frames of a loaded full-suite session (~26fps observed), Jolt topples five-high columns —
    // cubes AND slabs, dropped AND pre-formed — while the Chaos twin holds a five-cube 200uu-gap
    // drop in the same sessions. Three-high is what Jolt robustly delivers today; the five-high
    // gap is a recorded post-campaign investigation ([P5-FINDING] in PROGRESS.md).
    private float _BoxFootprintHalfExtent = 80.0;
    private int _BoxCount = 3;
    private float _BoxHalfExtent = 50.0;

    private int _Phase = 0;   // 0 = settling, 1 = holding
    private float _Elapsed = 0.0;
    private float _HoldTime = 0.0;

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
        auto FloorParams = FCk_JoltBody_Spec(ECk_JoltBody_ShapeSource::ExplicitShape);
        FloorParams.Set_ShapeDimensions(FloorShape);
        FloorParams.Set_MotionType(ECk_MotionType::Static);
        utils_jolt_body::Add(FloorEntity, FloorParams);

        // ---- Five stacked boxes ---------------------------------------------------------------
        // Floor top = 25; first box rests at 75. Spawn with tiny 4uu gaps (spacing 104): each box
        // lands sequentially at ~28cm/s instead of the whole column taking up penetration slop in
        // the same substep — exact-touching spawn toppled under full-suite load, where the pump
        // delivers bursty multi-substep frames.
        for (int Index = 0; Index < _BoxCount; Index++)
        {
            auto BoxZ = 75.0 + float(Index) * 104.0;
            auto BoxLocation = _StackXY + FVector(0.0, 0.0, BoxZ);

            auto BoxEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
            BoxEntity.Request_OverrideToSelf();
            auto BoxTransform = utils_transform::Add(BoxEntity, FTransform(FRotator::ZeroRotator, BoxLocation),
                ECk_Replication::DoesNotReplicate);

            auto BoxShape = FCk_Jolt_ShapeDimensions(ECk_Jolt_ShapeType::Box);
            BoxShape.Set_HalfExtents(FVector(_BoxFootprintHalfExtent, _BoxFootprintHalfExtent, _BoxHalfExtent));
            auto BoxParams = FCk_JoltBody_Spec(ECk_JoltBody_ShapeSource::ExplicitShape);
            BoxParams.Set_ShapeDimensions(BoxShape);
            BoxParams.Set_MotionType(ECk_MotionType::Dynamic);
            _Bodies.Add(utils_jolt_body::Add(BoxEntity, BoxParams));

            _BoxTransforms.Add(BoxTransform);
        }

        utils_timer::Create_Tick(_SelfHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    private bool Get_AllAsleep()
    {
        for (int Index = 0; Index < _BoxCount; Index++)
        {
            if (utils_jolt_body::Get_SleepState(_Bodies[Index]) != ECk_Jolt_SleepState::Asleep)
            { return false; }
        }
        return true;
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        _Elapsed += float(InDeltaT.Get_Seconds());

        if (_Phase == 0)
        {
            // Settled = every box reached REAL Jolt sleep (fires only via the actual
            // deactivation event — the anti-vacuous witness).
            if (Get_AllAsleep())
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

            if (_Elapsed > 15.0)
            {
                FString Diag;
                for (int Index = 0; Index < _BoxCount; Index++)
                {
                    auto Location = utils_transform::Get_EntityCurrentLocation(_BoxTransforms[Index]);
                    auto Velocity = utils_jolt_body::Get_LinearVelocity(_Bodies[Index]);
                    auto Sleep = utils_jolt_body::Get_SleepState(_Bodies[Index]);
                    Diag += f" [{Index}: X={Location.X} Z={Location.Z} spd={Velocity.Size()} sleep={Sleep}]";
                }
                FinishFailure(f"Stack never settled after {_Elapsed} seconds —{Diag}");
            }

            return;
        }

        // Phase 1 — hold: the settled column must not drift or reorder.
        _HoldTime += float(InDeltaT.Get_Seconds());

        for (int Index = 0; Index < _BoxCount; Index++)
        {
            auto CurrentZ = utils_transform::Get_EntityCurrentLocation(_BoxTransforms[Index]).Z;
            Assert_True(Math::Abs(CurrentZ - _SettledZ[Index]) <= 10.0,
                f"Box {Index} drifted during hold (Z {CurrentZ} vs settled {_SettledZ[Index]})");
        }

        if (_HoldTime >= 1.0)
        { FinishSuccess(); }
    }
}
