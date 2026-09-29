// Language=angelscript

struct FCkChainGym_Fixture
{
    FCk_Handle_Transform Root;
    FCk_Handle_Transform Head;
    FCk_Handle_Chain Chain;
    FCk_Handle_Chain SplitChain;
    FCk_Handle_Spline Spline;
    FCk_Handle_Tween Travel;
    TArray<FCk_Handle_Transform> Links;
    TArray<FCk_Handle_Transform> Lamps;
    FVector Origin;
    int32 Station = 0;
    bool Moving = false;
    bool FollowingPawn = false;

    bool Create(FCk_Handle InOwner, FVector InOrigin, int32 InStation, float32 InSpacing)
    {
        Origin = InOrigin;
        Station = InStation;
        Links.Reset();
        Lamps.Reset();
        Root = utils_transform::Create(InOwner, FTransform(Origin), ECk_Replication::DoesNotReplicate);
        Head = utils_transform::Create(Root, FTransform(Origin), ECk_Replication::DoesNotReplicate);
        auto Params = FCk_Chain_Spec(InStation == 1 ? ECk_Chain_Solver::DistanceConstraint : ECk_Chain_Solver::PathHistory);
        Params.Set_SampleSpacingCm(InSpacing);
        Params.Set_TeleportDistanceCm(500.0f);
        if (InStation == 2)
        {
            Params.Set_HistorySeed(ECk_Chain_HistorySeed::HoldUntilCovered);
        }
        Chain = utils_chain::Add(Head, Params);
        if (ck::Is_NOT_Valid(Chain))
        {
            Request_Destroy();
            return false;
        }
        auto Count = InStation == 1 ? 12 : 8;
        for (auto Index = 0; Index < Count; Index++)
        {
            auto Location = Origin + FVector(-60.0 * (Index + 1), InStation == 2 ? 180.0 : 0.0, 0.0);
            auto Link = utils_transform::Create(Root, FTransform(Location), ECk_Replication::DoesNotReplicate);
            Links.Add(Link);
            auto LinkParams = FCk_ChainLink_Spec(float32(60.0 * (Index + 1)));
            LinkParams.Set_Orientation(ECk_Chain_LinkOrientation::FollowPath);
            utils_chain::Request_AttachLink(Chain, FCk_Request_Chain_AttachLink(Link, LinkParams));
            if (InStation == 3)
            {
                auto Lamp = utils_scene_node::Create(Link, FTransform(FVector(0.0, 0.0, 65.0)));
                Lamps.Add(Lamp.As_Transform());
            }
        }
        auto Points = TArray<FVector>();
        for (auto Index = 0; Index < 48; Index++)
        {
            auto Angle = 2.0 * Math::PI * Index / 48.0;
            Points.Add(FVector(650.0 * Math::Sin(Angle), 350.0 * Math::Sin(2.0 * Angle), 0.0));
        }
        auto SplineOwner = utils_transform::Create(Root, FTransform(Origin), ECk_Replication::DoesNotReplicate);
        Spline = utils_spline::Create(SplineOwner, utils_spline::Make_Params_FromPoints(Points, true));
        if (InStation != 2)
        {
            Request_StartTravel();
        }
        return true;
    }

    // The same figure-eight as the Train, so both solvers can be compared side by side on the same corners.
    // Chasing the pawn is opt-in: the pawn is the camera in this gym, so an always-on follow drags the rope
    // up to the viewpoint the moment the station spawns.
    void Request_TogglePawnFollow(FCk_Handle_Transform InPawn)
    {
        DoStopTravel();
        if (FollowingPawn)
        {
            FollowingPawn = false;
            Request_StartTravel();
            return;
        }
        Travel = utils_tween::Create_TweenEntityLocation_FollowTarget(Head, InPawn, 0.8f,
            ECk_TweenEasing::Linear, ECk_TweenLoopType::Restart, -1);
        FollowingPawn = true;
        Moving = true;
    }

    void DoStopTravel()
    {
        if (ck::IsValid(Travel))
        {
            utils_tween::Stop(Travel, ECk_TweenStopBehavior::SelfDestruct);
        }
        Travel = FCk_Handle_Tween();
        Moving = false;
    }

    void Request_StartTravel()
    {
        if (ck::Is_NOT_Valid(Travel))
        {
            Travel = utils_tween::Create_TweenEntityTransform_FollowSpline(Head, Spline, 18.0f,
                ECk_Tween_SplineOrientation::OrientToSpline, ECk_TweenEasing::Linear,
                ECk_TweenLoopType::Restart, -1);
        }
        else
        {
            utils_tween::Resume(Travel);
        }
        Moving = true;
    }

    void Request_Teleport()
    {
        if (ck::IsValid(Travel))
        {
            utils_tween::Pause(Travel);
        }
        Moving = false;
        auto Current = utils_transform::Get_EntityCurrentLocation(Head);
        utils_transform::Request_SetLocation(Head, FCk_Request_Transform_SetLocation(Current + FVector(0.0, 850.0, 0.0)));
    }

    void Request_SplitAtFour()
    {
        auto Roster = utils_chain::Get_Links(Chain);
        if (ck::IsValid(SplitChain) || Roster.Num() < 4)
        {
            return;
        }
        SplitChain = utils_chain::Request_Split(Chain, FCk_Request_Chain_Split(Roster[3]));
    }

    void Draw()
    {
        if (ck::Is_NOT_Valid(Head))
        {
            return;
        }
        auto HeadPose = utils_transform::Get_EntityCurrentTransform(Head);
        utils_debug_draw::DrawDebugSolidBox(HeadPose.GetLocation(), FVector(25.0, 20.0, 20.0),
            FLinearColor(1.0f, 0.4f, 0.05f, 1.0f), HeadPose.Rotator());
        auto Previous = HeadPose.GetLocation();
        for (auto Link : Links)
        {
            if (ck::Is_NOT_Valid(Link))
            {
                continue;
            }
            auto Pose = utils_transform::Get_EntityCurrentTransform(Link);
            auto Color = Station == 2 ? FLinearColor(0.6f, 0.65f, 0.7f, 1.0f) : FLinearColor(0.05f, 0.8f, 0.75f, 1.0f);
            utils_debug_draw::DrawDebugSolidBox(Pose.GetLocation(), FVector(22.0, 18.0, 18.0), Color, Pose.Rotator());
            if (Station == 1)
            {
                utils_debug_draw::DrawDebugLine(Previous, Pose.GetLocation(), Color, 0.0f, 3.0f);
            }
            Previous = Pose.GetLocation();
        }
        for (auto Lamp : Lamps)
        {
            auto Location = utils_transform::Get_EntityCurrentLocation(Lamp);
            utils_debug_draw::DrawDebugSphere(Location, 10.0f, 12, FLinearColor::Yellow, 0.0f, 3.0f);
        }
    }

    void Request_Destroy()
    {
        if (ck::IsValid(Root))
        {
            utils_entity_lifetime::Request_DestroyEntity(Root);
        }
        Moving = false;
    }
}
