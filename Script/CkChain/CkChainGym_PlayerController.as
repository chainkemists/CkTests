// Language=angelscript

class ACk_ChainGym_PlayerController : ACk_Gym_Base_PlayerController
{
    private TArray<FCkChainGym_Fixture> _Fixtures;
    private bool _Started = false;
    private bool _ResetPending = false;
    private bool _TrainResetPending = false;
    private bool _HistoryOverridden = false;
    private bool _TargetsOverridden = false;
    private float32 _Spacing = 10.0f;
    private FString _CreateError;

    FString Get_StationTag(int32 InIndex) const
    {
        if (InIndex == 0)
        {
            return "Gym.CkChain.Train";
        }
        if (InIndex == 1)
        {
            return "Gym.CkChain.Rope";
        }
        if (InIndex == 2)
        {
            return "Gym.CkChain.Held";
        }
        return "Gym.CkChain.WagonsWithChildren";
    }

    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();
        for (auto Index = 0; Index < 4; Index++)
        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(FName(Get_StationTag(Index)));
            Station.Transform = FTransform(FVector(100.0 + 3600.0 * (Index % 2), 3000.0 * Math::IntegerDivisionTrunc(Index, 2), 0.0));
            Station.AutoSize = true;
            if (Index == 0)
            {
                Station.Title = FText::FromString("TRAIN - PATH HISTORY");
                Station.Description.Add(FText::FromString("Eight cube links at 60 cm follow a figure-eight spline tween."));
                Station.Description.Add(FText::FromString("F5/F6/F7: sample spacing 4/10/25 cm. T: pause and teleport. K: split at wagon four. R: reseed."));
            }
            else if (Index == 1)
            {
                Station.Title = FText::FromString("ROPE - DISTANCE CONSTRAINT");
                Station.Description.Add(FText::FromString("Twelve links at 60 cm keep their segment lengths behind a head on the Train's figure-eight; corners are cut, not traced."));
                Station.Description.Add(FText::FromString("P: the head chases the pawn instead. Walk the pawn along the floor and drag the rope."));
            }
            else if (Index == 2)
            {
                Station.Title = FText::FromString("HELD - WAIT FOR COVERAGE");
                Station.Description.Add(FText::FromString("Authored link poses remain still until the head records enough path. G starts the idle head."));
            }
            else
            {
                Station.Title = FText::FromString("WAGONS WITH CHILDREN");
                Station.Description.Add(FText::FromString("Yellow lamp markers are real SceneNode children 65 cm above each moving wagon. Watch for a frame of lag."));
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
        _TrainResetPending = false;
        _CreateError = "";
    }

    // The alcove opens toward +X, so the loop sits on the open side with the back wall as its backdrop.
    FVector Get_Origin(int32 InIndex)
    {
        return Get_StationAnchorLocation(Get_StationTag(InIndex), ECk_GymStation_Anchor::FootprintCenter)
            + FVector(1300.0, 0.0, 100.0);
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
            auto Pawn = GetControlledPawn();
            if (ck::Is_NOT_Valid(EntityOwner) || ck::Is_NOT_Valid(Pawn))
            {
                return;
            }
            auto PawnEntity = ck::ToEntity(Pawn);
            if (utils_transform::Has(PawnEntity) == false)
            {
                return;
            }
            _Fixtures.Reset();
            for (auto Index = 0; Index < 4; Index++)
            {
                _Fixtures.Add(FCkChainGym_Fixture());
                if (_Fixtures[Index].Create(EntityOwner, Get_Origin(Index), Index, _Spacing) == false)
                {
                    _CreateError = "A station failed composition; inspect the ensure log.";
                }
            }
            _ResetPending = false;
            Request_Frame(0);
        }
        if (_TrainResetPending && ck::Is_NOT_Valid(_Fixtures[0].Root))
        {
            auto EntityOwner = ck::ToEntity(this);
            if (_Fixtures[0].Create(EntityOwner, Get_Origin(0), 0, _Spacing) == false)
            {
                _CreateError = "Train failed composition; inspect the ensure log.";
            }
            _TrainResetPending = false;
        }
        for (auto Index = 0; Index < _Fixtures.Num(); Index++)
        {
            _Fixtures[Index].Draw();
        }
    }

    TArray<FCkGym_ControlRow> Get_ControlRows() override
    {
        auto Rows = TArray<FCkGym_ControlRow>();
        Rows.Add(CkGym_Control::Header("CHAIN"));
        Rows.Add(CkGym_Control::Status("State", _CreateError.IsEmpty() ? "Use controls to compare motion" : _CreateError, _ResetPending || _TrainResetPending));
        Rows.Add(CkGym_Control::Status("Train sample spacing", f"{_Spacing} cm"));
        if (_Fixtures.Num() == 4 && _ResetPending == false)
        {
            for (auto Index = 0; Index < 4; Index++)
            {
                if (ck::IsValid(_Fixtures[Index].Chain))
                {
                    auto NumLinks = utils_chain::Get_NumLinks(_Fixtures[Index].Chain);
                    auto NumSamples = utils_chain::Get_NumHistorySamples(_Fixtures[Index].Chain);
                    Rows.Add(CkGym_Control::Status(Get_StationTag(Index), f"{NumLinks} links; {NumSamples} history samples"));
                }
            }
        }
        Rows.Add(CkGym_Control::Action(EKeys::One, "1", "View Train"));
        Rows.Add(CkGym_Control::Action(EKeys::Two, "2", "View Rope"));
        Rows.Add(CkGym_Control::Action(EKeys::Three, "3", "View Held"));
        Rows.Add(CkGym_Control::Action(EKeys::Four, "4", "View Wagons with children"));
        Rows.Add(CkGym_Control::Action(EKeys::F5, "F5", "Train spacing 4 cm"));
        Rows.Add(CkGym_Control::Action(EKeys::F6, "F6", "Train spacing 10 cm"));
        Rows.Add(CkGym_Control::Action(EKeys::F7, "F7", "Train spacing 25 cm"));
        Rows.Add(CkGym_Control::Action(EKeys::T, "T", "Pause and teleport Train head", _ResetPending == false && _TrainResetPending == false));
        Rows.Add(CkGym_Control::Action(EKeys::K, "K", "Split at Train wagon four", _ResetPending == false && _TrainResetPending == false));
        Rows.Add(CkGym_Control::Action(EKeys::R, "R", "Reseed Train history", _ResetPending == false && _TrainResetPending == false));
        Rows.Add(CkGym_Control::Action(EKeys::G, "G", "Go: start Held head", _ResetPending == false));
        Rows.Add(CkGym_Control::Toggle(EKeys::P, "P", "Rope head chases the pawn",
            _Fixtures.Num() == 4 && _Fixtures[1].FollowingPawn, false, _ResetPending == false));
        Rows.Add(CkGym_Control::Action(EKeys::X, "X", "Reset all stations"));
        Rows.Add(CkGym_Control::Toggle(EKeys::B, "B", "History polyline", UCk_Utils_Chain_DebugSettings_UE::Get_DrawHistory()));
        Rows.Add(CkGym_Control::Toggle(EKeys::J, "J", "Link targets", UCk_Utils_Chain_DebugSettings_UE::Get_DrawLinkTargets()));
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
        if (Key == EKeys::B || Key == EKeys::J)
        {
            Request_ToggleDraw(Key == EKeys::B);
            return;
        }
        if (_ResetPending || _Fixtures.Num() != 4 || _CreateError.IsEmpty() == false)
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
        else if (Key == EKeys::Four)
        {
            Request_Frame(3);
        }
        else if (Key == EKeys::F5 || Key == EKeys::F6 || Key == EKeys::F7)
        {
            _Spacing = Key == EKeys::F5 ? 4.0f : (Key == EKeys::F6 ? 10.0f : 25.0f);
            _Fixtures[0].Request_Destroy();
            _TrainResetPending = true;
        }
        else if (Key == EKeys::G)
        {
            _Fixtures[2].Request_StartTravel();
        }
        else if (Key == EKeys::P)
        {
            auto Pawn = GetControlledPawn();
            if (ck::IsValid(Pawn))
            {
                auto PawnEntity = ck::ToEntity(Pawn);
                if (utils_transform::Has(PawnEntity))
                {
                    _Fixtures[1].Request_TogglePawnFollow(PawnEntity.As_Transform());
                }
            }
        }
        else if (_TrainResetPending == false)
        {
            if (Key == EKeys::T)
            {
                _Fixtures[0].Request_Teleport();
            }
            else if (Key == EKeys::K)
            {
                _Fixtures[0].Request_SplitAtFour();
            }
            else if (Key == EKeys::R)
            {
                utils_chain::Request_ReseedHistory(_Fixtures[0].Chain, FCk_Request_Chain_ReseedHistory());
            }
        }
    }

    void Request_ToggleDraw(bool InHistory)
    {
        auto DrawCVarName = InHistory ? n"ck.Chain.DrawHistory" : n"ck.Chain.DrawLinkTargets";
        if (UCk_Utils_AutoTest_UE::Get_CVarExists(DrawCVarName) == false)
        {
            ck::Error("Chain gym diagnostics are unavailable; the debug settings must be loaded.");
            return;
        }
        if (InHistory)
        {
            auto Enabled = !UCk_Utils_Chain_DebugSettings_UE::Get_DrawHistory();
            if (_HistoryOverridden)
            {
                UCk_Utils_AutoTest_UE::Request_PopCVarOverride(DrawCVarName);
            }
            UCk_Utils_AutoTest_UE::Request_PushCVarOverride(DrawCVarName, Enabled ? "1" : "0");
            _HistoryOverridden = true;
        }
        else
        {
            auto Enabled = !UCk_Utils_Chain_DebugSettings_UE::Get_DrawLinkTargets();
            if (_TargetsOverridden)
            {
                UCk_Utils_AutoTest_UE::Request_PopCVarOverride(DrawCVarName);
            }
            UCk_Utils_AutoTest_UE::Request_PushCVarOverride(DrawCVarName, Enabled ? "1" : "0");
            _TargetsOverridden = true;
        }
    }

    void Request_Frame(int32 InIndex)
    {
        auto Pawn = GetControlledPawn();
        if (ck::Is_NOT_Valid(Pawn) || _Fixtures.IsValidIndex(InIndex) == false)
        {
            return;
        }
        auto Target = _Fixtures[InIndex].Origin;
        auto Eye = Target + FVector(1500.0, -1700.0, 1400.0);
        Pawn.SetActorLocation(Eye);
        SetControlRotation((Target - Eye).Rotation());
    }

    UFUNCTION(Exec)
    void Ck_Chain_Control(int32 InRowIndex)
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
        if (_HistoryOverridden)
        {
            UCk_Utils_AutoTest_UE::Request_PopCVarOverride(n"ck.Chain.DrawHistory");
        }
        if (_TargetsOverridden)
        {
            UCk_Utils_AutoTest_UE::Request_PopCVarOverride(n"ck.Chain.DrawLinkTargets");
        }
    }
}
