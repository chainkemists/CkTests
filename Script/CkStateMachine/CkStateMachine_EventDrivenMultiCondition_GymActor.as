// ============================================================================
// SM EVENT-DRIVEN MULTI-CONDITION - GYM ACTOR
// ============================================================================
//
// Driver actor for CkStateMachine_TestStates_EventDrivenMultiCondition.as.
// Spawns a small entity hosting an SM with one Idle->Finish transition
// gated by two event-driven conditions resolving at staggered delays.
//
// PASS = Counter_Finish == 1 after the settle window (transition fired
//        exactly once, after the slower condition resolved).
// FAIL = Counter_Finish == 0 (FastEvent's Pass got clobbered during the
//        Reset cycle, so when SlowEvent fired the transition still saw a
//        Fail and never resolved).

UCLASS(Blueprintable)
class ACk_SmTest_EventDrivenMultiCondition_GymActor : AActor
{
    default bReplicates = true;
    default bAlwaysRelevant = true;
    // UE 5.7: CkEcs registers replicated subobjects via the registered-subobject list; without
    // this flag the engine raises an error ensure that poisons the autotest verdict.
    default bReplicateUsingRegisteredSubObjectList = true;

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

    // First event to resolve. Its Pass result must be preserved across the
    // Reset cycle until SlowEvent also resolves.
    UPROPERTY(ExposeOnSpawn)
    float32 FastDelaySeconds = 0.1f;

    // Second event to resolve. Once this fires, all conditions are Pass and
    // the transition fires.
    UPROPERTY(ExposeOnSpawn)
    float32 SlowDelaySeconds = 0.4f;

    // Settle window - must be > SlowDelaySeconds with margin so the test
    // captures a stable post-transition state.
    UPROPERTY(ExposeOnSpawn)
    float32 SettleSeconds = 0.6f;

    UPROPERTY(ExposeOnSpawn)
    FCk_Handle StationHandle;

    // ========================================================================
    // COUNTER - bumped by UCk_SmTest_EventDrivenMultiCondition_Task_Finish.
    // ========================================================================

    UPROPERTY() int32 Counter_Finish = 0;

    UPROPERTY() FCk_Handle SmEntity;
    UPROPERTY() FCk_Handle_StateMachine SmHandle;

    // ========================================================================
    // LIFECYCLE
    // ========================================================================

    UFUNCTION(BlueprintOverride)
    void BeginPlay()
    {
        auto _CkPerfScope = ck::ScopedStat();
        ResultText.SetText(ck::Text("SM Event-Driven Multi-Condition"));
        ResultText.SetTextRenderColor(FColor::White);
        DetailText.SetText(ck::Text("Waiting for both events..."));

        if (HasAuthority() == false)
        { return; }

        auto Pending = utils_entity_script::Request_SpawnEntity(
            ck::TransientEntity(),
            UCk_EntityScript_WithActor_UE,
            FCk_EntityScript_WithActor_SpawnParams(this));

        utils_pending_entity_script::Promise_OnConstructed(
            Pending,
            FCk_Delegate_EntityScript_Constructed(this, n"OnEntityConstructed"));

        System::SetTimer(this, n"OnSettled", SettleSeconds, false);
    }

    UFUNCTION()
    private void OnEntityConstructed(FCk_Handle_EntityScript InEntityScriptHandle)
    {
        if (System::IsServer() == false)
        { return; }

        SmEntity = FCk_Handle(InEntityScriptHandle);
        SmEntity.Set_DebugName(n"StateMachine");
        SmHandle = UCk_Utils_StateMachine_UE::Add(
            SmEntity, FCk_Fragment_StateMachine_ParamsData(UCk_SmTest_EventDrivenMultiCondition_State_Idle));
    }

    UFUNCTION()
    private void OnSettled()
    {
        UpdateDisplay();
    }

    // ========================================================================
    // VERDICT
    // ========================================================================

    private bool Run_OK() const
    {
        return Counter_Finish == 1;
    }

    private void UpdateDisplay()
    {
        auto OK = Run_OK();
        auto StatusLabel = OK ? "PASS" : "FAIL";
        auto StatusColor = OK ? FColor::Green : FColor::Red;
        auto TraceColor  = OK ? FLinearColor::Green : FLinearColor::Red;
        auto TraceDuration = OK ? 5.0f : 10.0f;

        auto ReportLine = f"Finish={Counter_Finish}";

        ResultText.SetText(ck::Text(StatusLabel));
        ResultText.SetTextRenderColor(StatusColor);
        DetailText.SetText(ck::Text(ReportLine));
        DetailText.SetTextRenderColor(OK ? FColor::White : FColor::Red);

        ck::Trace(f"[SmEventDrivenMultiCondition] {StatusLabel}: {ReportLine}",
            n"SmEventDrivenMultiCondition", TraceDuration, TraceColor);

        if (ck::IsValid(StationHandle))
        {
            auto VerdictLabel = OK
                ? "PASS - both conditions resolved, transition fired"
                : "FAIL - transition never fired (FastEvent's Pass was lost across Reset)";

            auto Title = f"EVENT-DRIVEN MULTI-CONDITION - {StatusLabel}";

            auto Setup =
                FString("Single transition Idle->Finish gated by TWO\n")
                + f"event-driven timer conditions:\n"
                + f"  FastEvent (resolves at {FastDelaySeconds}s, declared FIRST)\n"
                + f"  SlowEvent (resolves at {SlowDelaySeconds}s, declared SECOND)\n"
                + "\n"
                + "Guards the framework contract that event-driven cond Pass\n"
                + "results are preserved across transition Reset cycles.\n"
                + "FastEvent resolves Pass first, then the state evaluator\n"
                + "cycles through Reset many times waiting for SlowEvent.\n"
                + "When SlowEvent finally resolves, the transition must see\n"
                + "BOTH conds Pass and fire - which only works if FastEvent's\n"
                + "Pass survived all those Reset cycles.\n"
                + "\n"
                + "PASS = Counter_Finish exactly 1.\n"
                + "FAIL = Counter_Finish 0 (FastEvent's Pass was clobbered).\n"
                + "\n";

            auto Counts =
                f"Counter_Finish = {Counter_Finish}\n"
                + f"Verdict: {VerdictLabel}\n";

            auto Description = Setup + Counts;

            auto& Fragment = StationHandle.AddOrGet_Fragment(FCkGym_Station_TitleAndDescription);
            Fragment.Title = FText::FromString(Title);
            Fragment.Description = FText::FromString(Description);
            Fragment.Instructions = FText::FromString("Ck_GymSm_RestartEventDrivenMultiCondition");
        }
    }
};

// ============================================================================
