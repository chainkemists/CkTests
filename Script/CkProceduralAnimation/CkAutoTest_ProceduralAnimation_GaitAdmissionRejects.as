// Language=angelscript

class UCk_AutoTest_ProceduralAnimation_GaitAdmissionRejects : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;
    default _AutoStageOriginField = false;
    private FVector _Origin = FVector(120000.0, 60000.0, 1000.0);
    private FCk_Handle _Body;
    private FCk_Handle _OneLegBody;
    private FCk_Handle _ShortLegBody;
    private TArray<ECk_Request_OperationResult> _ApplyPresetResults;
    private int32 _AcceptedPresetResultsBefore = 0;

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

    // The side legs' rest feet sit 95.5 cm from their hips: within 0.8 of the authored 140 cm chains, beyond 0.8 of a
    // 100 cm chain and beyond 0.6 of the authored one.
    FCk_ProceduralLeg_Spec MakeShortLeg(FCk_ProceduralLeg_Spec InTemplate)
    {
        auto Lengths = TArray<float32>();
        Lengths.Add(50.0f);
        Lengths.Add(50.0f);
        auto Chain = InTemplate.Get_Chain();
        Chain.Set_SegmentLengths(Lengths);
        return FCk_ProceduralLeg_Spec(InTemplate.Get_Id(), InTemplate.Get_Placement(), Chain);
    }

    FCk_Request_ProceduralGait_ApplyPreset MakeReachRequest(float32 InTargetReachFraction, float32 InForceStepReachFraction = 0.92f,
        float32 InHardOverstretchReachFraction = 1.0f)
    {
        UCk_ProceduralGait_Data Preset = ck::ProceduralGym_Gait;
        auto Step = Preset.Get_Step();
        Step.Set_TargetReachFraction(InTargetReachFraction);
        Step.Set_ForceStepReachFraction(InForceStepReachFraction);
        Step.Set_HardOverstretchReachFraction(InHardOverstretchReachFraction);
        return FCk_Request_ProceduralGait_ApplyPreset(Preset.Get_Timing(), Step, Preset.Get_Probe());
    }

    void AssertPresetRejected(FCk_Handle_ProceduralGait InGait, FCk_Request_ProceduralGait_ApplyPreset InRequest, const FString& InCase)
    {
        auto Gait = InGait;
        auto ResultsBefore = _ApplyPresetResults.Num();
        auto EnsuresBefore = utils_ensure::Get_EnsureCount();
        utils_procedural_gait::Request_ApplyPreset(Gait, InRequest,
            FCk_Delegate_Request_OnCompleted(this, n"OnApplyPresetCompleted"));
        Assert_Equals_Int(_ApplyPresetResults.Num() - ResultsBefore, 1, f"{InCase}: the completion delegate fires once");
        if (_ApplyPresetResults.Num() > ResultsBefore)
        {
            Assert_True(_ApplyPresetResults.Last() == ECk_Request_OperationResult::Failed_NotEnqueued,
                f"{InCase}: the request completes Failed_NotEnqueued");
        }
        Assert_Equals_Int(utils_ensure::Get_EnsureCount() - EnsuresBefore, 1, f"{InCase}: exactly one ensure fires");
    }

    UFUNCTION()
    private void OnApplyPresetCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _ApplyPresetResults.Add(InResult);
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

        auto DyingBody = CreateBody(InHandle, _Origin + FVector(0.0, -500.0, 0.0));
        for (auto LegParams : ck::ProceduralTest_SideRig.Get_Legs())
        {
            Assert_True(ck::IsValid(utils_procedural_leg::Create(DyingBody, LegParams)),
                "Precondition: the dying body gets its two legs");
        }
        FCk_Handle DyingEntity = DyingBody;
        utils_entity_lifetime::Request_DestroyEntity(DyingEntity);
        EnsuresBefore = utils_ensure::Get_EnsureCount();
        AssertRejected(utils_procedural_gait::Add(DyingBody, ck::ProceduralGym_Gait), DyingBody, EnsuresBefore,
            false, "Body pending destruction");

        auto ShortLegBody = CreateBody(InHandle, _Origin + FVector(0.0, 1000.0, 0.0));
        _ShortLegBody = ShortLegBody;
        for (auto LegParams : ck::ProceduralTest_SideRig.Get_Legs())
        {
            Assert_True(ck::IsValid(utils_procedural_leg::Create(ShortLegBody, MakeShortLeg(LegParams))),
                "Precondition: the short-leg body gets its two legs");
        }
        EnsuresBefore = utils_ensure::Get_EnsureCount();
        AssertRejected(utils_procedural_gait::Add(ShortLegBody, ck::ProceduralGym_Gait), ShortLegBody, EnsuresBefore,
            false, "Rest foot beyond the target reach");

        EnsuresBefore = utils_ensure::Get_EnsureCount();
        auto Gait = utils_procedural_gait::Add(Body, ck::ProceduralGym_Gait);
        Assert_True(ck::IsValid(Gait) && HasGait(Body), "Positive control: the corrected composition admits a gait");
        Assert_Equals_Int(utils_ensure::Get_EnsureCount() - EnsuresBefore, 0, "Positive control: no ensure fires");

        EnsuresBefore = utils_ensure::Get_EnsureCount();
        AssertRejected(utils_procedural_gait::Add(Body, ck::ProceduralGym_Gait), Body, EnsuresBefore, true, "Existing gait");

        AssertPresetRejected(Gait, MakeReachRequest(0.6f), "Preset whose target reach excludes a rest foot");
        AssertPresetRejected(Gait, MakeReachRequest(0.95f), "Preset whose target reach exceeds its force-step reach");
        AssertPresetRejected(Gait, MakeReachRequest(0.8f, 0.92f, 0.99f), "Preset whose hard-overstretch reach is below the chain");
        AssertPresetRejected(Gait, MakeReachRequest(0.8f, 0.92f, 1.51f), "Preset whose hard-overstretch reach exceeds 1.5 chains");

        _AcceptedPresetResultsBefore = _ApplyPresetResults.Num();
        EnsuresBefore = utils_ensure::Get_EnsureCount();
        utils_procedural_gait::Request_ApplyPreset(Gait, MakeReachRequest(0.8f, 1.0f, 1.0f),
            FCk_Delegate_Request_OnCompleted(this, n"OnApplyPresetCompleted"));
        utils_procedural_gait::Request_ApplyPreset(Gait, MakeReachRequest(0.8f, 1.0f, 1.25f),
            FCk_Delegate_Request_OnCompleted(this, n"OnApplyPresetCompleted"));
        Assert_Equals_Int(_ApplyPresetResults.Num(), _AcceptedPresetResultsBefore,
            "Positive controls: presets whose force-step reach is the whole chain, with a hard-overstretch reach equal to it or above it, are enqueued");
        Assert_Equals_Int(utils_ensure::Get_EnsureCount() - EnsuresBefore, 0, "Positive controls: the accepted presets fire no ensure");

        // Three frames let the gait, leg and rig processors run over the surviving and rejected bodies.
        Add_Step_WaitFrames("the world keeps ticking over the rejected compositions", 3);
        Add_Step("retire both bodies", n"Step_Destroy");
        Add_Step_WaitUntil("both bodies are gone", n"Check_Destroyed");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_Destroy(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(ck::IsValid(_Body) && ck::IsValid(_OneLegBody) && ck::IsValid(_ShortLegBody), "Every body survived the rejections");
        Assert_Equals_Int(_ApplyPresetResults.Num() - _AcceptedPresetResultsBefore, 2, "Positive controls: each accepted preset completes once");
        for (auto Index = _AcceptedPresetResultsBefore; Index < _ApplyPresetResults.Num(); Index++)
        {
            Assert_True(_ApplyPresetResults[Index] == ECk_Request_OperationResult::Succeeded,
                "Positive controls: every accepted preset completes Succeeded");
        }
        utils_entity_lifetime::Request_DestroyEntity(_Body);
        utils_entity_lifetime::Request_DestroyEntity(_OneLegBody);
        utils_entity_lifetime::Request_DestroyEntity(_ShortLegBody);
    }

    UFUNCTION()
    private void Check_Destroyed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(ck::Is_NOT_Valid(_Body) && ck::Is_NOT_Valid(_OneLegBody) && ck::Is_NOT_Valid(_ShortLegBody));
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
        Errors.Add("lies farther from its hip than TargetReachFraction of its chain length.");
        Errors.Add("the gait must be live and the preset well-formed and within the leg count.");
        return Errors;
    }
}
