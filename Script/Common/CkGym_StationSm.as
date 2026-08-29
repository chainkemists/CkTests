// Language=angelscript

//============================================================================
// GYM STATION STATE MACHINE - HFSM-DRIVEN STEP SEQUENCES
//============================================================================
//
// Replaces the `AutoStep % TotalSteps` + if-else dispatch that gym stations
// used to drive their demo sequences with a real CkStateMachine graph: one
// state class per step, transitions gated by dwell conditions.
//
// Why. The integer-and-if-else shape is the exact anti-pattern CkStateMachine
// exists to remove ("Don't encode state transition logic in raw if-else chains
// in a Processor" - the CkStateMachine docs). It also made the step list a
// LIE: FCkGym_AutoStep carried Description/FirstIndex/LastIndex purely for the
// HUD while the real control flow lived in a modulo, so the two drifted freely.
// Under an SM the HUD reads the live current state, so what is displayed is
// what is running, and the SM debugger's graph walk can inspect a station the
// same way it inspects any other state machine.
//
//----------------------------------------------------------------------------
// AUTHORING A STATION SEQUENCE
//----------------------------------------------------------------------------
//
//   UCLASS()
//   class UCk_IntegerGym_Step_AddWeapon : UCk_Gym_StepState
//   {
//       UFUNCTION(BlueprintOverride)
//       void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
//       {
//           auto Trans = AddTransition(InHandle, UCk_IntegerGym_Step_AddBuff);
//           AddCondition(Trans, UCk_Gym_Dwell_Default);
//       }
//
//       UFUNCTION(BlueprintOverride)
//       void DoEnterState(FCk_Handle_SmState InHandle, ECk_Sm_NetContext InNetContext)
//       {
//           auto Station = Get_StationEntity();
//           // ... act on the station entity through utils_* ...
//       }
//   }
//
// The last step transitions back to the first, closing the cycle.
//
// NOTE ON STATE-OWNED DATA. A step state is its own entity script, so it must
// NOT reach into the station script's members. Read and write the station
// ENTITY through utils_* instead (Get_StationEntity() is the context owner).
// That is a feature, not a tax: it removes the script-member coupling the
// old stations had and makes each step independently inspectable.
//
// DETERMINISM. DoDefineState output is structurally hashed and must be
// identical across machines (the CkStateMachine docs, "DefineState
// determinism"). Gyms are local-only, but keep DefineState free of
// conditionals anyway - divergence faults the SM outright rather than
// degrading.
//
//============================================================================

//============================================================================
// DWELL CONDITIONS - how long a step holds before advancing
//============================================================================
//
// WHY NOT UCk_SmCondition_Timer. The framework's timer condition adds a plain
// CkTimer on the condition entity and MarkSatisfied()s from its OnDone
// (CkSmCondition_Timer.cpp:18-27). That timer ticks with the game and never
// consults the owning SM's run status - so while the SM is paused the dwell
// still elapses, the condition latches Pass, and the moment the station is
// un-paused the transition fires immediately. For a demo station whose auto
// toggle IS an SM pause, that makes pause look broken: you pause to study a
// step, and it advances the instant you resume.
//
// This mirrors UCk_SmTest_Condition_AfterDelay instead - the in-tree pattern
// that re-arms while the owner is paused. A dwell interrupted by a pause is
// re-armed in full on the pause check, so resuming gives the step a fresh
// dwell rather than an instant jump.

UCLASS()
class UCk_Gym_Dwell : UCk_SmCondition_EventDriven
{
    // Seconds the step holds before advancing. 2.5 matches the interval
    // gym_auto::Setup used, so a migrated station demos at the pace viewers
    // are used to. Subclass with a different default for a different dwell.
    UPROPERTY(EditAnywhere)
    float32 DwellSeconds = 2.5f;

    UFUNCTION(BlueprintOverride)
    void DoEnterCondition(FCk_Handle_SmCondition InHandle, ECk_Sm_NetContext InNetContext)
    {
        auto _CkPerfScope = ck::ScopedStat();
        System::SetTimer(this, n"TryAdvance", DwellSeconds, false);
    }

    UFUNCTION()
    private void TryAdvance()
    {
        auto OwnerSm = Get_OwningStateMachine();
        if (ck::Is_NOT_Valid(OwnerSm)) { return; }

        if (OwnerSm.Get_RunStatus() == ECk_SmRunStatus::Paused)
        {
            // Re-arm the FULL dwell, not the recheck interval: the step should
            // get a whole turn on screen once the viewer resumes.
            System::SetTimer(this, n"TryAdvance", DwellSeconds, false);
            return;
        }

        MarkSatisfied();
    }
}

UCLASS()
class UCk_Gym_Dwell_Short : UCk_Gym_Dwell
{
    default DwellSeconds = 1.0f;
}

UCLASS()
class UCk_Gym_Dwell_Long : UCk_Gym_Dwell
{
    default DwellSeconds = 5.0f;
}

//============================================================================
// STEP STATE BASE
//============================================================================

UCLASS()
class UCk_Gym_StepState : UCk_SmState_EntityScript
{
    // The gym station entity this step is running against - the SM's context
    // owner. Everything a step touches goes through this handle and utils_*,
    // never through the station script object.
    FCk_Handle Get_StationEntity() const
    {
        return Get_StateMachineContext();
    }
}

//============================================================================
// DISPLAY CONFIG - the HUD's view of the sequence
//============================================================================

// One row on the station panel, bound to the state class that IS that step.
// Highlighting compares against the SM's live current state, so the panel
// cannot drift from what is actually running.
USTRUCT()
struct FCkGym_SmStep
{
    UPROPERTY() TSubclassOf<UCk_SmState_EntityScript> StateClass;
    UPROPERTY() FString Description;

    FCkGym_SmStep(TSubclassOf<UCk_SmState_EntityScript> InStateClass = nullptr, FString InDescription = "")
    {
        StateClass = InStateClass;
        Description = InDescription;
    }
}

USTRUCT()
struct FCkGym_SmConfig
{
    UPROPERTY() TArray<FCkGym_SmStep> Steps;
    UPROPERTY() TArray<FString> ManualCommands;
    UPROPERTY() FString PerStationAutoCommand;
    UPROPERTY() FString GlobalAutoCommand;
    UPROPERTY() FString Description;
}

//============================================================================
// NAMESPACE - setup, auto toggle, display
//============================================================================

namespace gym_sm
{
    //------------------------------------------------------------------------
    // Setup - call from DoConstruct. Adds the state machine to the station
    // entity; it auto-starts on setup, so the first step enters on its own.
    //------------------------------------------------------------------------

    FCk_Handle_StateMachine Setup(
        FCk_Handle& InStationEntity,
        TSubclassOf<UCk_SmState_EntityScript> InInitialStateClass)
    {
        // _Replication already defaults to DoesNotReplicate, which is what a
        // local demo station wants.
        auto Params = FCk_Fragment_StateMachine_ParamsData(InInitialStateClass);
        return utils_state_machine::Add(InStationEntity, Params);
    }

    //------------------------------------------------------------------------
    // Auto on/off - the gym's panel auto row. Pausing the SM freezes it
    // in the current step (dwell conditions stop advancing) rather than
    // tearing the graph down, so resuming continues the demo where it stopped.
    //------------------------------------------------------------------------

    void Request_SetAutoRunning(FCk_Handle_StateMachine InSm, bool InRunning)
    {
        if (ck::Is_NOT_Valid(InSm)) { return; }

        if (InRunning) { utils_state_machine::Request_Resume(InSm); }
        else { utils_state_machine::Request_Pause(InSm); }
    }

    // Drop-in replacements for the gym_auto pair every station calls, so a
    // migrating station swaps the namespace and the timer handle for the SM
    // handle rather than hand-rolling payload parsing 36 times.
    //
    // StopAuto - call from a manual message handler: a viewer poking a manual
    // command means they want the demo to hold still.
    void StopAuto(FCk_Handle_StateMachine InSm)
    {
        Request_SetAutoRunning(InSm, false);
    }

    // HandleAutoSet - call from the station's OnAutoSet UFUNCTION. Mirrors
    // gym_auto::HandleAutoSet (CkGym_AutoStation.as:131): same
    // FCk_Message_Gym_AutoSet transport, so the gym's panel auto row
    // drives migrated and unmigrated stations identically.
    void HandleAutoSet(FInstancedStruct InPayload, FCk_Handle_StateMachine InSm)
    {
        auto Typed = InPayload.Get(FCk_Message_Gym_AutoSet);
        Request_SetAutoRunning(InSm, Typed.Enabled);
    }

    bool Get_IsAutoRunning(FCk_Handle_StateMachine InSm)
    {
        if (ck::Is_NOT_Valid(InSm)) { return false; }
        return utils_state_machine::Get_RunStatus(InSm) == ECk_SmRunStatus::Running;
    }

    // Jump straight to a step. Backs the per-station manual commands that used
    // to poke AutoStep directly.
    void Request_GoToStep(FCk_Handle_StateMachine InSm, TSubclassOf<UCk_SmState_EntityScript> InStateClass)
    {
        if (ck::Is_NOT_Valid(InSm)) { return; }
        utils_state_machine::Request_Transition(InSm, InStateClass);
    }

    //------------------------------------------------------------------------
    // Display helpers - drop-in replacements for the gym_auto formatters,
    // sourced from the SM's live state instead of an integer.
    //------------------------------------------------------------------------

    FString StatusLine(FCk_Handle_StateMachine InSm)
    {
        return Get_IsAutoRunning(InSm) ? "[AUTO] Running" : "[PAUSED]";
    }

    FString FormatHeader(const FCkGym_SmConfig& InConfig, FCk_Handle_StateMachine InSm)
    {
        auto Text = f"{StatusLine(InSm)}\n";
        if (InConfig.Description != "")
        {
            Text = f"{Text}{InConfig.Description}\n\n";
        }
        return Text;
    }

    FString FormatAutoSequence(const FCkGym_SmConfig& InConfig, FCk_Handle_StateMachine InSm)
    {
        auto Text = "===== Step Sequence =====\n";

        auto HasCurrent = ck::IsValid(InSm);
        TSubclassOf<UCk_SmState_EntityScript> Current;
        if (HasCurrent)
        { Current = utils_state_machine::Get_CurrentStateClass(InSm); }

        for (auto i = 0; i < InConfig.Steps.Num(); i++)
        {
            auto IsActive = HasCurrent && InConfig.Steps[i].StateClass == Current;
            auto Prefix = IsActive ? ">> " : "   ";
            Text = f"{Text}{Prefix}{InConfig.Steps[i].Description}\n";
        }

        return Text;
    }

    FString FormatCommands(const FCkGym_SmConfig& InConfig)
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

    FString FormatAutoAndCommands(const FCkGym_SmConfig& InConfig, FCk_Handle_StateMachine InSm)
    {
        auto Sequence = FormatAutoSequence(InConfig, InSm);
        auto Commands = FormatCommands(InConfig);
        return f"{Sequence}{Commands}";
    }
}
