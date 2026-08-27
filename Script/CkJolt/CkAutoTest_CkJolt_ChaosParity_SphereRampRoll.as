// Language=angelscript

//============================================================================
// CK JOLT - CHAOS PARITY TWIN: SPHERE ROLLS DOWN A RAMP AND SETTLES AT BOTTOM
//============================================================================
//
// Chaos-engine twin of CkAutoTest_CkJolt_SphereRollsDownRampToBottom: the SAME
// scenario and qualitative assertions, driven by stock UE/Chaos physics
// (AStaticMeshActor + SetSimulatePhysics) instead of the Jolt world - no
// JoltBody fragments. Shows Chaos agrees qualitatively with the pinned Jolt
// result.
//
//   1. Kinematic-stationary floor + a ramp box pitched 20 deg (high end +X,
//      low end -X) + a back wall near the low end.
//   2. Dynamic sphere placed above the ramp's high (+X) end.
//   3. Assert the sphere progresses well down-slope and settles PAST the
//      ramp's lower edge (against the back wall), far below where it started.
//
// Windows are TIME-based (accumulated tick delta), never frame-counted.
// Placed at an isolated Y (78000); all spawned actors destroyed before finish.
//============================================================================

class UCk_AutoTest_CkJolt_ChaosParity_SphereRampRoll : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 25.0f;

    private FCk_Handle _SelfHandle;
    private TArray<AStaticMeshActor> _Actors;
    private AStaticMeshActor _Sphere;

    private float _ParkY = 78000.0;
    private float _SphereStartX = 250.0;
    // Ramp half-extent X = 300 pitched 20 deg -> horizontal reach 300*cos(20) ~= 282; lower edge at -282.
    private float _RampLowerEdgeX = -280.0;

    private float _Elapsed = 0.0;
    private float _StableTime = 0.0;
    private FVector _LastPos = FVector::ZeroVector;

    private UStaticMesh _CubeMesh;
    private UStaticMesh _SphereMesh;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _SelfHandle = InHandle;

        _CubeMesh = Cast<UStaticMesh>(LoadObject(UStaticMesh, "/Engine/BasicShapes/Cube.Cube"));
        _SphereMesh = Cast<UStaticMesh>(LoadObject(UStaticMesh, "/Engine/BasicShapes/Sphere.Sphere"));
        if (!IsValid(_CubeMesh) || !IsValid(_SphereMesh))
        {
            FinishFailure("Failed to load /Engine/BasicShapes Cube/Sphere");
            return;
        }

        // ---- Kinematic-stationary floor (half-extents 700x200x25) ------------------------------
        DoSpawnCube(FVector(0.0, _ParkY, 0.0), FRotator::ZeroRotator, FVector(14.0, 4.0, 0.5));

        // ---- Ramp pitched 20 deg about Y (high end +X, low end -X): half-extents 300x150x15 ----
        DoSpawnCube(FVector(0.0, _ParkY, 150.0), FRotator(20.0, 0.0, 0.0), FVector(6.0, 3.0, 0.3));

        // ---- Back wall near the low end (half-extents 10x200x100) ------------------------------
        DoSpawnCube(FVector(-640.0, _ParkY, 100.0), FRotator::ZeroRotator, FVector(0.2, 4.0, 2.0));

        // ---- Dynamic sphere (radius 30) on the ramp's high (+X) end ----------------------------
        auto SphereStart = FVector(_SphereStartX, _ParkY, 330.0);
        _Sphere = Cast<AStaticMeshActor>(SpawnActor(AStaticMeshActor, SphereStart));
        auto Mesh = _Sphere.StaticMeshComponent;
        Mesh.SetMobility(EComponentMobility::Movable);
        Mesh.SetStaticMesh(_SphereMesh);
        _Sphere.SetActorScale3D(FVector(0.6, 0.6, 0.6));   // basic sphere radius 50 -> 30
        Mesh.SetCollisionProfileName(n"BlockAll");
        Mesh.SetSimulatePhysics(true);
        _Actors.Add(_Sphere);

        _LastPos = SphereStart;
        utils_timer::Create_Tick(_SelfHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    private void DoSpawnCube(FVector InCenter, FRotator InRotation, FVector InScale)
    {
        auto Actor = Cast<AStaticMeshActor>(SpawnActor(AStaticMeshActor, InCenter, InRotation));
        auto Mesh = Actor.StaticMeshComponent;
        Mesh.SetMobility(EComponentMobility::Movable);
        Mesh.SetStaticMesh(_CubeMesh);
        Actor.SetActorScale3D(InScale);
        Mesh.SetCollisionProfileName(n"BlockAll");
        _Actors.Add(Actor);
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
        auto CurrentPos = _Sphere.GetActorLocation();

        if (CurrentPos.Distance(_LastPos) < 0.5)
        { _StableTime += float(InDeltaT.Get_Seconds()); }
        else
        { _StableTime = 0.0; }
        _LastPos = CurrentPos;

        // Settled: stable for ~0.25s of continuous rest, resting against the back wall.
        if (_StableTime >= 0.25)
        {
            Assert_True(CurrentPos.X < _SphereStartX - 300.0,
                f"Sphere should progress well down-slope from its start (start X={_SphereStartX}, final X={CurrentPos.X})");
            Assert_True(CurrentPos.X < _RampLowerEdgeX,
                f"Sphere should settle PAST the ramp's lower edge (lowerEdge X={_RampLowerEdgeX}, final X={CurrentPos.X})");
            DoCleanup();
            FinishSuccess();
            return;
        }

        if (_Elapsed > 20.0)
        {
            DoCleanup();
            FinishFailure(f"Chaos sphere never settled after {_Elapsed} seconds (X={CurrentPos.X}, Z={CurrentPos.Z})");
        }
    }
}
