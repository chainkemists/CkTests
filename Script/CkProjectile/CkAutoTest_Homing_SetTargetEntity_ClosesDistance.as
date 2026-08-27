// Language=angelscript

//============================================================================
// CK HOMING - AUTOMATION TEST: SET TARGET ENTITY CLOSES DISTANCE
//============================================================================
//
// A projectile flying along +X is told to home on a static entity placed off
// to the side. The ProNav steering must bend the trajectory so the distance
// to the target keeps shrinking - the test passes once the projectile covers
// half the initial separation.
//============================================================================

class UCk_AutoTest_Homing_SetTargetEntity_ClosesDistance : UCk_AutoTest_Base
{
    private FCk_Handle_Transform _ProjectileTransform;
    private FCk_Handle_Transform _TargetTransform;
    private FCk_Handle_Homing _Homing;
    private float _InitialDistance = 0.0;
    private bool _SawActive = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;

        auto Projectile = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        _ProjectileTransform = utils_transform::Add(Projectile, FTransform(), ECk_Replication::DoesNotReplicate);

        auto ProjectileParams = FCk_Fragment_Projectile_ParamsData(
            FCk_Fragment_Velocity_ParamsData(ECk_LocalWorld::World, FVector(600.0, 0.0, 0.0)),
            FCk_Fragment_Acceleration_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector),
            FCk_Fragment_AutoReorient_ParamsData(ECk_AutoReorient_Policy::NoAutoReorient));
        utils_projectile::Add(Projectile, ProjectileParams, ECk_Replication::DoesNotReplicate);

        _Homing = utils_homing::Add(Projectile,
            FCk_Fragment_Homing_ParamsData(FCk_Homing_GuidanceSettings(2000.0)));

        auto Target = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        auto TargetLocation = FVector(2000.0, 1500.0, 0.0);
        _TargetTransform = utils_transform::Add(Target,
            FTransform(FRotator::ZeroRotator, TargetLocation, FVector::OneVector), ECk_Replication::DoesNotReplicate);

        _InitialDistance = TargetLocation.Size();

        utils_homing::Request_SetTargetEntity(_Homing, FCk_Request_Homing_SetTargetEntity(Target));

        utils_timer::Create_Tick(LocalHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        if (utils_homing::Get_IsActive(_Homing))
        {
            _SawActive = true;
        }

        auto ProjectileLocation = utils_transform::Get_EntityCurrentLocation(_ProjectileTransform);
        auto TargetLocation = utils_transform::Get_EntityCurrentLocation(_TargetTransform);
        auto Distance = ProjectileLocation.Distance(TargetLocation);

        if (Distance < _InitialDistance * 0.5)
        {
            Assert_True(_SawActive,
                "Homing should have been active while steering toward the target");
            Assert_True(utils_homing::Get_TargetMode(_Homing) == ECk_Homing_TargetMode::Entity,
                "Target mode should be Entity after Request_SetTargetEntity");

            FinishSuccess();
        }
    }
}
