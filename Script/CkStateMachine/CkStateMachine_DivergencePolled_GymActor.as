// ============================================================================
// SM DIVERGENCE FIRST-BRANCH (POLLED) — GYM ACTOR
// ============================================================================
//
// Polled mirror of CkStateMachine_DivergenceFirstBranchTimed_GymActor.as.
// Drives the same dual-pass divergence-point shape, but every linear hop
// uses a polled time-elapsed condition instead of an event-driven timer.
// Used to compare pump-budget behavior between event-driven and polled
// gating for an otherwise-identical sub-SM topology.

UCLASS(Blueprintable)
class ACk_SmTest_DivergencePolled_GymActor : AActor
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
    ECk_SmTest_DivergencePolled_PaymentChoice PaymentChoice = ECk_SmTest_DivergencePolled_PaymentChoice::Left;

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
        ResultText.SetText(ck::Text("SM Divergence FirstBranch (Polled)"));
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
        PaymentChoice = ECk_SmTest_DivergencePolled_PaymentChoice::Left;
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
        PassASmHandle = UCk_Utils_StateMachine_UE::Add(
            PassAEntity,
            UCk_SmTest_DivergencePolled_ParentState);
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
        PaymentChoice = ECk_SmTest_DivergencePolled_PaymentChoice::Right;
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
        PassBSmHandle = UCk_Utils_StateMachine_UE::Add(
            PassBEntity,
            UCk_SmTest_DivergencePolled_ParentState);
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

        ck::Trace(f"[SmDivergencePolled] {StatusLabel}: {ReportLine}",
            n"SmDivergencePolled", TraceDuration, TraceColor);

        if (ck::IsValid(StationHandle))
        {
            auto LabelA = OkA ? "OK" : "FAIL";
            auto LabelB = OkB ? "OK" : "FAIL";

            auto Title = f"DIVERGENCE FIRST-BRANCH (POLLED) — {StatusLabel}";

            auto Setup =
                FString("Polled mirror of DIVERGENCE FIRST-BRANCH (TIMED).\n")
                + "Same topology, but every linear hop's gate is a polled\n"
                + "time-elapsed condition (DoEvaluate returns true after\n"
                + "0.05s) instead of an event-driven timer.\n"
                + "\n"
                + "Used to compare pump-budget behavior between event-driven\n"
                + "and polled gating for an otherwise-identical sub-SM.\n"
                + "\n"
                + "PASS = every task counter is exactly 1 across both passes.\n"
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

            auto& Fragment = StationHandle.AddOrGet_Fragment(FCkGym_Station_TitleAndDescription);
            Fragment.Title = FText::FromString(Title);
            Fragment.Description = FText::FromString(Description);
            Fragment.Instructions = FText::FromString("Ck_GymSm_RestartDivergencePolled");
        }
    }
};

// ============================================================================
