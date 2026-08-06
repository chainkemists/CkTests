// Language=angelscript

//============================================================================
// CkProjectileGym — Homing Proximity Miss station
//
// Every cycle a projectile with ZERO steering budget is launched straight
// past a homing point sitting off its path. The moment it stops closing and
// starts receding inside the miss-notify threshold, OnTargetMissed fires
// with the closest-approach distance — the proximity-detonation hook.
//============================================================================

USTRUCT()
struct FCk_ProjectileGym_HomingProximityMiss_Station_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;
}

class UCk_EntityScript_ProjectileGym_HomingProximityMiss_Station : UCk_GenericEntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    private FCk_Handle _StationHandle;
    private FCk_Handle _ProjectileEntity;
    private FCk_Handle_Transform _ProjectileTransform;

    private int32 _Misses = 0;
    private float _LastMissDistance = 0.0;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow
    DoConstruct(FCk_Handle& InHandle)
    {
        _StationHandle = InHandle;
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);

        Launch_StraightProjectile();

        auto CycleParams = FCk_Timer_Spec(FCk_Time(3.0));
        CycleParams.Set_StartingState(ECk_Timer_State::Running)
                   .Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        auto CycleTimer = utils_timer::Add(InHandle, CycleParams);
        CycleTimer.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnCycle"));

        utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"OnTick"));

        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    private FVector Get_HomingPoint()
    {
        return InitialTransform.Location + FVector(600.0, 250.0, 200.0);
    }

    private void Launch_StraightProjectile()
    {
        auto Projectile = utils_entity_lifetime::Request_CreateEntity(_StationHandle);
        Projectile.Set_DebugName(n"Homing_ProximityMiss.Projectile");
        _ProjectileEntity = Projectile;

        auto PadLocation = InitialTransform.Location + FVector(-500.0, 0.0, 200.0);
        _ProjectileTransform = utils_transform::Add(
            Projectile, FTransform(FRotator::ZeroRotator, PadLocation), ECk_Replication::DoesNotReplicate);

        auto ProjectileParams = FCk_Projectile_Spec(
            FCk_Velocity_Spec(ECk_LocalWorld::World, FVector(700.0, 0.0, 0.0)),
            FCk_Acceleration_Spec(ECk_LocalWorld::World, FVector::ZeroVector),
            FCk_AutoReorient_Spec(ECk_AutoReorient_Policy::NoAutoReorient));
        utils_projectile::Add(Projectile, ProjectileParams, ECk_Replication::DoesNotReplicate);

        // Zero acceleration budget: homing can only WATCH the geometry, never steer
        auto HomingParams = FCk_Homing_Spec(FCk_Homing_GuidanceSettings(0.0));
        HomingParams.Set_MissNotifyDistanceThreshold(600.0);

        auto Homing = utils_homing::Add(Projectile, HomingParams);

        utils_homing::BindTo_OnTargetMissed(Homing, FCk_Delegate_Homing_OnTargetMissed(this, n"OnTargetMissed"));

        utils_homing::Request_SetTargetLocation(Homing,
            FCk_Request_Homing_SetTargetLocation(Get_HomingPoint()));
    }

    UFUNCTION()
    private void OnTargetMissed(FCk_Handle_Homing InHandle, FCk_Homing_Payload_OnTargetMissed InPayload)
    {
        _Misses++;
        _LastMissDistance = InPayload.Get_MissDistance();
    }

    UFUNCTION()
    private void OnCycle(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (ck::IsValid(_ProjectileEntity))
        {
            utils_entity_lifetime::Request_DestroyEntity(_ProjectileEntity);
        }

        Launch_StraightProjectile();
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        auto HomingPoint = Get_HomingPoint();
        utils_debug_draw::DrawDebugSphere(HomingPoint, 40.0, 8, FLinearColor(1.0, 0.5, 0.0), 0.0, 2.0);

        if (ck::IsValid(_ProjectileEntity))
        {
            auto ProjectileLocation = utils_transform::Get_EntityCurrentLocation(_ProjectileTransform);
            utils_debug_draw::DrawDebugSphere(ProjectileLocation, 25.0, 8, FLinearColor(0.0, 1.0, 1.0), 0.0, 2.0);
        }

        auto Body = f"Misses reported  {_Misses}\n"
            + f"Last miss dist   {int32(_LastMissDistance)} cm\n\n"
            + "Orange = homing point (off the path)\n"
            + "Cyan   = zero-budget projectile\n\n"
            + "OnTargetMissed fires at the\nclosing-to-receding flip.";

        CkGym_Common::Update_StationDisplay(ck::ToEntity(this),
            "STATION 3 / PROXIMITY MISS", Body,
            "Relaunches every 3 seconds.");
    }
}
