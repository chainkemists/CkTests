// Language=angelscript

//============================================================================
// CK INPUT KEY-BINDING GYM — CHANGE SIGNAL STATION
//
// The two ways to notice a rebind, side by side on one panel:
//   - PUSH: BindTo_OnMappingKeyChanged, one listener per row, each reporting
//     (MappingName, OldKey, NewKey) when that row actually moves.
//   - POLL: Get_DidMappingKeyChange against a cached key, re-checked each tick.
//
// ONE LISTENER PER ROW IS LOAD-BEARING, NOT TIDINESS. UnbindFrom_MappingKeyChanged
// matches on (MappingName, Slot) alone and removes EVERY listener on that pair
// (CkInput/CLAUDE.md anti-pattern 3), so a second listener on a row this station
// already watches would be silently killed by this station's own teardown.
//
// WHAT THIS PANEL ASSERTS: every watched row's listener has fired at least once.
// Nothing on this station synchronises with the demo's cycle — a row is either
// known to have fired or it is not, and that answer survives whatever the demo
// is doing at the moment you look. The demo on the Remap + Conflict station
// moves all four rows within one lap, so the header goes green on its own.
//
// This station never mutates the profile, so its DoEndPlay only unbinds.
//============================================================================

class UCk_EntityScript_InputGym_ChangeSignal : UCk_GenericEntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    UPROPERTY(ExposeOnSpawn)
    FString StationTitle;

    UPROPERTY(ExposeOnSpawn)
    FString StationDescription;

    private TArray<FCk_Handle_KeybindListener> _Listeners;
    private TArray<FKey> _PolledKeys;
    private TArray<int32> _FireCounts;

    private FString _LastDelegateEvent = "(nothing yet)";
    private FString _LastPolledEvent = "(nothing yet)";
    private int32 _PolledChangeCount = 0;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow
    DoConstruct(FCk_Handle& InHandle)
    {
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);
        utils_entity_tag::Add(InHandle, input_gym::k_Tag_ChangeSignal);
        utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"OnDisplayTick"));

        Request_BindListeners();

        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    UFUNCTION(BlueprintOverride)
    void DoEndPlay(FCk_Handle InHandle)
    {
        auto PlayerController = input_gym::Get_LocalPlayerController();
        if (ck::Is_NOT_Valid(PlayerController))
        { return; }

        for (auto Index = 0; Index < _Listeners.Num(); Index++)
        {
            utils_key_binding::UnbindFrom_OnMappingKeyChanged(PlayerController, _Listeners[Index]);
        }

        _Listeners.Empty();
    }

    private TArray<FName> Get_WatchedMappings()
    {
        auto Names = TArray<FName>();
        Names.Add(input_gym::k_Mapping_Jump);
        Names.Add(input_gym::k_Mapping_Crouch);
        Names.Add(input_gym::k_Mapping_Interact);
        Names.Add(input_gym::k_Mapping_Flashlight);
        return Names;
    }

    private void Request_BindListeners()
    {
        auto PlayerController = input_gym::Get_LocalPlayerController();
        if (ck::Is_NOT_Valid(PlayerController))
        { return; }

        auto OnChanged = FCk_OnMappingKeyChanged(this, n"OnMappingKeyChanged");
        auto Watched = Get_WatchedMappings();

        for (auto MappingName : Watched)
        {
            _Listeners.Add(utils_key_binding::BindTo_OnMappingKeyChanged(
                PlayerController, MappingName, EPlayerMappableKeySlot::First, OnChanged));

            _PolledKeys.Add(utils_key_binding::Get_KeyForMapping(
                PlayerController, MappingName, EPlayerMappableKeySlot::First));

            _FireCounts.Add(0);
        }
    }

    UFUNCTION()
    private void OnMappingKeyChanged(FName InMappingName, FKey InOldKey, FKey InNewKey)
    {
        _LastDelegateEvent = f"{InMappingName}: {input_gym::Format_Key(InOldKey)} -> {input_gym::Format_Key(InNewKey)}";

        auto Watched = Get_WatchedMappings();
        for (auto Index = 0; Index < Watched.Num(); Index++)
        {
            if (Watched[Index] != InMappingName)
            { continue; }

            if (Index < _FireCounts.Num())
            { _FireCounts[Index] = _FireCounts[Index] + 1; }
        }
    }

    UFUNCTION()
    private void OnDisplayTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        auto PlayerController = input_gym::Get_LocalPlayerController();
        if (ck::Is_NOT_Valid(PlayerController))
        { return; }

        // The listener subsystem hangs off the local player, so a construct that
        // ran before the PlayerController was reachable binds nothing. Retry
        // rather than leaving the station permanently deaf.
        if (_Listeners.Num() == 0)
        { Request_BindListeners(); }

        Request_PollForChanges(PlayerController);

        auto Lines = TArray<FCkGym_ColoredLine>();

        Add_HeaderVerdict(Lines);
        Add_PushRows(Lines, PlayerController);
        Add_PollBlock(Lines);

        CkGym_Common::Update_StationDisplay_Colored(
            ck::ToEntity(this), StationTitle, Lines, StationDescription);
    }

    private void Add_HeaderVerdict(TArray<FCkGym_ColoredLine>& OutLines)
    {
        auto FiredCount = Get_RowsEverFiredCount();
        auto Watched = Get_WatchedMappings();

        if (FiredCount == Watched.Num() && Watched.Num() > 0)
        {
            input_gym::Add_Line(OutLines, "  every row's change-listener has fired", gym_palette::Green);
        }
        else
        {
            input_gym::Add_Verdict(OutLines, "rows whose listener has fired", f"{Watched.Num()}", f"{FiredCount}");
        }

        input_gym::Add_Line(OutLines, f"  Listeners bound: {_Listeners.Num()} (one per row)", gym_palette::White);
    }

    private int32 Get_RowsEverFiredCount()
    {
        auto Count = 0;
        for (auto Index = 0; Index < _FireCounts.Num(); Index++)
        {
            if (_FireCounts[Index] > 0)
            { Count++; }
        }
        return Count;
    }

    private void Add_PushRows(TArray<FCkGym_ColoredLine>& OutLines, APlayerController InPlayerController)
    {
        input_gym::Add_Spacer(OutLines, gym_palette::White);
        input_gym::Add_Line(OutLines, "TOLD BY THE ENGINE (a listener per row)", gym_palette::White);

        auto Watched = Get_WatchedMappings();

        for (auto Index = 0; Index < Watched.Num(); Index++)
        {
            int32 FireCount = 0;
            if (Index < _FireCounts.Num())
            { FireCount = _FireCounts[Index]; }

            auto CurrentKey = utils_key_binding::Get_KeyForMapping(
                InPlayerController, Watched[Index], EPlayerMappableKeySlot::First);

            auto RowText = f"  {Watched[Index]} on {input_gym::Format_Key(CurrentKey)} — fired {FireCount} times";
            if (FireCount == 0)
            {
                RowText = f"  {Watched[Index]} on {input_gym::Format_Key(CurrentKey)} — never fired";
            }

            input_gym::Add_Line(OutLines, RowText, input_gym::Get_VerdictColour(FireCount > 0));
        }

        input_gym::Add_Line(OutLines, f"  last: {_LastDelegateEvent}", gym_palette::White);
    }

    private void Add_PollBlock(TArray<FCkGym_ColoredLine>& OutLines)
    {
        input_gym::Add_Spacer(OutLines, gym_palette::White);
        input_gym::Add_Line(OutLines, "FOUND BY ASKING EVERY TICK (the polling alternative)", gym_palette::White);
        input_gym::Add_Line(OutLines, f"  changes noticed: {_PolledChangeCount}", gym_palette::White);
        input_gym::Add_Line(OutLines, f"  last: {_LastPolledEvent}", gym_palette::White);

        input_gym::Add_Spacer(OutLines, gym_palette::White);
        input_gym::Add_Line(OutLines, "  Both columns should move together. Drive them from the", gym_palette::Cyan);
        input_gym::Add_Line(OutLines, "  Remap + Conflict station — its demo moves every row each lap.", gym_palette::Cyan);
    }

    // Get_DidMappingKeyChange compares against a key the CALLER cached, so the
    // cache has to be advanced on every detected change — otherwise the same
    // change re-reports forever and the counter measures ticks, not rebinds.
    private void Request_PollForChanges(APlayerController InPlayerController)
    {
        auto Watched = Get_WatchedMappings();

        for (auto Index = 0; Index < Watched.Num(); Index++)
        {
            if (Index >= _PolledKeys.Num())
            { continue; }

            FKey CurrentKey;
            auto Changed = utils_key_binding::Get_DidMappingKeyChange(
                InPlayerController, Watched[Index], EPlayerMappableKeySlot::First, _PolledKeys[Index], CurrentKey);

            if (Changed == false)
            { continue; }

            _PolledChangeCount++;
            _LastPolledEvent = f"{Watched[Index]}: {input_gym::Format_Key(_PolledKeys[Index])} -> {input_gym::Format_Key(CurrentKey)}";
            _PolledKeys[Index] = CurrentKey;
        }
    }
}
