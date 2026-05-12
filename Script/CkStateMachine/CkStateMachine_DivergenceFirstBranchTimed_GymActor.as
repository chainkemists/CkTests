// ============================================================================
// SM DIVERGENCE-FIRST-BRANCH (TIMED) — GYM ACTOR
// ============================================================================
//
// Driver actor for CkStateMachine_TestStates_DivergenceFirstBranchTimed.as.
//
// What the gym does:
//
// 1. Spawns one entity, adds the wrapper parent SM, lets the sub-SM run a
//    full cycle (Enter -> Idle -> Branch -> chosen -> Finish), then
//    snapshots the per-task counters. This is Pass A.
// 2. Repeats with the AddTransition order swapped and the chosen branch
//    swapped to match. This is Pass B.
//
// The two passes pin the doubling-vs-add-order relationship:
//
//   Pass A: AddOrderLeftFirst=true,  PaymentChoice=Left
//           => ToLeft is added first AND wins selection.
//           => If the bug is present, Counter_Left == 2.
//
//   Pass B: AddOrderLeftFirst=false, PaymentChoice=Right
//           => ToRight is added first AND wins selection.
//           => If the bug is present, Counter_Right == 2.
//
// Both passes must read 1 across every counter for the gym to report PASS.
// The two-pass design proves the doubling tracks add-order, not state
// class or branch direction — flipping the order flips which branch
// doubles, eliminating "maybe Left has a quirk" as a confounder.
//
// Settle window per pass: 1.5s. The sub-SM cycle is ~0.25s with the 0.05s
// FastDelay per hop, so 1.5s gives ~6x headroom and would also catch any
// duplicate-driven extra hops piling up beyond the expected 5.
//
// Why a fresh entity per pass: the wrapper parent SM has only one
// SubStateMachine task; once the sub-SM Stops at Finish, the parent's
// SubSm task succeeds and the parent SM also stops. Restarting requires
// either re-Adding to the same entity or just spawning a fresh one. The
// latter is simpler and avoids any state-leak interaction between Pass A
// and Pass B contaminating the assertion.

UCLASS(Blueprintable)
class ACk_SmTest_DivergenceTimed_GymActor : AActor
{
    default bReplicates = true;
    default bAlwaysRelevant = true;

    // ========================================================================
    // COMPONENTS
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

    // Per-pass settle window. Sub-SM cycle is ~0.25s (5 hops × 0.05s),
    // 1.5s gives lots of headroom and would catch any duplicate-driven
    // extra hops too.
    UPROPERTY(ExposeOnSpawn)
    float32 PerPassSettleSeconds = 1.5f;

    UPROPERTY(ExposeOnSpawn)
    FCk_Handle StationHandle;

    // ========================================================================
    // STATE READ BY THE SM
    // ========================================================================

    UPROPERTY()
    bool AddOrderLeftFirst = true;

    UPROPERTY()
    ECk_SmTest_DivergenceTimed_PaymentChoice PaymentChoice = ECk_SmTest_DivergenceTimed_PaymentChoice::Left;

    // ========================================================================
    // PER-PASS COUNTERS
    // ========================================================================

    UPROPERTY() int32 Counter_Enter = 0;
    UPROPERTY() int32 Counter_Idle = 0;
    UPROPERTY() int32 Counter_Branch = 0;
    UPROPERTY() int32 Counter_Left = 0;
    UPROPERTY() int32 Counter_Right = 0;
    UPROPERTY() int32 Counter_Finish = 0;

    UFUNCTION()
    void Increment_Counter(FName InLabel)
    {
        if      (InLabel == n"Enter")  { Counter_Enter  += 1; }
        else if (InLabel == n"Idle")   { Counter_Idle   += 1; }
        else if (InLabel == n"Branch") { Counter_Branch += 1; }
        else if (InLabel == n"Left")   { Counter_Left   += 1; }
        else if (InLabel == n"Right")  { Counter_Right  += 1; }
        else if (InLabel == n"Finish") { Counter_Finish += 1; }
    }

    UFUNCTION()
    void Reset_Counters()
    {
        Counter_Enter = 0;
        Counter_Idle = 0;
        Counter_Branch = 0;
        Counter_Left = 0;
        Counter_Right = 0;
        Counter_Finish = 0;
    }

    // ========================================================================
    // PASS SNAPSHOTS
    // ========================================================================

    UPROPERTY() int32 Snap_A_Enter = 0;
    UPROPERTY() int32 Snap_A_Idle = 0;
    UPROPERTY() int32 Snap_A_Branch = 0;
    UPROPERTY() int32 Snap_A_Left = 0;
    UPROPERTY() int32 Snap_A_Right = 0;
    UPROPERTY() int32 Snap_A_Finish = 0;

    UPROPERTY() int32 Snap_B_Enter = 0;
    UPROPERTY() int32 Snap_B_Idle = 0;
    UPROPERTY() int32 Snap_B_Branch = 0;
    UPROPERTY() int32 Snap_B_Left = 0;
    UPROPERTY() int32 Snap_B_Right = 0;
    UPROPERTY() int32 Snap_B_Finish = 0;

    // ========================================================================
    // ENTITIES
    // ========================================================================

    UPROPERTY() FCk_Handle PassAEntity;
    UPROPERTY() FCk_Handle_StateMachine PassASmHandle;

    UPROPERTY() FCk_Handle PassBEntity;
    UPROPERTY() FCk_Handle_StateMachine PassBSmHandle;

    // ========================================================================
    // LIFECYCLE
    // ========================================================================

    UFUNCTION(BlueprintOverride)
    void BeginPlay()
    {
        ResultText.SetText(ck::Text("SM Divergence FirstBranch (Timed)"));
        ResultText.SetTextRenderColor(FColor::White);
        DetailText.SetText(ck::Text("Pass A starting..."));

        if (HasAuthority() == false)
        { return; }

        StartPassA();
    }

    UFUNCTION()
    private void StartPassA()
    {
        AddOrderLeftFirst = true;
        PaymentChoice = ECk_SmTest_DivergenceTimed_PaymentChoice::Left;
        Reset_Counters();

        auto SpawnParams = FCk_EntityScript_WithActor_SpawnParams();
        SpawnParams._OwningActor = this;
        auto Pending = utils_entity_script::Request_SpawnEntity(
            ck::TransientEntity(),
            UCk_EntityScript_WithActor_UE,
            SpawnParams);
        utils_pending_entity_script::Promise_OnConstructed(
            Pending,
            FCk_Delegate_EntityScript_Constructed(this, n"OnPassAConstructed"));

        System::SetTimer(this, n"VerifyPassA", PerPassSettleSeconds, false);
    }

    UFUNCTION()
    private void OnPassAConstructed(FCk_Handle_EntityScript InEntityScriptHandle)
    {
        if (System::IsServer() == false)
        { return; }

        PassAEntity = FCk_Handle(InEntityScriptHandle);
        PassAEntity.Set_DebugName(n"PassA");
        PassASmHandle = UCk_Utils_StateMachine_UE::Add(
            PassAEntity,
            UCk_SmTest_DivergenceTimed_ParentState);
    }

    UFUNCTION()
    private void VerifyPassA()
    {
        Snap_A_Enter  = Counter_Enter;
        Snap_A_Idle   = Counter_Idle;
        Snap_A_Branch = Counter_Branch;
        Snap_A_Left   = Counter_Left;
        Snap_A_Right  = Counter_Right;
        Snap_A_Finish = Counter_Finish;

        StartPassB();
    }

    UFUNCTION()
    private void StartPassB()
    {
        AddOrderLeftFirst = false;
        PaymentChoice = ECk_SmTest_DivergenceTimed_PaymentChoice::Right;
        Reset_Counters();

        auto SpawnParams = FCk_EntityScript_WithActor_SpawnParams();
        SpawnParams._OwningActor = this;
        auto Pending = utils_entity_script::Request_SpawnEntity(
            ck::TransientEntity(),
            UCk_EntityScript_WithActor_UE,
            SpawnParams);
        utils_pending_entity_script::Promise_OnConstructed(
            Pending,
            FCk_Delegate_EntityScript_Constructed(this, n"OnPassBConstructed"));

        System::SetTimer(this, n"VerifyPassB", PerPassSettleSeconds, false);
    }

    UFUNCTION()
    private void OnPassBConstructed(FCk_Handle_EntityScript InEntityScriptHandle)
    {
        if (System::IsServer() == false)
        { return; }

        PassBEntity = FCk_Handle(InEntityScriptHandle);
        PassBEntity.Set_DebugName(n"PassB");
        PassBSmHandle = UCk_Utils_StateMachine_UE::Add(
            PassBEntity,
            UCk_SmTest_DivergenceTimed_ParentState);
    }

    UFUNCTION()
    private void VerifyPassB()
    {
        Snap_B_Enter  = Counter_Enter;
        Snap_B_Idle   = Counter_Idle;
        Snap_B_Branch = Counter_Branch;
        Snap_B_Left   = Counter_Left;
        Snap_B_Right  = Counter_Right;
        Snap_B_Finish = Counter_Finish;

        UpdateDisplay();
    }

    // ========================================================================
    // VERDICT
    // ========================================================================

    private bool PassA_OK()
    {
        if (Snap_A_Enter  != 1) { return false; }
        if (Snap_A_Idle   != 1) { return false; }
        if (Snap_A_Branch != 1) { return false; }
        if (Snap_A_Left   != 1) { return false; }
        if (Snap_A_Right  != 0) { return false; }
        if (Snap_A_Finish != 1) { return false; }
        return true;
    }

    private bool PassB_OK()
    {
        if (Snap_B_Enter  != 1) { return false; }
        if (Snap_B_Idle   != 1) { return false; }
        if (Snap_B_Branch != 1) { return false; }
        if (Snap_B_Left   != 0) { return false; }
        if (Snap_B_Right  != 1) { return false; }
        if (Snap_B_Finish != 1) { return false; }
        return true;
    }

    private void UpdateDisplay()
    {
        auto OkA = PassA_OK();
        auto OkB = PassB_OK();
        auto AllOk = OkA && OkB;

        auto StatusLabel = AllOk ? "PASS" : "FAIL";
        auto StatusColor = AllOk ? FColor::Green : FColor::Red;
        auto TraceColor  = AllOk ? FLinearColor::Green : FLinearColor::Red;
        auto TraceDuration = AllOk ? 5.0f : 10.0f;

        auto ReportLine = f"A[E={Snap_A_Enter} I={Snap_A_Idle} B={Snap_A_Branch} L={Snap_A_Left} R={Snap_A_Right} F={Snap_A_Finish}]"
            + f" B[E={Snap_B_Enter} I={Snap_B_Idle} B={Snap_B_Branch} L={Snap_B_Left} R={Snap_B_Right} F={Snap_B_Finish}]";

        ResultText.SetText(ck::Text(StatusLabel));
        ResultText.SetTextRenderColor(StatusColor);
        DetailText.SetText(ck::Text(ReportLine));
        DetailText.SetTextRenderColor(AllOk ? FColor::White : FColor::Red);

        ck::Trace(f"[SmDivergenceTimed] {StatusLabel}: {ReportLine}",
            n"SmDivergenceTimed", TraceDuration, TraceColor);

        if (ck::IsValid(StationHandle))
        {
            auto LabelA = OkA ? "OK" : "FAIL";
            auto LabelB = OkB ? "OK" : "FAIL";

            auto Title = f"DIVERGENCE FIRST-BRANCH (TIMED) — {StatusLabel}";

            auto Setup =
                FString("Sub-SM with a divergence-point state (two outgoing\n")
                + "transitions). Every linear hop uses a 0.05s event-driven\n"
                + "timer condition; each divergence transition adds a polled\n"
                + "payment-method check so exactly one branch wins.\n"
                + "\n"
                + "Enter -> Idle -> Branch -+-> Left  -> Finish\n"
                + "                         `-> Right -/\n"
                + "\n"
                + "Pass A: ToLeft added first + Left chosen -> Left first &\n"
                + "        first-added.\n"
                + "Pass B: ToRight added first + Right chosen -> Right first\n"
                + "        & first-added.\n"
                + "\n"
                + "Tests: when a divergence-state's first-added transition is\n"
                + "the chosen one, the target state-task chain must be built\n"
                + "exactly once. The bug duplicates it (cached Pass result on\n"
                + "the dying source state's transition fires Request_Transition\n"
                + "a second time before the source state is fully torn down).\n"
                + "\n"
                + "PASS = every task counter is exactly 1.\n"
                + "FAIL = chosen-and-first-added branch counter is 2 (or more).\n"
                + "\n";

            auto Counts =
                f"Pass A (AddLeftFirst, PaymentLeft):\n"
                + f"  Enter={Snap_A_Enter} Idle={Snap_A_Idle} Branch={Snap_A_Branch}\n"
                + f"  Left={Snap_A_Left} Right={Snap_A_Right} Finish={Snap_A_Finish}\n"
                + f"  -> {LabelA}\n"
                + "\n"
                + f"Pass B (AddRightFirst, PaymentRight):\n"
                + f"  Enter={Snap_B_Enter} Idle={Snap_B_Idle} Branch={Snap_B_Branch}\n"
                + f"  Left={Snap_B_Left} Right={Snap_B_Right} Finish={Snap_B_Finish}\n"
                + f"  -> {LabelB}\n";

            auto Description = Setup + Counts;

            if (AllOk == false)
            {
                auto Why = FString("\nWhy failed:\n");
                if (OkA == false && Snap_A_Left >= 2)
                {
                    Why = Why
                        + "- Pass A: Left task fired 2x (expected 1).\n"
                        + "  Left was first-added AND chosen branch.\n";
                }
                if (OkB == false && Snap_B_Right >= 2)
                {
                    Why = Why
                        + "- Pass B: Right task fired 2x (expected 1).\n"
                        + "  Right was first-added AND chosen branch.\n"
                        + "  Doubling tracks add-order, confirming the bug.\n";
                }
                Description = Description + Why;
            }

            auto& Fragment = StationHandle.AddOrGet_Fragment(FCkGym_Station_TitleAndDescription);
            Fragment.Title = FText::FromString(Title);
            Fragment.Description = FText::FromString(Description);
            Fragment.Instructions = FText::FromString("Ck_GymSm_RestartDivergenceTimed");
        }
    }
};

// ============================================================================
