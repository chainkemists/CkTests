// Language=angelscript

//============================================================================
// CkProjectileGym — LagComp Compensated Shot station
//
// The full MWO-style loop, continuously: a hitbox-recorded target strafes
// while a fixed shooter post "suffers" 250ms of lag. Every cycle the shooter
// aims at where the target WAS 250ms ago (its rewound pose — what a laggy
// client would have seen) and fires via Request_LaunchCompensated with that
// window. The rewind validation confirms the hit against the past pose even
// though the target has long since strafed away.
//============================================================================

USTRUCT()
struct FCk_ProjectileGym_LagCompCompensatedShot_Station_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;
}

class UCk_EntityScript_ProjectileGym_LagCompCompensatedShot_Station : UCk_GenericEntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    private FCk_Handle _StationHandle;
    private FCk_Handle_Transform _TargetTransform;
    private FCk_Handle_RewindHistory _History;
    private FCk_Handle _ProjectileEntity;

    private float _StrafePhase = 0.0;
    private float _LagWindowSeconds = 0.25;

    private int32 _ShotsFired = 0;
    private int32 _RewindConfirmedHits = 0;
    private FVector _LastAimPoint = FVector::ZeroVector;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow
    DoConstruct(FCk_Handle& InHandle)
    {
        _StationHandle = InHandle;
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);

        auto Target = utils_entity_lifetime::Request_CreateEntity(InHandle);
        Target.Set_DebugName(n"LagComp_CompensatedShot.Target");
        _TargetTransform = utils_transform::Add(
            Target, FTransform(FRotator::ZeroRotator, Get_StrafeLocation()), ECk_Replication::DoesNotReplicate);

        auto HitShapes = TArray<FCk_LagComp_HitShape>();
        HitShapes.Add(FCk_LagComp_HitShape(
            utils_gameplay_tag::ResolveGameplayTag(n"CkTests.LagComp.Body"),
            UCk_Utils_Shapes_UE::Make_Sphere(FCk_ShapeSphere_Dimensions(60.0))));

        _History = UCk_Utils_RewindHistory_UE::Add(Target, FCk_Fragment_RewindHistory_ParamsData(HitShapes));

        auto CycleParams = FCk_Fragment_Timer_ParamsData(FCk_Time(3.0));
        CycleParams.Set_StartingState(ECk_Timer_State::Running)
                   .Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        auto CycleTimer = utils_timer::Add(InHandle, CycleParams);
        CycleTimer.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnFireCycle"));

        utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"OnTick"));

        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    private FVector Get_StrafeLocation()
    {
        return InitialTransform.Location + FVector(600.0, Math::Sin(_StrafePhase) * 350.0, 250.0);
    }

    private FVector Get_ShooterPost()
    {
        return InitialTransform.Location + FVector(-500.0, 0.0, 250.0);
    }

    UFUNCTION()
    private void OnFireCycle(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        // The laggy client's view of the world: the target's pose LagWindow seconds ago
        auto NewestTime = _History.Get_NewestFrameTime().Get_Seconds();
        auto PastSnapshots = _History.Get_InterpolatedSnapshotsAtTime(FCk_Time(NewestTime - _LagWindowSeconds));

        if (PastSnapshots.Num() == 0)
        { return; }

        if (ck::IsValid(_ProjectileEntity))
        {
            utils_entity_lifetime::Request_DestroyEntity(_ProjectileEntity);
        }

        _LastAimPoint = PastSnapshots[0].Get_WorldTransform().Location;

        auto ShooterPost = Get_ShooterPost();
        auto AimDirection = (_LastAimPoint - ShooterPost).GetSafeNormal();

        auto Projectile = utils_entity_lifetime::Request_CreateEntity(_StationHandle);
        Projectile.Set_DebugName(n"LagComp_CompensatedShot.Projectile");
        _ProjectileEntity = Projectile;
        utils_transform::Add(
            Projectile, FTransform(FRotator::ZeroRotator, ShooterPost), ECk_Replication::DoesNotReplicate);

        // Very high terminal velocity = near-dragless, near-straight flight over this short
        // range, so the "laggy" aim at the past pose stays effectively exact (sag < 5cm)
        auto TrajectoryParams = FCk_Ballistic_TrajectoryParams(FVector(0.0, 0.0, -100000.0));
        auto Motion = UCk_Utils_BallisticMotion_UE::Add(Projectile, FCk_Fragment_BallisticMotion_ParamsData(TrajectoryParams));

        Motion.BindTo_OnRewindHit(FCk_Delegate_LagCompProjectile_OnRewindHit(this, n"OnRewindHit"));

        Motion.Request_LaunchCompensated(
            FCk_Request_LagCompProjectile_LaunchCompensated(AimDirection * 12000.0, FCk_Time(_LagWindowSeconds)));

        _ShotsFired++;
    }

    UFUNCTION()
    private void OnRewindHit(
        FCk_Handle_BallisticMotion InHandle,
        FCk_LagComp_RewindHit InHit)
    {
        _RewindConfirmedHits++;
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        _StrafePhase += 2.2 * float(InDeltaT.Get_Seconds());
        utils_transform::Request_SetLocation(_TargetTransform,
            FCk_Request_Transform_SetLocation(Get_StrafeLocation()));

        auto PresentLocation = utils_transform::Get_EntityCurrentLocation(_TargetTransform);
        auto ShooterPost = Get_ShooterPost();

        utils_debug_draw::DrawDebugSphere(PresentLocation, 60.0, 12, FLinearColor(0.9, 0.9, 0.9), 0.0, 2.0);
        utils_debug_draw::DrawDebugBox(ShooterPost, FVector(40.0, 40.0, 40.0), FLinearColor(0.2, 0.6, 1.0), FRotator::ZeroRotator, 0.0, 2.0);

        if (!_LastAimPoint.IsNearlyZero())
        {
            utils_debug_draw::DrawDebugSphere(_LastAimPoint, 30.0, 8, FLinearColor(0.05, 0.05, 0.05), 0.0, 1.5);
            utils_debug_draw::DrawDebugDashedLine(ShooterPost, _LastAimPoint, 25.0, FLinearColor(1.0, 0.2, 0.2), 0.0, 1.0);
        }

        auto Body = f"Shots fired      {_ShotsFired}\n"
            + f"Rewind hits      {_RewindConfirmedHits}\n"
            + f"Lag window       {int32(_LagWindowSeconds * 1000.0)} ms\n\n"
            + "White = target NOW\n"
            + "Black = where the laggy shooter aimed\n"
            + "Red   = the compensated shot line";

        CkGym_Common::Update_StationDisplay(ck::ToEntity(this),
            "STATION 5 / COMPENSATED SHOT", Body,
            "Hits confirm against the PAST pose.");
    }
}
