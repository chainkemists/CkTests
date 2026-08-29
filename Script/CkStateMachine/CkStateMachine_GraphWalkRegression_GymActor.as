// ============================================================================
// SM GRAPH-WALK GHOST-TASK REGRESSION - GYM ACTOR
// ============================================================================
//
// Driver actor for CkStateMachine_TestStates_GraphWalkRegression.as. On
// BeginPlay (server only), constructs one top-level linear SM and one
// parent-state sub-SM variant, then asserts after one tick + one settle
// pass that only the initial state of each SM fired its task enter-body.
//
// Pass criterion:
//   TopA == 1, TopB..TopD == 0, TopStopE == 0
//   SubA == 1, SubB..SubD == 0, SubStopE == 0
//   both SMs still RunStatus::Running
//   counters unchanged across a second settle pass (polled-false blocks
//   transitions for real, not just at t=0)
//
// Any deviation indicates the CkFoundation graph-walk ghost-entity
// short-circuit (PR #643) has regressed for that code path.

UCLASS(Blueprintable)
class ACk_SmTest_GraphWalkRegression_GymActor : AActor
{
    default bReplicates = true;
    default bReplicateUsingRegisteredSubObjectList = true;
    default bAlwaysRelevant = true;

    // ========================================================================
    // COMPONENTS (visual feedback mirroring ACk_SmTest_GymActor)
    // ========================================================================

    UPROPERTY(DefaultComponent)
    UStaticMeshComponent Mesh;
    default Mesh.StaticMesh = Cast<UStaticMesh>(
        utils_i_o::LoadAssetByName("Cube1", ECk_AssetSearchScope::Engine,
        ECk_AssetSearchStrategy::ExactOnly)._Asset);
    default Mesh.CollisionEnabled = ECollisionEnabled::NoCollision;

    UPROPERTY(DefaultComponent)
    UTextRenderComponent ResultText;
    default ResultText.RelativeLocation = FVector(0.0f, 0.0f, 120.0f);
    default ResultText.SetHorizontalAlignment(EHorizTextAligment::EHTA_Center);
    default ResultText.WorldSize = 40.0f;
    default ResultText.TextRenderColor = FColor::White;

    UPROPERTY(DefaultComponent)
    UTextRenderComponent DetailText;
    default DetailText.RelativeLocation = FVector(0.0f, 0.0f, 60.0f);
    default DetailText.SetHorizontalAlignment(EHorizTextAligment::EHTA_Center);
    default DetailText.WorldSize = 14.0f;
    default DetailText.TextRenderColor = FColor::White;

    // ========================================================================
    // CONFIGURATION
    // ========================================================================

    // Delay between SM construction and the first Verify pass. Needs to be
    // long enough for the graph-walk processor to finish its walk (~100ms
    // in practice) plus one tick of the real SM to enter its initial state.
    UPROPERTY(ExposeOnSpawn)
    float32 FirstVerifyDelay = 0.2f;

    // Second Verify pass - confirms the polled-false conditions actually
    // block transitions across frames (not just trivially zero on frame 0).
    UPROPERTY(ExposeOnSpawn)
    float32 SecondVerifyDelay = 0.8f;

    // Station entity handle - the BP_DemoDisplay reads the
    // FCkGym_Station_TitleAndDescription fragment off this entity. Set by
    // the PlayerController's Request_StartGraphWalkRegression before
    // FinishSpawningActor so the actor can push PASS/FAIL straight to the
    // demo display panel.
    UPROPERTY(ExposeOnSpawn)
    FCk_Handle StationHandle;

    // ========================================================================
    // STATE
    // ========================================================================

    // An ECS entity can hold only one state machine (the SM fragments
    // collide on the second Add), so we spawn a dedicated EntityScript per
    // SM. Both are lifetime-owned by ck::TransientEntity() and hold a back
    // reference to this actor.
    UPROPERTY()
    FCk_Handle TopEntity;

    UPROPERTY()
    FCk_Handle_StateMachine TopSmHandle;

    UPROPERTY()
    FCk_Handle SubEntity;

    UPROPERTY()
    FCk_Handle_StateMachine SubSmParentHandle;

    UPROPERTY()
    bool FirstVerifyFailed = false;

    // Per-label counters incremented by each state's EnterExitOnly task via
    // SmGraphWalk_Regression::Increment. Individual fields rather than a
    // TMap - AS TMap ergonomics are limited, and there are only ten labels
    // (5 top + 5 sub, of which each terminal is a Request_Stop channel).
    UPROPERTY() int32 Counter_TopA = 0;
    UPROPERTY() int32 Counter_TopB = 0;
    UPROPERTY() int32 Counter_TopC = 0;
    UPROPERTY() int32 Counter_TopD = 0;
    UPROPERTY() int32 Counter_TopStopE = 0;
    UPROPERTY() int32 Counter_SubA = 0;
    UPROPERTY() int32 Counter_SubB = 0;
    UPROPERTY() int32 Counter_SubC = 0;
    UPROPERTY() int32 Counter_SubD = 0;
    UPROPERTY() int32 Counter_SubStopE = 0;

    UFUNCTION()
    void Increment_Counter(FName InLabel)
    {
        if      (InLabel == n"TopA")     { Counter_TopA     += 1; }
        else if (InLabel == n"TopB")     { Counter_TopB     += 1; }
        else if (InLabel == n"TopC")     { Counter_TopC     += 1; }
        else if (InLabel == n"TopD")     { Counter_TopD     += 1; }
        else if (InLabel == n"TopStopE") { Counter_TopStopE += 1; }
        else if (InLabel == n"SubA")     { Counter_SubA     += 1; }
        else if (InLabel == n"SubB")     { Counter_SubB     += 1; }
        else if (InLabel == n"SubC")     { Counter_SubC     += 1; }
        else if (InLabel == n"SubD")     { Counter_SubD     += 1; }
        else if (InLabel == n"SubStopE") { Counter_SubStopE += 1; }
    }

    UFUNCTION()
    int32 Get_Counter(FName InLabel) const
    {
        if      (InLabel == n"TopA")     { return Counter_TopA; }
        else if (InLabel == n"TopB")     { return Counter_TopB; }
        else if (InLabel == n"TopC")     { return Counter_TopC; }
        else if (InLabel == n"TopD")     { return Counter_TopD; }
        else if (InLabel == n"TopStopE") { return Counter_TopStopE; }
        else if (InLabel == n"SubA")     { return Counter_SubA; }
        else if (InLabel == n"SubB")     { return Counter_SubB; }
        else if (InLabel == n"SubC")     { return Counter_SubC; }
        else if (InLabel == n"SubD")     { return Counter_SubD; }
        else if (InLabel == n"SubStopE") { return Counter_SubStopE; }
        return 0;
    }

    UFUNCTION()
    void Reset_Counters()
    {
        Counter_TopA = 0;
        Counter_TopB = 0;
        Counter_TopC = 0;
        Counter_TopD = 0;
        Counter_TopStopE = 0;
        Counter_SubA = 0;
        Counter_SubB = 0;
        Counter_SubC = 0;
        Counter_SubD = 0;
        Counter_SubStopE = 0;
    }

    // ========================================================================
    // LIFECYCLE
    // ========================================================================

    UFUNCTION(BlueprintOverride)
    void BeginPlay()
    {
        auto _CkPerfScope = ck::ScopedStat();
        ResultText.SetText(ck::Text("SM GraphWalk Regression"));
        ResultText.SetTextRenderColor(FColor::White);
        DetailText.SetText(ck::Text("Constructing..."));

        if (HasAuthority() == false)
        { return; }

        // Reset counters BEFORE constructing the SMs - graph-walk runs
        // synchronously inside Add(), so any late reset would zero out the
        // very signal we're trying to observe.
        Reset_Counters();

        auto TopSpawnParams = FCk_EntityScript_WithActor_SpawnParams();
        TopSpawnParams._OwningActor = this;
        auto PendingTop = utils_entity_script::Request_SpawnEntity(
            ck::TransientEntity(),
            UCk_EntityScript_WithActor_UE,
            TopSpawnParams);
        utils_pending_entity_script::Promise_OnConstructed(
            PendingTop,
            FCk_Delegate_EntityScript_Constructed(this, n"OnTopEntityConstructed"));

        auto SubSpawnParams = FCk_EntityScript_WithActor_SpawnParams();
        SubSpawnParams._OwningActor = this;
        auto PendingSub = utils_entity_script::Request_SpawnEntity(
            ck::TransientEntity(),
            UCk_EntityScript_WithActor_UE,
            SubSpawnParams);
        utils_pending_entity_script::Promise_OnConstructed(
            PendingSub,
            FCk_Delegate_EntityScript_Constructed(this, n"OnSubEntityConstructed"));

        DetailText.SetText(ck::Text(f"Verifying at +{FirstVerifyDelay}s, +{SecondVerifyDelay}s..."));

        System::SetTimer(this, n"Verify_FirstPass", FirstVerifyDelay, false);
        System::SetTimer(this, n"Verify_SecondPass", SecondVerifyDelay, false);
    }

    UFUNCTION()
    private void OnTopEntityConstructed(FCk_Handle_EntityScript InEntityScriptHandle)
    {
        if (System::IsServer() == false)
        { return; }

        TopEntity = FCk_Handle(InEntityScriptHandle);
        TopEntity.Set_DebugName(n"TopEntity");

        // Top-level linear SM - exercises the non-hierarchical graph-walk
        // path. The walk runs synchronously inside Add() and instantiates
        // temp entities for every reachable state/condition/task before
        // this call returns.
        TopSmHandle = UCk_Utils_StateMachine_UE::Add(
            TopEntity,
            FCk_Fragment_StateMachine_ParamsData(UCk_SmTest_GraphWalk_Top_State_A));
    }

    UFUNCTION()
    private void OnSubEntityConstructed(FCk_Handle_EntityScript InEntityScriptHandle)
    {
        if (System::IsServer() == false)
        { return; }

        SubEntity = FCk_Handle(InEntityScriptHandle);
        SubEntity.Set_DebugName(n"SubEntity");

        // Sub-SM variant - parent wrapper state holds UCk_SmTask_SubStateMachine
        // pointing at Sub_State_A. Exercises the hierarchical code path in the
        // graph-walk processor independently from the top-level case.
        SubSmParentHandle = UCk_Utils_StateMachine_UE::Add(
            SubEntity,
            FCk_Fragment_StateMachine_ParamsData(UCk_SmTest_GraphWalk_SubSmWrapper_State));
    }

    // ========================================================================
    // VERIFY
    // ========================================================================

    UFUNCTION()
    private void Verify_FirstPass()
    {
        auto Pass = EvaluatePass();
        if (Pass == false)
        { FirstVerifyFailed = true; }

        UpdateDisplay(Pass, "Pass 1/2", BuildReport());
    }

    UFUNCTION()
    private void Verify_SecondPass()
    {
        auto Pass = EvaluatePass();

        // A second-pass failure after a first-pass success would indicate
        // the polled-false conditions didn't truly block transitions - a
        // different bug than the ghost-walk regression, but still worth
        // surfacing.
        if (FirstVerifyFailed)
        { UpdateDisplay(false, "Pass 2/2 (first failed)", BuildReport()); return; }

        UpdateDisplay(Pass, "Pass 2/2", BuildReport());
    }

    private FString BuildReport()
    {
        auto TopA = Get_Counter(n"TopA");
        auto TopB = Get_Counter(n"TopB");
        auto TopC = Get_Counter(n"TopC");
        auto TopD = Get_Counter(n"TopD");
        auto TopStopE = Get_Counter(n"TopStopE");

        auto SubA = Get_Counter(n"SubA");
        auto SubB = Get_Counter(n"SubB");
        auto SubC = Get_Counter(n"SubC");
        auto SubD = Get_Counter(n"SubD");
        auto SubStopE = Get_Counter(n"SubStopE");

        auto TopRun = ck::IsValid(TopSmHandle)
            ? (TopSmHandle.Get_RunStatus() == ECk_SmRunStatus::Running ? "Running" : "Stopped")
            : "Invalid";
        auto SubRun = ck::IsValid(SubSmParentHandle)
            ? (SubSmParentHandle.Get_RunStatus() == ECk_SmRunStatus::Running ? "Running" : "Stopped")
            : "Invalid";

        return f"Top[A={TopA} B={TopB} C={TopC} D={TopD} StopE={TopStopE} SM={TopRun}] Sub[A={SubA} B={SubB} C={SubC} D={SubD} StopE={SubStopE} SM={SubRun}]";
    }

    private bool EvaluatePass()
    {
        if (Get_Counter(n"TopA") != 1) { return false; }
        if (Get_Counter(n"TopB") != 0) { return false; }
        if (Get_Counter(n"TopC") != 0) { return false; }
        if (Get_Counter(n"TopD") != 0) { return false; }
        if (Get_Counter(n"TopStopE") != 0) { return false; }

        if (Get_Counter(n"SubA") != 1) { return false; }
        if (Get_Counter(n"SubB") != 0) { return false; }
        if (Get_Counter(n"SubC") != 0) { return false; }
        if (Get_Counter(n"SubD") != 0) { return false; }
        if (Get_Counter(n"SubStopE") != 0) { return false; }

        if (ck::Is_NOT_Valid(TopSmHandle)) { return false; }
        if (TopSmHandle.Get_RunStatus() != ECk_SmRunStatus::Running) { return false; }
        if (ck::Is_NOT_Valid(SubSmParentHandle)) { return false; }
        if (SubSmParentHandle.Get_RunStatus() != ECk_SmRunStatus::Running) { return false; }

        return true;
    }

    private void UpdateDisplay(bool InPass, FString InPassLabel, FString InReport)
    {
        auto StatusLabel = InPass ? "PASS" : "FAIL";
        auto StatusColor = InPass ? FColor::Green : FColor::Red;
        auto TraceColor = InPass ? FLinearColor::Green : FLinearColor::Red;
        auto TraceDuration = InPass ? 5.0f : 10.0f;

        // In-world cube indicator - quick glance while walking the gym.
        ResultText.SetText(ck::Text(f"{StatusLabel} ({InPassLabel})"));
        ResultText.SetTextRenderColor(StatusColor);
        DetailText.SetText(ck::Text(InReport));
        DetailText.SetTextRenderColor(InPass ? FColor::White : FColor::Red);

        ck::Trace(f"[SmGraphWalkRegression] {StatusLabel} {InPassLabel}: {InReport}",
            n"SmRegression", TraceDuration, TraceColor);

        // BP_DemoDisplay panel - write the FCkGym_Station_TitleAndDescription
        // fragment directly onto the station entity. (Can't use
        // CkGym_Common::Update_StationDisplay since that expects an entity
        // whose LIFETIME OWNER is the station - we only have the station
        // handle itself.)
        if (ck::IsValid(StationHandle))
        {
            // Nested quotes don't interpolate inside f"" - build the report
            // in a local first so FName lookups stay outside the f-string.
            auto TopA_ = Get_Counter(n"TopA");
            auto TopB_ = Get_Counter(n"TopB");
            auto TopC_ = Get_Counter(n"TopC");
            auto TopD_ = Get_Counter(n"TopD");
            auto TopStopE_ = Get_Counter(n"TopStopE");
            auto SubA_ = Get_Counter(n"SubA");
            auto SubB_ = Get_Counter(n"SubB");
            auto SubC_ = Get_Counter(n"SubC");
            auto SubD_ = Get_Counter(n"SubD");
            auto SubStopE_ = Get_Counter(n"SubStopE");
            auto TopSm_ = Get_SmStatus(TopSmHandle);
            auto SubSm_ = Get_SmStatus(SubSmParentHandle);

            auto Title = f"GRAPH-WALK REGRESSION - {StatusLabel} ({InPassLabel})";

            // Setup summary (shown every pass): two 5-state linear SMs A->E
            // whose transitions are all gated by a polled-false condition.
            // The real SMs should never advance past A. State E's task
            // calls Request_Stop on its owning SM - so if the framework
            // mistakenly fires task enter-bodies during SM construction,
            // the real SMs get stopped immediately.
            auto Setup =
                FString("Two 5-state linear SMs (A->B->C->D->E).\n")
                + "All transitions gated by polled-false -> never fire.\n"
                + "Terminal task at E stops the owning SM.\n"
                + "\n"
                + "PASS = only A's task ran, both SMs Running.\n";

            auto Counts =
                FString("\n")
                + f"Top: A={TopA_} B={TopB_} C={TopC_} D={TopD_}\n"
                + f"     StopE={TopStopE_} SM={TopSm_}\n"
                + f"Sub: A={SubA_} B={SubB_} C={SubC_} D={SubD_}\n"
                + f"     StopE={SubStopE_} SM={SubSm_}\n";

            auto Description = Setup + Counts;

            // On FAIL, explain which invariant broke. The two distinct
            // symptoms map to the two failure modes the test is guarding:
            //   - Non-initial B/C/D counters nonzero  => task enter-bodies
            //     fired on states never actually entered by the SM.
            //   - StopE counter nonzero / SM=Stopped  => the terminal
            //     kill-task ran before the SM even started.
            if (InPass == false)
            {
                auto GhostTop = (TopB_ + TopC_ + TopD_) > 0;
                auto GhostSub = (SubB_ + SubC_ + SubD_) > 0;
                auto StoppedByGhost = (TopStopE_ > 0) || (SubStopE_ > 0);

                auto Why = FString("\nWhy failed:\n");
                if (GhostTop || GhostSub)
                {
                    Why = Why
                        + "- Task DoEnterTask fired on states the SM\n"
                        + "  never actually entered. Transitions are\n"
                        + "  polled-false so only A should have run.\n";
                }
                if (StoppedByGhost)
                {
                    Why = Why
                        + "- Terminal state E's Request_Stop task ran\n"
                        + "  during construction -> the real SM was\n"
                        + "  killed before it could start.\n";
                }
                if (GhostTop == false && GhostSub == false && StoppedByGhost == false)
                {
                    Why = Why
                        + "- Initial state task didn't run, or SM\n"
                        + "  stopped for an unrelated reason.\n";
                }

                Description = Description + Why;
            }

            auto& Fragment = StationHandle.AddOrGet_Fragment(FCkGym_Station_TitleAndDescription);
            Fragment.Title = FText::FromString(Title);
            Fragment.Description = FText::FromString(Description);
            Fragment.Instructions = FText::FromString("panel [5] GraphWalk regression");
        }
    }

    private FString Get_SmStatus(FCk_Handle_StateMachine InHandle)
    {
        if (ck::Is_NOT_Valid(InHandle)) { return "Invalid"; }
        return InHandle.Get_RunStatus() == ECk_SmRunStatus::Running ? "Running" : "Stopped";
    }
};

// ============================================================================
