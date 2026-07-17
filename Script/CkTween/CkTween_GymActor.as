UCLASS(Blueprintable)
class ACk_TweenTest_GymActor : AActor
{
    default bReplicates = true;
    default bReplicateUsingRegisteredSubObjectList = true;
    default bAlwaysRelevant = true;
    default bReplicateMovement = true;

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
        auto _CkPerfScope = ck::ScopedStat();
        TextRenderer.SetText(ck::Text(f"{TweenEasingMethod}"));

        auto PendingEntity = utils_entity_script_with_actor::Request_SpawnEntityScript_OnActor(
            this, UCk_EntityScript_WithActor_UE);
        if (utils_pending_entity_script::Get_IsValid(PendingEntity))
        {
            utils_pending_entity_script::Promise_OnConstructed(
                PendingEntity, FCk_Delegate_EntityScript_Constructed(this, n"OnEntityConstructed"));
        }
    }

    UFUNCTION()
    void OnTextUpdated()
    {
        TextRenderer.SetText(ck::Text(f"{TweenEasingMethod}"));
    }

    UPROPERTY()
    FVector StartLocation = FVector::ZeroVector;

    UPROPERTY()
    FVector EndLocation = FVector::ZeroVector;

    UPROPERTY()
    FCk_Handle_Tween TweenHandle;

	UFUNCTION()
	private void OnEntityConstructed(FCk_Handle_EntityScript InEntityScriptHandle)
	{
		if (System::IsServer() == false)
		{ return; }

        auto InEntity = FCk_Handle(InEntityScriptHandle);
        InEntity.Set_DebugName(n"TweenCube");
        StartLocation = GetActorLocation();
        EndLocation = StartLocation + FVector(0.0f, 0.0f, 200.0f);
        TweenToLocation(InEntity.As_Transform());
	}

    UFUNCTION()
    private void TweenToLocation(FCk_Handle_Transform InEntity)
    {
        TweenHandle = utils_tween::Create_TweenEntityLocation(InEntity, EndLocation, TweenDuration, TweenEasingMethod, ECk_TweenLoopType::Yoyo, -1, 0.0f);
	}
};
