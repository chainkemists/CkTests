// Language=angelscript

//============================================================================
// CK HOMING — AUTOMATION TEST: WORLD-SPACE POINT ON TARGET TRACKS THE OFFSET
//============================================================================
//
// The projectile is told to home on a specific world-space point captured
// relative to the target (a "weak spot" 400 units above its center) rather
// than the target's transform location. Steering must converge on the offset
// point: the moment the projectile is within 120 units of the weak spot, it
// is necessarily still far (>250 units) from the target's center — proving
// the local offset is what was chased.
//============================================================================

class UCk_AutoTest_Homing_WorldSpacePointOnTarget_TracksOffset : UCk_AutoTest_Base
{
    private FCk_Handle _SelfHandle;
    private FCk_Handle_Transform _ProjectileTransform;
    private FCk_Handle_Transform _TargetTransform;
    private FCk_Handle_Homing _Homing;

    private FVector _TargetLocation = FVector(1500.0, 800.0, 0.0);
    private FVector _WeakSpotOffset = FVector(0.0, 0.0, 400.0);

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _SelfHandle = InHandle;

        auto Projectile = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        _ProjectileTransform = utils_transform::Add(Projectile, FTransform(), ECk_Replication::DoesNotReplicate);

        auto ProjectileParams = FCk_Fragment_Projectile_ParamsData(
            FCk_Fragment_Velocity_ParamsData(ECk_LocalWorld::World, FVector(600.0, 0.0, 0.0)),
            FCk_Fragment_Acceleration_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector),
            FCk_Fragment_AutoReorient_ParamsData(ECk_AutoReorient_Policy::NoAutoReorient));
        utils_projectile::Add(Projectile, ProjectileParams, ECk_Replication::DoesNotReplicate);

        _Homing = utils_homing::Add(Projectile,
            FCk_Fragment_Homing_ParamsData(FCk_Homing_GuidanceSettings(3000.0)));

        auto Target = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        _TargetTransform = utils_transform::Add(Target,
            FTransform(FRotator::ZeroRotator, _TargetLocation, FVector::OneVector), ECk_Replication::DoesNotReplicate);

        auto Request = FCk_Request_Homing_SetTargetEntity(Target);
        Request.Set_TargetPoint(ECk_Homing_TargetPoint::WorldSpacePointOnTarget);
        Request.Set_WorldSpacePoint(_TargetLocation + _WeakSpotOffset);

        utils_homing::Request_SetTargetEntity(_Homing, Request);

        utils_timer::Create_Tick(_SelfHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto ProjectileLocation = utils_transform::Get_EntityCurrentLocation(_ProjectileTransform);
        auto WeakSpot = utils_transform::Get_EntityCurrentLocation(_TargetTransform) + _WeakSpotOffset;
        auto TargetCenter = utils_transform::Get_EntityCurrentLocation(_TargetTransform);

        if (ProjectileLocation.Distance(WeakSpot) < 120.0)
        {
            Assert_True(ProjectileLocation.Distance(TargetCenter) > 250.0,
                "Converging on the weak spot means the projectile is still far from the target's center");
            Assert_True(utils_homing::Get_TargetMode(_Homing) == ECk_Homing_TargetMode::Entity,
                "Point-on-target homing is still Entity mode");

            FinishSuccess();
        }
    }
}
