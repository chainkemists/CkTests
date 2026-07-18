// Language=angelscript

//============================================================================
// CK JOLT — AUTOMATION TEST: CCD PROJECTILE DOES NOT TUNNEL A THIN WALL
//============================================================================
//
// A small, very fast Dynamic sphere with MotionQuality LinearCast (Jolt's native
// continuous collision detection) must NOT tunnel a thin Static wall: at 12000uu/s
// it would jump ~200uu per 60Hz step, far past the 10uu-thick wall, unless CCD
// catches the swept collision.
//
//   1. Thin Static wall (thin along the travel axis X: half-extents 5 x 500 x 500).
//   2. Small Dynamic sphere (radius 10), _MotionQuality = LinearCast, launched at
//      the wall via Request_SetLinearVelocity (+X, 12000uu/s).
//   3. Assert the sphere stops on the NEAR side of the wall (final X < wall centre),
//      having actually travelled most of the way there (not a no-op launch).
//
// (The Discrete negative control is deliberately omitted: whether Discrete tunnels
// is timestep-dependent and non-deterministic — the dispatch says do not assert it.)
//
// Placed at an isolated Y so it never touches other autotests' physics bodies.
//============================================================================

class UCk_AutoTest_CkJolt_FastProjectileWithCcdStopsAtThinWall : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 12.0f;

    private FCk_Handle _SelfHandle;
    private FCk_Handle_JoltBody _Projectile;
    private FCk_Handle_Transform _ProjectileTransform;

    private float _ParkY = 54000.0;
    private float _WallX = 0.0;                 // wall centre X (thin in X)
    private float _LaunchSpeed = 12000.0;

    private int _Phase = 0;   // 0 = wait for setup then launch, 1 = watch for stop
    private float _Elapsed = 0.0;
    private float _ElapsedSinceLaunch = 0.0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _SelfHandle = InHandle;

        // ---- Thin static wall (thin along X, the projectile's travel axis) --------------------
        auto WallEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        WallEntity.Request_OverrideToSelf();
        utils_transform::Add(WallEntity, FTransform(FRotator::ZeroRotator, FVector(_WallX, _ParkY, 300.0)),
            ECk_Replication::DoesNotReplicate);

        auto WallShape = FCk_Jolt_ShapeDimensions(ECk_Jolt_ShapeType::Box);
        WallShape.Set_HalfExtents(FVector(5.0, 500.0, 500.0));
        auto WallParams = FCk_Fragment_JoltBody_ParamsData(ECk_JoltBody_ShapeSource::ExplicitShape);
        WallParams.Set_ShapeDimensions(WallShape);
        WallParams.Set_MotionType(ECk_MotionType::Static);
        utils_jolt_body::Add(WallEntity, WallParams);

        // ---- Fast dynamic sphere with continuous collision detection --------------------------
        auto ProjectileStart = FVector(_WallX - 400.0, _ParkY, 300.0);
        auto ProjectileEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        ProjectileEntity.Request_OverrideToSelf();
        _ProjectileTransform = utils_transform::Add(ProjectileEntity,
            FTransform(FRotator::ZeroRotator, ProjectileStart), ECk_Replication::DoesNotReplicate);

        auto SphereShape = FCk_Jolt_ShapeDimensions(ECk_Jolt_ShapeType::Sphere);
        SphereShape.Set_Radius(10.0);
        auto SphereParams = FCk_Fragment_JoltBody_ParamsData(ECk_JoltBody_ShapeSource::ExplicitShape);
        SphereParams.Set_ShapeDimensions(SphereShape);
        SphereParams.Set_MotionType(ECk_MotionType::Dynamic);
        SphereParams.Set_MotionQuality(ECk_MotionQuality::LinearCast);
        // No gravity influence so the horizontal CCD result is not muddied by any vertical drop;
        // zero restitution so it stops dead at the wall instead of bouncing back.
        SphereParams.Set_GravityFactor(0.0);
        SphereParams.Set_SurfaceSource(ECk_JoltBody_SurfaceSource::Explicit);
        SphereParams.Set_Friction(0.0);
        SphereParams.Set_Restitution(0.0);
        _Projectile = utils_jolt_body::Add(ProjectileEntity, SphereParams);

        utils_timer::Create_Tick(_SelfHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        if (_Phase == 0)
        {
            // Let the body finish setup (velocity requests are dropped until the body is added), then launch.
            _Elapsed += float(InDeltaT.Get_Seconds());
            if (_Elapsed >= 0.167)
            {
                utils_jolt_body::Request_SetLinearVelocity(_Projectile,
                    FCk_Request_JoltBody_SetLinearVelocity(FVector(_LaunchSpeed, 0.0, 0.0)));
                _Phase = 1;
                _ElapsedSinceLaunch = 0.0;
            }
            return;
        }

        // Phase 1 — give it time to reach and stop at the wall, then assert it did not tunnel.
        _ElapsedSinceLaunch += float(InDeltaT.Get_Seconds());
        if (_ElapsedSinceLaunch >= 0.667)
        {
            auto FinalX = utils_transform::Get_EntityCurrentLocation(_ProjectileTransform).X;

            Assert_True(FinalX > _WallX - 390.0,
                f"Projectile should have launched and travelled toward the wall (final X={FinalX})");
            Assert_True(FinalX < _WallX,
                f"CCD projectile must NOT tunnel the wall — it should stop on the near side (final X={FinalX}, wall X={_WallX})");
            FinishSuccess();
        }
    }
}
