UCLASS()
class ACk_TweenTest_GymPawn : ADefaultPawn
{
    UPROPERTY()
    UEnvQuery TestActorSpawnPointsQuery = Cast<UEnvQuery>(
        utils_i_o::LoadAssetByName("TweenActorSpawnPoints_Query_CkTests_EQS", ECk_AssetSearchScope::All, ECk_AssetSearchStrategy::ExactOnly)._Asset);

    UFUNCTION(BlueprintOverride)
    void BeginPlay()
    {
        if (System::IsServer() == false)
		{ return; }

        auto Result = UEnvQueryManager::RunEQSQuery(TestActorSpawnPointsQuery, this, EEnvQueryRunMode::AllMatching, nullptr);
        Result.OnQueryFinishedEvent.AddUFunction(this, n"OnEQSResult");
    }

    UFUNCTION()
    private void OnEQSResult(UEnvQueryInstanceBlueprintWrapper QueryInstance,
                             EEnvQueryStatus QueryStatus)
    {
        TArray<FVector> Locations;
        QueryInstance.GetQueryResultsAsLocations(Locations);

        
        for (auto Index = 0; Index < int32(ECk_TweenEasing::ECk_MAX); ++Index)
        {
            auto SpawnedActor = SpawnActor(ACk_TweenTest_GymActor, Locations[Index], FRotator(0, 180, 0), NAME_None, true);
            SpawnedActor.TweenEasingMethod = ECk_TweenEasing(Index);
            FinishSpawningActor(SpawnedActor);
        }
    }
}