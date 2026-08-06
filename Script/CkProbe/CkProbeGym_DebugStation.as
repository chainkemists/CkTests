//============================================================================
// PROBE GYM — DEBUG STATION
//
// Pure-ECS station that composes a Box Probe (Static, Notify, filter matches
// CkTests.Probe.Gym.Marker) on itself and drives the Request_BeginOverlap /
// Request_EndOverlap pipeline through a 4-step auto cycle:
//   0: BeginOverlap(self)       → 0→1, OnBeginOverlap fires
//   1: BeginOverlap(self) again → dedup, no signal expected
//   2: EndOverlap(self)         → 1→0, OnEndOverlap fires
//   3: EndOverlap(self) again   → no-op, no signal expected
//
// HUD shows current overlap count, signal counters, and last event so the
// dedup behavior is visible without reading logs.
//============================================================================

class UCk_EntityScript_ProbeGym_DebugStation : UCk_GenericEntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    FCk_Handle_Probe ProbeHandle;

    // Auto mode
    FCk_Handle_Timer AutoTimer;
    bool AutoRunning = true;
    int32 AutoStep = 0;
    FCkGym_AutoConfig AutoConfig;

    // Display state
    FString LastEventLine = "(none)";
    int32 EnterSignalCount = 0;
    int32 ExitSignalCount = 0;

    //------------------------------------------------------------------------
    // Construction & Initialization
    //------------------------------------------------------------------------

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto TransformHandle = utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);
        utils_entity_tag::Add(InHandle, n"TAG_ProbeGym_DebugStation");

        // Box probe — Static, Notify. Filter contains the Marker tag so
        // anything detectable can physically overlap too, though the auto
        // cycle uses Request_BeginOverlap/EndOverlap directly (bypassing
        // physical overlap entirely — it exercises the request pipeline
        // and signal state with the station's own handle as the dummy
        // other-entity).
        auto ProbeParams = FCk_Probe_Spec(
            utils_gameplay_tag::ResolveGameplayTag(n"CkTests.Probe.Gym.Detector"));
        ProbeParams.Set_MotionType(ECk_MotionType::Static);
        ProbeParams.Set_ResponsePolicy(ECk_ProbeResponse_Policy::Notify);

        auto Filter = FGameplayTagContainer();
        Filter.AddTag(utils_gameplay_tag::ResolveGameplayTag(n"CkTests.Probe.Gym.Marker"));
        ProbeParams.Set_Filter(Filter);

        auto DebugInfo = FCk_Probe_DebugInfo();
        ProbeHandle = utils_probe::Add_Box(TransformHandle, FVector(200.0f, 200.0f, 100.0f), ProbeParams, DebugInfo);

        // Display timer (every frame)
        auto DisplayTimerParams = FCk_Timer_Spec(FCk_Time(0.0f));
        DisplayTimerParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        auto DisplayTimer = utils_timer::Add(InHandle, DisplayTimerParams);
        DisplayTimer.BindTo_OnUpdate(FCk_Delegate_Timer(this, n"DisplayTick"));

        // Auto timer (1s cycle)
        AutoTimer = gym_auto::Setup(InHandle, this, FCk_Time(1.0f));

        AutoConfig.TotalSteps = 4;
        AutoConfig.Description = "Tests raw Probe: Request_Begin/EndOverlap + dedup.";
        AutoConfig.GlobalAutoCommand = "Ck_GymProbe_Auto [0/1]";
        AutoConfig.PerStationAutoCommand = "Ck_GymProbe_AutoDebug";
        AutoConfig.Steps.Add(FCkGym_AutoStep("BeginOverlap self (0->1, OnBegin fires)", 0, 0));
        AutoConfig.Steps.Add(FCkGym_AutoStep("BeginOverlap self again (dedup, no signal)", 1, 1));
        AutoConfig.Steps.Add(FCkGym_AutoStep("EndOverlap self (1->0, OnEnd fires)", 2, 2));
        AutoConfig.Steps.Add(FCkGym_AutoStep("EndOverlap self again (no-op, no signal)", 3, 3));
        AutoConfig.ManualCommands.Add("Ck_GymProbe_ForceEnter");
        AutoConfig.ManualCommands.Add("Ck_GymProbe_ForceExit");
        AutoConfig.ManualCommands.Add("Ck_GymProbe_Reset");

        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        Request_BindProbeSignals();
        Request_BindMessages(InHandle);
    }

    void Request_BindProbeSignals()
    {
        utils_probe::BindTo_OnBeginOverlap(ProbeHandle,
            FCk_Delegate_Probe_OnBeginOverlap(this, n"OnProbeBeginOverlap"));
        utils_probe::BindTo_OnEndOverlap(ProbeHandle,
            FCk_Delegate_Probe_OnEndOverlap(this, n"OnProbeEndOverlap"));
    }

    void Request_BindMessages(FCk_Handle InHandle)
    {
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_ProbeGym_ForceEnter,
            FCk_Delegate_Messaging_OnBroadcast(this, n"OnForceEnterMsg"));
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_ProbeGym_ForceExit,
            FCk_Delegate_Messaging_OnBroadcast(this, n"OnForceExitMsg"));
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_ProbeGym_Reset,
            FCk_Delegate_Messaging_OnBroadcast(this, n"OnResetMsg"));
    }

    //------------------------------------------------------------------------
    // Probe signal handlers
    //------------------------------------------------------------------------

    UFUNCTION()
    void OnProbeBeginOverlap(FCk_Handle_Probe InProbe, FCk_Probe_Payload_OnBeginOverlap InPayload)
    {
        EnterSignalCount++;
        auto Other = InPayload.Get_OtherEntity();
        LastEventLine = f"ENTER: {Other.ToString()}";
    }

    UFUNCTION()
    void OnProbeEndOverlap(FCk_Handle_Probe InProbe, FCk_Probe_Payload_OnEndOverlap InPayload)
    {
        ExitSignalCount++;
        auto Other = InPayload.Get_OtherEntity();
        LastEventLine = f"EXIT:  {Other.ToString()}";
    }

    //------------------------------------------------------------------------
    // Message handlers
    //------------------------------------------------------------------------

    UFUNCTION()
    private void OnForceEnterMsg(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        gym_auto::StopAuto(AutoTimer, AutoRunning);
        auto Empty = TArray<FVector>();
        auto Req = FCk_Request_Probe_BeginOverlap(InHandle, Empty, FVector::ZeroVector, nullptr);
        utils_probe::Request_BeginOverlap(ProbeHandle, Req);
    }

    UFUNCTION()
    private void OnForceExitMsg(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        gym_auto::StopAuto(AutoTimer, AutoRunning);
        utils_probe::Request_EndOverlap(ProbeHandle,
            FCk_Request_Probe_EndOverlap(InHandle));
    }

    UFUNCTION()
    private void OnResetMsg(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        gym_auto::StopAuto(AutoTimer, AutoRunning);
        // The auto cycle only ever force-enters `self`, so force-exiting self
        // drains whatever state the cycle left behind. (TSet iteration isn't
        // exposed to AS, so we can't snapshot Get_CurrentOverlaps here.)
        utils_probe::Request_EndOverlap(ProbeHandle,
            FCk_Request_Probe_EndOverlap(InHandle));
        EnterSignalCount = 0;
        ExitSignalCount = 0;
        LastEventLine = "(reset)";
    }

    UFUNCTION()
    private void OnAutoSet(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        gym_auto::HandleAutoSet(InPayload, AutoTimer, AutoRunning);
    }

    //------------------------------------------------------------------------
    // Auto Mode — drives Request_BeginOverlap / Request_EndOverlap on self
    //------------------------------------------------------------------------

    UFUNCTION()
    private void AutoTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        auto Step = AutoStep % AutoConfig.TotalSteps;
        AutoStep++;

        auto SelfEntity = ck::ToEntity(this);

        switch (Step)
        {
            case 0: // BeginOverlap self → 0→1, signal fires
            case 1: // BeginOverlap self again → dedup, no signal
            {
                auto Empty = TArray<FVector>();
                auto Req = FCk_Request_Probe_BeginOverlap(SelfEntity, Empty, FVector::ZeroVector, nullptr);
                utils_probe::Request_BeginOverlap(ProbeHandle, Req);
                break;
            }

            case 2: // EndOverlap self → 1→0, signal fires
            case 3: // EndOverlap self again → no-op, no signal
                utils_probe::Request_EndOverlap(ProbeHandle,
                    FCk_Request_Probe_EndOverlap(SelfEntity));
                break;
        }
    }

    //------------------------------------------------------------------------
    // Display
    //------------------------------------------------------------------------

    UFUNCTION()
    private void DisplayTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        DisplayCurrentValues();
    }

    void DisplayCurrentValues()
    {
        auto SelfEntity = ck::ToEntity(this);
        auto NetworkRole = CkGym_Common::Get_NetworkRoleTitle(SelfEntity);
        auto TitleText = f"PROBE DEBUG ({NetworkRole})";

        auto DisplayText = gym_auto::FormatHeader(AutoConfig, AutoRunning);

        DisplayText = DisplayText + "===== Probe State =====\n";

        auto Count = utils_probe::Get_CurrentOverlaps(ProbeHandle).Num();
        DisplayText = f"{DisplayText}Current overlaps: {Count}\n";

        DisplayText = DisplayText + "\n";
        DisplayText = f"{DisplayText}Signals: enter={EnterSignalCount} exit={ExitSignalCount}\n";
        DisplayText = f"{DisplayText}Last event: {LastEventLine}\n";

        DisplayText = DisplayText + gym_auto::FormatAutoAndCommands(AutoConfig, AutoStep, AutoRunning);

        auto Owner = utils_entity_lifetime::Get_LifetimeOwner(SelfEntity);
        auto& Fragment = Owner.AddOrGet_Fragment(FCkGym_Station_TitleAndDescription);
        Fragment.Title = FText::FromString(TitleText);
        Fragment.Description = FText::FromString(DisplayText);
    }
}
