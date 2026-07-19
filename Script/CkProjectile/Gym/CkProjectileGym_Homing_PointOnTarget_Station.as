// Language=angelscript

//============================================================================
// CkProjectileGym — Homing Point-on-Target station
//
// The target is a big slowly-spinning body with a "weak spot" 250 units off
// its center. The interceptor is told to home on that point via
// WorldSpacePointOnTarget — the offset is captured in the target's local
// space at request time, so as the target spins, the chased point orbits it
// and the interceptor follows the orbit, not the center.
//============================================================================

USTRUCT()
struct FCk_ProjectileGym_HomingPointOnTarget_Station_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;
}

class UCk_EntityScript_ProjectileGym_HomingPointOnTarget_Station : UCk_GenericEntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    private FCk_Handle _StationHandle;
    private FCk_Handle _TargetEntity;
    private FCk_Handle_Transform _TargetTransform;
    private FCk_Handle _ProjectileEntity;
    private FCk_Handle_Transform _ProjectileTransform;
    private FCk_Handle_Homing _Homing;

    private FVector _WeakSpotLocal = FVector(250.0, 0.0, 0.0);
    private int32 _WeakSpotHits = 0;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow
    DoConstruct(FCk_Handle& InHandle)
    {
        _StationHandle = InHandle;
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);

        _TargetEntity = utils_entity_lifetime::Request_CreateEntity(InHandle);
        _TargetEntity.Set_DebugName(n"Homing_PointOnTarget.Target");
        _TargetTransform = utils_transform::Add(
            _TargetEntity,
            FTransform(FRotator::ZeroRotator, InitialTransform.Location + FVector(0.0, 0.0, 350.0)),
            ECk_Replication::DoesNotReplicate);

        Spawn_Interceptor();

        utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"OnTick"));

        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    private FVector Get_WeakSpotWorld()
    {
        return utils_transform::Get_EntityCurrentTransform(_TargetTransform).TransformPosition(_WeakSpotLocal);
    }

    private void Spawn_Interceptor()
    {
        auto Projectile = utils_entity_lifetime::Request_CreateEntity(_StationHandle);
        Projectile.Set_DebugName(n"Homing_PointOnTarget.Interceptor");
        _ProjectileEntity = Projectile;

        auto PadLocation = InitialTransform.Location + FVector(0.0, -400.0, 120.0);
        _ProjectileTransform = utils_transform::Add(
            Projectile, FTransform(FRotator::ZeroRotator, PadLocation), ECk_Replication::DoesNotReplicate);

        auto ProjectileParams = FCk_Fragment_Projectile_ParamsData(
            FCk_Fragment_Velocity_ParamsData(ECk_LocalWorld::World, FVector(0.0, 0.0, 400.0)),
            FCk_Fragment_Acceleration_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector),
            FCk_Fragment_AutoReorient_ParamsData(ECk_AutoReorient_Policy::NoAutoReorient));
        utils_projectile::Add(Projectile, ProjectileParams, ECk_Replication::DoesNotReplicate);

        _Homing = utils_homing::Add(Projectile,
            FCk_Fragment_Homing_ParamsData(FCk_Homing_GuidanceSettings(3500.0)));

        auto Request = FCk_Request_Homing_SetTargetEntity(_TargetEntity);
        Request.Set_TargetPoint(ECk_Homing_TargetPoint::WorldSpacePointOnTarget);
        Request.Set_WorldSpacePoint(Get_WeakSpotWorld());

        utils_homing::Request_SetTargetEntity(_Homing, Request);
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        // Spin the target — the captured local-space weak spot orbits with it
        utils_transform::Request_AddRotationOffset(FCk_Handle(_TargetTransform),
            FRotator(0.0, 60.0 * float(InDeltaT.Get_Seconds()), 0.0), ECk_LocalWorld::World);

        auto TargetCenter = utils_transform::Get_EntityCurrentLocation(_TargetTransform);
        auto WeakSpot = Get_WeakSpotWorld();

        utils_debug_draw::DrawDebugSphere(TargetCenter, 120.0, 12, FLinearColor(0.8, 0.8, 0.8), 0.0, 1.5);
        utils_debug_draw::DrawDebugSphere(WeakSpot, 40.0, 8, FLinearColor(1.0, 0.1, 0.1), 0.0, 2.0);

        if (ck::Is_NOT_Valid(_ProjectileEntity))
        { return; }

        auto ProjectileLocation = utils_transform::Get_EntityCurrentLocation(_ProjectileTransform);
        utils_debug_draw::DrawDebugSphere(ProjectileLocation, 25.0, 8, FLinearColor(0.0, 1.0, 1.0), 0.0, 2.0);
        utils_debug_draw::DrawDebugLine(ProjectileLocation, WeakSpot, FLinearColor(0.4, 0.4, 0.4), 0.0, 0.5);

        if (ProjectileLocation.Distance(WeakSpot) < 70.0)
        {
            _WeakSpotHits++;
            utils_entity_lifetime::Request_DestroyEntity(_ProjectileEntity);
            Spawn_Interceptor();
            return;
        }

        auto Body = f"Weak spot hits   {_WeakSpotHits}\n"
            + f"Distance         {int32(ProjectileLocation.Distance(WeakSpot))} cm\n\n"
            + "White = target body (spinning)\n"
            + "Red   = weak spot (local offset)\n"
            + "Cyan  = interceptor";

        CkGym_Common::Update_StationDisplay(ck::ToEntity(this),
            "STATION 2 / POINT ON TARGET", Body,
            "The chased point rotates WITH the target.");
    }
}
