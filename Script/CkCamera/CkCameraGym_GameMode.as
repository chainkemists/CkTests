// Language=angelscript

//============================================================================
// CK CAMERA - GAMEPLAYCAMERA GYM
//============================================================================
//
// Visual gym for the GameplayCamera stack. A flyable pawn carries the camera director; the player orbits with
// the mouse and cycles modes (third-person / top-down / lock-on) with E/Q, watching blended transitions,
// collision push-in, and auto-reorient lock-on on screen.
//
// First CkTests gym to combine a controllable pawn + Enhanced Input + a driven camera. Input is plain Enhanced
// Input (IMC over AS-asset IAs + BindAction) - no input-profile-object wrapper.
//
// Register: CkTests_GymRegistry.as -> "Camera". Runs in the shared TestGyms_CkTests_Level.
//============================================================================

class ACk_CameraGym_GameMode : ACkTests_Gym_Base_GameMode
{
    default PlayerControllerClass = ACk_CameraGym_PlayerController;
    default DefaultPawnClass      = ACk_CameraGym_Pawn;
}

// --------------------------------------------------------------------------------------------------------------------

class ACk_CameraGym_PlayerController : ACk_Gym_Base_PlayerController
{
    UPROPERTY(DefaultComponent)
    UEnhancedInputComponent InputComp;

    UFUNCTION(BlueprintOverride)
    void BeginPlay()
    {
        auto _CkPerfScope = ck::ScopedStat();
        Super::BeginPlay();

        // The Enhanced Input subsystem only exists for the local player, so this also gates input setup to it.
        auto Subsystem = UEnhancedInputLocalPlayerSubsystem::Get(this);
        if (ck::Is_NOT_Valid(Subsystem))
        { return; }

        auto MappingContext = NewObject(this, UInputMappingContext);
        MappingContext.MapKey(ck_camera_gym::Asset_IA_CameraLook,     EKeys::Mouse2D);
        MappingContext.MapKey(ck_camera_gym::Asset_IA_CameraNextMode, EKeys::E);
        MappingContext.MapKey(ck_camera_gym::Asset_IA_CameraPrevMode, EKeys::Q);

        FModifyContextOptions Options;
        Subsystem.AddMappingContext(MappingContext, 0, Options);

        PushInputComponent(InputComp);
        InputComp.BindAction(ck_camera_gym::Asset_IA_CameraLook, ETriggerEvent::Triggered,
            FEnhancedInputActionHandlerDynamicSignature(this, n"OnLook"));
        InputComp.BindAction(ck_camera_gym::Asset_IA_CameraNextMode, ETriggerEvent::Started,
            FEnhancedInputActionHandlerDynamicSignature(this, n"OnNextMode"));
        InputComp.BindAction(ck_camera_gym::Asset_IA_CameraPrevMode, ETriggerEvent::Started,
            FEnhancedInputActionHandlerDynamicSignature(this, n"OnPrevMode"));
    }

    // Skip the base gym-selector menu - the camera gym is interactive from the start (Tab still toggles the menu).
    void Request_StartGym() override
    {
        Print("Camera Gym - Mouse: orbit | E/Q: cycle mode (ThirdPerson / TopDown / LockOn) | "
            + "control panel: J/K cycle mode, B zoom trim | Tab: gym menu", 12.0f);
    }

    // ----------------------------------------------------------------------------------------------------------------
    // INPUT HANDLERS
    // ----------------------------------------------------------------------------------------------------------------

    UFUNCTION()
    private void OnLook(FInputActionValue ActionValue, float32 ElapsedTime, float32 TriggeredTime, const UInputAction SourceAction)
    {
        auto CameraPawn = Cast<ACk_CameraGym_Pawn>(GetControlledPawn());
        if (ck::IsValid(CameraPawn))
        { CameraPawn.Request_Look(ActionValue.GetAxis2D()); }
    }

    UFUNCTION()
    private void OnNextMode(FInputActionValue ActionValue, float32 ElapsedTime, float32 TriggeredTime, const UInputAction SourceAction)
    {
        DoCycleMode(1);
    }

    UFUNCTION()
    private void OnPrevMode(FInputActionValue ActionValue, float32 ElapsedTime, float32 TriggeredTime, const UInputAction SourceAction)
    {
        DoCycleMode(-1);
    }

    // ----------------------------------------------------------------------------------------------------------------
    // MODE / TRIM DRIVE
    //
    // The pawn owns the mode index and the zoom flag privately and exposes no getter, so the panel
    // mirrors both here. Every path that changes them - E/Q and the rows alike - goes through these
    // two functions, which is what keeps the mirrors honest.
    // ----------------------------------------------------------------------------------------------------------------

    private int32 _ModeIndex = 0;
    private bool _ZoomActive = false;

    private void DoCycleMode(int32 InDir)
    {
        auto CameraPawn = Cast<ACk_CameraGym_Pawn>(GetControlledPawn());
        if (ck::Is_NOT_Valid(CameraPawn))
        { return; }

        // Three modes, in the order the pawn composes them (ACk_CameraGym_Pawn::_Modes).
        _ModeIndex = (_ModeIndex + InDir + 3) % 3;
        CameraPawn.Request_CycleMode(InDir);
    }

    private void DoToggleZoom()
    {
        auto CameraPawn = Cast<ACk_CameraGym_Pawn>(GetControlledPawn());
        if (ck::Is_NOT_Valid(CameraPawn))
        { return; }

        _ZoomActive = !_ZoomActive;
        CameraPawn.Request_ToggleZoom();
    }

    private FString Get_ModeLabel(int32 InIndex)
    {
        if (InIndex == 0) { return "Third-Person"; }
        if (InIndex == 1) { return "Top-Down"; }
        return "Lock-On";
    }

    //--------------------------------------------------------------------------------------------------------------------------
    // CONTROL PANEL (Script/Common/CkGym_ControlPanel.as)
    //
    // E/Q still cycle - the rows exist so the mode ring and the FOV trim are visible and reachable
    // without knowing that E/Q do anything, and so the ACTIVE mode is on screen rather than only in
    // the four-second Print that announced the last change.
    //--------------------------------------------------------------------------------------------------------------------------

    FString Get_ControlPanelTitle() override
    {
        return "GAMEPLAY CAMERA";
    }

    TArray<FCkGym_ControlRow> Get_ControlRows() override
    {
        auto Rows = TArray<FCkGym_ControlRow>();
        Rows.Add(CkGym_Control::Cycle(EKeys::J, "J", "Camera mode (next)", Get_ModeLabel(_ModeIndex)));
        Rows.Add(CkGym_Control::Action(EKeys::K, "K", "Camera mode (previous)"));
        Rows.Add(CkGym_Control::Toggle(EKeys::B, "B", "FOV zoom trim", _ZoomActive));
        return Rows;
    }

    void Request_ControlActivated(int32 InRowIndex) override
    {
        if (InRowIndex == 0) { DoCycleMode(1); }
        else if (InRowIndex == 1) { DoCycleMode(-1); }
        else if (InRowIndex == 2) { DoToggleZoom(); }
    }
}
