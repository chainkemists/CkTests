// Language=angelscript

class ACk_GaitGym_PlayerController : ACk_Gym_Base_PlayerController
{
    private FCkGaitGym_Fixture _Fixture;
    private bool _Started = false;
    private bool _ResetPending = false;
    private bool _Composed = false;
    private bool _DrawOverridden = false;
    private FString _CreateError;

    FString Get_StationTag() const
    {
        return "Gym.CkGait.Walker";
    }

    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();
        auto Station = FCkGym_Station_SpawnParams_Payload();
        Station.Tags.Add(FName(Get_StationTag()));
        Station.Transform = FTransform(FVector(100.0, 0.0, 0.0));
        Station.AutoSize = true;
        Station.Title = FText::FromString("WALKER - GAIT-DRIVEN BOB");
        Station.Description.Add(FText::FromString("A treadmill walker reports +X / -X at 420 cm/s (3 s each) and hops every 7 s. One Gait drives every cube."));
        Station.Description.Add(FText::FromString("Left cube: raw bob (dip, sway, roll, pitch). Right cube: rigid twin. Top cube: the same bob with first-order lag (14/s)."));
        Station.Description.Add(FText::FromString("Watch the dip at each footfall, the lift while falling and the spring kick on landing. O draws each bob's axes, its rest-to-node line and the gait readout."));
        Stations.Add(Station);
        return Stations;
    }

    void Request_StartGym() override
    {
        _Started = true;
        Request_ResetAll();
    }

    void Request_ResetAll()
    {
        _Fixture.Request_Destroy();
        _ResetPending = true;
        _Composed = false;
        _CreateError = "";
    }

    FVector Get_Origin()
    {
        return Get_StationAnchorLocation(Get_StationTag(), ECk_GymStation_Anchor::FootprintCenter)
            + FVector(1300.0, 0.0, 150.0);
    }

    UFUNCTION(BlueprintOverride)
    void Tick(float InDeltaSeconds)
    {
        if (_Started == false || _ResetPending == false)
        {
            return;
        }

        if (ck::IsValid(_Fixture.Walker) || ck::Is_NOT_Valid(GetControlledPawn()))
        {
            return;
        }

        _ResetPending = false;
        _Fixture = FCkGaitGym_Fixture();
        if (_Fixture.Spawn(Get_Origin()) == false)
        {
            _CreateError = "The walker failed to spawn.";
            return;
        }

        utils_pending_entity_script::Promise_OnConstructed(_Fixture.Walker.PendingEntity,
            FCk_Delegate_EntityScript_Constructed(this, n"OnWalkerReady"));
        Request_Frame();
    }

    UFUNCTION()
    private void OnWalkerReady(FCk_Handle_EntityScript InEntityScript)
    {
        if (_Fixture.Compose(this, InEntityScript) == false)
        {
            _CreateError = "The station failed composition; inspect the ensure log.";
            return;
        }

        _Composed = true;
    }

    UFUNCTION()
    private void OnGaitGymCubeAdded(FCk_Handle_UnrealComponent InHandle)
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
        Rows.Add(CkGym_Control::Header("GAIT"));
        Rows.Add(CkGym_Control::Status("State", _CreateError.IsEmpty() ? "Watch the bobbed cubes against the rigid twin" : _CreateError, _ResetPending));
        if (_Composed && ck::IsValid(_Fixture.Gait))
        {
            const auto Gait = _Fixture.Gait;
            const auto Phase = utils_gait::Get_Phase(Gait);
            const auto Amount = utils_gait::Get_Amount(Gait);
            const auto Landings = utils_gait::Get_LandingCount(Gait);
            Rows.Add(CkGym_Control::Status(Get_StationTag(), f"phase {Phase :.2}, amount {Amount :.2}, landings {Landings}"));
        }

        Rows.Add(CkGym_Control::Action(EKeys::One, "1", "View Walker"));
        Rows.Add(CkGym_Control::Action(EKeys::X, "X", "Reset the station"));
        Rows.Add(CkGym_Control::Toggle(EKeys::O, "O", "Draw bobs (ck.Gait.DrawBobs)", UCk_Utils_Gait_DebugSettings_UE::Get_DrawBobs()));
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

        if (Key == EKeys::One)
        {
            Request_Frame();
        }
    }

    void Request_ToggleDraw()
    {
        auto DrawCVarName = n"ck.Gait.DrawBobs";
        if (UCk_Utils_AutoTest_UE::Get_CVarExists(DrawCVarName) == false)
        {
            ck::Error("Gait gym diagnostics are unavailable; the debug settings must be loaded.");
            return;
        }

        auto Enabled = !UCk_Utils_Gait_DebugSettings_UE::Get_DrawBobs();
        if (_DrawOverridden)
        {
            UCk_Utils_AutoTest_UE::Request_PopCVarOverride(DrawCVarName);
        }

        UCk_Utils_AutoTest_UE::Request_PushCVarOverride(DrawCVarName, Enabled ? "1" : "0");
        _DrawOverridden = true;
    }

    void Request_Frame()
    {
        auto Pawn = GetControlledPawn();
        if (ck::Is_NOT_Valid(Pawn))
        {
            return;
        }

        auto Target = _Fixture.Origin + FVector(0.0, 0.0, 80.0);
        auto Eye = Target + FVector(-300.0, -400.0, 150.0);
        Pawn.SetActorLocation(Eye);
        SetControlRotation((Target - Eye).Rotation());
    }

    UFUNCTION(Exec)
    void Ck_Gait_Control(int32 InRowIndex)
    {
        Request_ControlActivated(InRowIndex);
    }

    UFUNCTION(BlueprintOverride)
    void EndPlay(EEndPlayReason InReason)
    {
        _Fixture.Request_Destroy();
        if (_DrawOverridden)
        {
            UCk_Utils_AutoTest_UE::Request_PopCVarOverride(n"ck.Gait.DrawBobs");
        }
    }
}
