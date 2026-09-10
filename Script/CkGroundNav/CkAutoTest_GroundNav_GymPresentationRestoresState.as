// Language=angelscript

//============================================================================
// GROUND NAV - AUTOMATION TEST: SHARED GYM PRESENTATION RESTORES STATE
//============================================================================
//
// Exercises the shared navigation presentation controller itself, not a gym
// adapter. The controller and view pawn are test-owned: this never takes over
// the PIE player's controller or starts a scenario gym. A spawned controller
// receives its real PlayerCameraManager in APlayerController::PostInitialize-
// Components, so its public row dispatcher can run Home, End and Backspace
// against a real camera, pawn and StaticMeshComponent.
//
// The fixture controller deliberately suppresses ACk_Gym_Base_PlayerController
// startup. That isolates inherited presentation/camera/material behaviour from
// unrelated gym station, ECS bootstrap and switchboard lifecycle. This is not
// whole-gym visual, input-routing, startup or lifecycle acceptance.
//============================================================================

class ACkGroundNavPresentationFixtureController : ACk_NavigationGym_Presentation_PlayerController
{
    // The production base boots gym station/ECS/switchboard infrastructure. This focused test needs
    // only its inherited public presentation controls and must not queue unrelated actor-backed ECS work.
    UFUNCTION(BlueprintOverride)
    void BeginPlay()
    {
    }
}

class UCk_AutoTest_GroundNav_GymPresentationRestoresState : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;

    private ACkGroundNavPresentationFixtureController _PresentationController;
    private APawn _ViewPawn;
    private AStaticMeshActor _TaggedMesh;
    private AStaticMeshActor _UntaggedMesh;
    private UMaterialInterface _TaggedOriginalMaterial;
    private UMaterialInterface _UntaggedOriginalMaterial;
    private FTransform _TaggedOriginalTransform;
    private FTransform _UntaggedOriginalTransform;
    private FName _TaggedOriginalCollision;
    private FName _UntaggedOriginalCollision;
    private ECk_NavSurface_Provider _ProviderBefore;
    private int64 _SurfaceRevisionBefore = 0;
    private ECkGym_ControlPanel_Mode _PanelModeBefore;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Cube = Cast<UStaticMesh>(LoadObject(UStaticMesh, "/Engine/BasicShapes/Cube.Cube"));
        if (ck::Is_NOT_Valid(Cube))
        {
            FailAndCleanUp("staging failed: /Engine/BasicShapes/Cube.Cube could not be loaded");
            return;
        }

        _PresentationController = Cast<ACkGroundNavPresentationFixtureController>(SpawnActor(
            ACkGroundNavPresentationFixtureController, FVector(0.0, 50000.0, 500.0)));
        _ViewPawn = Cast<APawn>(SpawnActor(APawn, FVector(0.0, 50000.0, 500.0)));
        _TaggedMesh = SpawnMesh(Cube, FVector(-300.0, 50000.0, 100.0), true);
        _UntaggedMesh = SpawnMesh(Cube, FVector(300.0, 50000.0, 100.0), false);

        if (ck::Is_NOT_Valid(_PresentationController) || ck::Is_NOT_Valid(_ViewPawn) ||
            ck::Is_NOT_Valid(_TaggedMesh) || ck::Is_NOT_Valid(_UntaggedMesh))
        {
            FailAndCleanUp("staging failed: the isolated presentation controller, view pawn, or mesh actor could not be spawned");
            return;
        }

        _TaggedOriginalMaterial = _TaggedMesh.StaticMeshComponent.GetMaterial(0);
        _UntaggedOriginalMaterial = _UntaggedMesh.StaticMeshComponent.GetMaterial(0);
        _TaggedOriginalTransform = _TaggedMesh.GetActorTransform();
        _UntaggedOriginalTransform = _UntaggedMesh.GetActorTransform();
        _TaggedOriginalCollision = _TaggedMesh.StaticMeshComponent.GetCollisionProfileName();
        _UntaggedOriginalCollision = _UntaggedMesh.StaticMeshComponent.GetCollisionProfileName();
        _ProviderBefore = utils_nav_surface::Get_Provider();
        _SurfaceRevisionBefore = utils_nav_surface::Get_SurfaceRevision();
        _PanelModeBefore = UCk_Utils_GymStartup_UE::Get_ControlPanelMode();

        if (ck::Is_NOT_Valid(_TaggedOriginalMaterial) || ck::Is_NOT_Valid(_UntaggedOriginalMaterial))
        {
            FailAndCleanUp("staging failed: the engine cube has no slot-zero material to restore");
            return;
        }

        Assert_Equals_Int(_PresentationController.Get_ControlRows().Num(), 4,
            "The standalone shared presentation controller exposes its three actions and Provider status row");
        Assert_True(_PresentationController.Request_HandlePresentationControl(-1) == false,
            "An out-of-range control row is rejected without dispatch");
        Assert_True(_PresentationController.Get_PresentationMode() == ECkNavigationGym_PresentationMode::Baseline,
            "An out-of-range control row must leave the persisted presentation mode at Baseline");

        // Home is dispatched through the production row entry point while no pawn is possessed.
        // Request_PresentationFrame must reject it before it changes material or persisted mode.
        _PresentationController.Request_ControlActivated(0);
        Assert_True(_PresentationController.Get_PresentationMode() == ECkNavigationGym_PresentationMode::Baseline,
            "An unpossessed Hero request must leave the persisted presentation mode at Baseline");
        Assert_True(_TaggedMesh.StaticMeshComponent.GetMaterial(0) == _TaggedOriginalMaterial,
            "An unpossessed Hero request must not change a tagged mesh material");

        // This is a test-owned pawn and controller. Do not borrow or replace the PIE player's pair.
        _PresentationController.Possess(_ViewPawn);
        if (ck::Is_NOT_Valid(_PresentationController.PlayerCameraManager) ||
            ck::Is_NOT_Valid(_PresentationController.GetControlledPawn()))
        {
            FailAndCleanUp("staging failed: spawned PlayerController did not provide a camera manager and possessed pawn");
            return;
        }

        _PresentationController.Request_ControlActivated(0); // Home
        Assert_True(_PresentationController.Get_PresentationMode() == ECkNavigationGym_PresentationMode::Hero,
            "Home through Request_ControlActivated enters Hero presentation mode");
        Assert_True(_TaggedMesh.StaticMeshComponent.GetMaterial(0) != _TaggedOriginalMaterial,
            "Home applies the showcase material only to tagged presentation geometry");
        Assert_True(_UntaggedMesh.StaticMeshComponent.GetMaterial(0) == _UntaggedOriginalMaterial,
            "Home leaves untagged geometry on its original material");

        _PresentationController.Request_ControlActivated(1); // End
        Assert_True(_PresentationController.Get_PresentationMode() == ECkNavigationGym_PresentationMode::Diagnostic,
            "End through Request_ControlActivated enters Diagnostic presentation mode");

        _PresentationController.Request_ControlActivated(2); // Backspace
        Assert_True(_PresentationController.Get_PresentationMode() == ECkNavigationGym_PresentationMode::Baseline,
            "Backspace through Request_ControlActivated restores persisted Baseline presentation mode");
        Assert_True(_TaggedMesh.StaticMeshComponent.GetMaterial(0) == _TaggedOriginalMaterial,
            "Backspace restores the tagged mesh's original material");
        Assert_True(_UntaggedMesh.StaticMeshComponent.GetMaterial(0) == _UntaggedOriginalMaterial,
            "Backspace leaves the untagged mesh material unchanged");
        Assert_True(_TaggedMesh.GetActorTransform().Equals(_TaggedOriginalTransform),
            "Presentation controls do not move or scale tagged geometry");
        Assert_True(_UntaggedMesh.GetActorTransform().Equals(_UntaggedOriginalTransform),
            "Presentation controls do not move or scale untagged geometry");
        Assert_True(_TaggedMesh.StaticMeshComponent.GetCollisionProfileName() == _TaggedOriginalCollision &&
            _UntaggedMesh.StaticMeshComponent.GetCollisionProfileName() == _UntaggedOriginalCollision,
            "Presentation controls do not change collision on either mesh");
        Assert_True(utils_nav_surface::Get_Provider() == _ProviderBefore,
            "Presentation controls do not change the active navigation provider");
        Assert_True(utils_nav_surface::Get_SurfaceRevision() == _SurfaceRevisionBefore,
            "Presentation controls do not rebuild or otherwise advance the navigation surface revision");
        Assert_True(UCk_Utils_GymStartup_UE::Get_ControlPanelMode() == _PanelModeBefore,
            "Presentation controls leave the user's persisted panel preference unchanged");

        CleanUp();
        FinishSuccess();
    }

    UFUNCTION(BlueprintOverride)
    void DoEndPlay(FCk_Handle InHandle)
    {
        CleanUp();
    }

    private AStaticMeshActor SpawnMesh(UStaticMesh InMesh, FVector InLocation, bool InIsPresentationMesh)
    {
        auto MeshActor = Cast<AStaticMeshActor>(SpawnActor(AStaticMeshActor, InLocation));
        if (ck::Is_NOT_Valid(MeshActor))
        { return nullptr; }

        MeshActor.StaticMeshComponent.SetMobility(EComponentMobility::Movable);
        MeshActor.StaticMeshComponent.SetStaticMesh(InMesh);
        MeshActor.StaticMeshComponent.SetCollisionProfileName(n"NoCollision");
        if (InIsPresentationMesh)
        { MeshActor.Tags.Add(n"CkNavigationGym.Presentation"); }
        return MeshActor;
    }

    private void FailAndCleanUp(FString InMessage)
    {
        CleanUp();
        FinishFailure(InMessage);
    }

    private void CleanUp()
    {
        if (ck::IsValid(_PresentationController))
        { _PresentationController.UnPossess(); }
        if (ck::IsValid(_TaggedMesh))
        { _TaggedMesh.DestroyActor(); }
        if (ck::IsValid(_UntaggedMesh))
        { _UntaggedMesh.DestroyActor(); }
        if (ck::IsValid(_ViewPawn))
        { _ViewPawn.DestroyActor(); }
        if (ck::IsValid(_PresentationController))
        { _PresentationController.DestroyActor(); }
    }
}
