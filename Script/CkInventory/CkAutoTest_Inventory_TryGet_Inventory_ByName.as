// Language=angelscript

//============================================================================
// CK INVENTORY — AUTOMATION TEST: TRYGET_INVENTORY BY NAME
//============================================================================
//
// Pins the `TryGet_Inventory(Owner, Name)` lookup contract on an owner that
// hosts MULTIPLE inventories distinguished by FGameplayTag name:
//   1. Create two DataOnly inventories on the same owner with distinct
//      gameplay-tag names (Inventory.AutoTest_Primary and
//      Inventory.AutoTest_Secondary).
//   2. TryGet_Inventory(owner, Primary)  -> returns the first inventory's handle.
//   3. TryGet_Inventory(owner, Secondary)-> returns the second inventory's handle.
//   4. TryGet_Inventory(owner, Unknown)  -> returns the invalid handle.
//
// We compare handles by inspecting Get_NumItems on the returned handle vs
// the originals — a quick way to verify identity without typesafe handle
// equality in AS f-strings.
//
// Uses bare-trait Key items (Tags only, no Stackable, no Dimensions) to
// keep the test independent of the Stackable framework warning.
//============================================================================

class UCk_AutoTest_Inventory_TryGet_Inventory_ByName : UCk_AutoTest_Base
{
    private FCk_Handle _Owner;
    private FCk_Handle_Inventory_DataOnly _Primary;
    private FCk_Handle_Inventory_DataOnly _Secondary;
    private FGameplayTag _PrimaryName;
    private FGameplayTag _SecondaryName;
    private FGameplayTag _UnknownName;
    private int32 _AddsObserved = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        _Owner = InHandle;
        _PrimaryName   = utils_gameplay_tag::ResolveGameplayTag(n"Inventory.AutoTest_Primary");
        _SecondaryName = utils_gameplay_tag::ResolveGameplayTag(n"Inventory.AutoTest_Secondary");
        _UnknownName   = utils_gameplay_tag::ResolveGameplayTag(n"Inventory.AutoTest_Unknown");

        auto PrimaryParams = utils_inventory_data_only::Make_Params(
            _PrimaryName,
            FCk_Delegate_Inventory_CustomCanAcceptItem_Dynamic(),
            FCk_Delegate_Inventory_CustomCanStackItems_Dynamic());
        _Primary = utils_inventory_data_only::Add(_Owner, PrimaryParams, ECk_Replication::DoesNotReplicate);

        auto SecondaryParams = utils_inventory_data_only::Make_Params(
            _SecondaryName,
            FCk_Delegate_Inventory_CustomCanAcceptItem_Dynamic(),
            FCk_Delegate_Inventory_CustomCanStackItems_Dynamic());
        _Secondary = utils_inventory_data_only::Add(_Owner, SecondaryParams, ECk_Replication::DoesNotReplicate);

        // Seed the inventories with different item counts so we can identify
        // them by Get_NumItems on the result of TryGet_Inventory.
        auto Request1 = FCk_Request_Inventory_AddItemByDefinition(inv_gym_items::Key(), 1);
        _Primary.Request_AddItemByDefinition(Request1,
            FCk_Delegate_Inventory_OnOperationResult_AddByDefinition(this, n"OnAddResult"));

        auto Request2 = FCk_Request_Inventory_AddItemByDefinition(inv_gym_items::Key(), 1);
        _Secondary.Request_AddItemByDefinition(Request2,
            FCk_Delegate_Inventory_OnOperationResult_AddByDefinition(this, n"OnAddResult"));

        auto Request3 = FCk_Request_Inventory_AddItemByDefinition(inv_gym_items::Key(), 1);
        _Secondary.Request_AddItemByDefinition(Request3,
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
        _AddsObserved += 1;

        if (_AddsObserved < 3) { return; }

        // All three adds done. Primary has 1 Key, Secondary has 2 Keys.
        Assert_Equals_Int(_Primary.Get_NumItems(), 1,
            "Primary inventory should have 1 Key after setup");
        Assert_Equals_Int(_Secondary.Get_NumItems(), 2,
            "Secondary inventory should have 2 Keys after setup");

        auto FoundPrimary = utils_inventory::TryGet_Inventory(_Owner, _PrimaryName);
        Assert_True(ck::IsValid(FoundPrimary),
            "TryGet_Inventory(Primary) should return a valid handle");
        Assert_Equals_Int(FoundPrimary.Get_NumItems(), 1,
            "TryGet_Inventory(Primary) should resolve to the inventory with 1 Key");

        auto FoundSecondary = utils_inventory::TryGet_Inventory(_Owner, _SecondaryName);
        Assert_True(ck::IsValid(FoundSecondary),
            "TryGet_Inventory(Secondary) should return a valid handle");
        Assert_Equals_Int(FoundSecondary.Get_NumItems(), 2,
            "TryGet_Inventory(Secondary) should resolve to the inventory with 2 Keys");

        auto FoundUnknown = utils_inventory::TryGet_Inventory(_Owner, _UnknownName);
        Assert_True(ck::Is_NOT_Valid(FoundUnknown),
            "TryGet_Inventory with an unknown name should return an invalid handle");

        FinishSuccess();
    }
}
