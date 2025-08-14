UCLASS()
class ACk_AudioGym_Pawn : ADefaultPawn
{
    UPROPERTY(DefaultComponent)
    USceneComponent Root;

    UPROPERTY(DefaultComponent)
    UCk_EntityBridge_ActorComponent_UE EntityBridge;
    default EntityBridge._Replication = ECk_Replication::Replicates;
    default EntityBridge._ConstructionScript = UCk_Entity_ConstructionScript_WithTransform_PDA;

    UFUNCTION(BlueprintOverride)
    void ConstructionScript()
    {
        EntityBridge._OnPreConstruct.AddUFunction(this, n"EcsConstructionScript");
        EntityBridge._OnReplicationComplete_MC.AddUFunction(this, n"OnReplicationComplete");
    }

    UFUNCTION()
    private void EcsConstructionScript(FCk_Handle InEntity)
    {
        utils_transform::Add(InEntity, GetActorTransform(), ECk_Replication::DoesNotReplicate);
    }

    UFUNCTION()
    void OnReplicationComplete(FCk_Handle InEntity)
    {
        // Add player tag and shape for zone detection
        auto SelfEntity = ck::SelfEntity(this);
        auto TransformHandle = SelfEntity.To_FCk_Handle_Transform();

        utils_entity_tag::Add_UsingGameplayTag(SelfEntity,
            utils_gameplay_tag::ResolveGameplayTag(n"Pawn.Player"));

        auto PlayerShape = utils_shapes::Make_Capsule(
            FCk_ShapeCapsule_Dimensions(50.0f, 25.0f)); // HalfHeight, Radius
        utils_shapes::Add(SelfEntity, PlayerShape);

        auto ProbeParams = FCk_Fragment_Probe_ParamsData();
        ProbeParams._ProbeName = utils_gameplay_tag::ResolveGameplayTag(n"Player.Probe");
        ProbeParams._MotionType = ECk_MotionType::Kinematic;
        ProbeParams._ResponsePolicy = ECk_ProbeResponse_Policy::Notify;

        utils_probe::Add(TransformHandle, ProbeParams, FCk_Probe_DebugInfo());
    }

    UFUNCTION(BlueprintOverride)
    void Tick(float DeltaTime)
    {
        // Draw player indicator
        utils_debug_draw::DrawDebugSphere(GetActorLocation(), 50.0f, 8,
            FLinearColor::Green, 0.0f, 2.0f);
        utils_debug_draw::DrawDebugString(GetActorLocation() + FVector(0, 0, 100),
            "PLAYER", nullptr, FLinearColor::White, 0.0f);
    }
};