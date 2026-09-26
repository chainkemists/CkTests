// Language=angelscript

class UCk_AutoTest_ProceduralAnimation_BodyPoseAdmissionRejects : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;
    default _AutoStageOriginField = false;
    private FVector _Origin = FVector(120000.0, 88000.0, 1000.0);
    private TArray<FCk_Handle> _Roots;
    private FCk_Handle_ProceduralLeg _LostLeg;
    private FCk_Handle_ProceduralGait _LossGait;
    private FCk_Handle_Transform _LossPresentation;

    FCk_Handle_Transform CreateTransform(FCk_Handle InOwner, FVector InLocation)
    {
        auto Owner = InOwner;
        auto Entity = utils_entity_lifetime::Request_CreateEntity(Owner);
        Entity.Request_OverrideToSelf();
        return utils_transform::Add(Entity, FTransform(InLocation), ECk_Replication::DoesNotReplicate);
    }

    bool HasBodyPose(FCk_Handle InBody)
    {
        return utils_procedural_body_pose::DoCast(InBody).IsSet();
    }

    FCk_ProceduralBodyPose_Spec MakeSpecWithSpring(FCk_Handle_Transform InPresentation, float32 InStiffness, float32 InMass)
    {
        auto Spring = FCk_ProceduralBodyPose_Spring();
        Spring.Set_Stiffness(InStiffness);
        Spring.Set_Mass(InMass);
        auto Spec = FCk_ProceduralBodyPose_Spec(InPresentation);
        Spec.Set_Spring(Spring);
        return Spec;
    }

    FCk_ProceduralBodyPose_Spec MakeSpecWithSupport(FCk_Handle_Transform InPresentation, float32 InCollapseDrop, float32 InMaxTilt)
    {
        auto Support = FCk_ProceduralBodyPose_Support();
        Support.Set_CollapseDrop(InCollapseDrop);
        Support.Set_MaxTilt(InMaxTilt);
        auto Spec = FCk_ProceduralBodyPose_Spec(InPresentation);
        Spec.Set_Support(Support);
        return Spec;
    }

    FCk_ProceduralBodyPose_Spec MakeSpecWithConform(FCk_Handle_Transform InPresentation, float32 InMaxTilt, float32 InHeightWeight,
        float32 InMaxHeight)
    {
        auto Conform = FCk_ProceduralBodyPose_Conform();
        Conform.Set_Mode(ECk_ProceduralBodyPose_ConformMode::PlantedFeet);
        Conform.Set_MaxTilt(InMaxTilt);
        Conform.Set_HeightWeight(InHeightWeight);
        Conform.Set_MaxHeight(InMaxHeight);
        auto Spec = FCk_ProceduralBodyPose_Spec(InPresentation);
        Spec.Set_Conform(Conform);
        return Spec;
    }

    void AssertRejected(FCk_Handle_ProceduralBodyPose InBodyPose, FCk_Handle InBody, int32 InEnsuresBefore,
        bool InExpectBodyPose, const FString& InCase)
    {
        Assert_True(ck::Is_NOT_Valid(InBodyPose), f"{InCase}: Add returns an invalid body pose handle");
        Assert_True(HasBodyPose(InBody) == InExpectBodyPose, f"{InCase}: the body's body pose presence is unchanged");
        Assert_Equals_Int(utils_ensure::Get_EnsureCount() - InEnsuresBefore, 1, f"{InCase}: exactly one ensure fires");
    }

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Body = CreateTransform(InHandle, _Origin);
        _Roots.Add(Body);
        FCk_Handle_ProceduralLeg RiggedLeg = utils_procedural_leg::Create(Body, ck::ProceduralTest_SideRig.Get_Legs()[0]);
        FCk_Handle_ProceduralLeg OpenLeg = utils_procedural_leg::Create(Body, ck::ProceduralTest_SideRig.Get_Legs()[1]);
        Assert_True(ck::IsValid(RiggedLeg) && ck::IsValid(OpenLeg), "Precondition: the body gets its two legs");
        auto Gait = utils_procedural_gait::Add(Body, ck::ProceduralGym_Gait);
        Assert_True(ck::IsValid(Gait), "Precondition: the body walks");

        auto Upper = CreateTransform(Body, _Origin + FVector(10.0, 0.0, 0.0));
        auto Lower = CreateTransform(Body, _Origin + FVector(20.0, 0.0, 0.0));
        auto Segments = TArray<FCk_Handle_Transform>();
        Segments.Add(Upper);
        Segments.Add(Lower);
        auto Chain = FCk_ProceduralRig_Spec();
        Chain.Set_Segments(Segments);
        Assert_True(ck::IsValid(utils_procedural_rig::Add(RiggedLeg, Chain)), "Precondition: the first leg binds its own chain");

        auto Presentation = CreateTransform(Body, _Origin);
        auto Foreign = CreateTransform(InHandle, _Origin + FVector(0.0, 200.0, 0.0));
        _Roots.Add(Foreign);
        auto Dying = CreateTransform(Body, _Origin);
        FCk_Handle DyingEntity = Dying;
        utils_entity_lifetime::Request_DestroyEntity(DyingEntity);

        auto EnsuresBefore = utils_ensure::Get_EnsureCount();
        AssertRejected(utils_procedural_body_pose::Add(FCk_Handle_ProceduralGait(), FCk_ProceduralBodyPose_Spec(Presentation)),
            Body, EnsuresBefore, false, "Invalid gait handle");

        EnsuresBefore = utils_ensure::Get_EnsureCount();
        AssertRejected(utils_procedural_body_pose::Add(Gait, FCk_ProceduralBodyPose_Spec(Body)), Body, EnsuresBefore, false,
            "Presentation is the body");

        EnsuresBefore = utils_ensure::Get_EnsureCount();
        AssertRejected(utils_procedural_body_pose::Add(Gait, FCk_ProceduralBodyPose_Spec(Dying)), Body, EnsuresBefore, false,
            "Presentation pending destruction");

        EnsuresBefore = utils_ensure::Get_EnsureCount();
        AssertRejected(utils_procedural_body_pose::Add(Gait, FCk_ProceduralBodyPose_Spec(Foreign)), Body, EnsuresBefore, false,
            "Presentation owned by another entity");

        EnsuresBefore = utils_ensure::Get_EnsureCount();
        AssertRejected(utils_procedural_body_pose::Add(Gait, FCk_ProceduralBodyPose_Spec(Upper)), Body, EnsuresBefore, false,
            "Presentation is a rig segment");

        EnsuresBefore = utils_ensure::Get_EnsureCount();
        AssertRejected(utils_procedural_body_pose::Add(Gait, MakeSpecWithSpring(Presentation, 0.0f, 1.0f)), Body, EnsuresBefore, false,
            "Zero spring stiffness");

        EnsuresBefore = utils_ensure::Get_EnsureCount();
        AssertRejected(utils_procedural_body_pose::Add(Gait, MakeSpecWithSpring(Presentation, 40.0f, 0.0f)), Body, EnsuresBefore, false,
            "Zero spring mass");

        EnsuresBefore = utils_ensure::Get_EnsureCount();
        AssertRejected(utils_procedural_body_pose::Add(Gait, MakeSpecWithSupport(Presentation, -1.0f, 25.0f)), Body, EnsuresBefore, false,
            "Negative collapse drop");

        EnsuresBefore = utils_ensure::Get_EnsureCount();
        AssertRejected(utils_procedural_body_pose::Add(Gait, MakeSpecWithSupport(Presentation, 40.0f, 90.0f)), Body, EnsuresBefore, false,
            "Max tilt of 90 degrees");

        EnsuresBefore = utils_ensure::Get_EnsureCount();
        AssertRejected(utils_procedural_body_pose::Add(Gait, MakeSpecWithConform(Presentation, 90.0f, 0.5f, 10.0f)), Body, EnsuresBefore,
            false, "Conform max tilt of 90 degrees");

        EnsuresBefore = utils_ensure::Get_EnsureCount();
        AssertRejected(utils_procedural_body_pose::Add(Gait, MakeSpecWithConform(Presentation, 20.0f, 1.5f, 10.0f)), Body, EnsuresBefore,
            false, "Conform height weight above 1");

        EnsuresBefore = utils_ensure::Get_EnsureCount();
        AssertRejected(utils_procedural_body_pose::Add(Gait, MakeSpecWithConform(Presentation, 20.0f, 0.5f, -1.0f)), Body, EnsuresBefore,
            false, "Negative conform max height");

        EnsuresBefore = utils_ensure::Get_EnsureCount();
        auto BodyPose = utils_procedural_body_pose::Add(Gait, MakeSpecWithConform(Presentation, 20.0f, 0.5f, 10.0f));
        Assert_True(ck::IsValid(BodyPose) && HasBodyPose(Body), "Positive control: a valid presentation admits a conforming body pose");
        Assert_Equals_Int(utils_ensure::Get_EnsureCount() - EnsuresBefore, 0, "Positive control: no ensure fires");

        auto SecondPresentation = CreateTransform(Body, _Origin);
        EnsuresBefore = utils_ensure::Get_EnsureCount();
        AssertRejected(utils_procedural_body_pose::Add(Gait, FCk_ProceduralBodyPose_Spec(SecondPresentation)), Body, EnsuresBefore,
            true, "Second body pose on one gait");
        Assert_True(utils_procedural_body_pose::Get_Presentation(BodyPose) == Presentation,
            "Second body pose on one gait: the first presentation stays bound");

        auto LossBody = CreateTransform(InHandle, _Origin + FVector(0.0, 400.0, 0.0));
        _Roots.Add(LossBody);
        FCk_Handle_ProceduralLeg KeptLeg = utils_procedural_leg::Create(LossBody, ck::ProceduralTest_SideRig.Get_Legs()[0]);
        _LostLeg = utils_procedural_leg::Create(LossBody, ck::ProceduralTest_SideRig.Get_Legs()[1]);
        _LossGait = utils_procedural_gait::Add(LossBody, ck::ProceduralGym_Gait);
        _LossPresentation = CreateTransform(LossBody, _Origin + FVector(0.0, 400.0, 0.0));
        Assert_True(ck::IsValid(KeptLeg) && ck::IsValid(_LostLeg) && ck::IsValid(_LossGait),
            "Precondition: the second body walks on two legs");
        auto LostLeg = _LostLeg;
        utils_procedural_leg::Request_Detach(LostLeg,
            FCk_Request_ProceduralLeg_Detach(ECk_ProceduralLeg_ReleasedPartsOwnership::KeepBodyOwned));

        Add_Step_WaitUntil("the detached leg's handle reads invalid", n"Check_LegLost");
        Add_Step("a gait that lost a captured leg rejects a body pose", n"Step_RejectLostLeg");
        // Three frames let the gait, body pose and rig processors run over the admitted and rejected compositions.
        Add_Step_WaitFrames("the world ticks over the admitted and rejected body poses", 3);
        Add_Step("retire the bodies", n"Step_Destroy");
        Add_Step_WaitUntil("every body is gone", n"Check_Destroyed");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Check_LegLost(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(ck::Is_NOT_Valid(_LostLeg));
    }

    UFUNCTION()
    private void Step_RejectLostLeg(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto LossGait = _LossGait;
        auto EnsuresBefore = utils_ensure::Get_EnsureCount();
        AssertRejected(utils_procedural_body_pose::Add(LossGait, FCk_ProceduralBodyPose_Spec(_LossPresentation)), LossGait,
            EnsuresBefore, false, "A captured leg was detached");
    }

    UFUNCTION()
    private void Step_Destroy(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        for (auto Root : _Roots)
        {
            Assert_True(ck::IsValid(Root), "Every body survived the rejections");
            auto RootEntity = Root;
            utils_entity_lifetime::Request_DestroyEntity(RootEntity);
        }
    }

    UFUNCTION()
    private void Check_Destroyed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Gone = true;
        for (auto Root : _Roots)
        {
            Gone = Gone && ck::Is_NOT_Valid(Root);
        }
        auto Result = OutResult;
        Result.Set(Gone);
    }
}

class ACk_AutoTest_ProceduralAnimation_BodyPoseAdmissionRejects_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 6.0f;

    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_ProceduralAnimation_BodyPoseAdmissionRejects");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }

    UFUNCTION(BlueprintOverride)
    TArray<FString> Get_ExpectedLogErrors() const
    {
        auto Errors = TArray<FString>();
        Errors.Add("The gait must be live with no body pose; the presentation must be a live transform entity");
        return Errors;
    }
}
