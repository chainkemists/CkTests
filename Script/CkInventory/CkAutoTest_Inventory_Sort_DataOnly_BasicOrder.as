// Language=angelscript

//============================================================================
// CK INVENTORY — AUTOMATION TEST: SORT — DATAONLY BASIC ORDER
//============================================================================
//
// Pins the Request_Sort contract: with a custom sort predicate bound on
// FCk_Request_Inventory_Sort, after Request_Sort completes the inventory's
// item list is reordered per the predicate, and OnOperationResult_Sort fires
// with Success.
//
// Setup:
//   1. Create an unbounded DataOnly inventory.
//   2. Seed it with three distinct items in arbitrary order:
//      Sword (rank=2), Shield (rank=1), Key (rank=3) — captured as
//      _Sword/_Shield/_Key handles.
//   3. Bind a sort predicate that ranks _Shield < _Sword < _Key.
//   4. Issue Request_Sort.
//   5. On Sort result: Success, Get_Items returns the three items in the
//      expected order [Shield, Sword, Key].
//
// All three items are bare-trait (Tags+Dimensions or Tags only) — no
// Stackable, so the Stackable framework warning is avoided.
//============================================================================

class UCk_AutoTest_Inventory_Sort_DataOnly_BasicOrder : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 5.0f;

    private FCk_Handle_Inventory_DataOnly _Inventory;
    private FCk_Handle_Item _Sword;
    private FCk_Handle_Item _Shield;
    private FCk_Handle_Item _Key;
    private int32 _AddsObserved = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto Params = utils_inventory_data_only::Make_Params(
            utils_gameplay_tag::ResolveGameplayTag(n"Inventory.AutoTest_SortBasic"),
            FCk_Delegate_Inventory_CustomCanAcceptItem_Dynamic(),
            FCk_Delegate_Inventory_CustomCanStackItems_Dynamic());
        _Inventory = utils_inventory_data_only::Add(LocalHandle, Params, ECk_Replication::DoesNotReplicate);

        // Seed in arbitrary order (Sword first, then Shield, then Key).
        auto R1 = FCk_Request_Inventory_AddItemByDefinition(inv_gym_items::Sword(), 1);
        R1.Set_Policy(ECk_Inventory_AddPolicy::ForceNewItem);
        _Inventory.Request_AddItemByDefinition(R1,
            FCk_Delegate_Inventory_OnOperationResult_AddByDefinition(this, n"OnSeedResult"));

        auto R2 = FCk_Request_Inventory_AddItemByDefinition(inv_gym_items::Shield(), 1);
        R2.Set_Policy(ECk_Inventory_AddPolicy::ForceNewItem);
        _Inventory.Request_AddItemByDefinition(R2,
            FCk_Delegate_Inventory_OnOperationResult_AddByDefinition(this, n"OnSeedResult"));

        auto R3 = FCk_Request_Inventory_AddItemByDefinition(inv_gym_items::Key(), 1);
        R3.Set_Policy(ECk_Inventory_AddPolicy::ForceNewItem);
        _Inventory.Request_AddItemByDefinition(R3,
            FCk_Delegate_Inventory_OnOperationResult_AddByDefinition(this, n"OnSeedResult"));
    }

    UFUNCTION()
    private void OnSeedResult(
        FCk_Handle_Inventory InInventory,
        ECk_Inventory_OperationResult_AddByDefinition InResult,
        int InAmountAdded,
        const TArray<FCk_Handle_Item>&in InItemsCreated)
    {
        if (IsFinished()) { return; }
        if (InItemsCreated.Num() == 0)
        {
            FinishFailure(f"Setup: failed to seed an item (result={InResult})");
            return;
        }

        _AddsObserved += 1;
        if (_AddsObserved == 1)      { _Sword  = InItemsCreated[0]; }
        else if (_AddsObserved == 2) { _Shield = InItemsCreated[0]; }
        else                         { _Key    = InItemsCreated[0]; }

        if (_AddsObserved < 3) { return; }

        // All three items seeded. Build the Sort request with a dynamic
        // predicate UFUNCTION bound to this test entity.
        auto SortRequest = FCk_Request_Inventory_Sort();
        SortRequest.Set_SortPredicateDynamic(
            FCk_Delegate_Inventory_SortPredicate_Dynamic(this, n"ComparePair"));

        FCk_Handle_Inventory InvAsBase = _Inventory;
        utils_inventory::Request_Sort(InvAsBase, SortRequest,
            FCk_Delegate_Inventory_OnOperationResult_Sort(this, n"OnSortResult"));
    }

    // Sort predicate — returns true if A should come BEFORE B.
    // Desired final order: Shield (rank 1), Sword (rank 2), Key (rank 3).
    UFUNCTION()
    private void ComparePair(
        FCk_Handle_Item InItemA,
        FCk_Handle_Item InItemB,
        bool& OutABeforeB)
    {
        OutABeforeB = Rank(InItemA) < Rank(InItemB);
    }

    private int32 Rank(FCk_Handle_Item InItem)
    {
        if (InItem == _Shield) { return 1; }
        if (InItem == _Sword)  { return 2; }
        return 3; // Key, or anything else
    }

    UFUNCTION()
    private void OnSortResult(
        FCk_Handle_Inventory InInventory,
        ECk_Inventory_OperationResult_Sort InResult)
    {
        if (IsFinished()) { return; }

        Assert_True(InResult == ECk_Inventory_OperationResult_Sort::Success,
            f"Request_Sort with a bound predicate should return Success (got {InResult})");

        auto Items = utils_inventory::Get_Items(_Inventory);
        Assert_Equals_Int(Items.Num(), 3,
            "Sort should not change the item count");

        if (Items.Num() == 3)
        {
            Assert_True(Items[0] == _Shield,
                "After sort, Items[0] should be the Shield (rank 1)");
            Assert_True(Items[1] == _Sword,
                "After sort, Items[1] should be the Sword (rank 2)");
            Assert_True(Items[2] == _Key,
                "After sort, Items[2] should be the Key (rank 3)");
        }

        FinishSuccess();
    }
}
