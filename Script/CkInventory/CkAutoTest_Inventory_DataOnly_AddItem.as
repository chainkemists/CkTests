// Language=angelscript

//============================================================================
// CK INVENTORY — AUTOMATION TEST: DATA-ONLY ADD ITEM
//============================================================================
//
// Verifies the basic add-item-by-definition flow on a data-only bounded
// inventory:
//   1. Create a bounded(5) data-only inventory.
//   2. Request_AddItemByDefinition(Potion, 1).
//   3. The result delegate fires with Result=Success_AllAdded, AmountAdded=1,
//      and ItemsCreated.Num()=1.
//   4. Get_NumItems(Inventory) == 1.
//
//============================================================================
// EXPECTED FAILURE — FRAMEWORK BUG (canonical explanation)
//============================================================================
//
// This test (and the other Stackable-using inventory AutoTests) currently
// FAILS at the framework level even when every assertion passes. Cause:
//
//   Constructing items from a definition that carries
//   UCk_ItemTrait_Stackable (e.g. inv_gym_items::Potion, Arrow) emits
//   CkEnsure warnings during item creation:
//     - "Cannot Connect RecordEntry [...StackCount]... already an entry"
//     - "Fragment [FFragment_TagSet] already exists in Entity"
//
//   The bug is narrowed to the Stackable trait setup path specifically:
//   item defs with only Tags+Dimensions (e.g. Sword) construct cleanly
//   without warnings — verified by CkAutoTest_Inventory_TagsTrait_*
//   passing green. So Stackable's init code appears to double-apply
//   both its own StackCount fragment AND the Tags trait's TagSet
//   fragment when both are present on the same item def.
//
//   UE's automation framework treats Warning-level log output during a
//   Functional Test as a test failure regardless of assertion outcome.
//   The same warnings fire on entry to CkInventoryGym_DataOnly_Bounded
//   interactively — this is a real framework regression.
//
// We DELIBERATELY use the traited Potion def (rather than a bare-trait
// item workaround) so this test and its siblings fail loudly until the
// framework regression is fixed. Once the warning regression is resolved,
// the four CkAutoTest_Inventory_DataOnly_* tests should turn green
// automatically with no test-side changes required.
//
// The CkAutoTest_Inventory_StackableTrait_* tests carry an ADDITIONAL
// caveat — see their banners for separate count-semantic anomalies that
// will need investigation independent of the framework warning fix.
//============================================================================

class UCk_AutoTest_Inventory_DataOnly_AddItem : UCk_AutoTest_Base
{
    private FCk_Handle_Inventory_DataOnly _Inventory;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;

        auto Params = utils_inventory_data_only::Make_Params_Bounded(
            utils_gameplay_tag::ResolveGameplayTag(n"Inventory.AutoTest_Bounded"),
            5,
            FCk_Delegate_Inventory_CustomCanAcceptItem_Dynamic(),
            FCk_Delegate_Inventory_CustomCanStackItems_Dynamic());

        _Inventory = utils_inventory_data_only::Add(LocalHandle, Params, ECk_Replication::DoesNotReplicate);

        auto PotionDef = inv_gym_items::Potion();
        Assert_True(PotionDef != nullptr, "Potion item definition should be loadable");

        auto Request = FCk_Request_Inventory_AddItemByDefinition(PotionDef, 1);
        Request.Set_Policy(ECk_Inventory_AddPolicy::ForceNewItem);
        _Inventory.Request_AddItemByDefinition(Request,
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

        Assert_True(InResult == ECk_Inventory_OperationResult_AddByDefinition::Success_AllAdded,
            f"Add result should be Success_AllAdded (got {InResult})");
        Assert_Equals_Int(InAmountAdded, 1, "AmountAdded should be 1");
        Assert_Equals_Int(InItemsCreated.Num(), 1, "ItemsCreated should contain exactly 1 item");
        Assert_Equals_Int(_Inventory.Get_NumItems(), 1,
            "Inventory should report 1 item after a successful add");

        FinishSuccess();
    }
}
