// Language=angelscript

class UCk_AutoTest_ProceduralAnimation_WalkerAdmissionRejects : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;
    default _AutoStageOriginField = false;
    private FVector _Origin = FVector(120000.0, 66000.0, 1000.0);
    private FCk_Handle _Body;

    FCk_Handle_Transform CreateTransform(FCk_Handle InOwner, FVector InLocation)
    {
        auto Owner = InOwner;
        auto Entity = utils_entity_lifetime::Request_CreateEntity(Owner);
        Entity.Request_OverrideToSelf();
        return utils_transform::Add(Entity, FTransform(InLocation), ECk_Replication::DoesNotReplicate);
    }

    FCk_ProceduralWalker_LegChain MakeLegChain(FName InLegId, FCk_Handle_Transform InBody, int32 InSegmentCount)
    {
        auto Segments = TArray<FCk_Handle_Transform>();
        for (auto Index = 0; Index < InSegmentCount; Index++)
        {
            Segments.Add(CreateTransform(InBody, _Origin + FVector(0.0, 0.0, -10.0 * Index)));
        }
        auto Chain = FCk_ProceduralRig_Spec();
        Chain.Set_Segments(Segments);
        return FCk_ProceduralWalker_LegChain(InLegId, Chain);
    }

    void AssertRejected(FCk_ProceduralWalker InWalker, FCk_Handle_Transform InBody, int32 InEnsuresBefore, const FString& InCase)
    {
        Assert_True(ck::Is_NOT_Valid(InWalker.Get_Gait()) && InWalker.Get_Legs().Num() == 0,
            f"{InCase}: Add_Walker returns an empty walker");
        Assert_Equals_Int(utils_procedural_leg::Get_Legs(InBody).Num(), 0, f"{InCase}: no leg was created");
        Assert_False(utils_procedural_gait::DoCast(InBody).IsSet(), f"{InCase}: no gait was added");
        Assert_Equals_Int(utils_ensure::Get_EnsureCount() - InEnsuresBefore, 1, f"{InCase}: exactly one ensure fires");
    }

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Body = CreateTransform(InHandle, _Origin);
        _Body = Body;

        auto UnknownLeg = TArray<FCk_ProceduralWalker_LegChain>();
        UnknownLeg.Add(MakeLegChain(n"LegX", Body, 2));
        auto EnsuresBefore = utils_ensure::Get_EnsureCount();
        AssertRejected(utils_procedural_animation::Add_Walker(Body, ck::ProceduralTest_SideRig, ck::ProceduralGym_Gait, UnknownLeg),
            Body, EnsuresBefore, "Chain names an unknown leg");

        auto RepeatedLeg = TArray<FCk_ProceduralWalker_LegChain>();
        RepeatedLeg.Add(MakeLegChain(n"Leg0", Body, 2));
        RepeatedLeg.Add(MakeLegChain(n"Leg0", Body, 2));
        EnsuresBefore = utils_ensure::Get_EnsureCount();
        AssertRejected(utils_procedural_animation::Add_Walker(Body, ck::ProceduralTest_SideRig, ck::ProceduralGym_Gait, RepeatedLeg),
            Body, EnsuresBefore, "Two chains for one leg");

        auto WrongCount = TArray<FCk_ProceduralWalker_LegChain>();
        WrongCount.Add(MakeLegChain(n"Leg0", Body, 3));
        EnsuresBefore = utils_ensure::Get_EnsureCount();
        AssertRejected(utils_procedural_animation::Add_Walker(Body, ck::ProceduralTest_SideRig, ck::ProceduralGym_Gait, WrongCount),
            Body, EnsuresBefore, "Segment count mismatch");

        auto Valid = TArray<FCk_ProceduralWalker_LegChain>();
        Valid.Add(MakeLegChain(n"Leg0", Body, 2));
        EnsuresBefore = utils_ensure::Get_EnsureCount();
        auto Walker = utils_procedural_animation::Add_Walker(Body, ck::ProceduralTest_SideRig, ck::ProceduralGym_Gait, Valid);
        Assert_True(ck::IsValid(Walker.Get_Gait()) && Walker.Get_Legs().Num() == 2,
            "Positive control: the same body accepts a well-formed walker after the rejections");
        Assert_Equals_Int(utils_procedural_leg::Get_Legs(Body).Num(), 2, "Positive control: both legs are connected");
        Assert_Equals_Int(utils_ensure::Get_EnsureCount() - EnsuresBefore, 0, "Positive control: no ensure fires");

        Add_Step("retire the body", n"Step_Destroy");
        Add_Step_WaitUntil("the body is gone", n"Check_Destroyed");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_Destroy(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        utils_entity_lifetime::Request_DestroyEntity(_Body);
    }

    UFUNCTION()
    private void Check_Destroyed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(ck::Is_NOT_Valid(_Body));
    }
}

class ACk_AutoTest_ProceduralAnimation_WalkerAdmissionRejects_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 6.0f;

    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_ProceduralAnimation_WalkerAdmissionRejects");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }

    UFUNCTION(BlueprintOverride)
    TArray<FString> Get_ExpectedLogErrors() const
    {
        auto Errors = TArray<FString>();
        Errors.Add("It needs a live transform body that can own children with no gait and no legs");
        return Errors;
    }
}
