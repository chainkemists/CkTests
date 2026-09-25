// Language=angelscript

class UCk_AutoTest_ProceduralAnimation_GaitAdmissionRejects : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;
    default _AutoStageOriginField = false;
    private FVector _Origin = FVector(120000.0, 60000.0, 1000.0);
    private FCk_Handle _Body;
    private FCk_Handle _OneLegBody;

    FCk_Handle_Transform CreateBody(FCk_Handle InOwner, FVector InLocation)
    {
        auto Owner = InOwner;
        auto Entity = utils_entity_lifetime::Request_CreateEntity(Owner);
        Entity.Request_OverrideToSelf();
        return utils_transform::Add(Entity, FTransform(InLocation), ECk_Replication::DoesNotReplicate);
    }

    bool HasGait(FCk_Handle InBody)
    {
        return utils_procedural_gait::DoCast(InBody).IsSet();
    }

    void AssertRejected(FCk_Handle_ProceduralGait InGait, FCk_Handle InBody, int32 InEnsuresBefore,
        bool InExpectGait, const FString& InCase)
    {
        Assert_True(ck::Is_NOT_Valid(InGait), f"{InCase}: Add returns an invalid gait handle");
        Assert_True(HasGait(InBody) == InExpectGait, f"{InCase}: the body's gait presence is unchanged");
        Assert_Equals_Int(utils_ensure::Get_EnsureCount() - InEnsuresBefore, 1, f"{InCase}: exactly one ensure fires");
    }

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Body = CreateBody(InHandle, _Origin);
        _Body = Body;
        for (auto LegParams : ck::ProceduralTest_SideRig.Get_Legs())
        {
            Assert_True(ck::IsValid(utils_procedural_leg::Create(Body, LegParams)), "Precondition: the body gets its two legs");
        }

        auto EnsuresBefore = utils_ensure::Get_EnsureCount();
        AssertRejected(utils_procedural_gait::Add(Body, nullptr), Body, EnsuresBefore, false, "Null preset");

        EnsuresBefore = utils_ensure::Get_EnsureCount();
        AssertRejected(utils_procedural_gait::Add(Body, ck::ProceduralTest_ZeroStepDurationGait), Body, EnsuresBefore,
            false, "Zero step duration");

        auto OneLegBody = CreateBody(InHandle, _Origin + FVector(0.0, 500.0, 0.0));
        _OneLegBody = OneLegBody;
        Assert_True(ck::IsValid(utils_procedural_leg::Create(OneLegBody, ck::ProceduralTest_SideRig.Get_Legs()[0])),
            "Precondition: the second body gets a single leg");
        EnsuresBefore = utils_ensure::Get_EnsureCount();
        AssertRejected(utils_procedural_gait::Add(OneLegBody, ck::ProceduralGym_Gait), OneLegBody, EnsuresBefore,
            false, "One leg");

        EnsuresBefore = utils_ensure::Get_EnsureCount();
        auto Gait = utils_procedural_gait::Add(Body, ck::ProceduralGym_Gait);
        Assert_True(ck::IsValid(Gait) && HasGait(Body), "Positive control: the corrected composition admits a gait");
        Assert_Equals_Int(utils_ensure::Get_EnsureCount() - EnsuresBefore, 0, "Positive control: no ensure fires");

        EnsuresBefore = utils_ensure::Get_EnsureCount();
        AssertRejected(utils_procedural_gait::Add(Body, ck::ProceduralGym_Gait), Body, EnsuresBefore, true, "Existing gait");

        // Three frames let the gait, leg and rig processors run over the surviving and rejected bodies.
        Add_Step_WaitFrames("the world keeps ticking over the rejected compositions", 3);
        Add_Step("retire both bodies", n"Step_Destroy");
        Add_Step_WaitUntil("both bodies are gone", n"Check_Destroyed");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_Destroy(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(ck::IsValid(_Body) && ck::IsValid(_OneLegBody), "Both bodies survived the rejections");
        utils_entity_lifetime::Request_DestroyEntity(_Body);
        utils_entity_lifetime::Request_DestroyEntity(_OneLegBody);
    }

    UFUNCTION()
    private void Check_Destroyed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(ck::Is_NOT_Valid(_Body) && ck::Is_NOT_Valid(_OneLegBody));
    }
}

class ACk_AutoTest_ProceduralAnimation_GaitAdmissionRejects_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 6.0f;

    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_ProceduralAnimation_GaitAdmissionRejects");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }

    UFUNCTION(BlueprintOverride)
    TArray<FString> Get_ExpectedLogErrors() const
    {
        auto Errors = TArray<FString>();
        Errors.Add("the gait data asset is missing or its timing, step or probe settings are malformed.");
        Errors.Add("create 2..64 legs before the gait and keep MaxSimultaneousSwings within the leg count.");
        Errors.Add("it must be a live transform entity with no existing gait.");
        return Errors;
    }
}
