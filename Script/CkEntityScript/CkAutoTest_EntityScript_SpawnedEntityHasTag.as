// Language=angelscript

//============================================================================
// CK ENTITY SCRIPT — AUTOMATION TEST: SPAWNED ENTITY HAS TAG
//============================================================================
//
// Verifies that fragments added by the spawned entity-script's DoConstruct
// are observable on the resulting entity:
//   1. Spawn the gym entity script (its DoConstruct calls
//      utils_entity_tag::Add(InHandle, n"TAG_EntityScriptGym_Spawn")).
//   2. After construction, looking up children by that tag from the test
//      entity (via utils_entity_tag::ForEach_Entity) finds the spawned one.
//
// This catches regressions where DoConstruct fragments don't actually
// land on the entity, OR where spawned-as-child entities aren't reachable
// via ForEach_Entity from the owner.
//============================================================================

class UCk_AutoTest_EntityScript_SpawnedEntityHasTag : UCk_AutoTest_Base
{
    private FCk_Handle _Owner;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
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

        auto Found = utils_entity_tag::ForEach_Entity(_Owner, n"TAG_EntityScriptGym_Spawn");
        Assert_True(Found.Num() >= 1,
            f"ForEach_Entity should find at least one entity tagged TAG_EntityScriptGym_Spawn (got {Found.Num()})");

        FinishSuccess();
    }
}
