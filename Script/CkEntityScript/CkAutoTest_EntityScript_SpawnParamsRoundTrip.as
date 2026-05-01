// Language=angelscript

//============================================================================
// CK ENTITY SCRIPT — AUTOMATION TEST: SPAWN PARAMS ROUND-TRIP
//============================================================================
//
// Verifies that ExposeOnSpawn fields populated on the SpawnParams reach
// the spawned entity-script's DoConstruct, where the gym writes them into
// a verification fragment:
//   1. Build SpawnParams with TestName="AutoTest", TestInt=42, TestFloat=3.14.
//   2. Spawn UCk_EntityScript_EntityScriptGym_Spawn (its DoConstruct copies
//      the ExposeOnSpawn props into a FEntityScriptGym_SpawnParams fragment).
//   3. In OnConstructed, read the fragment and verify all three fields
//      round-tripped intact.
//
// This catches regressions in the spawn-params marshalling path (AS class
// instantiation, ExposeOnSpawn reflection, the auto-generated Params()
// helper) that BasicSpawn alone wouldn't notice.
//============================================================================

class UCk_AutoTest_EntityScript_SpawnParamsRoundTrip : UCk_AutoTest_Base
{
    private const FName _ExpectedName = n"AutoTest";
    private const int32 _ExpectedInt = 42;
    private const float32 _ExpectedFloat = 3.14f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Owner = InHandle;

        auto SpawnParams = UCk_EntityScript_EntityScriptGym_Spawn::Params();
        SpawnParams.InitialTransform = FTransform::Identity;
        SpawnParams.TestName = _ExpectedName;
        SpawnParams.TestInt = _ExpectedInt;
        SpawnParams.TestFloat = _ExpectedFloat;

        auto SpawnRequest = utils_entity_script::Request_SpawnEntity(
            Owner,
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

        const auto& Received = InEntityScriptHandle.Get_Fragment(FEntityScriptGym_SpawnParams);

        Assert_True(Received.TestName == _ExpectedName,
            f"TestName should round-trip via ExposeOnSpawn (expected '{_ExpectedName}', got '{Received.TestName}')");
        Assert_Equals_Int(Received.TestInt, _ExpectedInt,
            "TestInt should round-trip via ExposeOnSpawn");
        Assert_True(Math::Abs(Received.TestFloat - _ExpectedFloat) < 0.001f,
            f"TestFloat should round-trip via ExposeOnSpawn (expected {_ExpectedFloat}, got {Received.TestFloat})");

        FinishSuccess();
    }
}
