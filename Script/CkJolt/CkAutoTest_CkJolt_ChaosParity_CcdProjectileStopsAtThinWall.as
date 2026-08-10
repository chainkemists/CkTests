// Language=angelscript

//============================================================================
// CK JOLT — CHAOS PARITY TWIN: CCD PROJECTILE DOES NOT TUNNEL A THIN WALL
//============================================================================
//
// Chaos-engine twin of CkAutoTest_CkJolt_FastProjectileWithCcdStopsAtThinWall:
// the SAME scenario and qualitative assertions, driven by stock UE/Chaos
// physics instead of the Jolt world — no JoltBody fragments. Continuous
// collision detection is enabled on the body instance via SetUseCCD(true).
//
// A small, very fast dynamic sphere with CCD must NOT tunnel a thin static
// wall: at 12000uu/s it would jump ~200uu per 60Hz step, far past the
// 10uu-thick wall, unless CCD catches the swept collision.
//
//   1. Thin kinematic-stationary wall (thin along the travel axis X: half-
//      extents 5 x 500 x 500).
//   2. Small dynamic sphere (radius 10), CCD enabled, gravity disabled,
//      launched at the wall via SetPhysicsLinearVelocity (+X, 12000uu/s).
//   3. Assert on the PEAK X the sphere ever reaches: it must get to the wall
//      (peak > wall - 50) and its centre must never cross the wall plane
//      (peak < wall). Chaos's default physical material has restitution 0.3,
//      so the sphere BOUNCES back hard after impact — final X is behind the
//      launch point and useless as a travel witness; the peak is the correct
//      tunnel discriminator (a tunneling sphere peaks PAST the wall).
//
// Windows are TIME-based (accumulated tick delta), never frame-counted.
// Placed at an isolated Y (84000); all spawned actors destroyed before finish.
//============================================================================

class UCk_AutoTest_CkJolt_ChaosParity_CcdProjectileStopsAtThinWall : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 12.0f;

    private FCk_Handle _SelfHandle;
    private TArray<AStaticMeshActor> _Actors;
    private AStaticMeshActor _Projectile;
    private UStaticMeshComponent _ProjectileMesh;
    private AStaticMeshActor _Wall;
    private bool _HitWall = false;

    private float _ParkY = 84000.0;
    private float _WallX = 0.0;                 // wall centre X (thin in X)
    private float _LaunchX = -400.0;            // projectile spawn X
    private float _LaunchSpeed = 12000.0;

    private int _Phase = 0;   // 0 = wait for setup then launch, 1 = watch for stop
    private float _Elapsed = 0.0;
    private float _ElapsedSinceLaunch = 0.0;
    private float _PeakX = -100000.0;

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

        // ---- Thin kinematic-stationary wall (thin along X: half-extents 5x500x500) -------------
        auto Wall = Cast<AStaticMeshActor>(SpawnActor(AStaticMeshActor, FVector(_WallX, _ParkY, 300.0)));
        auto WallMesh = Wall.StaticMeshComponent;
        WallMesh.SetMobility(EComponentMobility::Movable);
        WallMesh.SetStaticMesh(_CubeMesh);
        Wall.SetActorScale3D(FVector(0.1, 10.0, 10.0));
        WallMesh.SetCollisionProfileName(n"BlockAll");
        _Wall = Wall;
        _Actors.Add(Wall);

        // ---- Fast dynamic sphere (radius 10) with continuous collision detection ---------------
        _LaunchX = _WallX - 400.0;
        auto ProjectileStart = FVector(_LaunchX, _ParkY, 300.0);
        _Projectile = Cast<AStaticMeshActor>(SpawnActor(AStaticMeshActor, ProjectileStart));
        _ProjectileMesh = _Projectile.StaticMeshComponent;
        _ProjectileMesh.SetMobility(EComponentMobility::Movable);
        _ProjectileMesh.SetStaticMesh(_SphereMesh);
        _Projectile.SetActorScale3D(FVector(0.2, 0.2, 0.2));   // basic sphere radius 50 -> 10
        _ProjectileMesh.SetCollisionProfileName(n"BlockAll");
        _ProjectileMesh.SetSimulatePhysics(true);
        // No gravity so the horizontal CCD result is not muddied by any vertical drop.
        _ProjectileMesh.SetEnableGravity(false);
        _ProjectileMesh.SetUseCCD(true);
        // The impact is witnessed by EVENT, not by tick sampling — see OnTick for why.
        _ProjectileMesh.SetNotifyRigidBodyCollision(true);
        _ProjectileMesh.OnComponentHit.AddUFunction(this, n"OnProjectileHit");
        _Actors.Add(_Projectile);

        utils_timer::Create_Tick(_SelfHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnProjectileHit(UPrimitiveComponent HitComp, AActor OtherActor, UPrimitiveComponent OtherComp,
                                 FVector NormalImpulse, const FHitResult&in Hit)
    {
        if (OtherActor == _Wall)
        { _HitWall = true; }
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
            // Let the body finish its physics-state setup, then launch.
            _Elapsed += float(InDeltaT.Get_Seconds());
            if (_Elapsed >= 0.167)
            {
                _ProjectileMesh.SetPhysicsLinearVelocity(FVector(_LaunchSpeed, 0.0, 0.0));
                _Phase = 1;
                _ElapsedSinceLaunch = 0.0;
            }
            return;
        }

        // Phase 1 — track the farthest X the sphere ever reaches (it bounces back after impact),
        // then assert on the peak: reached the wall, never crossed it.
        _ElapsedSinceLaunch += float(InDeltaT.Get_Seconds());
        _PeakX = Math::Max(_PeakX, float(_Projectile.GetActorLocation().X));

        if (_ElapsedSinceLaunch >= 0.667)
        {
            // REACHED THE WALL — witnessed two frame-rate-independent ways, never by the sampled
            // peak. At 12000uu/s a contended ~30ms frame steps over the ENTIRE 400uu approach, so
            // no sample lands between (wall-50) and the wall and the peak reads short; that was a
            // phantom red under three test lanes (peak -53.2 vs a -50 threshold, true peak -15).
            //   1. the impact event fired, or
            //   2. the sphere is now well BEHIND its launch point, which only a restitution bounce
            //      off the wall can do (nothing else is in this Y band and gravity is off).
            // Widening the old threshold was rejected: it weakens the "the experiment actually
            // ran" guard without fixing the sampling.
            const auto FinalX = float(_Projectile.GetActorLocation().X);
            const auto BouncedBack = FinalX < _LaunchX - 100.0;

            Assert_True(_HitWall || BouncedBack,
                f"Projectile should have launched and struck the wall (hit event={_HitWall}, final X={FinalX}, launch X={_LaunchX}, peak X={_PeakX}, wall X={_WallX})");

            // The peak stays the TUNNEL discriminator and is safe against coarse sampling in that
            // role: under-sampling can only make the peak SMALLER, never larger, so it cannot
            // manufacture a false tunnel report — and a sphere that did tunnel keeps going (no
            // gravity, nothing to stop it), so every later sample is far past the wall.
            Assert_True(_PeakX < _WallX,
                f"CCD projectile must NOT tunnel the wall — its centre must stay on the near side (peak X={_PeakX}, final X={FinalX}, wall X={_WallX})");
            DoCleanup();
            FinishSuccess();
        }
    }
}
