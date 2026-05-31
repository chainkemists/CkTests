// Language=angelscript

//============================================================================
// CK CAMERA — GAMEPLAYCAMERA GYM
//============================================================================
//
// Visual gym for the GameplayCamera stack. A flyable pawn carries the camera director; the player orbits with
// the mouse and cycles modes (third-person / top-down / lock-on) with E/Q, watching blended transitions,
// collision push-in, and auto-reorient lock-on on screen.
//
// First CkTests gym to combine a controllable pawn + Enhanced Input + a driven camera. Input is plain Enhanced
// Input (IMC over AS-asset IAs + BindAction) — no input-profile-object wrapper.
//
// Register: CkTests_GymRegistry.as → "Camera". Runs in the shared TestGyms_CkTests_Level.
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

    // Skip the base gym-selector menu — the camera gym is interactive from the start (Tab still toggles the menu).
    void Request_StartGym() override
    {
        Print("Camera Gym — Mouse: orbit | E/Q: cycle mode (ThirdPerson / TopDown / LockOn) | "
            + "console: Ck_GymCamera_ToggleZoom (FOV trim) | Tab: gym menu", 12.0f);
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
        auto CameraPawn = Cast<ACk_CameraGym_Pawn>(GetControlledPawn());
        if (ck::IsValid(CameraPawn))
        { CameraPawn.Request_CycleMode(1); }
    }

    UFUNCTION()
    private void OnPrevMode(FInputActionValue ActionValue, float32 ElapsedTime, float32 TriggeredTime, const UInputAction SourceAction)
    {
        auto CameraPawn = Cast<ACk_CameraGym_Pawn>(GetControlledPawn());
        if (ck::IsValid(CameraPawn))
        { CameraPawn.Request_CycleMode(-1); }
    }

    // ----------------------------------------------------------------------------------------------------------------
    // CONSOLE COMMANDS (keyboard-free mode switching)
    // ----------------------------------------------------------------------------------------------------------------

    UFUNCTION(Exec, DisplayName="Camera Gym - Next Mode")
    void Ck_GymCamera_NextMode()
    {
        auto CameraPawn = Cast<ACk_CameraGym_Pawn>(GetControlledPawn());
        if (ck::IsValid(CameraPawn))
        { CameraPawn.Request_CycleMode(1); }
    }

    UFUNCTION(Exec, DisplayName="Camera Gym - Prev Mode")
    void Ck_GymCamera_PrevMode()
    {
        auto CameraPawn = Cast<ACk_CameraGym_Pawn>(GetControlledPawn());
        if (ck::IsValid(CameraPawn))
        { CameraPawn.Request_CycleMode(-1); }
    }

    // Toggles the FOV-zoom Trim — layers over whichever mode is active, demonstrating the Mode/Trim split.
    UFUNCTION(Exec, DisplayName="Camera Gym - Toggle Zoom Trim")
    void Ck_GymCamera_ToggleZoom()
    {
        auto CameraPawn = Cast<ACk_CameraGym_Pawn>(GetControlledPawn());
        if (ck::IsValid(CameraPawn))
        { CameraPawn.Request_ToggleZoom(); }
    }
}
