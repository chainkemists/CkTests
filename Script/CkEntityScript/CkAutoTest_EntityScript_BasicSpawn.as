// Language=angelscript

//============================================================================
// CK ENTITY SCRIPT — AUTOMATION TEST: BASIC SPAWN + PROMISE
//============================================================================
//
// Smoke test for the AS entity-script spawn flow:
//   1. Build SpawnParams via the auto-generated ::Params() static.
//   2. utils_entity_script::Request_SpawnEntity returns a valid pending
//      handle.
//   3. Promise_OnConstructed callback fires.
//   4. The constructed entity-script handle is valid.
//
// Reuses the gym's UCk_EntityScript_EntityScriptGym_Spawn entity script
// as a known-good spawn target.
//============================================================================

class UCk_AutoTest_EntityScript_BasicSpawn : UCk_AutoTest_Base
{
    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Owner = InHandle;

        auto SpawnParams = UCk_EntityScript_EntityScriptGym_Spawn::Params();
        SpawnParams.InitialTransform = FTransform::Identity;
        SpawnParams.TestName = n"";
        SpawnParams.TestInt = 0;
        SpawnParams.TestFloat = 0.0f;

        auto SpawnRequest = utils_entity_script::Request_SpawnEntity(
            Owner,
            UCk_EntityScript_EntityScriptGym_Spawn,
            SpawnParams);

        Assert_True(ck::IsValid(SpawnRequest),
            "Request_SpawnEntity should return a valid pending handle");

        utils_pending_entity_script::Promise_OnConstructed(
            SpawnRequest,
            FCk_Delegate_EntityScript_Constructed(this, n"OnConstructed"));
    }

    UFUNCTION()
    private void OnConstructed(FCk_Handle_EntityScript InEntityScriptHandle)
    {
        if (IsFinished()) { return; }

        Assert_True(ck::IsValid(InEntityScriptHandle),
            "Promise_OnConstructed should fire with a valid entity-script handle");
        FinishSuccess();
    }
}
