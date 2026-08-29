// Language=angelscript

//============================================================================
// GYM AUTO-STATION - REUSABLE AUTO-MODE INFRASTRUCTURE
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
// MESSAGE - used by all gyms for auto on/off
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
// AUTO CONFIG - declarative station configuration
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
// NAMESPACE - setup, stop, and display helpers
//============================================================================

namespace gym_auto
{
    //------------------------------------------------------------------------
    // Setup - call from DoConstruct. Creates timer + binds AutoSet message.
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
    // StopAuto - call from manual message handlers.
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
    // HandleAutoSet - call from OnAutoSet UFUNCTION.
    //------------------------------------------------------------------------

    void HandleAutoSet(FInstancedStruct InPayload, FCk_Handle_Timer InTimer, bool& InAutoRunning)
    {
        auto Typed = InPayload.Get(FCk_Message_Gym_AutoSet);
        InAutoRunning = Typed.Enabled;
        if (InAutoRunning) { utils_timer::Request_Resume(InTimer); }
        else { utils_timer::Request_Pause(InTimer); }
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

        auto GlobalCmd = InConfig.GlobalAutoCommand != "" ? InConfig.GlobalAutoCommand : "the gym's panel auto row";
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
