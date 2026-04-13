// Language=angelscript

//============================================================================
// GYM AUTO-STATION — REUSABLE AUTO-MODE INFRASTRUCTURE
//============================================================================
//
// Provides shared helpers for gyms that auto-cycle through operations.
// Each station entity script owns its own AutoTimer/AutoRunning/AutoStep
// members and calls these helpers from DoConstruct and DisplayStats.
//
// See CkGym_CreationSpecification.txt sections 12-13 for usage patterns.
// See CkInventoryGym_DataOnly_Unbounded.as for a reference implementation.
//
//============================================================================

//============================================================================
// MESSAGE — used by all gyms for auto on/off
//============================================================================

USTRUCT()
struct FCk_Message_Gym_AutoSet
{
    UPROPERTY()
    bool Enabled;

    FCk_Message_Gym_AutoSet(bool InEnabled = true)
    {
        Enabled = InEnabled;
    }
}

//============================================================================
// AUTO STEP DEFINITION
//============================================================================

USTRUCT()
struct FCkGym_AutoStep
{
    UPROPERTY()
    FString Description;

    UPROPERTY()
    int32 FirstIndex;

    UPROPERTY()
    int32 LastIndex;

    FCkGym_AutoStep(FString InDescription = "", int32 InFirstIndex = 0, int32 InLastIndex = 0)
    {
        Description = InDescription;
        FirstIndex = InFirstIndex;
        LastIndex = InLastIndex;
    }
}

//============================================================================
// AUTO CONFIG — declarative station configuration
//============================================================================

USTRUCT()
struct FCkGym_AutoConfig
{
    UPROPERTY()
    int32 TotalSteps = 1;

    UPROPERTY()
    TArray<FCkGym_AutoStep> Steps;

    UPROPERTY()
    TArray<FString> ManualCommands;

    UPROPERTY()
    FString PerStationAutoCommand;

    UPROPERTY()
    FString GlobalAutoCommand;

    UPROPERTY()
    FString Description;
}

//============================================================================
// NAMESPACE — setup, stop, and display helpers
//============================================================================

namespace gym_auto
{
    //------------------------------------------------------------------------
    // Station height normalization — call after building all stations in
    // Get_RequiredStations(). Sets every station to the tallest height
    // so that all displays in a gym are the same size.
    //------------------------------------------------------------------------

    void NormalizeStationHeights(TArray<FCkGym_Station_SpawnParams_Payload>& InStations)
    {
        auto MaxHeight = 0.0f;
        for (auto& Station : InStations)
        {
            if (Station.Height > MaxHeight) { MaxHeight = Station.Height; }
        }
        for (auto& Station : InStations)
        {
            Station.Height = MaxHeight;
        }
    }

    //------------------------------------------------------------------------
    // Setup — call from DoConstruct. Creates timer + binds AutoSet message.
    // The caller must still define OnAutoSet and AutoTick as UFUNCTIONs
    // on their class (delegates need a UObject target).
    //------------------------------------------------------------------------

    FCk_Handle_Timer Setup(
        FCk_Handle& InHandle,
        UObject InTarget,
        FCk_Time InInterval = FCk_Time(0.5f),
        FName InAutoTickName = n"AutoTick",
        FName InAutoSetName = n"OnAutoSet")
    {
        auto TimerParams = FCk_Fragment_Timer_ParamsData(InInterval);
        TimerParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        auto Timer = utils_timer::Add(InHandle, TimerParams);
        Timer.BindTo_OnDone(FCk_Delegate_Timer(InTarget, InAutoTickName));

        utils_messaging::BindTo_OnBroadcast(
            InHandle,
            FCk_Message_Gym_AutoSet,
            FCk_Delegate_Messaging_OnBroadcast(InTarget, InAutoSetName));

        return Timer;
    }

    //------------------------------------------------------------------------
    // StopAuto — call from manual message handlers.
    //------------------------------------------------------------------------

    void StopAuto(FCk_Handle_Timer InTimer, bool& InAutoRunning)
    {
        if (InAutoRunning)
        {
            InAutoRunning = false;
            utils_timer::Request_Pause(InTimer);
        }
    }

    //------------------------------------------------------------------------
    // HandleAutoSet — call from OnAutoSet UFUNCTION.
    //------------------------------------------------------------------------

    void HandleAutoSet(FInstancedStruct InPayload, FCk_Handle_Timer InTimer, bool& InAutoRunning)
    {
        auto Typed = InPayload.Get(FCk_Message_Gym_AutoSet);
        InAutoRunning = Typed.Enabled;
        if (InAutoRunning) { utils_timer::Request_Resume(InTimer); }
        else { utils_timer::Request_Pause(InTimer); }
    }

    //------------------------------------------------------------------------
    // Station height estimation
    //------------------------------------------------------------------------

    // Estimates station height from AutoConfig + expected live-data lines.
    // Call from Get_RequiredStations() to avoid hand-tuning heights.
    //   InLiveDataLines: how many lines of station-specific data you expect
    //   InLineHeight: world units per text line (tweak if text scale changes)
    float EstimateStationHeight(const FCkGym_AutoConfig& InConfig, int32 InLiveDataLines = 10, float InLineHeight = 0.35f)
    {
        auto Lines = 2;  // status line + blank
        if (InConfig.Description != "") { Lines += 2; }  // description + blank
        Lines += InLiveDataLines;
        Lines += 1 + InConfig.Steps.Num();  // "===== Auto Sequence =====" + steps
        Lines += 2 + InConfig.ManualCommands.Num();  // "===== Commands =====" + commands + global
        if (InConfig.PerStationAutoCommand != "") { Lines += 1; }
        return float(Lines) * InLineHeight;
    }

    // Lightweight overload when you don't have the config handy (e.g. in PlayerController).
    //   InAutoStepCount: number of step descriptions
    //   InCommandCount: number of manual commands
    //   InLiveDataLines: how many lines of station-specific data
    //   InHasDescription: whether the station has a description block
    float EstimateStationHeight(int32 InAutoStepCount, int32 InCommandCount, int32 InLiveDataLines = 10, bool InHasDescription = true, float InLineHeight = 0.35f)
    {
        auto Lines = 2;
        if (InHasDescription) { Lines += 2; }
        Lines += InLiveDataLines;
        Lines += 1 + InAutoStepCount;
        Lines += 3 + InCommandCount;  // header + commands + global + per-station
        return float(Lines) * InLineHeight;
    }

    //------------------------------------------------------------------------
    // Display helpers
    //------------------------------------------------------------------------

    FString StatusLine(bool InAutoRunning)
    {
        return InAutoRunning ? "[AUTO] Running" : "[MANUAL]";
    }

    FString FormatHeader(const FCkGym_AutoConfig& InConfig, bool InAutoRunning)
    {
        auto Text = f"{StatusLine(InAutoRunning)}\n";
        if (InConfig.Description != "")
        {
            Text = f"{Text}{InConfig.Description}\n\n";
        }
        return Text;
    }

    FString FormatAutoSequence(const FCkGym_AutoConfig& InConfig, int32 InAutoStep, bool InAutoRunning)
    {
        auto Text = "===== Auto Sequence =====\n";
        auto CurrentStep = InAutoStep % InConfig.TotalSteps;

        for (auto i = 0; i < InConfig.Steps.Num(); i++)
        {
            auto IsActive = InAutoRunning
                && CurrentStep >= InConfig.Steps[i].FirstIndex
                && CurrentStep <= InConfig.Steps[i].LastIndex;
            auto Prefix = IsActive ? ">> " : "   ";
            Text = f"{Text}{Prefix}{InConfig.Steps[i].Description}\n";
        }

        return Text;
    }

    FString FormatCommands(const FCkGym_AutoConfig& InConfig)
    {
        auto Text = "\n===== Commands =====\n";

        for (auto Cmd : InConfig.ManualCommands)
        {
            Text = f"{Text}{Cmd}\n";
        }

        auto GlobalCmd = InConfig.GlobalAutoCommand != "" ? InConfig.GlobalAutoCommand : "Ck_Gym*_Auto [0/1]";
        Text = f"{Text}\n{GlobalCmd}\n";
        if (InConfig.PerStationAutoCommand != "")
        {
            Text = f"{Text}{InConfig.PerStationAutoCommand}";
        }

        return Text;
    }

    FString FormatAutoAndCommands(const FCkGym_AutoConfig& InConfig, int32 InAutoStep, bool InAutoRunning)
    {
        return FormatAutoSequence(InConfig, InAutoStep, InAutoRunning)
            + FormatCommands(InConfig);
    }
}
