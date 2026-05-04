// Language=angelscript

//============================================================================
// CK INVENTORY — AUTOMATION TEST: ADD-BY-DEFINITION GRACEFUL NULL HANDLING
//============================================================================
//
// Verifies that Request_AddItemByDefinition with a null/missing
// UCk_InventoryItem_Definition produces a clean failure result rather
// than crashing or silently succeeding:
//
//   1. Create a bounded(5) data-only inventory.
//   2. Issue Request_AddItemByDefinition with Definition = nullptr, Amount = 1.
//   3. Result delegate fires with Result == Failed_InvalidDefinition (or
//      another Failed_* enum), AmountAdded == 0, ItemsCreated empty.
//   4. Get_NumItems(Inventory) remains 0 — no partial state.
//
// Reference: CkInventory_Processor.cpp:441 sets the initial result to
// Failed_InvalidDefinition; a valid definition then advances past that.
//
//============================================================================
// EXPECTED HARNESS-LEVEL FAILURE — INTENTIONAL FRAMEWORK WARNING
//============================================================================
//
// This test deliberately passes a null definition. CkInventory_Processor.cpp:462
// logs `inventory::Warning(TEXT("AddItemByDefinition: Invalid definition"))`
// when validation rejects the request — and per Gotcha #1 of the AutoTest
// framework spec, Warning-level log output during a Functional Test is
// treated as a test failure regardless of assertion outcome.
//
// All 4 assertions in this test pass (verified). Session Frontend reports
// the row as "Failed" only because of the captured warning. To turn this
// green at the harness level, the framework would need to either:
//   - Downgrade `AddItemByDefinition: Invalid definition` to LogLevel::Log
//     (it's an expected, handled rejection path — not an actionable warning), OR
//   - Provide a per-test opt-out for expected-warning patterns.
//
// Test is left as-is so the inventory contract (null def → Failed_InvalidDefinition,
// no partial state, predicate path bypassed) remains pinned regardless
// of how the framework log-level decision lands.
//============================================================================

class UCk_AutoTest_Inventory_AddItemByDefinition_MissingAsset : UCk_AutoTest_Base
{
    private FCk_Handle_Inventory _Inventory;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;

        auto Params = utils_inventory::Make_InventoryParams_DataOnly_Bounded(
            utils_gameplay_tag::ResolveGameplayTag(n"Inventory.AutoTest_NullDef"),
            5,
            FCk_Delegate_Inventory_CustomCanAcceptItem_Dynamic(),
            FCk_Delegate_Inventory_CustomCanStackItems_Dynamic());
        _Inventory = utils_inventory::Add(LocalHandle, Params, ECk_Replication::DoesNotReplicate);

        // Null definition deliberately.
        UCk_InventoryItem_Definition NullDef = nullptr;
        auto Request = FCk_Request_Inventory_AddItemByDefinition(NullDef, 1);
        Request.Set_Policy(ECk_Inventory_AddPolicy::ForceNewItem);
        utils_inventory::Request_AddItemByDefinition(
            _Inventory,
            Request,
            FCk_Delegate_Inventory_OnOperationResult_AddByDefinition(this, n"OnAddResult"));
    }

    UFUNCTION()
    private void OnAddResult(
        FCk_Handle_Inventory InInventory,
        ECk_Inventory_OperationResult_AddByDefinition InResult,
        int InAmountAdded,
        const TArray<FCk_Handle_Item>&in InItemsCreated)
    {
        if (IsFinished()) { return; }

        Assert_True(InResult == ECk_Inventory_OperationResult_AddByDefinition::Failed_InvalidDefinition,
            f"Null definition should produce Failed_InvalidDefinition (got {InResult})");
        Assert_Equals_Int(InAmountAdded, 0, "AmountAdded must be 0 for an invalid definition");
        Assert_Equals_Int(InItemsCreated.Num(), 0, "ItemsCreated must be empty for an invalid definition");
        Assert_Equals_Int(utils_inventory::Get_NumItems(_Inventory), 0,
            "Inventory must remain empty after a rejected add — no partial-state leakage");

        FinishSuccess();
    }
}
