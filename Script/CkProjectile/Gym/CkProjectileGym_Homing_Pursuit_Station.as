// Language=angelscript

//============================================================================
// CkProjectileGym — Homing Pursuit station
//
// A target orbits the station while an interceptor chases it under ProNav
// guidance. On intercept the projectile is destroyed and a fresh one is
// launched from the pad — an endless chase loop. The target is moved via
// raw transform requests (no Velocity feature), so this station also
// exercises homing's finite-difference target-velocity fallback.
//============================================================================

USTRUCT()
struct FCk_ProjectileGym_HomingPursuit_Station_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;
}

class UCk_EntityScript_ProjectileGym_HomingPursuit_Station : UCk_GenericEntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    private FCk_Handle _StationHandle;
    private FCk_Handle_Transform _TargetTransform;
    private FCk_Handle _ProjectileEntity;
    private FCk_Handle_Transform _ProjectileTransform;
    private FCk_Handle_Homing _Homing;

    private float _OrbitAngle = 0.0;
    private int32 _Intercepts = 0;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow
    DoConstruct(FCk_Handle& InHandle)
    {
        _StationHandle = InHandle;
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);

        auto Target = utils_entity_lifetime::Request_CreateEntity(InHandle);
        Target.Set_DebugName(n"Homing_Pursuit.Target");
        _TargetTransform = utils_transform::Add(
            Target, FTransform(FRotator::ZeroRotator, Get_OrbitLocation()), ECk_Replication::DoesNotReplicate);

        Spawn_Interceptor();

        utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"OnTick"));

        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    private FVector Get_OrbitLocation()
    {
        auto Center = InitialTransform.Location + FVector(0.0, 0.0, 300.0);
        return Center + FVector(Math::Cos(_OrbitAngle) * 400.0, Math::Sin(_OrbitAngle) * 400.0, 0.0);
    }

    private void Spawn_Interceptor()
    {
        auto Projectile = utils_entity_lifetime::Request_CreateEntity(_StationHandle);
        Projectile.Set_DebugName(n"Homing_Pursuit.Interceptor");
        _ProjectileEntity = Projectile;

        auto PadLocation = InitialTransform.Location + FVector(0.0, 0.0, 120.0);
        _ProjectileTransform = utils_transform::Add(
            Projectile, FTransform(FRotator::ZeroRotator, PadLocation), ECk_Replication::DoesNotReplicate);

        auto ProjectileParams = FCk_Projectile_Spec(
            FCk_Velocity_Spec(ECk_LocalWorld::World, FVector(0.0, 0.0, 500.0)),
            FCk_Acceleration_Spec(ECk_LocalWorld::World, FVector::ZeroVector),
            FCk_AutoReorient_Spec(ECk_AutoReorient_Policy::NoAutoReorient));
        utils_projectile::Add(Projectile, ProjectileParams, ECk_Replication::DoesNotReplicate);

        _Homing = utils_homing::Add(Projectile,
            FCk_Homing_Spec(FCk_Homing_GuidanceSettings(4000.0)));

        utils_homing::Request_SetTargetEntity(_Homing,
            FCk_Request_Homing_SetTargetEntity(FCk_Handle(_TargetTransform)));
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        _OrbitAngle += 1.2 * float(InDeltaT.Get_Seconds());
        utils_transform::Request_SetLocation(_TargetTransform,
            FCk_Request_Transform_SetLocation(Get_OrbitLocation()));

        auto TargetLocation = utils_transform::Get_EntityCurrentLocation(_TargetTransform);
        utils_debug_draw::DrawDebugSphere(TargetLocation, 60.0, 12, FLinearColor(1.0, 0.5, 0.0), 0.0, 2.0);

        if (ck::Is_NOT_Valid(_ProjectileEntity))
        { return; }

        auto ProjectileLocation = utils_transform::Get_EntityCurrentLocation(_ProjectileTransform);
        utils_debug_draw::DrawDebugSphere(ProjectileLocation, 25.0, 8, FLinearColor(0.0, 1.0, 1.0), 0.0, 2.0);
        utils_debug_draw::DrawDebugLine(ProjectileLocation, TargetLocation, FLinearColor(0.4, 0.4, 0.4), 0.0, 0.5);

        auto Distance = ProjectileLocation.Distance(TargetLocation);

        if (Distance < 90.0)
        {
            _Intercepts++;
            utils_entity_lifetime::Request_DestroyEntity(_ProjectileEntity);
            Spawn_Interceptor();
            return;
        }

        auto GuidanceState = utils_homing::Get_LastGuidanceState(_Homing);

        auto Body = f"Intercepts       {_Intercepts}\n"
            + f"Distance         {int32(Distance)} cm\n"
            + f"Closing speed    {int32(GuidanceState.Get_ClosingSpeed())} cm/s\n\n"
            + "Orange = target (orbiting)\n"
            + "Cyan   = ProNav interceptor";

        CkGym_Common::Update_StationDisplay(ck::ToEntity(this),
            "STATION 1 / HOMING PURSUIT", Body,
            "Endless chase — relaunches after every intercept.");
    }
}
