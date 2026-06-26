// Language=angelscript

//============================================================================
// CK ENTITY LIFECYCLE — AUTOMATION TEST: ENTITY-SCRIPT CAST QUERIES
//============================================================================
//
// Bundled coverage for the entity-script handle query/cast utility surface
// against a freshly-spawned entity script. EntityScript_BasicSpawn /
// EntityScript_SpawnParamsRoundTrip already cover the spawn flow itself —
// this test focuses on the after-spawn introspection APIs:
//
//   - utils_entity_script::Has — does this entity carry an entity script?
//   - utils_entity_script::Get_ScriptClass — returns its class
//   - utils_entity_script::DoCast — handle-to-script-handle cast (optional)
//   - utils_entity_script::DoCastChecked — non-optional cast
//   - utils_entity_script::TryGet_Entity_EntityScript_InOwnershipChain —
//     walks ownership chain from any entity up to the nearest entity-script
//
// Spawns the gym's UCk_EntityScript_EntityLifecycleGym_SpawnTarget (a
// minimal entity-script with no ExposeOnSpawn payload) and exercises all
// the queries in the OnConstructed callback.
//============================================================================

class UCk_AutoTest_EntityLifecycle_ScriptCastQueries : UCk_AutoTest_Base
{
    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto SpawnParams = UCk_EntityScript_EntityLifecycleGym_SpawnTarget::Params();
        SpawnParams.InitialTransform = FTransform::Identity;

        auto Pending = utils_entity_script::Request_SpawnEntity(
            LocalHandle,
            UCk_EntityScript_EntityLifecycleGym_SpawnTarget,
            SpawnParams);

        utils_pending_entity_script::Promise_OnConstructed(
            Pending,
            FCk_Delegate_EntityScript_Constructed(this, n"OnConstructed"));
    }

    UFUNCTION()
    private void OnConstructed(FCk_Handle_EntityScript InEntityScriptHandle)
    {
        if (IsFinished()) { return; }

        auto AsHandle = FCk_Handle(InEntityScriptHandle);

        Assert_True(utils_entity_script::Has(AsHandle),
            "utils_entity_script::Has should be true on a freshly-spawned entity-script entity");

        auto ScriptClass = utils_entity_script::Get_ScriptClass(InEntityScriptHandle);
        Assert_True(ck::IsValid(ScriptClass),
            "Get_ScriptClass should return a valid UClass on a constructed entity script");

        auto CastResult = utils_entity_script::DoCast(AsHandle);
        Assert_True(CastResult.IsSet(),
            "DoCast on an entity-script-bearing entity should return a populated optional");

        auto CastChecked = utils_entity_script::DoCastChecked(AsHandle);
        Assert_True(utils_handle::Get_IsValid(FCk_Handle(CastChecked)),
            "DoCastChecked should return a valid handle on an entity-script-bearing entity");

        auto InChain = utils_entity_script::TryGet_Entity_EntityScript_InOwnershipChain(AsHandle);
        Assert_True(utils_handle::Get_IsValid(InChain),
            "TryGet_Entity_EntityScript_InOwnershipChain should resolve from the entity itself when it carries an entity script");

        FinishSuccess();
    }
}
