//--------------------------------------------------------------------------------------------------------------------------
// The base gym pawn: ADefaultPawn for its collision + FloatingPawnMovement, but with the engine's
// own input bindings DISABLED - movement and mouse look are driven from a CkInput layer at the
// bottom of the gym input stack instead. That is what lets the switchboard (and anything else
// above priority 100) mask movement structurally: while a catch-all Consume sits above, this layer
// receives nothing and the pawn freezes, with no flag anyone has to remember to clear.
//
// Held state is tracked from the layer's press/release edges. The router guarantees the release
// reaches whoever consumed the press, and CkInput's focus-loss flush writes synthetic Releases for
// every recorded-down key - so a key held across an alt-tab reads as up here, exactly as it does
// in every other Ck input consumer.
//
// A subclass that overrides Tick calls Tick_StandardMovement() from its own to keep standard
// movement; a pawn replacing movement wholesale (Camera, PixelArt, Playground) deliberately
// overrides Tick without it.
//--------------------------------------------------------------------------------------------------------------------------

class ACk_Gym_Base_Pawn : ADefaultPawn
{
    default Replicates = true;
    default bAddDefaultMovementBindings = false;

    private FCk_Handle _LayerOwner;
    private FCk_Handle_InputLayer _MoveLayer;

    private bool _HeldForward = false;
    private bool _HeldBack = false;
    private bool _HeldRight = false;
    private bool _HeldLeft = false;
    private bool _HeldUp = false;
    private bool _HeldDown = false;

    // The legacy input path scaled mouse deltas by BaseInput.ini's MouseX/MouseY axis
    // Sensitivity (0.07) before they reached AddControllerYaw/PitchInput; the raw layer delivers
    // unconditioned deltas, so the same scale is restored here for feel parity with ADefaultPawn.
    private float32 _MouseLookScale = 0.07f;

    UFUNCTION(BlueprintOverride)
    void BeginPlay()
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto PendingEntity = utils_entity_script_with_actor::Request_SpawnEntityScript_OnActor(
            this, UCk_EntityScript_WithActor_UE);
        if (utils_pending_entity_script::Get_IsValid(PendingEntity))
        {
            utils_pending_entity_script::Promise_OnConstructed(
                PendingEntity, FCk_Delegate_EntityScript_Constructed(this, n"OnEntityConstructed"));
        }
    }

    UFUNCTION(BlueprintOverride)
    void EndPlay(EEndPlayReason EndPlayReason)
    {
        // The layer must not outlive the pawn: a stale layer would keep consuming movement keys on
        // the shared source, and a respawned pawn would find its priority slot taken.
        if (ck::IsValid(_LayerOwner))
        {
            utils_entity_lifetime::Request_DestroyEntity(_LayerOwner);
        }
    }

    UFUNCTION()
    void OnEntityConstructed(FCk_Handle_EntityScript InEntityScriptHandle)
    {
        ck::Trace("Gym pawn entity setup complete");
        Request_OnPawnReady();
    }

    // Override this in derived gym classes if custom pawn behavior is needed
    void Request_OnPawnReady()
    {
        // Base implementation does nothing - gyms typically handle logic in PlayerController
    }

    UFUNCTION(BlueprintOverride)
    void Tick(float32 InDeltaSeconds)
    {
        Tick_StandardMovement();
    }

    // Also the entry point for subclasses that override Tick but still want standard movement
    // (call it from your Tick); a pawn replacing movement wholesale simply doesn't.
    void Tick_StandardMovement()
    {
        DoEnsureMoveLayer();
        DoApplyMovement();
    }

    //------------------------------------------------------------------------
    // Input layer
    //------------------------------------------------------------------------

    // Idempotent, retried from Tick: the local player's source is invalid until the engine has
    // handed the player a controller, and possession itself can lag spawn.
    private void DoEnsureMoveLayer()
    {
        if (ck::IsValid(_MoveLayer))
        { return; }

        auto PC = Cast<APlayerController>(GetController());
        if (ck::Is_NOT_Valid(PC))
        { return; }

        auto SourceSubsystem = UCk_InputSource_Subsystem::Get(PC);
        if (ck::Is_NOT_Valid(SourceSubsystem))
        { return; }

        auto Source = SourceSubsystem.Get_InputSource();
        if (ck::Is_NOT_Valid(Source))
        { return; }

        // A previous pawn's layer that has not finished tearing down still holds the slot; wait a
        // frame rather than ensure-failing the create.
        if (ck::IsValid(utils_input_layer::TryGet_LayerWithPriority(Source, CkGym_InputStack::Priority_Pawn)))
        { return; }

        _LayerOwner = utils_entity_lifetime::Request_CreateEntity_TransientOwner();
        _MoveLayer = utils_input_layer::Create(_LayerOwner,
            FCk_Fragment_InputLayer_ParamsData(Source, CkGym_InputStack::Priority_Pawn));

        if (ck::Is_NOT_Valid(_MoveLayer))
        { return; }

        utils_input_layer::BindTo_OnCaptureTriggered(_MoveLayer,
            FCk_Delegate_InputLayer_CaptureTriggered(this, n"OnMoveCaptured"),
            ECk_Signal_BindingPolicy::IgnorePayloadInFlight,
            ECk_Signal_PostFireBehavior::DoNothing);

        DoAddKeyCapture(EKeys::W);
        DoAddKeyCapture(EKeys::S);
        DoAddKeyCapture(EKeys::A);
        DoAddKeyCapture(EKeys::D);
        DoAddKeyCapture(EKeys::E);
        DoAddKeyCapture(EKeys::Q);
        DoAddKeyCapture(EKeys::SpaceBar);
        DoAddKeyCapture(EKeys::C);

        // Mouse look observes rather than consumes: the deltas keep flowing to anything else that
        // reads them (a debugger, the intent record) while the pawn is the one acting on them.
        utils_input_layer::Request_AddCapture(_MoveLayer, FCk_Request_InputLayer_AddCapture(
            utils_input_layer::Make_KeyCapture(EKeys::MouseX, ECk_InputLayer_CaptureBehavior::PassThrough)));
        utils_input_layer::Request_AddCapture(_MoveLayer, FCk_Request_InputLayer_AddCapture(
            utils_input_layer::Make_KeyCapture(EKeys::MouseY, ECk_InputLayer_CaptureBehavior::PassThrough)));
    }

    private void DoAddKeyCapture(FKey InKey)
    {
        utils_input_layer::Request_AddCapture(_MoveLayer, FCk_Request_InputLayer_AddCapture(
            utils_input_layer::Make_KeyCapture(InKey, ECk_InputLayer_CaptureBehavior::Consume)));
    }

    UFUNCTION()
    private void OnMoveCaptured(FCk_Handle_InputLayer InLayer, FCk_InputSource_RawEvent InEvent, FCk_InputLayer_Capture InCapture)
    {
        auto Key = InEvent.Get_Key();

        if (InEvent.Get_EventType() == ECk_InputSource_EventType::AnalogAxis)
        {
            // Pitch is inverted to match the stock LookUp mapping's -1 scale; the controller's
            // InputYaw/PitchScale still applies downstream of these calls.
            if (Key == EKeys::MouseX)
            { AddControllerYawInput(InEvent.Get_AnalogValue() * _MouseLookScale); }
            else if (Key == EKeys::MouseY)
            { AddControllerPitchInput(-InEvent.Get_AnalogValue() * _MouseLookScale); }
            return;
        }

        auto Pressed = InEvent.Get_EventType() == ECk_InputSource_EventType::Pressed;

        if (Key == EKeys::W)             { _HeldForward = Pressed; }
        else if (Key == EKeys::S)        { _HeldBack = Pressed; }
        else if (Key == EKeys::D)        { _HeldRight = Pressed; }
        else if (Key == EKeys::A)        { _HeldLeft = Pressed; }
        else if (Key == EKeys::E)        { _HeldUp = Pressed; }
        else if (Key == EKeys::SpaceBar) { _HeldUp = Pressed; }
        else if (Key == EKeys::Q)        { _HeldDown = Pressed; }
        else if (Key == EKeys::C)        { _HeldDown = Pressed; }
    }

    //------------------------------------------------------------------------
    // Movement
    //------------------------------------------------------------------------

    private void DoApplyMovement()
    {
        auto ForwardAxis = (_HeldForward ? 1.0f : 0.0f) - (_HeldBack ? 1.0f : 0.0f);
        auto RightAxis   = (_HeldRight ? 1.0f : 0.0f) - (_HeldLeft ? 1.0f : 0.0f);
        auto UpAxis      = (_HeldUp ? 1.0f : 0.0f) - (_HeldDown ? 1.0f : 0.0f);

        if (ForwardAxis == 0.0f && RightAxis == 0.0f && UpAxis == 0.0f)
        { return; }

        // Fly-style, matching ADefaultPawn: forward/right follow the full control rotation
        // (pitch included), up/down is world Z.
        auto ControlRot = GetControlRotation();

        if (ForwardAxis != 0.0f)
        { AddMovementInput(ControlRot.GetForwardVector(), ForwardAxis); }

        if (RightAxis != 0.0f)
        { AddMovementInput(ControlRot.GetRightVector(), RightAxis); }

        if (UpAxis != 0.0f)
        { AddMovementInput(FVector(0.0, 0.0, 1.0), UpAxis); }
    }
}
