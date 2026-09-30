// Language=angelscript
class UCk_AutoTest_RotateTowards_LockedAxesHold : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;
    private FCk_RotateTowardsAutoTestFixture _F;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step("move the target up and diagonally ahead", n"Step_MoveTarget");
        Add_Step_WaitUntil("target lands at its new location", n"Check_TargetMoved");
        Add_Step("compose a turret with its pitch locked", n"Step_Add");
        Add_Step_WaitUntil("turret reports at target", n"Check_AtTarget");
        Add_Step("assert pitch held at 0 while yaw turned to 45", n"Step_Verify");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_MoveTarget(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _F.InitWorld(InHandle, FVector(28000.0, 0.0, -40000.0));
        _F.MoveTarget(_F.Origin + FVector(1000.0, 1000.0, 1000.0));
    }

    UFUNCTION()
    private void Check_TargetMoved(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        const auto Location = utils_transform::Get_EntityCurrentLocation(_F.Target);
        Res.Set(Location.Equals(_F.Origin + FVector(1000.0, 1000.0, 1000.0), 0.1));
    }

    UFUNCTION()
    private void Step_Add(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Spec = _F.Make_DefaultSpec();
        auto Tunables = Spec.Get_Tunables();
        auto Pitch = Tunables.Get_Pitch();
        Pitch.Set_Mode(ECk_RotateTowards_AxisMode::Locked);
        Tunables.Set_Pitch(Pitch);
        Spec.Set_Tunables(Tunables);
        Spec.Set_Target(_F.Target);

        _F.RotateTowards = utils_rotate_towards::Add(_F.Turret, Spec);
        Assert_Valid(_F.RotateTowards, "rotate-towards composed");
    }

    UFUNCTION()
    private void Check_AtTarget(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_rotate_towards::Get_IsAtTarget(_F.RotateTowards));
    }

    UFUNCTION()
    private void Step_Verify(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto Rotation = _F.TurretRotation();
        const auto DesiredPitch = utils_rotate_towards::Get_DesiredRotation(_F.RotateTowards).Pitch;
        Assert_True(CkRotateTowardsAutoTest::Is_Near(Rotation.Pitch, 0.0, 0.5), f"locked pitch {Rotation.Pitch} held at 0");
        Assert_True(CkRotateTowardsAutoTest::Is_Near(Rotation.Yaw, 45.0, 1.0), f"yaw {Rotation.Yaw} is within 1 deg of 45");
        Assert_True(CkRotateTowardsAutoTest::Is_Near(DesiredPitch, 0.0, 0.5), f"desired pitch {DesiredPitch} honors the lock");
        FinishSuccess();
    }
}

class ACk_AutoTest_RotateTowards_LockedAxesHold_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_RotateTowards_LockedAxesHold;
    default _TimeoutSeconds = 8.0f;
}
