UCLASS(Blueprintable)
class ACk_TweenTest_GymActor : AActor
{
    default bReplicates = true;
    default bAlwaysRelevant = true;
    default bReplicateMovement = true;

    UPROPERTY(DefaultComponent)
	UCk_EntityBridge_ActorComponent_UE EntityBridge;
	default EntityBridge._ConstructionScript = UCk_Entity_ConstructionScript_WithTransform_PDA;
	default EntityBridge._Replication = ECk_Replication::Replicates;

    UPROPERTY(DefaultComponent)
    UStaticMeshComponent Mesh;
    default Mesh.StaticMesh = Cast<UStaticMesh>(utils_i_o::LoadAssetByName("Cube1", ECk_AssetSearchScope::Engine, ECk_AssetSearchStrategy::ExactOnly)._Asset);
    default Mesh.CollisionEnabled = ECollisionEnabled::NoCollision;

    UPROPERTY(DefaultComponent)
    UTextRenderComponent TextRenderer;
    default TextRenderer.RelativeLocation = FVector(0.0f, 0.0f, 75.0f);
    default TextRenderer.SetHorizontalAlignment(EHorizTextAligment::EHTA_Center);
    default TextRenderer.WorldSize = 40.0f;
    default TextRenderer.TextRenderColor = FColor::Orange;

    UPROPERTY(ExposeOnSpawn, ReplicatedUsing=OnTextUpdated)
    ECk_TweenEasing TweenEasingMethod = ECk_TweenEasing::Linear;

    UPROPERTY(ExposeOnSpawn)
    float32 TweenDuration = 1.0f;

    UFUNCTION(BlueprintOverride)
    void BeginPlay()
    {
        TextRenderer.SetText(ck::Text(f"{TweenEasingMethod}"));
    }

    UFUNCTION()
    void OnTextUpdated()
    {
        TextRenderer.SetText(ck::Text(f"{TweenEasingMethod}"));
    }

    UFUNCTION(BlueprintOverride)
    void ConstructionScript()
    {
        EntityBridge._OnReplicationComplete_MC.AddUFunction(this, n"OnReplicationComplete");
        EntityBridge._OnPreConstruct.AddUFunction(this, n"EcsConstructionScript");
    }

    UPROPERTY()
    FVector StartLocation = FVector::ZeroVector;

    UPROPERTY()
    FVector EndLocation = FVector::ZeroVector;

    UPROPERTY()
    FCk_Handle_Tween TweenHandle;

	UFUNCTION()
	private void OnReplicationComplete(FCk_Handle InEntity)
	{
		if (System::IsServer() == false)
		{ return; }

        StartLocation = GetActorLocation();
        EndLocation = StartLocation + FVector(0.0f, 0.0f, 200.0f);
        TweenToLocation(InEntity.To_FCk_Handle_Transform());
	}

    UFUNCTION()
    private void TweenToLocation(FCk_Handle_Transform InEntity)
    {
        TweenHandle = utils_tween::Create_TweenEntityLocation(InEntity, EndLocation, TweenDuration, TweenEasingMethod, ECk_TweenLoopType::Yoyo, -1, 0.0f);
	}

    UFUNCTION()
	private void EcsConstructionScript(FCk_Handle InEntity)
	{
        utils_transform::Add(InEntity, GetActorTransform());
	}
};