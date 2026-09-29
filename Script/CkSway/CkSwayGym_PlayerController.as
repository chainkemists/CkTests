// Language=angelscript

class ACk_SwayGym_PlayerController : ACk_Gym_Base_PlayerController
{
    private TArray<FCkSwayGym_Fixture> _Fixtures;
    private bool _Started = false;
    private bool _ResetPending = false;
    private bool _DrawOverridden = false;
    private FString _CreateError;

    FString Get_StationTag(int32 InIndex) const
    {
        if (InIndex == 0)
        {
            return "Gym.CkSway.Turntable";
        }
        if (InIndex == 1)
        {
            return "Gym.CkSway.Shuttle";
        }
        return "Gym.CkSway.Compare";
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
                Station.Title = FText::FromString("TURNTABLE - YAW SWAY");
                Station.Description.Add(FText::FromString("The orange head yaws -90..+90 deg every 2 s. The large cube hangs on a default sway; the small cube is its rigid twin."));
                Station.Description.Add(FText::FromString("Watch the large cube lag opposite the turn, overshoot slightly, and settle on the twin at each end."));
            }
            else if (Index == 1)
            {
                Station.Title = FText::FromString("SHUTTLE - LINEAR SWAY");
                Station.Description.Add(FText::FromString("The head shuttles +-400 cm on X every 2 s. The large cube trails the move and catches up at each end."));
            }
            else
            {
                Station.Title = FText::FromString("COMPARE - DEFAULT / HEAVY / DISABLED");
                Station.Description.Add(FText::FromString("Turn and shuttle together. Left: default spec. Middle: heavy (slower springs, less damping, double gains). Right: disabled."));
                Station.Description.Add(FText::FromString("The disabled cube must stay rigid on the head. O draws each sway's offset readout (red = disabled)."));
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
        if (_ResetPending)
        {
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
                _Fixtures.Add(FCkSwayGym_Fixture());
                if (_Fixtures[Index].Create(EntityOwner, this, Get_Origin(Index), Index) == false)
                {
                    _CreateError = "A station failed composition; inspect the ensure log.";
                }
            }
            _ResetPending = false;
            Request_Frame(0);
        }
        for (auto Index = 0; Index < _Fixtures.Num(); Index++)
        {
            _Fixtures[Index].Draw();
        }
    }

    UFUNCTION()
    private void OnSwayGymCubeAdded(FCk_Handle_UnrealComponent InHandle)
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
        Rows.Add(CkGym_Control::Header("SWAY"));
        Rows.Add(CkGym_Control::Status("State", _CreateError.IsEmpty() ? "Watch each cube against the head" : _CreateError, _ResetPending));
        if (_Fixtures.Num() == 3 && _ResetPending == false)
        {
            for (auto Index = 0; Index < 3; Index++)
            {
                if (_Fixtures[Index].Sways.Num() > 0 && ck::IsValid(_Fixtures[Index].Sways[0]))
                {
                    const auto Sway = _Fixtures[Index].Sways[0];
                    const auto Yaw = utils_sway::Get_RotationOffset(Sway).Yaw;
                    const auto X = utils_sway::Get_LocationOffset(Sway).X;
                    const auto Settled = utils_sway::Get_IsSettled(Sway) ? "settled" : "moving";
                    Rows.Add(CkGym_Control::Status(Get_StationTag(Index), f"yaw {Yaw :.2} deg, x {X :.2} cm, {Settled}"));
                }
            }
        }
        Rows.Add(CkGym_Control::Action(EKeys::One, "1", "View Turntable"));
        Rows.Add(CkGym_Control::Action(EKeys::Two, "2", "View Shuttle"));
        Rows.Add(CkGym_Control::Action(EKeys::Three, "3", "View Compare"));
        Rows.Add(CkGym_Control::Action(EKeys::X, "X", "Reset all stations"));
        Rows.Add(CkGym_Control::Toggle(EKeys::O, "O", "Draw sway offsets (ck.Sway.DrawOffsets)", UCk_Utils_Sway_DebugSettings_UE::Get_DrawOffsets()));
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
        auto DrawCVarName = n"ck.Sway.DrawOffsets";
        if (UCk_Utils_AutoTest_UE::Get_CVarExists(DrawCVarName) == false)
        {
            ck::Error("Sway gym diagnostics are unavailable; the debug settings must be loaded.");
            return;
        }
        auto Enabled = !UCk_Utils_Sway_DebugSettings_UE::Get_DrawOffsets();
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
        auto Target = _Fixtures[InIndex].Origin;
        auto Eye = Target + FVector(-700.0, -900.0, 450.0);
        Pawn.SetActorLocation(Eye);
        SetControlRotation((Target - Eye).Rotation());
    }

    UFUNCTION(Exec)
    void Ck_Sway_Control(int32 InRowIndex)
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
            UCk_Utils_AutoTest_UE::Request_PopCVarOverride(n"ck.Sway.DrawOffsets");
        }
    }
}
