// Language=angelscript
struct FCk_RotateTowardsAutoTestFixture
{
    FCk_Handle_Transform Root;
    // Identity rotation: faces +X.
    FCk_Handle_Transform Turret;
    // 90 deg of yaw to the turret's right.
    FCk_Handle_Transform Target;
    // Straight ahead of the turret: rest yaw 0.
    FCk_Handle_Transform RestPoint;
    FCk_Handle_RotateTowards RotateTowards;
    FVector Origin;

    // Every transform is a lifetime child of Root, so destroying Root tears the row down.
    void InitWorld(FCk_Handle InOwner, FVector InOrigin)
    {
        Origin = InOrigin;
        Root = utils_transform::Create(InOwner, FTransform(Origin), ECk_Replication::DoesNotReplicate);
        Turret = utils_transform::Create(Root, FTransform(Origin), ECk_Replication::DoesNotReplicate);
        Target = utils_transform::Create(Root, FTransform(Origin + FVector(0.0, 1000.0, 0.0)), ECk_Replication::DoesNotReplicate);
        RestPoint = utils_transform::Create(Root, FTransform(Origin + FVector(1000.0, 0.0, 0.0)), ECk_Replication::DoesNotReplicate);
    }

    void Init(FCk_Handle InOwner, FCk_RotateTowards_Spec InSpec, FVector InOrigin)
    {
        InitWorld(InOwner, InOrigin);
        auto Spec = InSpec;
        if (ck::Is_NOT_Valid(Spec.Get_Target()))
        {
            Spec.Set_Target(Target);
        }
        RotateTowards = utils_rotate_towards::Add(Turret, Spec);
    }

    FCk_RotateTowards_Spec Make_DefaultSpec() const
    {
        auto Axis = FCk_RotateTowards_Axis();
        Axis.Set_Mode(ECk_RotateTowards_AxisMode::Free);
        Axis.Set_TurnRateDegPerSec(90.0f);

        auto Tunables = FCk_RotateTowards_Tunables();
        Tunables.Set_Mode(ECk_RotateTowards_Mode::RateLimited);
        Tunables.Set_Pitch(Axis);
        Tunables.Set_Yaw(Axis);
        Tunables.Set_Roll(Axis);
        Tunables.Set_ReachedToleranceDeg(1.0f);

        auto Spec = FCk_RotateTowards_Spec();
        Spec.Set_Tunables(Tunables);
        Spec.Set_StartingState(ECk_EnableDisable::Enable);
        return Spec;
    }

    void MoveTarget(FVector InWorldLocation)
    {
        const auto Current = utils_transform::Get_EntityCurrentTransform(Target);
        auto Request = FCk_Request_Transform_SetLocationAndRotation(InWorldLocation, Current.Rotator());
        Request.Set_LocalWorld(ECk_LocalWorld::World);
        utils_transform::Request_SetLocationAndRotation(Target, Request);
    }

    FRotator TurretRotation() const
    {
        return utils_transform::Get_EntityCurrentRotation(Turret);
    }

    void Request_Destroy()
    {
        if (ck::IsValid(Root))
        {
            utils_entity_lifetime::Request_DestroyEntity(Root);
        }
    }
}

namespace CkRotateTowardsAutoTest
{
    // A yaw range clamp about the rest line from the turret through InRestPoint.
    FCk_RotateTowards_RangeClamp Make_YawClamp(FCk_Handle_Transform InRestPoint, float InMinDeg, float InMaxDeg)
    {
        auto Clamp = FCk_RotateTowards_RangeClamp(InRestPoint);
        Clamp.Set_Yaw(FCk_RotateTowards_AxisRange(ECk_EnableDisable::Enable, FCk_FloatRange(InMinDeg, InMaxDeg)));
        return Clamp;
    }

    bool Is_Near(float InActualDeg, float InExpectedDeg, float InToleranceDeg)
    {
        return Math::Abs(Math::FindDeltaAngleDegrees(InActualDeg, InExpectedDeg)) <= InToleranceDeg;
    }
}
