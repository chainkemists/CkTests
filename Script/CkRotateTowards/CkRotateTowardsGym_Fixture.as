// Language=angelscript

struct FCkRotateTowardsGym_Fixture
{
    FCk_Handle_Transform Root;
    FCk_Handle_Transform Target;
    FCk_Handle_Transform RestPoint;
    TArray<FCk_Handle_RotateTowards> Turrets;
    TArray<FCk_Handle_Tween> Tweens;
    FVector Origin;
    int32 Station = 0;

    // Station 0 = Tracker (rate-limited vs instant), 1 = Clamped (+-45 deg yaw about a rest line), 2 = Modes (free /
    // yaw-locked / pitch-locked / disabled). InMeshListener receives the cube mesh components as they are added
    // (FCk_Delegate_UnrealComponent_OnAdded needs a UObject).
    bool Create(FCk_Handle InOwner, UObject InMeshListener, FVector InOrigin, int32 InStation)
    {
        Origin = InOrigin;
        Station = InStation;
        Turrets.Reset();
        Tweens.Reset();

        Root = utils_transform::Create(InOwner, FTransform(Origin), ECk_Replication::DoesNotReplicate);

        auto Composed = true;
        if (InStation == 0)
        {
            Create_LateralTarget(InMeshListener);
            Composed = Add_Turret(InMeshListener, FVector(0.0, -75.0, 0.0), Make_Spec(ECk_RotateTowards_Mode::RateLimited, 60.0f))
                && Add_Turret(InMeshListener, FVector(0.0, 75.0, 0.0), Make_Spec(ECk_RotateTowards_Mode::Instant, 60.0f));
        }
        else if (InStation == 1)
        {
            // The target tweens along the chord between the points at +70 and -70 deg of yaw on a 400 cm circle: it stays
            // in front of the turret (137 cm ahead at mid-sweep) and spends the ends of each sweep outside the +-45 deg range.
            const auto Start = Origin + FRotator(0.0, 70.0, 0.0).Vector() * 400.0;
            const auto End = Origin + FRotator(0.0, -70.0, 0.0).Vector() * 400.0;
            Target = utils_transform::Create(Root, FTransform(Start), ECk_Replication::DoesNotReplicate);
            Tweens.Add(utils_tween::Create_TweenEntityLocation(Target, End, 4.0f,
                ECk_TweenEasing::InOutSine, ECk_TweenLoopType::Yoyo, -1));
            Add_Cube(InMeshListener, Target, FVector::ZeroVector, FVector(0.25, 0.25, 0.25));

            RestPoint = utils_transform::Create(Root, FTransform(Origin + FVector(400.0, 0.0, 0.0)), ECk_Replication::DoesNotReplicate);
            Add_Cube(InMeshListener, RestPoint, FVector::ZeroVector, FVector(0.1, 0.1, 0.1));

            auto Clamp = FCk_RotateTowards_RangeClamp(RestPoint);
            Clamp.Set_Yaw(FCk_RotateTowards_AxisRange(ECk_EnableDisable::Enable, FCk_FloatRange(-45.0, 45.0)));
            auto Spec = Make_Spec(ECk_RotateTowards_Mode::RateLimited, 90.0f);
            Spec.Set_RangeClamp(Clamp);
            Composed = Add_Turret(InMeshListener, FVector::ZeroVector, Spec);
        }
        else
        {
            // Two tweens on two entities: a carrier sweeps Y, the target (a scene node under it) sweeps Z in its offset.
            auto Carrier = utils_transform::Create(Root, FTransform(Origin + FVector(400.0, -300.0, 0.0)), ECk_Replication::DoesNotReplicate);
            Tweens.Add(utils_tween::Create_TweenEntityLocation(Carrier, Origin + FVector(400.0, 300.0, 0.0), 3.0f,
                ECk_TweenEasing::InOutSine, ECk_TweenLoopType::Yoyo, -1));
            auto TargetNode = utils_scene_node::Create(Carrier, FTransform(FVector(0.0, 0.0, -150.0)));
            Tweens.Add(utils_tween::Create_TweenSceneNodeOffsetLocation(TargetNode, FVector(0.0, 0.0, 150.0), 2.0f,
                ECk_TweenEasing::InOutSine, ECk_TweenLoopType::Yoyo, -1));
            Target = TargetNode.As_Transform();
            Add_Cube(InMeshListener, Target, FVector::ZeroVector, FVector(0.25, 0.25, 0.25));

            auto YawLocked = Make_Spec(ECk_RotateTowards_Mode::RateLimited, 90.0f);
            auto YawLockedTunables = YawLocked.Get_Tunables();
            YawLockedTunables.Set_Yaw(FCk_RotateTowards_Axis(ECk_RotateTowards_AxisMode::Locked, 90.0f));
            YawLocked.Set_Tunables(YawLockedTunables);

            auto PitchLocked = Make_Spec(ECk_RotateTowards_Mode::RateLimited, 90.0f);
            auto PitchLockedTunables = PitchLocked.Get_Tunables();
            PitchLockedTunables.Set_Pitch(FCk_RotateTowards_Axis(ECk_RotateTowards_AxisMode::Locked, 90.0f));
            PitchLocked.Set_Tunables(PitchLockedTunables);

            auto Disabled = Make_Spec(ECk_RotateTowards_Mode::RateLimited, 90.0f);
            Disabled.Set_StartingState(ECk_EnableDisable::Disable);

            Composed = Add_Turret(InMeshListener, FVector(0.0, -225.0, 0.0), Make_Spec(ECk_RotateTowards_Mode::RateLimited, 90.0f))
                && Add_Turret(InMeshListener, FVector(0.0, -75.0, 0.0), YawLocked)
                && Add_Turret(InMeshListener, FVector(0.0, 75.0, 0.0), PitchLocked)
                && Add_Turret(InMeshListener, FVector(0.0, 225.0, 0.0), Disabled);
        }

        if (Composed == false)
        {
            Request_Destroy();
            return false;
        }
        return true;
    }

    // The target sweeps +-300 cm laterally, 400 cm ahead of the turrets.
    void Create_LateralTarget(UObject InMeshListener)
    {
        Target = utils_transform::Create(Root, FTransform(Origin + FVector(400.0, -300.0, 0.0)), ECk_Replication::DoesNotReplicate);
        Tweens.Add(utils_tween::Create_TweenEntityLocation(Target, Origin + FVector(400.0, 300.0, 0.0), 3.0f,
            ECk_TweenEasing::InOutSine, ECk_TweenLoopType::Yoyo, -1));
        Add_Cube(InMeshListener, Target, FVector::ZeroVector, FVector(0.25, 0.25, 0.25));
    }

    FCk_RotateTowards_Spec Make_Spec(ECk_RotateTowards_Mode InMode, float32 InTurnRateDegPerSec) const
    {
        const auto Axis = FCk_RotateTowards_Axis(ECk_RotateTowards_AxisMode::Free, InTurnRateDegPerSec);
        auto Tunables = FCk_RotateTowards_Tunables(InMode);
        Tunables.Set_Pitch(Axis);
        Tunables.Set_Yaw(Axis);
        Tunables.Set_Roll(Axis);
        Tunables.Set_ReachedToleranceDeg(1.0f);

        auto Spec = FCk_RotateTowards_Spec(Target);
        Spec.Set_Tunables(Tunables);
        return Spec;
    }

    bool Add_Turret(UObject InMeshListener, FVector InLocalOffset, FCk_RotateTowards_Spec InSpec)
    {
        auto Turret = utils_transform::Create(Root, FTransform(Origin + InLocalOffset), ECk_Replication::DoesNotReplicate);
        auto RotateTowards = utils_rotate_towards::Add(Turret, InSpec);
        if (ck::Is_NOT_Valid(RotateTowards))
        {
            return false;
        }
        Turrets.Add(RotateTowards);
        // Elongated along +X and pushed forward of the pivot, so the cube's long axis reads as the facing.
        Add_Cube(InMeshListener, Turret, FVector(40.0, 0.0, 0.0), FVector(0.9, 0.3, 0.3));
        return true;
    }

    void Add_Cube(UObject InMeshListener, FCk_Handle_Transform InAttachTo, FVector InOffset, FVector InScale)
    {
        auto Node = utils_scene_node::Create(InAttachTo, FTransform(FRotator::ZeroRotator, InOffset, InScale));
        const auto ComponentParams = utils_unreal_component::Make_Params(UStaticMeshComponent,
            ECk_UnrealComponent_TickPolicy::DoNotTick, n"RotateTowardsGym_Cube");
        auto ComponentHandle = utils_unreal_component::Add(FCk_Handle(Node), ComponentParams);
        utils_unreal_component::BindTo_OnAdded(ComponentHandle,
            FCk_Delegate_UnrealComponent_OnAdded(InMeshListener, n"OnRotateTowardsGymCubeAdded"));
    }

    void Request_Destroy()
    {
        if (ck::IsValid(Root))
        {
            utils_entity_lifetime::Request_DestroyEntity(Root);
        }
    }
}
