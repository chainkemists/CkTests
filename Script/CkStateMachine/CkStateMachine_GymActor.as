// ============================================================================
// STATE MACHINE GYM ACTOR
// ============================================================================

// Spawnable actor that demonstrates CkStateMachine functionality.
// Creates a state machine from the initial state only. The graph is built
// dynamically by state scripts (Idle -> Patrol -> Alert -> Idle).
// Visual feedback via TextRenderComponent.
//
// When EnablePauseResume is true, the SM pauses after PauseAfterTransitions
// transitions and resumes after PauseDuration seconds.

UCLASS(Blueprintable)
class ACk_SmTest_GymActor : AActor
{
    default bReplicates = true;
    default bReplicateUsingRegisteredSubObjectList = true;
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
    UTextRenderComponent StateText;
    default StateText.RelativeLocation = FVector(0.0f, 0.0f, 100.0f);
    default StateText.SetHorizontalAlignment(EHorizTextAligment::EHTA_Center);
    default StateText.WorldSize = 50.0f;
    default StateText.TextRenderColor = FColor::White;

    UPROPERTY(DefaultComponent)
    UTextRenderComponent InfoText;
    default InfoText.RelativeLocation = FVector(0.0f, 0.0f, 150.0f);
    default InfoText.SetHorizontalAlignment(EHorizTextAligment::EHTA_Center);
    default InfoText.WorldSize = 30.0f;
    default InfoText.TextRenderColor = FColor::Orange;

    // ========================================================================
    // CONFIGURATION
    // ========================================================================

    UPROPERTY(ExposeOnSpawn)
    float32 CycleDuration = 2.0f;

    UPROPERTY(ExposeOnSpawn)
    bool EnablePauseResume = false;

    UPROPERTY(ExposeOnSpawn)
    int32 PauseAfterTransitions = 6;

    UPROPERTY(ExposeOnSpawn)
    float32 PauseDuration = 3.0f;

    UPROPERTY(ExposeOnSpawn)
    TSubclassOf<UCk_SmState_EntityScript> InitialStateClass;

    // ========================================================================
    // STATE
    // ========================================================================

    UPROPERTY()
    FCk_Handle_StateMachine SmHandle;

    UPROPERTY()
    int32 TransitionCount = 0;

    UPROPERTY()
    bool IsPaused = false;

    // ========================================================================
    // LIFECYCLE
    // ========================================================================

    UFUNCTION(BlueprintOverride)
    void BeginPlay()
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto ModeLabel = EnablePauseResume ? "Pause/Resume + State Graph" : "State Graph Auto";
        InfoText.SetText(ck::Text(f"SM: {ModeLabel}"));

        if (HasAuthority())
        {
            auto SpawnParams = FCk_EntityScript_WithActor_SpawnParams();
            SpawnParams._OwningActor = this;
            auto PendingEntity = utils_entity_script::Request_SpawnEntity(
                ck::TransientEntity(), UCk_EntityScript_WithActor_UE, SpawnParams);
            utils_pending_entity_script::Promise_OnConstructed(
                PendingEntity, FCk_Delegate_EntityScript_Constructed(this, n"OnEntityConstructed"));
        }
    }

    // ========================================================================
    // ECS SETUP
    // ========================================================================

    UFUNCTION()
    private void OnEntityConstructed(FCk_Handle_EntityScript InEntityScriptHandle)
    {
        if (System::IsServer() == false)
        { return; }

        auto OwnerHandle = FCk_Handle(InEntityScriptHandle);
        OwnerHandle.Set_DebugName(n"StateMachine");
        auto StateClass = InitialStateClass.IsValid()
            ? InitialStateClass
            : TSubclassOf<UCk_SmState_EntityScript>(UCk_SmTest_State_Idle);
        SmHandle = UCk_Utils_StateMachine_UE::Add(
            OwnerHandle,
            FCk_StateMachine_Spec(StateClass));

        BindSignals();
    }

    // ========================================================================
    // SIGNAL BINDING
    // ========================================================================

    private void BindSignals()
    {
        FCk_Delegate_Sm_OnStateChanged OnStateChangedDelegate;
        OnStateChangedDelegate.BindUFunction(this, n"OnSmStateChanged");
        SmHandle.BindTo_OnStateChanged(OnStateChangedDelegate);

        FCk_Delegate_Sm_OnStarted OnStartedDelegate;
        OnStartedDelegate.BindUFunction(this, n"OnSmStarted");
        SmHandle.BindTo_OnStarted(OnStartedDelegate);

        FCk_Delegate_Sm_OnStopped OnStoppedDelegate;
        OnStoppedDelegate.BindUFunction(this, n"OnSmStopped");
        SmHandle.BindTo_OnStopped(OnStoppedDelegate);
    }

    // ========================================================================
    // SIGNAL HANDLERS
    // ========================================================================

    UFUNCTION()
    private void OnSmStateChanged(
        FCk_Handle_StateMachine InHandle,
        FCk_Sm_Payload_OnStateChanged InPayload)
    {
        TransitionCount++;

        auto NewStateClass = InPayload.Get_NewStateClass();
        auto StateName = GetFriendlyStateName(NewStateClass);

        StateText.SetText(ck::Text(StateName));
        StateText.SetTextRenderColor(GetStateColor(NewStateClass));
        InfoText.SetText(ck::Text(f"Transitions: {TransitionCount}"));

        if (EnablePauseResume && TransitionCount >= PauseAfterTransitions && !IsPaused)
        {
            DoPause();
        }
    }

    UFUNCTION()
    private void OnSmStarted(
        FCk_Handle_StateMachine InHandle,
        FCk_Sm_Payload_OnStarted InPayload)
    {
        StateText.SetText(ck::Text("Idle"));
        StateText.SetTextRenderColor(FColor::Blue);
    }

    UFUNCTION()
    private void OnSmStopped(
        FCk_Handle_StateMachine InHandle,
        FCk_Sm_Payload_OnStopped InPayload)
    {
        StateText.SetText(ck::Text("STOPPED"));
        StateText.SetTextRenderColor(FColor(128, 128, 128));
    }

    // ========================================================================
    // PAUSE / RESUME
    // ========================================================================

    private void DoPause()
    {
        SmHandle.Request_Pause();
        IsPaused = true;

        StateText.SetText(ck::Text("PAUSED"));
        StateText.SetTextRenderColor(FColor(255, 165, 0));
        InfoText.SetText(ck::Text(f"Resuming in {PauseDuration}s..."));

        System::SetTimer(this, n"DoResume", PauseDuration, false);
    }

    UFUNCTION()
    private void DoResume()
    {
        SmHandle.Request_Resume();
        IsPaused = false;
        TransitionCount = 0;

        InfoText.SetText(ck::Text("Resumed! Count reset."));
    }

    // ========================================================================
    // HELPERS
    // ========================================================================

    private FString GetFriendlyStateName(TSubclassOf<UCk_SmState_EntityScript> InStateClass) const
    {
        // Simple states
        if (InStateClass == UCk_SmTest_State_Idle)   { return "Idle"; }
        if (InStateClass == UCk_SmTest_State_Patrol) { return "Patrol"; }
        if (InStateClass == UCk_SmTest_State_Alert)  { return "Alert"; }

        // Complex states
        if (InStateClass == UCk_SmTest_Complex_State_Idle)   { return "Idle"; }
        if (InStateClass == UCk_SmTest_Complex_State_Patrol) { return "Patrol"; }
        if (InStateClass == UCk_SmTest_Complex_State_Chase)  { return "Chase"; }
        if (InStateClass == UCk_SmTest_Complex_State_Attack) { return "Attack"; }
        if (InStateClass == UCk_SmTest_Complex_State_Search) { return "Search"; }
        if (InStateClass == UCk_SmTest_Complex_State_Flee)   { return "Flee"; }

        // Hierarchical states (parent)
        if (InStateClass == UCk_SmTest_Hier_Parent_Spawn)    { return "Spawn"; }
        if (InStateClass == UCk_SmTest_Hier_Parent_Approach) { return "Approach"; }
        if (InStateClass == UCk_SmTest_Hier_Parent_Engage)   { return "Engage [Combat SM]"; }
        if (InStateClass == UCk_SmTest_Hier_Parent_Retreat)  { return "Retreat"; }
        if (InStateClass == UCk_SmTest_Hier_Parent_Heal)     { return "Heal [Heal SM]"; }
        if (InStateClass == UCk_SmTest_Hier_Parent_Flee)     { return "Flee"; }

        return "Unknown";
    }

    private FColor GetStateColor(TSubclassOf<UCk_SmState_EntityScript> InStateClass) const
    {
        // Simple states
        if (InStateClass == UCk_SmTest_State_Idle)   { return FColor::Blue; }
        if (InStateClass == UCk_SmTest_State_Patrol) { return FColor::Green; }
        if (InStateClass == UCk_SmTest_State_Alert)  { return FColor::Red; }

        // Complex states
        if (InStateClass == UCk_SmTest_Complex_State_Idle)   { return FColor::Blue; }
        if (InStateClass == UCk_SmTest_Complex_State_Patrol) { return FColor::Green; }
        if (InStateClass == UCk_SmTest_Complex_State_Chase)  { return FColor(255, 128, 0); }
        if (InStateClass == UCk_SmTest_Complex_State_Attack) { return FColor::Red; }
        if (InStateClass == UCk_SmTest_Complex_State_Search) { return FColor(128, 0, 255); }
        if (InStateClass == UCk_SmTest_Complex_State_Flee)   { return FColor(255, 255, 0); }

        // Hierarchical states (parent)
        if (InStateClass == UCk_SmTest_Hier_Parent_Spawn)    { return FColor(128, 128, 128); }
        if (InStateClass == UCk_SmTest_Hier_Parent_Approach) { return FColor(0, 128, 255); }
        if (InStateClass == UCk_SmTest_Hier_Parent_Engage)   { return FColor::Red; }
        if (InStateClass == UCk_SmTest_Hier_Parent_Retreat)  { return FColor(255, 255, 0); }
        if (InStateClass == UCk_SmTest_Hier_Parent_Heal)     { return FColor(77, 230, 77); }
        if (InStateClass == UCk_SmTest_Hier_Parent_Flee)     { return FColor(255, 102, 0); }

        return FColor::White;
    }
};

// ============================================================================
