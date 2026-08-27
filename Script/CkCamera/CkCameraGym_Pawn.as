// Language=angelscript

//============================================================================
// CK CAMERA - GYM PAWN
//============================================================================
//
// A flyable pawn (ADefaultPawn movement) carrying the GameplayCamera director, plus a visible subject so the
// driven camera has something to frame. On ready it:
//   - adds the camera director on the pawn entity (whose actor-synced transform is the camera anchor, so the
//     boom follows the pawn) and hands it this pawn's UCk_CameraComponent, which the default
//     PlayerCameraManager reads via GetCameraView,
//   - spawns reference geometry centered on the pawn (floor + a ring of pillars for orbit parallax and camera
//     collision push-in) and a bright beacon as the lock-on target, and
//   - pushes the first camera mode.
//
// The pawn carries a visible body sphere + a forward "nose" cube (ADefaultPawn has no in-game mesh) so you can
// see what the camera frames and which way the pawn faces. These are visual-only (no collision) and the camera's
// collision whiskers ignore the whole pawn actor anyway (_TraceIgnoreActor = owning actor).
//
// The PlayerController drives orbit (look axis -> Request_SetOrientationIntention) and mode cycling, which
// call Request_Look / Request_CycleMode here.
//============================================================================

// The demo zoom trim uses a distinct (negative) priority so cycling modes (OneOnly at the default priority 0) does
// not evict it, and so the active mode - not the look-at-less trim - stays the dominant layer for auto-reorient.
const int32 k_TrimPriority = -10;

class ACk_CameraGym_Pawn : ACk_Gym_Base_Pawn
{
    // We drive the view via the GameplayCamera director, so turn off ADefaultPawn's built-in WASD + mouse-look
    // those move along / pitch the hidden control rotation (the cause of "W/S goes up/down" and the double-acting
    // mouse). Instead the mouse only orbits the camera, and movement is polled in Tick (enabled in Request_OnPawnReady)
    // and applied on the horizontal plane relative to the camera's view yaw.
    default bAddDefaultMovementBindings = false;

    // The director does NOT create this. _OutputComponent is the single essential constructor parameter of
    // FCk_Fragment_Camera_ParamsData and is get-only, so the component has to exist on the actor before Add
    // is called - Add ensures on it and returns an invalid handle otherwise.
    UPROPERTY(DefaultComponent)
    UCk_CameraComponent CameraComponent;

    // Visible subject - ADefaultPawn shows nothing in-game, so the third-person / top-down / lock-on cameras
    // would frame empty space. Body sphere + forward nose cube make position and facing readable.
    UPROPERTY(DefaultComponent)
    UStaticMeshComponent BodyMesh;

    UPROPERTY(DefaultComponent)
    UStaticMeshComponent NoseMesh;

    private FCk_Handle                _PawnEntity;
    private FCk_Handle_Camera _Camera;
    private FCk_Handle_Transform      _LockOnTarget;

    private TArray<TSubclassOf<UCk_CameraLayer_EntityScript>> _Modes;
    private int32                     _ModeIndex = 0;

    // Demo Trim toggle (FOV zoom) - layers over the active mode without being evicted on mode cycle.
    private bool                      _ZoomActive = false;

    UFUNCTION(BlueprintOverride)
    void ConstructionScript()
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Sphere = Cast<UStaticMesh>(LoadObject(this, "/Engine/BasicShapes/Sphere.Sphere"));
        auto Cube   = Cast<UStaticMesh>(LoadObject(this, "/Engine/BasicShapes/Cube.Cube"));
        auto Mat    = Cast<UMaterialInterface>(LoadObject(this, "/Engine/BasicShapes/BasicShapeMaterial.BasicShapeMaterial"));

        if (Sphere != nullptr) { BodyMesh.SetStaticMesh(Sphere); }
        if (Mat    != nullptr) { BodyMesh.SetMaterial(0, Mat); }
        BodyMesh.SetRelativeScale3D(FVector(0.7f, 0.7f, 0.7f));
        BodyMesh.SetCollisionEnabled(ECollisionEnabled::NoCollision);

        if (Cube != nullptr) { NoseMesh.SetStaticMesh(Cube); }
        if (Mat  != nullptr) { NoseMesh.SetMaterial(0, Mat); }
        NoseMesh.SetRelativeLocation(FVector(45.0f, 0.0f, 0.0f)); // pokes out +X (pawn forward)
        NoseMesh.SetRelativeScale3D(FVector(0.35f, 0.35f, 0.35f));
        NoseMesh.SetCollisionEnabled(ECollisionEnabled::NoCollision);
    }

    void OnEntityConstructed(FCk_Handle_EntityScript InEntityScriptHandle) override
    {
        _PawnEntity = FCk_Handle(InEntityScriptHandle);
        Request_OnPawnReady();
    }

    void Request_OnPawnReady() override
    {
        if (ck::Is_NOT_Valid(_PawnEntity))
        { return; }

        // The pawn entity (a WithActor entity script) already carries an actor-synced transform - that IS the camera
        // anchor, and the POV reads it each frame, so the boom follows the pawn with no extra transform to add.

        auto PawnTransform = _PawnEntity.As_Transform();
        _Camera = utils_camera::Add(PawnTransform, FCk_Fragment_Camera_ParamsData(CameraComponent));

        Request_SpawnReferenceGeometry();

        // Poll WASD / Space / Ctrl each frame for camera-relative free-fly (see Tick).
        SetActorTickEnabled(true);

        _Modes.Add(UCk_CameraLayer_ThirdPerson);
        _Modes.Add(UCk_CameraLayer_TopDown);
        _Modes.Add(UCk_CameraLayer_LockOn);

        _ModeIndex = 0;
        Request_ApplyMode();
    }

    // Floor + pillar ring + beacon, centered on the pawn's spawn point (robust to wherever the PlayerStart is).
    private void Request_SpawnReferenceGeometry()
    {
        const auto Center = GetActorLocation();

        // Floor: 4000cm x 4000cm slab. ACk_Gym_Floor puts its walkable surface ON its origin, so
        // spawning at Center lands the top face at the pawn's spawn height.
        auto Floor = SpawnActor(ACk_Gym_Floor, Center, FRotator::ZeroRotator, NAME_None, true);
        if (Floor != nullptr)
        {
            Floor.SetActorScale3D(FVector(40.0f, 40.0f, 0.5f));
            FinishSpawningActor(Floor);
        }

        // A ring of tall grey pillars (block ECC_Camera) - orbit parallax + camera collision push-in when one
        // passes between the camera and the pawn. 100cm footprint, 400cm tall, base on the floor.
        TArray<FVector2D> Offsets;
        Offsets.Add(FVector2D( 700.0f,    0.0f));
        Offsets.Add(FVector2D(-700.0f,    0.0f));
        Offsets.Add(FVector2D(   0.0f,  700.0f));
        Offsets.Add(FVector2D(   0.0f, -700.0f));
        Offsets.Add(FVector2D( 500.0f,  500.0f));
        Offsets.Add(FVector2D(-500.0f,  500.0f));
        Offsets.Add(FVector2D( 500.0f, -500.0f));
        Offsets.Add(FVector2D(-500.0f, -500.0f));

        for (auto Offset : Offsets)
        {
            const auto PillarLocation = Center + FVector(Offset.X, Offset.Y, 200.0f);
            auto Pillar = SpawnActor(ACk_Gym_ObstacleWall, PillarLocation, FRotator::ZeroRotator, NAME_None, true);
            if (Pillar != nullptr)
            {
                Pillar.SetActorScale3D(FVector(1.0f, 1.0f, 4.0f));
                FinishSpawningActor(Pillar);
            }
        }

        // Beacon = the fixed lock-on target, ~600cm in front (+X) of spawn at eye height. The lock-on transform
        // entity sits at the same world point so the auto-reorient mode tracks the visible sphere.
        const auto BeaconLocation = Center + FVector(600.0f, 0.0f, 150.0f);

        auto Beacon = SpawnActor(ACk_CameraGym_Beacon, BeaconLocation, FRotator::ZeroRotator, NAME_None, true);
        if (Beacon != nullptr)
        {
            Beacon.SetActorScale3D(FVector(1.5f, 1.5f, 1.5f));
            FinishSpawningActor(Beacon);
        }

        auto TargetEntity = utils_entity_lifetime::Request_CreateEntity(_PawnEntity);
        TargetEntity.Set_DebugName(n"Camera.LockOnTarget");
        _LockOnTarget = utils_transform::Add(
            TargetEntity, FTransform(BeaconLocation), ECk_Replication::DoesNotReplicate);
    }

    // Mouse-look sensitivity: scales raw Mouse2D pixel-delta into a roughly-normalized [0,1] orbit intention.
    // The modifier's OrientationControl speeds (deg/sec) then set the actual orbit rate. Bump this for faster look.
    const float32 _LookSensitivity = 0.05f;

    void Request_Look(FVector2D InLook)
    {
        if (ck::Is_NOT_Valid(_Camera))
        { return; }

        // X = yaw intention, Y = pitch intention. User-pref invert would also be applied here in a real game.
        _Camera.Request_SetOrientationIntention(
            FVector(InLook.X * _LookSensitivity, InLook.Y * _LookSensitivity, 0.0f));
    }

    // Free-fly movement, polled each frame and applied relative to the camera's view yaw so "forward" always means
    // "into the screen" regardless of where the pawn faces. Horizontal only (camera pitch is ignored) - Space/Ctrl
    // handle vertical. ADefaultPawn's default WASD/mouse-look are disabled (see class defaults), so nothing fights this.
    UFUNCTION(BlueprintOverride)
    void Tick(float32 InDeltaSeconds)
    {
        auto _CkPerfScope = ck::ScopedStat();
        if (ck::Is_NOT_Valid(_Camera))
        { return; }

        auto PC = Cast<APlayerController>(GetController());
        if (PC == nullptr)
        { return; }

        const auto YawRot  = FRotator(0.0f, utils_camera::Get_ViewRotation(_Camera).Yaw, 0.0f);
        const auto Forward = YawRot.GetForwardVector();
        const auto Right   = YawRot.GetRightVector();

        if (PC.IsInputKeyDown(EKeys::W)) { AddMovementInput(Forward,  1.0f); }
        if (PC.IsInputKeyDown(EKeys::S)) { AddMovementInput(Forward, -1.0f); }
        if (PC.IsInputKeyDown(EKeys::D)) { AddMovementInput(Right,    1.0f); }
        if (PC.IsInputKeyDown(EKeys::A)) { AddMovementInput(Right,   -1.0f); }

        // Vertical free-fly - Space up, Left Ctrl down (E/Q are taken by mode cycling).
        if (PC.IsInputKeyDown(EKeys::SpaceBar))    { AddMovementInput(FVector(0.0f, 0.0f, 1.0f),  1.0f); }
        if (PC.IsInputKeyDown(EKeys::LeftControl)) { AddMovementInput(FVector(0.0f, 0.0f, 1.0f), -1.0f); }
    }

    void Request_CycleMode(int32 InDir)
    {
        if (_Modes.Num() == 0)
        { return; }

        _ModeIndex = (_ModeIndex + InDir + _Modes.Num()) % _Modes.Num();
        Request_ApplyMode();
    }

    // Toggles a FOV-zoom Trim that layers on top of whichever mode is active. Because it lives in its own ordering
    // group, cycling modes does not evict it; because the profile is rebuilt each frame, removing it just restores
    // the mode's FOV next frame.
    void Request_ToggleZoom()
    {
        if (ck::Is_NOT_Valid(_Camera))
        { return; }

        if (_ZoomActive)
        {
            auto Request = FCk_Request_Camera_RemoveLayer(UCk_CameraLayer_FovZoom);
            Request.Set_BlendOutTime(FCk_Time(0.2));
            _Camera.Request_RemoveLayer(Request);
            _ZoomActive = false;
            Print("Camera zoom: OFF", 4.0f);
        }
        else
        {
            auto Request = FCk_Request_Camera_AddLayer(UCk_CameraLayer_FovZoom);
            Request.Set_StackingBehavior(ECk_Camera_StackingBehavior::Additive);
            Request.Set_Priority(k_TrimPriority);
            Request.Set_BlendInTime(FCk_Time(0.2));
            _Camera.Request_AddLayer(Request);
            _ZoomActive = true;
            Print("Camera zoom: ON (FOV Trim layered over the active mode)", 4.0f);
        }
    }

    private void Request_ApplyMode()
    {
        if (ck::Is_NOT_Valid(_Camera))
        { return; }

        auto ModeClass = _Modes[_ModeIndex];

        // OneOnly (shared default ordering group) -> the new mode blends in and evicts the previous one.
        auto Request = FCk_Request_Camera_AddLayer(ModeClass);
        Request.Set_StackingBehavior(ECk_Camera_StackingBehavior::OneOnly);
        Request.Set_BlendInTime(FCk_Time(0.4));

        if (ModeClass == UCk_CameraLayer_LockOn)
        { Request.Set_CameraTarget(FCk_Camera_Target(_LockOnTarget, ECk_Camera_TargetMode::LookAt)); }

        _Camera.Request_AddLayer(Request);

        Print("Camera mode: " + Get_ModeName(ModeClass) + "   [E/Q to cycle, mouse to orbit]", 4.0f);
    }

    private FString Get_ModeName(TSubclassOf<UCk_CameraLayer_EntityScript> InClass) const
    {
        if (InClass == UCk_CameraLayer_ThirdPerson) { return "Third-Person (orbit + collision)"; }
        if (InClass == UCk_CameraLayer_TopDown)     { return "Top-Down (fixed framing)"; }
        if (InClass == UCk_CameraLayer_LockOn)      { return "Lock-On (auto-reorient to beacon)"; }
        return "Unknown";
    }
}
