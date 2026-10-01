// Language=angelscript
// A character whose entity is spawned on the actor (the ActorEntity helper's pattern); its movement component is the
// gait's motion source (AddGait puts it on the spec). Flying mode is the test's "grounded, moving" state: IsFalling() is false and a set Velocity persists
// (BrakingDecelerationFlying is 0 by default), which Walking cannot offer 40 000 cm below any floor.
class ACk_GaitAutoTest_Character : ACharacter
{
    default bReplicates = false;
    default CharacterMovement.MaxFlySpeed = 2000.0f;

    FCk_Handle_PendingEntityScript PendingEntity;

    UFUNCTION(BlueprintOverride)
    void BeginPlay()
    {
        auto _CkPerfScope = ck::ScopedStat();
        PendingEntity = utils_entity_script_with_actor::Request_SpawnEntityScript_OnActor(this, UCkAutoTest_ActorEntity_EntityScript);
    }

    void Fly(FVector InVelocity)
    {
        CharacterMovement.SetMovementMode(EMovementMode::MOVE_Flying);
        CharacterMovement.Velocity = InVelocity;
    }

    void Fall(float32 InDownSpeed)
    {
        CharacterMovement.SetMovementMode(EMovementMode::MOVE_Falling);
        CharacterMovement.Velocity = FVector(0.0, 0.0, -InDownSpeed);
    }

    // "Landing" for the tests is Falling -> Flying: Flying is not falling and stays put (Walking with no floor under the
    // character would drop back to Falling on the next movement tick).
    void Land()
    {
        CharacterMovement.SetMovementMode(EMovementMode::MOVE_Flying);
        CharacterMovement.Velocity = FVector::ZeroVector;
    }
}

struct FCk_GaitAutoTestFixture
{
    ACk_GaitAutoTest_Character Character;
    FCk_Handle Entity;              // the character's entity (gait lives here)
    FCk_Handle_Transform Root;      // a plain transform NOT owned by the character: bob nodes hang here so a destroyed
                                    // character leaves the bob alive with a dead gait (DestroyingGaitRelaxesToRest)
    FCk_Handle_Gait Gait;
    FCk_Handle_Bob Bob;
    FVector Origin;

    // Spawns the character at InOrigin; the caller promises OnConstructed on Character.PendingEntity and then calls Ready.
    void Spawn(UCk_AutoTest_Base InTest, FVector InOrigin = FVector(0.0, 0.0, -40000.0))
    {
        Origin = InOrigin;
        Character = Cast<ACk_GaitAutoTest_Character>(SpawnActor(ACk_GaitAutoTest_Character, InOrigin, FRotator::ZeroRotator));
        if (ck::Is_NOT_Valid(Character))
        {
            InTest.FinishFailure("Failed to spawn the gait test character");
            return;
        }
        // Start in the "grounded, at rest" state so the gait's first sample is not an airborne one that a later Fly would
        // turn into a landing.
        Character.Fly(FVector::ZeroVector);
    }

    void Ready(FCk_Handle InOwner, FCk_Handle_EntityScript InEntityScript)
    {
        Entity = FCk_Handle(InEntityScript);
        Root = utils_transform::Create(InOwner, FTransform(Origin), ECk_Replication::DoesNotReplicate);
    }

    void AddGait(FCk_Gait_Spec InTunables)
    {
        auto Spec = InTunables;
        Spec.Set_MovementComponent(Character.CharacterMovement);
        Gait = utils_gait::Add(Entity, Spec);
    }

    void CreateBob(FTransform InRest, FCk_Bob_Spec InSpec)
    {
        auto Spec = InSpec;
        Spec.Set_Gait(Gait);
        Bob = utils_bob::Create(Root, InRest, Spec);
    }

    FTransform BobWorld() const
    {
        return utils_transform::Get_EntityCurrentTransform(Bob.As_Transform());
    }

    FTransform RootWorld() const
    {
        return utils_transform::Get_EntityCurrentTransform(Root);
    }

    void DestroyCharacter()
    {
        if (ck::IsValid(Character))
        {
            Character.DestroyActor();
        }
    }
}
