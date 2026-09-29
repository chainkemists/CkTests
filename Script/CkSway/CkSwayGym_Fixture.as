// Language=angelscript

struct FCkSwayGym_Fixture
{
    FCk_Handle_Transform Root;
    FCk_Handle_Transform Head;
    TArray<FCk_Handle_Sway> Sways;
    TArray<FCk_Handle_Tween> Tweens;
    FVector Origin;
    int32 Station = 0;

    // Station 0 = Turntable (yaw ping-pong), 1 = Shuttle (X ping-pong), 2 = Compare (both, three specs side by side).
    // InMeshListener receives the cube mesh components as they are added (FCk_Delegate_UnrealComponent_OnAdded needs a UObject).
    bool Create(FCk_Handle InOwner, UObject InMeshListener, FVector InOrigin, int32 InStation)
    {
        Origin = InOrigin;
        Station = InStation;
        Sways.Reset();
        Tweens.Reset();

        const auto Turns = InStation != 1;
        const auto Shuttles = InStation != 0;
        const auto HeadStart = FTransform(FRotator(0.0, Turns ? -90.0 : 0.0, 0.0),
            Origin - FVector(Shuttles ? 400.0 : 0.0, 0.0, 0.0), FVector::OneVector);

        Root = utils_transform::Create(InOwner, FTransform(Origin), ECk_Replication::DoesNotReplicate);
        Head = utils_transform::Create(Root, HeadStart, ECk_Replication::DoesNotReplicate);
        if (Turns)
        {
            Tweens.Add(utils_tween::Create_TweenEntityRotation(Head, FRotator(0.0, 90.0, 0.0), 2.0f,
                ECk_TweenEasing::InOutSine, ECk_TweenLoopType::Yoyo, -1));
        }
        if (Shuttles)
        {
            Tweens.Add(utils_tween::Create_TweenEntityLocation(Head, Origin + FVector(400.0, 0.0, 0.0), 2.0f,
                ECk_TweenEasing::InOutSine, ECk_TweenLoopType::Yoyo, -1));
        }

        auto Composed = true;
        if (InStation == 2)
        {
            Composed = Add_SwayedCube(InMeshListener, Make_DemoSpec(), -120.0)
                && Add_SwayedCube(InMeshListener, Make_HeavySpec(), 0.0)
                && Add_SwayedCube(InMeshListener, Make_DisabledSpec(), 120.0);
        }
        else
        {
            Composed = Add_SwayedCube(InMeshListener, Make_DemoSpec(), 0.0);
            // The rigid twin: same offset, half size, directly under the head, so the lag reads against it.
            Add_Cube(InMeshListener, Head, FVector(80.0, 0.0, 0.0), 0.2);
        }

        if (Composed == false)
        {
            Request_Destroy();
            return false;
        }
        return true;
    }

    // Demonstration tune. The gym tweens drive the head at ~70 deg/s and ~300 cm/s (a mouse flick is 5-10x that),
    // so the framework defaults would read as a rigid node here; gains and clamps are raised until the lag is
    // unmistakable against the rigid twin. Not a recommended gameplay tune.
    FCk_Sway_Spec Make_DemoSpec() const
    {
        auto Spec = FCk_Sway_Spec();
        Spec.Set_Location(FCk_Sway_Response(FVector(30.0, 30.0, 30.0), 3.5f, 0.7f));
        Spec.Set_Rotation(FCk_Sway_Response(FVector(25.0, 25.0, 25.0), 4.5f, 0.75f));
        Spec.Set_RotationFromAngularVelocity(FVector(0.05, 0.05, 0.05));
        Spec.Set_LocationFromLinearVelocity(FVector(0.03, 0.03, 0.03));
        Spec.Set_LateralCmFromYawRate(0.12f);
        Spec.Set_VerticalCmFromPitchRate(0.08f);
        Spec.Set_RollDegFromLateralVelocity(0.02f);
        Spec.Set_PitchDegFromForwardVelocity(0.0f);
        return Spec;
    }

    FCk_Sway_Spec Make_HeavySpec() const
    {
        const auto Default = Make_DemoSpec();
        auto Spec = Make_DemoSpec();

        auto Location = Spec.Get_Location();
        Location.Set_FrequencyHz(2.0f);
        Location.Set_DampingRatio(0.5f);
        Spec.Set_Location(Location);

        auto Rotation = Spec.Get_Rotation();
        Rotation.Set_FrequencyHz(2.5f);
        Rotation.Set_DampingRatio(0.45f);
        Spec.Set_Rotation(Rotation);

        Spec.Set_RotationFromAngularVelocity(Default.Get_RotationFromAngularVelocity() * 2.0);
        Spec.Set_LocationFromLinearVelocity(Default.Get_LocationFromLinearVelocity() * 2.0);
        Spec.Set_LateralCmFromYawRate(Default.Get_LateralCmFromYawRate() * 2.0f);
        Spec.Set_VerticalCmFromPitchRate(Default.Get_VerticalCmFromPitchRate() * 2.0f);
        Spec.Set_RollDegFromLateralVelocity(Default.Get_RollDegFromLateralVelocity() * 2.0f);
        Spec.Set_PitchDegFromForwardVelocity(Default.Get_PitchDegFromForwardVelocity() * 2.0f);
        return Spec;
    }

    FCk_Sway_Spec Make_DisabledSpec() const
    {
        auto Spec = FCk_Sway_Spec();
        Spec.Set_StartingState(ECk_EnableDisable::Disable);
        return Spec;
    }

    bool Add_SwayedCube(UObject InMeshListener, FCk_Sway_Spec InSpec, float InY)
    {
        auto Node = utils_scene_node::Create(Head, FTransform(FVector(80.0, InY, 0.0)));
        auto Sway = utils_sway::Add(Node, InSpec);
        if (ck::Is_NOT_Valid(Sway))
        {
            return false;
        }
        Sways.Add(Sway);
        Add_Cube(InMeshListener, Node.As_Transform(), FVector::ZeroVector, 0.4);
        return true;
    }

    void Add_Cube(UObject InMeshListener, FCk_Handle_Transform InAttachTo, FVector InOffset, float InScale)
    {
        auto Node = utils_scene_node::Create(InAttachTo,
            FTransform(FRotator::ZeroRotator, InOffset, FVector(InScale, InScale, InScale)));
        const auto ComponentParams = utils_unreal_component::Make_Params(UStaticMeshComponent,
            ECk_UnrealComponent_TickPolicy::DoNotTick, n"SwayGym_Cube");
        auto ComponentHandle = utils_unreal_component::Add(FCk_Handle(Node), ComponentParams);
        utils_unreal_component::BindTo_OnAdded(ComponentHandle,
            FCk_Delegate_UnrealComponent_OnAdded(InMeshListener, n"OnSwayGymCubeAdded"));
    }

    void Draw()
    {
        if (ck::Is_NOT_Valid(Head))
        {
            return;
        }
        const auto HeadPose = utils_transform::Get_EntityCurrentTransform(Head);
        utils_debug_draw::DrawDebugSolidBox(HeadPose.GetLocation(), FVector(25.0, 20.0, 20.0),
            FLinearColor(1.0f, 0.4f, 0.05f, 1.0f), HeadPose.Rotator());
    }

    void Request_Destroy()
    {
        if (ck::IsValid(Root))
        {
            utils_entity_lifetime::Request_DestroyEntity(Root);
        }
    }
}
