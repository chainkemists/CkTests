// Language=angelscript

class UCk_AutoTest_ProceduralAnimation_LegAndRigAdmissionRejects : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;
    default _AutoStageOriginField = false;
    private FVector _Origin = FVector(120000.0, 64000.0, 1000.0);
    private TArray<FCk_Handle> _Roots;
    private TArray<FCk_Handle_Transform> _Parts;
    private TArray<FVector> _PartLocations;

    FCk_Handle_Transform CreateTransform(FCk_Handle InOwner, FVector InLocation)
    {
        auto Owner = InOwner;
        auto Entity = utils_entity_lifetime::Request_CreateEntity(Owner);
        Entity.Request_OverrideToSelf();
        return utils_transform::Add(Entity, FTransform(InLocation), ECk_Replication::DoesNotReplicate);
    }

    FCk_Handle_Transform CreatePart(FCk_Handle InOwner, FVector InLocation)
    {
        auto Part = CreateTransform(InOwner, InLocation);
        _Parts.Add(Part);
        _PartLocations.Add(InLocation);
        return Part;
    }

    FCk_ProceduralLeg_Spec MakeLegWithSegmentCount(FCk_ProceduralLeg_Spec InTemplate, int32 InSegmentCount)
    {
        auto Lengths = TArray<float32>();
        for (auto Index = 0; Index < InSegmentCount; Index++)
        {
            Lengths.Add(40.0f);
        }
        auto Chain = InTemplate.Get_Chain();
        Chain.Set_SegmentLengths(Lengths);
        return FCk_ProceduralLeg_Spec(n"ParamsRejected", InTemplate.Get_Placement(), Chain);
    }

    FCk_ProceduralRig_Spec MakeChain(TArray<FCk_Handle_Transform> InSegments)
    {
        auto Chain = FCk_ProceduralRig_Spec();
        Chain.Set_Segments(InSegments);
        return Chain;
    }

    void AssertLegRejected(FCk_Handle_ProceduralLeg InLeg, FCk_Handle InBody, int32 InExpectedLegs, int32 InEnsuresBefore,
        const FString& InCase)
    {
        Assert_True(ck::Is_NOT_Valid(InLeg), f"{InCase}: Create returns an invalid leg handle");
        Assert_Equals_Int(utils_procedural_leg::Get_Legs(InBody).Num(), InExpectedLegs, f"{InCase}: no leg was connected");
        Assert_Equals_Int(utils_ensure::Get_EnsureCount() - InEnsuresBefore, 1, f"{InCase}: exactly one ensure fires");
    }

    void AssertRigRejected(FCk_Handle_ProceduralRig InRig, FCk_Handle_ProceduralLeg InLeg, int32 InEnsuresBefore,
        const FString& InCase)
    {
        Assert_True(ck::Is_NOT_Valid(InRig), f"{InCase}: Add returns an invalid rig handle");
        Assert_False(utils_procedural_rig::DoCast(InLeg).IsSet(), f"{InCase}: the leg carries no partial rig");
        Assert_Equals_Int(utils_ensure::Get_EnsureCount() - InEnsuresBefore, 1, f"{InCase}: exactly one ensure fires");
    }

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LegA = ck::ProceduralTest_SideRig.Get_Legs()[0];
        auto LegB = ck::ProceduralTest_SideRig.Get_Legs()[1];

        auto LegBody = CreateTransform(InHandle, _Origin);
        _Roots.Add(LegBody);
        Assert_True(ck::IsValid(utils_procedural_leg::Create(LegBody, LegA)), "Positive control: the first leg is created");
        auto EnsuresBefore = utils_ensure::Get_EnsureCount();
        AssertLegRejected(utils_procedural_leg::Create(LegBody, LegA), LegBody, 1, EnsuresBefore, "Duplicate leg id");

        auto NoIdLeg = FCk_ProceduralLeg_Spec(NAME_None, LegB.Get_Placement(), LegB.Get_Chain());
        EnsuresBefore = utils_ensure::Get_EnsureCount();
        AssertLegRejected(utils_procedural_leg::Create(LegBody, NoIdLeg), LegBody, 1, EnsuresBefore, "None leg id");

        EnsuresBefore = utils_ensure::Get_EnsureCount();
        AssertLegRejected(utils_procedural_leg::Create(LegBody, MakeLegWithSegmentCount(LegB, 0)), LegBody, 1, EnsuresBefore,
            "Zero segment lengths");

        EnsuresBefore = utils_ensure::Get_EnsureCount();
        AssertLegRejected(utils_procedural_leg::Create(LegBody, MakeLegWithSegmentCount(LegB, 9)), LegBody, 1, EnsuresBefore,
            "Nine segment lengths");

        auto GaitBody = CreateTransform(InHandle, _Origin + FVector(0.0, 400.0, 0.0));
        _Roots.Add(GaitBody);
        utils_procedural_leg::Create(GaitBody, LegA);
        utils_procedural_leg::Create(GaitBody, LegB);
        Assert_True(ck::IsValid(utils_procedural_gait::Add(GaitBody, ck::ProceduralGym_Gait)), "Precondition: the gait body walks");
        auto ThirdLeg = ck_procedural_gym_assets::MakeRadialLeg(2, 4, 2);
        EnsuresBefore = utils_ensure::Get_EnsureCount();
        AssertLegRejected(utils_procedural_leg::Create(GaitBody, ThirdLeg), GaitBody, 2, EnsuresBefore, "Leg after gait");

        // No gait on this body: a rig is admitted but never posed, so every part must stay where it was created.
        auto RigBody = CreateTransform(InHandle, _Origin + FVector(0.0, 800.0, 0.0));
        _Roots.Add(RigBody);
        FCk_Handle_ProceduralLeg RiggedLeg = utils_procedural_leg::Create(RigBody, LegA);
        FCk_Handle_ProceduralLeg OpenLeg = utils_procedural_leg::Create(RigBody, LegB);
        Assert_True(ck::IsValid(RiggedLeg) && ck::IsValid(OpenLeg), "Precondition: the rig body has two two-segment legs");

        auto RigLocation = _Origin + FVector(0.0, 800.0, 0.0);
        auto Upper = CreatePart(RigBody, RigLocation + FVector(10.0, 0.0, 0.0));
        auto Lower = CreatePart(RigBody, RigLocation + FVector(20.0, 0.0, 0.0));
        auto Extra = CreatePart(RigBody, RigLocation + FVector(30.0, 0.0, 0.0));
        auto Foreign = CreatePart(InHandle, RigLocation + FVector(40.0, 0.0, 0.0));
        auto Spare = CreatePart(RigBody, RigLocation + FVector(50.0, 0.0, 0.0));

        auto ThreeSegments = TArray<FCk_Handle_Transform>();
        ThreeSegments.Add(Upper);
        ThreeSegments.Add(Lower);
        ThreeSegments.Add(Extra);
        EnsuresBefore = utils_ensure::Get_EnsureCount();
        AssertRigRejected(utils_procedural_rig::Add(OpenLeg, MakeChain(ThreeSegments)), OpenLeg, EnsuresBefore,
            "Three segments on a two-length leg");

        auto ForeignSegments = TArray<FCk_Handle_Transform>();
        ForeignSegments.Add(Upper);
        ForeignSegments.Add(Foreign);
        EnsuresBefore = utils_ensure::Get_EnsureCount();
        AssertRigRejected(utils_procedural_rig::Add(OpenLeg, MakeChain(ForeignSegments)), OpenLeg, EnsuresBefore,
            "Segment owned by another entity");

        auto BodySegments = TArray<FCk_Handle_Transform>();
        BodySegments.Add(Upper);
        BodySegments.Add(RigBody);
        EnsuresBefore = utils_ensure::Get_EnsureCount();
        AssertRigRejected(utils_procedural_rig::Add(OpenLeg, MakeChain(BodySegments)), OpenLeg, EnsuresBefore,
            "Segment is the body");

        auto RiggedSegments = TArray<FCk_Handle_Transform>();
        RiggedSegments.Add(Upper);
        RiggedSegments.Add(Lower);
        EnsuresBefore = utils_ensure::Get_EnsureCount();
        Assert_True(ck::IsValid(utils_procedural_rig::Add(RiggedLeg, MakeChain(RiggedSegments))),
            "Positive control: the first leg binds its own chain");
        Assert_Equals_Int(utils_ensure::Get_EnsureCount() - EnsuresBefore, 0, "Positive control: no ensure fires");

        auto ReusedSegments = TArray<FCk_Handle_Transform>();
        ReusedSegments.Add(Lower);
        ReusedSegments.Add(Spare);
        EnsuresBefore = utils_ensure::Get_EnsureCount();
        AssertRigRejected(utils_procedural_rig::Add(OpenLeg, MakeChain(ReusedSegments)), OpenLeg, EnsuresBefore,
            "Segment reused across two legs");

        // Three frames let the transform, leg and rig processors run; a rejected part must still not move.
        Add_Step_WaitFrames("the world ticks over the rejected rigs", 3);
        Add_Step("verify no part moved and retire the bodies", n"Step_CheckAndDestroy");
        Add_Step_WaitUntil("every body and part is gone", n"Check_Destroyed");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_CheckAndDestroy(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        for (auto Index = 0; Index < _Parts.Num(); Index++)
        {
            auto Location = utils_transform::Get_EntityCurrentLocation(_Parts[Index]);
            Assert_True(Location.Equals(_PartLocations[Index], 0.01), f"Part {Index} keeps its pre-call transform");
        }
        for (auto Root : _Roots)
        {
            utils_entity_lifetime::Request_DestroyEntity(Root);
        }
        for (auto Part : _Parts)
        {
            auto PartEntity = FCk_Handle(Part);
            utils_entity_lifetime::Request_DestroyEntity(PartEntity);
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
        for (auto Part : _Parts)
        {
            Gone = Gone && ck::Is_NOT_Valid(Part);
        }
        auto Result = OutResult;
        Result.Set(Gone);
    }
}

class ACk_AutoTest_ProceduralAnimation_LegAndRigAdmissionRejects_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 6.0f;

    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_ProceduralAnimation_LegAndRigAdmissionRejects");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }

    UFUNCTION(BlueprintOverride)
    TArray<FString> Get_ExpectedLogErrors() const
    {
        auto Errors = TArray<FString>();
        Errors.Add("the Id is already used or the body already has 64 legs.");
        Errors.Add("it needs an Id, a finite placement and 1..8 positive segment lengths.");
        Errors.Add("it must be a live transform entity that can own children and has no gait yet.");
        Errors.Add("The leg must be live with no rig; the chain needs 1..8 unique live segments");
        return Errors;
    }
}
