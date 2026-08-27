// Language=angelscript

//============================================================================
// CK ENTITY SCRIPT - AUTOMATION TEST: SPAWNED ENTITY IS A LIFETIME DEPENDENT
//============================================================================
//
// Verifies that an entity-script spawned with an owner appears in that
// owner's lifetime-dependents collection:
//   1. Spawn UCk_EntityScript_EntityScriptGym_Spawn with the test entity
//      as owner.
//   2. After construction, query Get_LifetimeDependents on the test entity.
//   3. Find the spawned entity-script's underlying entity in the result.
//
// This pins down the ownership-chain contract that destruction relies on:
// when the test entity is destroyed at end-of-test, the spawned entity
// goes with it. If this contract regresses, leaked entities accumulate
// across test runs.
//============================================================================

class UCk_AutoTest_EntityScript_SpawnedEntityIsDependent : UCk_AutoTest_Base
{
    private FCk_Handle _Owner;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        _Owner = InHandle;

        auto SpawnParams = UCk_EntityScript_EntityScriptGym_Spawn::Params();
        SpawnParams.InitialTransform = FTransform::Identity;

        auto SpawnRequest = utils_entity_script::Request_SpawnEntity(
            _Owner,
            UCk_EntityScript_EntityScriptGym_Spawn,
            SpawnParams);

        utils_pending_entity_script::Promise_OnConstructed(
            SpawnRequest,
            FCk_Delegate_EntityScript_Constructed(this, n"OnConstructed"));
    }

    UFUNCTION()
    private void OnConstructed(FCk_Handle_EntityScript InEntityScriptHandle)
    {
        if (IsFinished()) { return; }

        auto SpawnedAsHandle = FCk_Handle(InEntityScriptHandle);
        auto Dependents = utils_entity_lifetime::Get_LifetimeDependents(_Owner);

        auto FoundSpawnedInDependents = false;
        for (auto Dep : Dependents)
        {
            if (utils_handle::IsEqual(Dep, SpawnedAsHandle))
            {
                FoundSpawnedInDependents = true;
                break;
            }
        }

        Assert_True(FoundSpawnedInDependents,
            f"Spawned entity-script should appear in owner's Get_LifetimeDependents (got {Dependents.Num()} deps total)");

        FinishSuccess();
    }
}
