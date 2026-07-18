// Language=angelscript

//============================================================================
// CK JOLT — CHAOS PARITY TWIN: KINEMATIC PLATFORM CARRIES A DYNAMIC BOX
//============================================================================
//
// Chaos-engine twin of CkAutoTest_CkJolt_KinematicPlatformCarriesDynamicBox:
// the SAME scenario and qualitative assertions, driven by stock UE/Chaos
// physics instead of the Jolt world — no JoltBody fragments. A non-simulating
// Movable mesh (kinematic in the Chaos scene) is moved from the test's tick via
// SetActorLocation; Chaos derives its velocity from the position delta and
// carries a resting simulating box through contact friction.
//
//   1. Kinematic platform (wide thin box) + a dynamic box resting on it.
//   2. Let the box settle onto the stationary platform.
//   3. Drive the platform ~200uu in +X over 2.5s (SetActorLocation per tick),
//      then hold.
//   4. Assert the box tracked the platform (within +/-30uu) and it never fell
//      below the platform top.
//
// Windows are TIME-based (accumulated tick delta), never frame-counted.
// Placed at an isolated Y (81000); all spawned actors destroyed before finish.
//============================================================================

class UCk_AutoTest_CkJolt_ChaosParity_KinematicPlatformCarry : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 25.0f;

    private FCk_Handle _SelfHandle;
    private TArray<AStaticMeshActor> _Actors;
    private AStaticMeshActor _Platform;
    private AStaticMeshActor _Box;

    private float _PlatformY = 81000.0;
    private float _PlatformTopZ = 25.0;   // platform center Z 0 + half-height 25

    private int _Phase = 0;   // 0 = settling, 1 = driving + holding
    private float _Elapsed = 0.0;
    private float _StableTime = 0.0;
    private float _LastBoxZ = 0.0;
    private float _DriveTime = 0.0;

    private float _MaxDriveX = 200.0;
    private float _DriveDuration = 2.5;   // gentle ramp so friction can hold the box
    private float _HoldDuration = 1.0;

    private UStaticMesh _CubeMesh;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _SelfHandle = InHandle;

        _CubeMesh = Cast<UStaticMesh>(LoadObject(UStaticMesh, "/Engine/BasicShapes/Cube.Cube"));
        if (!IsValid(_CubeMesh))
        {
            FinishFailure("Failed to load /Engine/BasicShapes/Cube.Cube");
            return;
        }

        // ---- Kinematic platform (half-extents 300x300x25), non-simulating: moved by the tick ---
        _Platform = DoSpawnCube(FVector(0.0, _PlatformY, 0.0), FVector(6.0, 6.0, 0.5), false);

        // ---- Dynamic box resting just above the platform top -----------------------------------
        _Box = DoSpawnCube(FVector(0.0, _PlatformY, 80.0), FVector(1.0, 1.0, 1.0), true);

        _LastBoxZ = 80.0;
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

        if (_Phase == 0)
        {
            _Elapsed += float(InDeltaT.Get_Seconds());

            // Wait for the box to settle onto the stationary platform.
            auto BoxZ = _Box.GetActorLocation().Z;
            if (Math::Abs(BoxZ - _LastBoxZ) < 0.1)
            { _StableTime += float(InDeltaT.Get_Seconds()); }
            else
            { _StableTime = 0.0; }
            _LastBoxZ = BoxZ;

            if (_StableTime >= 0.25)
            { _Phase = 1; }

            if (_Elapsed > 10.0)
            {
                DoCleanup();
                FinishFailure(f"Chaos box never settled on the platform (last Z={BoxZ})");
            }

            return;
        }

        // Phase 1 — drive the platform in +X, then hold.
        _DriveTime += float(InDeltaT.Get_Seconds());

        float TargetX = _MaxDriveX;
        if (_DriveTime < _DriveDuration)
        { TargetX = (_DriveTime / _DriveDuration) * _MaxDriveX; }

        _Platform.SetActorLocation(FVector(TargetX, _PlatformY, 0.0));

        auto BoxLoc = _Box.GetActorLocation();
        Assert_True(BoxLoc.Z > _PlatformTopZ,
            f"Box must stay on the platform, never below its top (Z={BoxLoc.Z}, top={_PlatformTopZ})");

        if (_DriveTime >= _DriveDuration + _HoldDuration)
        {
            auto PlatformX = _Platform.GetActorLocation().X;
            Assert_True(Math::Abs(BoxLoc.X - PlatformX) <= 30.0,
                f"Box X should track the carried platform (box {BoxLoc.X} vs platform {PlatformX})");
            DoCleanup();
            FinishSuccess();
        }
    }
}
