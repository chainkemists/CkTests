// Language=angelscript

//============================================================================
// CK JOLT - CHAOS PARITY TWIN: FIVE-BOX STACK SETTLES AND STAYS STACKED
//============================================================================
//
// Chaos-engine twin of CkAutoTest_CkJolt_BoxStackOfFiveSettlesAndStays: the
// SAME scenario and qualitative assertions, but driven by stock UE/Chaos
// physics (AStaticMeshActor + SetSimulatePhysics) instead of the Jolt world
// no JoltBody fragments at all. It exists to show Chaos agrees qualitatively
// with the Jolt result already pinned.
//
//   1. Kinematic-stationary floor + five 100uu dynamic cubes dropped in a
//      column with wide 200uu gaps (settled 100uu spacing DIFFERS from spawn
//      spacing, so a non-simulating column fails the "~100uu" assertion).
//   2. Poll until every cube's Z is stable for ~0.25s of continuous rest.
//   3. Assert bottom-to-top order preserved and consecutive spacing ~100uu.
//   4. Hold 1s; the stack must not drift or collapse.
//
// Windows are TIME-based (accumulated tick delta), never frame-counted - the
// automation PIE runs uncapped. Placed at an isolated Y (75000); all spawned
// actors are destroyed before finish (shared-map leak hygiene).
//============================================================================

class UCk_AutoTest_CkJolt_ChaosParity_BoxStackSettles : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 25.0f;

    private FCk_Handle _SelfHandle;
    private TArray<AStaticMeshActor> _Actors;      // everything spawned (for cleanup)
    private TArray<AStaticMeshActor> _BoxActors;   // the five dynamic cubes
    private TArray<float> _LastZ;
    private TArray<float> _SettledZ;

    private float _ParkY = 75000.0;
    private int _BoxCount = 5;

    private int _Phase = 0;   // 0 = settling, 1 = holding
    private float _Elapsed = 0.0;
    private float _StableTime = 0.0;
    private float _HoldTime = 0.0;
    private bool _HasMoved = false;

    private UStaticMesh _CubeMesh;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _SelfHandle = InHandle;

        // Resolve engine content at RUNTIME (engine-scope finds are null at literal-init time).
        _CubeMesh = Cast<UStaticMesh>(LoadObject(UStaticMesh, "/Engine/BasicShapes/Cube.Cube"));
        if (!IsValid(_CubeMesh))
        {
            FinishFailure("Failed to load /Engine/BasicShapes/Cube.Cube");
            return;
        }

        // ---- Kinematic-stationary floor (half-extents 500x500x25) ------------------------------
        DoSpawnCube(FVector(0.0, _ParkY, 0.0), FVector(10.0, 10.0, 0.5), false);

        // ---- Five dynamic cubes with wide 200uu gaps ------------------------------------------
        for (int Index = 0; Index < _BoxCount; Index++)
        {
            auto BoxZ = 75.0 + float(Index) * 200.0;
            auto Box = DoSpawnCube(FVector(0.0, _ParkY, BoxZ), FVector(1.0, 1.0, 1.0), true);
            _BoxActors.Add(Box);
            _LastZ.Add(BoxZ);
        }

        utils_timer::Create_Tick(_SelfHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    private AStaticMeshActor DoSpawnCube(FVector InCenter, FVector InScale, bool InSimulate)
    {
        auto Actor = Cast<AStaticMeshActor>(SpawnActor(AStaticMeshActor, InCenter));
        auto Mesh = Actor.StaticMeshComponent;
        Mesh.SetMobility(EComponentMobility::Movable);
        Mesh.SetStaticMesh(_CubeMesh);
        Actor.SetActorScale3D(InScale);
        Mesh.SetCollisionProfileName(n"BlockAll");
        if (InSimulate)
        { Mesh.SetSimulatePhysics(true); }
        _Actors.Add(Actor);
        return Actor;
    }

    private float Get_MaxDelta()
    {
        float MaxDelta = 0.0;
        for (int Index = 0; Index < _BoxCount; Index++)
        {
            auto CurrentZ = _BoxActors[Index].GetActorLocation().Z;
            auto Delta = Math::Abs(CurrentZ - _LastZ[Index]);
            if (Delta > MaxDelta)
            { MaxDelta = Delta; }
            _LastZ[Index] = CurrentZ;
        }
        return MaxDelta;
    }

    private void DoCleanup()
    {
        for (auto Actor : _Actors)
        {
            if (IsValid(Actor))
            { Actor.DestroyActor(); }
        }
        _Actors.Empty();
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        _Elapsed += float(InDeltaT.Get_Seconds());
        auto MaxDelta = Get_MaxDelta();

        if (_Phase == 0)
        {
            // "At rest" and "has not started falling yet" are the SAME reading - every delta is
            // exactly 0 until Chaos first steps these bodies. Latch real motion before the
            // stability window may count, or the window completes at the SPAWN positions and the
            // spacing assertion measures the 200uu spawn gap instead of the 100uu settled one.
            // (Observed as a phantom red under three contended test lanes: "got 200.0".)
            if (MaxDelta > 1.0)
            { _HasMoved = true; }

            if (_HasMoved && MaxDelta < 0.1)
            { _StableTime += float(InDeltaT.Get_Seconds()); }
            else
            { _StableTime = 0.0; }

            // Settled: stable for ~0.25s of continuous rest.
            if (_StableTime >= 0.25)
            {
                for (int Index = 0; Index < _BoxCount; Index++)
                { _SettledZ.Add(_BoxActors[Index].GetActorLocation().Z); }

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
                DoCleanup();
                FinishFailure(_HasMoved
                    ? f"Chaos stack never settled after {_Elapsed} seconds"
                    : f"Chaos stack never started simulating after {_Elapsed} seconds (no box ever moved)");
            }

            return;
        }

        // Phase 1 - hold: the settled column must not drift or reorder.
        _HoldTime += float(InDeltaT.Get_Seconds());

        for (int Index = 0; Index < _BoxCount; Index++)
        {
            auto CurrentZ = _BoxActors[Index].GetActorLocation().Z;
            Assert_True(Math::Abs(CurrentZ - _SettledZ[Index]) <= 10.0,
                f"Box {Index} drifted during hold (Z {CurrentZ} vs settled {_SettledZ[Index]})");
        }

        if (_HoldTime >= 1.0)
        {
            DoCleanup();
            FinishSuccess();
        }
    }
}
