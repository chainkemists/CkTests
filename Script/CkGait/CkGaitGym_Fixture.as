// Language=angelscript

// The gym's walking character. It has no controller, so its movement component runs no physics: the scripted velocity
// is reported to the gait exactly as set and the body stays on its station (a treadmill), which keeps the bobs framed.
class ACk_GaitGym_Walker : ACharacter
{
    default bReplicates = false;
    default CharacterMovement.MaxFlySpeed = 2000.0f;

    // A capsule-sized body so the bobbed head cubes read against something.
    UPROPERTY(DefaultComponent)
    UStaticMeshComponent Body;

    FCk_Handle_PendingEntityScript PendingEntity;

    private float _ScriptSeconds = 0.0f;
    private int32 _AppliedCommand = -1;

    UFUNCTION(BlueprintOverride)
    void ConstructionScript()
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Cube = Cast<UStaticMesh>(LoadObject(this, "/Engine/BasicShapes/Cube.Cube"));
        if (Cube != nullptr)
        {
            Body.SetStaticMesh(Cube);
        }

        Body.SetRelativeScale3D(FVector(0.6, 0.6, 1.7));
        Body.SetCollisionEnabled(ECollisionEnabled::NoCollision);
    }

    UFUNCTION(BlueprintOverride)
    void BeginPlay()
    {
        auto _CkPerfScope = ck::ScopedStat();
        PendingEntity = utils_entity_script_with_actor::Request_SpawnEntityScript_OnActor(this, UCkAutoTest_ActorEntity_EntityScript);
    }

    // Motion script (no input): fly +X at 420 cm/s for 3 s, -X for 3 s, repeat; every 7 s a 0.5 s hop (falling at 500 cm/s),
    // then back to flying. Flying is the gait's "grounded, moving" state; leaving the hop is the landing.
    UFUNCTION(BlueprintOverride)
    void Tick(float InDeltaSeconds)
    {
        _ScriptSeconds += InDeltaSeconds;
        const auto Command = Get_ScriptCommand(_ScriptSeconds);
        if (Command == _AppliedCommand)
        {
            return;
        }

        _AppliedCommand = Command;

        if (Command == 2)
        {
            CharacterMovement.SetMovementMode(EMovementMode::MOVE_Falling);
            CharacterMovement.Velocity = FVector(0.0, 0.0, -500.0);
            return;
        }

        CharacterMovement.SetMovementMode(EMovementMode::MOVE_Flying);
        CharacterMovement.Velocity = FVector(Command == 0 ? 420.0 : -420.0, 0.0, 0.0);
    }

    // 0 = fly +X, 1 = fly -X, 2 = hop.
    int32 Get_ScriptCommand(float InSeconds) const
    {
        const auto HopClock = InSeconds - 7.0 * int32(InSeconds / 7.0);
        if (HopClock >= 6.5)
        {
            return 2;
        }

        return int32(InSeconds / 3.0) % 2 == 0 ? 0 : 1;
    }
}

struct FCkGaitGym_Fixture
{
    ACk_GaitGym_Walker Walker;
    FCk_Handle_Gait Gait;
    TArray<FCk_Handle_Bob> Bobs;
    FVector Origin;

    // Spawns the walker; the caller promises OnConstructed on Walker.PendingEntity and then calls Compose.
    bool Spawn(FVector InOrigin)
    {
        Origin = InOrigin;
        Bobs.Reset();
        Walker = Cast<ACk_GaitGym_Walker>(SpawnActor(ACk_GaitGym_Walker, InOrigin, FRotator::ZeroRotator));
        return ck::IsValid(Walker);
    }

    // InMeshListener receives the cube mesh components as they are added (FCk_Delegate_UnrealComponent_OnAdded needs a UObject).
    bool Compose(UObject InMeshListener, FCk_Handle_EntityScript InEntityScript)
    {
        auto Entity = FCk_Handle(InEntityScript);
        auto GaitSpec = FCk_Gait_Spec();
        GaitSpec.Set_MovementComponent(Walker.CharacterMovement);
        Gait = utils_gait::Add(Entity, GaitSpec);
        if (ck::Is_NOT_Valid(Gait))
        {
            return false;
        }

        auto WalkerTransform = Entity.As_Transform();
        auto Raw = utils_bob::Create(WalkerTransform, FTransform(FVector(0.0, -40.0, 80.0)), Make_DemoSpec());
        auto Lagged = Make_DemoSpec();
        Lagged.Set_LagRate(14.0f);
        auto Smoothed = utils_bob::Create(WalkerTransform, FTransform(FVector(0.0, 0.0, 110.0)), Lagged);
        if (ck::Is_NOT_Valid(Raw) || ck::Is_NOT_Valid(Smoothed))
        {
            return false;
        }

        Bobs.Add(Raw);
        Bobs.Add(Smoothed);

        Add_Cube(InMeshListener, Raw.As_Transform());
        Add_Cube(InMeshListener, Smoothed.As_Transform());
        // The rigid twin: same height, 80 cm across from the raw bob, directly on the walker, so the bob reads against it.
        auto Twin = utils_scene_node::Create(WalkerTransform, FTransform(FVector(0.0, 40.0, 80.0)));
        Add_Cube(InMeshListener, Twin.As_Transform());
        return true;
    }

    // Demonstration tune: larger than a gameplay head bob so it reads at gym distance. Not a recommended gameplay tune.
    FCk_Bob_Spec Make_DemoSpec() const
    {
        auto Stride = FCk_Bob_StrideParams(6.0f, 4.0f);
        Stride.Set_RollDeg(6.0f);
        Stride.Set_PitchDeg(4.0f);
        auto Air = FCk_Bob_AirParams();
        Air.Set_Spring(FCk_Bob_SpringResponse(3.0f, 0.35f));

        auto Spec = FCk_Bob_Spec();
        Spec.Set_Gait(Gait);
        Spec.Set_Stride(Stride);
        Spec.Set_Air(Air);
        Spec.Set_LagRate(0.0f);
        return Spec;
    }

    void Add_Cube(UObject InMeshListener, FCk_Handle_Transform InAttachTo)
    {
        auto Node = utils_scene_node::Create(InAttachTo, FTransform(FRotator::ZeroRotator, FVector::ZeroVector, FVector(0.25, 0.25, 0.25)));
        const auto ComponentParams = utils_unreal_component::Make_Params(UStaticMeshComponent,
            ECk_UnrealComponent_TickPolicy::DoNotTick, n"GaitGym_Cube");
        auto ComponentHandle = utils_unreal_component::Add(FCk_Handle(Node), ComponentParams);
        utils_unreal_component::BindTo_OnAdded(ComponentHandle,
            FCk_Delegate_UnrealComponent_OnAdded(InMeshListener, n"OnGaitGymCubeAdded"));
    }

    void Request_Destroy()
    {
        if (ck::IsValid(Walker))
        {
            Walker.DestroyActor();
        }
    }
}
