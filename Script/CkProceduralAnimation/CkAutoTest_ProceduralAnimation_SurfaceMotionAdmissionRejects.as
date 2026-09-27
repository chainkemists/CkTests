// Language=angelscript

class UCk_AutoTest_ProceduralAnimation_SurfaceMotionAdmissionRejects : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;
    default _AutoStageOriginField = false;
    private FVector _Origin = FVector(120000.0, 62000.0, 1000.0);
    private FCk_Handle _Body;
    private FCk_Handle _FeetBody;
    // Above the default 65 cm clearance and within the default 200 cm probe reach.
    private float32 _ValidStepHeight = 85.0f;

    bool HasMotion(FCk_Handle InBody)
    {
        return utils_surface_motion::DoCast(InBody).IsSet();
    }

    void AssertRejected(FCk_Handle_SurfaceMotion InMotion, int32 InEnsuresBefore, bool InExpectMotion, const FString& InCase)
    {
        Assert_True(ck::Is_NOT_Valid(InMotion), f"{InCase}: Add returns an invalid surface-motion handle");
        Assert_True(HasMotion(_Body) == InExpectMotion, f"{InCase}: the body's surface-motion presence is unchanged");
        Assert_Equals_Int(utils_ensure::Get_EnsureCount() - InEnsuresBefore, 1, f"{InCase}: exactly one ensure fires");
    }

    FCk_SurfaceMotion_Spec MakeSpecWithConfirm(float32 InConfirmAngle, FCk_Time InConfirmTime)
    {
        auto Contact = FCk_SurfaceMotion_Contact();
        Contact.Set_ConfirmAngle(InConfirmAngle);
        Contact.Set_ConfirmTime(InConfirmTime);
        auto Spec = FCk_SurfaceMotion_Spec();
        Spec.Set_Contact(Contact);
        return Spec;
    }

    FCk_SurfaceMotion_Spec MakeSpecWithStepHeight(float32 InMaxStepHeight)
    {
        auto Contact = FCk_SurfaceMotion_Contact();
        Contact.Set_MaxStepHeight(InMaxStepHeight);
        auto Spec = FCk_SurfaceMotion_Spec();
        Spec.Set_Contact(Contact);
        return Spec;
    }

    FCk_SurfaceMotion_Spec MakeSpecWithSteerFloor(float32 InSteerFloor)
    {
        auto Movement = FCk_SurfaceMotion_Movement();
        Movement.Set_SteerFloor(InSteerFloor);
        auto Spec = FCk_SurfaceMotion_Spec();
        Spec.Set_Movement(Movement);
        return Spec;
    }

    void AssertSpecRejected(FCk_Handle_Transform InBody, FCk_SurfaceMotion_Spec InSpec, const FString& InCase)
    {
        auto Body = InBody;
        auto EnsuresBefore = utils_ensure::Get_EnsureCount();
        AssertRejected(utils_surface_motion::Add(Body, InSpec), EnsuresBefore, false, InCase);
    }

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Owner = InHandle;
        auto Entity = utils_entity_lifetime::Request_CreateEntity(Owner);
        Entity.Request_OverrideToSelf();
        auto Body = utils_transform::Add(Entity, FTransform(_Origin), ECk_Replication::DoesNotReplicate);
        _Body = Body;

        auto ShortReach = FCk_SurfaceMotion_Spec();
        auto Contact = FCk_SurfaceMotion_Contact();
        Contact.Set_Clearance(65.0f);
        Contact.Set_ProbeReach(65.0f);
        ShortReach.Set_Contact(Contact);
        auto EnsuresBefore = utils_ensure::Get_EnsureCount();
        AssertRejected(utils_surface_motion::Add(Body, ShortReach), EnsuresBefore, false, "Probe reach at the clearance");

        auto Stationary = FCk_SurfaceMotion_Spec();
        auto StationaryMovement = FCk_SurfaceMotion_Movement();
        StationaryMovement.Set_MaxSpeed(0.0f);
        Stationary.Set_Movement(StationaryMovement);
        EnsuresBefore = utils_ensure::Get_EnsureCount();
        AssertRejected(utils_surface_motion::Add(Body, Stationary), EnsuresBefore, false, "Zero max speed");

        auto NaN = Math::Sqrt(-1.0);
        auto BrokenGravity = FCk_SurfaceMotion_Spec();
        auto BrokenMovement = FCk_SurfaceMotion_Movement();
        BrokenMovement.Set_Gravity(FVector(0.0, 0.0, NaN));
        BrokenGravity.Set_Movement(BrokenMovement);
        Assert_True(BrokenMovement.Get_Gravity().ContainsNaN(), "Precondition: the gravity carries a NaN");
        EnsuresBefore = utils_ensure::Get_EnsureCount();
        AssertRejected(utils_surface_motion::Add(Body, BrokenGravity), EnsuresBefore, false, "NaN gravity");

        auto DefaultConfirmTime = FCk_SurfaceMotion_Contact().Get_ConfirmTime();
        AssertSpecRejected(Body, MakeSpecWithConfirm(-1.0f, DefaultConfirmTime), "Negative confirm angle");
        AssertSpecRejected(Body, MakeSpecWithConfirm(181.0f, DefaultConfirmTime), "Confirm angle above 180 degrees");
        AssertSpecRejected(Body, MakeSpecWithConfirm(float32(NaN), DefaultConfirmTime), "NaN confirm angle");
        AssertSpecRejected(Body, MakeSpecWithConfirm(30.0f, FCk_Time(-0.01)), "Negative confirm time");
        AssertSpecRejected(Body, MakeSpecWithConfirm(30.0f, FCk_Time(NaN)), "NaN confirm time");
        AssertSpecRejected(Body, MakeSpecWithSteerFloor(-0.1f), "Negative steer floor");
        AssertSpecRejected(Body, MakeSpecWithSteerFloor(1.1f), "Steer floor above 1");
        AssertSpecRejected(Body, MakeSpecWithSteerFloor(float32(NaN)), "NaN steer floor");
        auto DefaultContact = FCk_SurfaceMotion_Contact();
        AssertSpecRejected(Body, MakeSpecWithStepHeight(-1.0f), "Negative max step height");
        AssertSpecRejected(Body, MakeSpecWithStepHeight(DefaultContact.Get_Clearance()), "Max step height at the clearance");
        AssertSpecRejected(Body, MakeSpecWithStepHeight(DefaultContact.Get_ProbeReach() + 1.0f), "Max step height beyond the probe reach");
        AssertSpecRejected(Body, MakeSpecWithStepHeight(float32(NaN)), "NaN max step height");

        auto DyingEntity = utils_entity_lifetime::Request_CreateEntity(Owner);
        DyingEntity.Request_OverrideToSelf();
        auto DyingBody = utils_transform::Add(DyingEntity, FTransform(_Origin + FVector(0.0, -500.0, 0.0)),
            ECk_Replication::DoesNotReplicate);
        FCk_Handle DyingHandle = DyingBody;
        utils_entity_lifetime::Request_DestroyEntity(DyingHandle);
        EnsuresBefore = utils_ensure::Get_EnsureCount();
        auto DyingMotion = utils_surface_motion::Add(DyingBody, FCk_SurfaceMotion_Spec());
        Assert_True(ck::Is_NOT_Valid(DyingMotion), "Body pending destruction: Add returns an invalid surface-motion handle");
        Assert_False(HasMotion(DyingBody), "Body pending destruction: the body gets no surface motion");
        Assert_Equals_Int(utils_ensure::Get_EnsureCount() - EnsuresBefore, 1, "Body pending destruction: exactly one ensure fires");

        EnsuresBefore = utils_ensure::Get_EnsureCount();
        auto Motion = utils_surface_motion::Add(Body, FCk_SurfaceMotion_Spec());
        Assert_True(ck::IsValid(Motion) && HasMotion(Body), "Positive control: default parameters are admitted");
        Assert_Equals_Int(utils_ensure::Get_EnsureCount() - EnsuresBefore, 0, "Positive control: no ensure fires");
        Assert_True(utils_surface_motion::Get_HeightSource(Motion) == ECk_SurfaceMotion_HeightSource::Rays,
            "The default height source reads back as Rays");
        Assert_True(utils_surface_motion::Get_WallPolicy(Motion) == ECk_SurfaceMotion_WallPolicy::Climb,
            "The default wall policy reads back as Climb");
        Assert_Equals_Float(utils_surface_motion::Get_MaxStepHeight(Motion), 0.0, 0.0, "The default max step height reads back as 0");

        auto FeetEntity = utils_entity_lifetime::Request_CreateEntity(Owner);
        FeetEntity.Request_OverrideToSelf();
        auto FeetBody = utils_transform::Add(FeetEntity, FTransform(_Origin + FVector(0.0, 500.0, 0.0)), ECk_Replication::DoesNotReplicate);
        _FeetBody = FeetBody;
        auto FeetContact = FCk_SurfaceMotion_Contact();
        FeetContact.Set_HeightSource(ECk_SurfaceMotion_HeightSource::PlantedFeet);
        FeetContact.Set_WallPolicy(ECk_SurfaceMotion_WallPolicy::Slide);
        FeetContact.Set_MaxStepHeight(_ValidStepHeight);
        auto FeetSpec = FCk_SurfaceMotion_Spec();
        FeetSpec.Set_Contact(FeetContact);
        EnsuresBefore = utils_ensure::Get_EnsureCount();
        auto FeetMotion = utils_surface_motion::Add(FeetBody, FeetSpec);
        Assert_True(ck::IsValid(FeetMotion) && HasMotion(FeetBody), "A PlantedFeet height source is admitted");
        Assert_Equals_Int(utils_ensure::Get_EnsureCount() - EnsuresBefore, 0, "A PlantedFeet height source fires no ensure");
        Assert_True(utils_surface_motion::Get_HeightSource(FeetMotion) == ECk_SurfaceMotion_HeightSource::PlantedFeet,
            "The PlantedFeet height source reads back as PlantedFeet");
        Assert_True(utils_surface_motion::Get_WallPolicy(FeetMotion) == ECk_SurfaceMotion_WallPolicy::Slide,
            "The Slide wall policy reads back as Slide");
        Assert_Equals_Float(utils_surface_motion::Get_MaxStepHeight(FeetMotion), _ValidStepHeight, 0.0,
            "A max step height above the clearance and within the probe reach reads back as set");

        EnsuresBefore = utils_ensure::Get_EnsureCount();
        AssertRejected(utils_surface_motion::Add(Body, FCk_SurfaceMotion_Spec()), EnsuresBefore, true,
            "Duplicate add");

        // Three frames let the surface-motion processors run over the surviving feature.
        Add_Step_WaitFrames("the world keeps ticking over the rejected compositions", 3);
        Add_Step("retire the body", n"Step_Destroy");
        Add_Step_WaitUntil("the body is gone", n"Check_Destroyed");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_Destroy(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(ck::IsValid(_Body), "The body survived the rejections");
        utils_entity_lifetime::Request_DestroyEntity(_Body);
        utils_entity_lifetime::Request_DestroyEntity(_FeetBody);
    }

    UFUNCTION()
    private void Check_Destroyed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(ck::Is_NOT_Valid(_Body) && ck::Is_NOT_Valid(_FeetBody));
    }
}

class ACk_AutoTest_ProceduralAnimation_SurfaceMotionAdmissionRejects_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 6.0f;

    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_ProceduralAnimation_SurfaceMotionAdmissionRejects");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }

    UFUNCTION(BlueprintOverride)
    TArray<FString> Get_ExpectedLogErrors() const
    {
        auto Errors = TArray<FString>();
        Errors.Add("invalid clearance, probe reach, contact grace, confirm angle, confirm time, speed, turn rate, gravity or steer floor.");
        Errors.Add("it must be a live transform entity with no existing surface motion.");
        return Errors;
    }
}
