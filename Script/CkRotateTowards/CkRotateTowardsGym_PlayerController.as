// Language=angelscript

class ACk_RotateTowardsGym_PlayerController : ACk_Gym_Base_PlayerController
{
    private TArray<FCkRotateTowardsGym_Fixture> _Fixtures;
    private bool _Started = false;
    private bool _ResetPending = false;
    private bool _DrawOverridden = false;
    private FString _CreateError;

    FString Get_StationTag(int32 InIndex) const
    {
        if (InIndex == 0)
        {
            return "Gym.CkRotateTowards.Tracker";
        }
        if (InIndex == 1)
        {
            return "Gym.CkRotateTowards.Clamped";
        }
        return "Gym.CkRotateTowards.Modes";
    }

    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();
        for (auto Index = 0; Index < 3; Index++)
        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(FName(Get_StationTag(Index)));
            Station.Transform = FTransform(FVector(100.0 + 3600.0 * (Index % 2), 3000.0 * Math::IntegerDivisionTrunc(Index, 2), 0.0));
            Station.AutoSize = true;
            if (Index == 0)
            {
                Station.Title = FText::FromString("TRACKER - RATE-LIMITED VS INSTANT");
                Station.Description.Add(FText::FromString("The small cube sweeps +-300 cm sideways, 400 cm ahead. Left turret: rate-limited at 60 deg/s. Right turret: Instant."));
                Station.Description.Add(FText::FromString("Watch the left turret lag and catch up smoothly at each end with no stepping; the right one stays locked on. O draws each turret's target line (green at target, yellow while turning)."));
            }
            else if (Index == 1)
            {
                Station.Title = FText::FromString("CLAMPED - +-45 DEG YAW ABOUT THE REST LINE");
                Station.Description.Add(FText::FromString("The rest point is the tiny cube 400 cm straight ahead. The target sweeps across the front between +70 and -70 deg of yaw, beyond the clamp at both ends."));
                Station.Description.Add(FText::FromString("The turret tracks the target while it is inside +-45 deg, then stops at the edge and reports at target there until the target comes back. O draws the blue rest line and the cyan range edges."));
            }
            else
            {
                Station.Title = FText::FromString("MODES - FREE / YAW-LOCKED / PITCH-LOCKED / DISABLED");
                Station.Description.Add(FText::FromString("One cube sweeps sideways (+-300 cm) and up and down (+-150 cm). Left to right: free, yaw locked, pitch locked, disabled."));
                Station.Description.Add(FText::FromString("The yaw-locked turret only pitches, the pitch-locked one only yaws, and the disabled one never moves (red with O on)."));
            }
            Stations.Add(Station);
        }
        return Stations;
    }

    void Request_StartGym() override
    {
        _Started = true;
        Request_ResetAll();
    }

    void Request_ResetAll()
    {
        for (auto Index = 0; Index < _Fixtures.Num(); Index++)
        {
            _Fixtures[Index].Request_Destroy();
        }
        _ResetPending = true;
        _CreateError = "";
    }

    FVector Get_Origin(int32 InIndex)
    {
        return Get_StationAnchorLocation(Get_StationTag(InIndex), ECk_GymStation_Anchor::FootprintCenter)
            + FVector(1300.0, 0.0, 150.0);
    }

    UFUNCTION(BlueprintOverride)
    void Tick(float InDeltaSeconds)
    {
        if (_Started == false)
        {
            return;
        }
        if (_ResetPending == false)
        {
            return;
        }
        for (auto Fixture : _Fixtures)
        {
            if (ck::IsValid(Fixture.Root))
            {
                return;
            }
        }
        auto EntityOwner = ck::ToEntity(this);
        if (ck::Is_NOT_Valid(EntityOwner) || ck::Is_NOT_Valid(GetControlledPawn()))
        {
            return;
        }
        _Fixtures.Reset();
        for (auto Index = 0; Index < 3; Index++)
        {
            _Fixtures.Add(FCkRotateTowardsGym_Fixture());
            if (_Fixtures[Index].Create(EntityOwner, this, Get_Origin(Index), Index) == false)
            {
                _CreateError = "A station failed composition; inspect the ensure log.";
            }
        }
        _ResetPending = false;
        Request_Frame(0);
    }

    UFUNCTION()
    private void OnRotateTowardsGymCubeAdded(FCk_Handle_UnrealComponent InHandle)
    {
        auto MeshComponent = Cast<UStaticMeshComponent>(utils_unreal_component::Get_Component(InHandle));
        if (ck::Is_NOT_Valid(MeshComponent))
        {
            return;
        }
        MeshComponent.SetCollisionEnabled(ECollisionEnabled::NoCollision);
        MeshComponent.SetStaticMesh(Cast<UStaticMesh>(LoadObject(this, "/Engine/BasicShapes/Cube.Cube")));
    }

    TArray<FCkGym_ControlRow> Get_ControlRows() override
    {
        auto Rows = TArray<FCkGym_ControlRow>();
        Rows.Add(CkGym_Control::Header("ROTATE TOWARDS"));
        Rows.Add(CkGym_Control::Status("State", _CreateError.IsEmpty() ? "Watch each turret against its target" : _CreateError, _ResetPending));
        if (_Fixtures.Num() == 3 && _ResetPending == false)
        {
            for (auto Index = 0; Index < 3; Index++)
            {
                if (_Fixtures[Index].Turrets.Num() > 0 && ck::IsValid(_Fixtures[Index].Turrets[0]))
                {
                    const auto Turret = _Fixtures[Index].Turrets[0];
                    const auto Yaw = utils_transform::Get_EntityCurrentRotation(Turret.As_Transform()).Yaw;
                    const auto Rem = utils_rotate_towards::Get_RemainingRotation(Turret).Yaw;
                    const auto State = utils_rotate_towards::Get_IsAtTarget(Turret) ? "at target" : "turning";
                    Rows.Add(CkGym_Control::Status(Get_StationTag(Index), f"yaw {Yaw :.1} deg, rem {Rem :.1}, {State}"));
                }
            }
        }
        Rows.Add(CkGym_Control::Action(EKeys::One, "1", "View Tracker"));
        Rows.Add(CkGym_Control::Action(EKeys::Two, "2", "View Clamped"));
        Rows.Add(CkGym_Control::Action(EKeys::Three, "3", "View Modes"));
        Rows.Add(CkGym_Control::Action(EKeys::X, "X", "Reset all stations"));
        Rows.Add(CkGym_Control::Toggle(EKeys::O, "O", "Draw targets (ck.RotateTowards.DrawTargets)", UCk_Utils_RotateTowards_DebugSettings_UE::Get_DrawTargets()));
        return Rows;
    }

    void Request_ControlActivated(int32 InRowIndex) override
    {
        auto Rows = Get_ControlRows();
        if (Rows.IsValidIndex(InRowIndex) == false)
        {
            return;
        }
        auto Key = Rows[InRowIndex].Key;
        if (Key == EKeys::X)
        {
            Request_ResetAll();
            return;
        }
        if (Key == EKeys::O)
        {
            Request_ToggleDraw();
            return;
        }
        if (_ResetPending || _Fixtures.Num() != 3)
        {
            return;
        }
        if (Key == EKeys::One)
        {
            Request_Frame(0);
        }
        else if (Key == EKeys::Two)
        {
            Request_Frame(1);
        }
        else if (Key == EKeys::Three)
        {
            Request_Frame(2);
        }
    }

    void Request_ToggleDraw()
    {
        auto DrawCVarName = n"ck.RotateTowards.DrawTargets";
        if (UCk_Utils_AutoTest_UE::Get_CVarExists(DrawCVarName) == false)
        {
            ck::Error("Rotate Towards gym diagnostics are unavailable; the debug settings must be loaded.");
            return;
        }
        auto Enabled = !UCk_Utils_RotateTowards_DebugSettings_UE::Get_DrawTargets();
        if (_DrawOverridden)
        {
            UCk_Utils_AutoTest_UE::Request_PopCVarOverride(DrawCVarName);
        }
        UCk_Utils_AutoTest_UE::Request_PushCVarOverride(DrawCVarName, Enabled ? "1" : "0");
        _DrawOverridden = true;
    }

    void Request_Frame(int32 InIndex)
    {
        auto Pawn = GetControlledPawn();
        if (ck::Is_NOT_Valid(Pawn) || _Fixtures.IsValidIndex(InIndex) == false)
        {
            return;
        }
        auto Target = _Fixtures[InIndex].Origin + FVector(200.0, 0.0, 0.0);
        auto Eye = Target + FVector(-700.0, -900.0, 650.0);
        Pawn.SetActorLocation(Eye);
        SetControlRotation((Target - Eye).Rotation());
    }

    UFUNCTION(Exec)
    void Ck_RotateTowards_Control(int32 InRowIndex)
    {
        Request_ControlActivated(InRowIndex);
    }

    UFUNCTION(BlueprintOverride)
    void EndPlay(EEndPlayReason InReason)
    {
        for (auto Index = 0; Index < _Fixtures.Num(); Index++)
        {
            _Fixtures[Index].Request_Destroy();
        }
        if (_DrawOverridden)
        {
            UCk_Utils_AutoTest_UE::Request_PopCVarOverride(n"ck.RotateTowards.DrawTargets");
        }
    }
}
