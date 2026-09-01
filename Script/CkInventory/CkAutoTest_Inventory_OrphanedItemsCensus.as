// Language=angelscript

//============================================================================
// CK INVENTORY - AUTOMATION TEST: THE ORPHAN CENSUS SEES THE LEAK SHAPE
//============================================================================
//
// Get_OrphanedItems is the detector for the removal contract, and it is what a
// project's load-time migration decides to destroy from. So it has to be exact
// in BOTH directions, and a test that only checked one would be worse than none:
// a census that misses orphans leaves the leak invisible, and one that reports a
// held item hands a migration a live item to delete.
//
// STRANDED is the shape a save can carry: an item entity that is a LIFETIME
// CHILD of an inventory whose record does not list it. That is what a pre-fix
// Remove left behind, and it is what a restored save comes back as, because the
// lifetime edge is the part the snapshot records.
//
// Staged by creating an item directly under the inventory entity - the same
// primitive UCk_Utils_Item_UE::Create uses, just pointed at the container - so
// the entity is parented without ever being connected to the record. No private
// state is poked and no removal is faked.
//
// The census is world-wide and a lane shares one PIE world with every other
// test, so this asserts MEMBERSHIP rather than a total: the stranded item is in
// the report and names its container, and the properly-held control is not.
//============================================================================

class UCk_AutoTest_Inventory_OrphanedItemsCensus : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 5.0f;

    private FCk_Handle _Self;
    private FCk_Handle_Inventory_DataOnly _Inventory;
    private FCk_Handle_Item _HeldItem;
    private FCk_Handle_Item _StrandedItem;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        _Self = InHandle;
        auto LocalHandle = InHandle;

        auto Params = utils_inventory_data_only::Make_Params_Bounded(
            utils_gameplay_tag::ResolveGameplayTag(n"Inventory.AutoTest_OrphanCensus"), 5,
            FCk_Delegate_Inventory_CustomCanAcceptItem_Dynamic(),
            FCk_Delegate_Inventory_CustomCanStackItems_Dynamic());

        _Inventory = utils_inventory_data_only::Add(LocalHandle, Params, ECk_Replication::DoesNotReplicate);

        auto AddRequest = FCk_Request_Inventory_AddItemByDefinition(inv_gym_items::Potion(), 1);
        AddRequest.Set_Policy(ECk_Inventory_AddPolicy::ForceNewItem);
        _Inventory.Request_AddItemByDefinition(AddRequest,
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
        if (ck::IsValid(_HeldItem)) { return; }

        if (InItemsCreated.Num() != 1)
        {
            FinishFailure(f"Setup: the control item was not added (result={InResult})");
            return;
        }
        _HeldItem = InItemsCreated[0];

        // The leak shape, staged: an item entity parented to the inventory that the inventory's
        // record has never heard of.
        auto InventoryEntity = FCk_Handle(_Inventory);
        _StrandedItem = utils_item::Create(InventoryEntity, inv_gym_items::Potion());

        WaitUntil(n"Check_StrandedItemBuilt", n"OnStaged");
    }

    UFUNCTION()
    private void Check_StrandedItemBuilt(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(ck::IsValid(_StrandedItem));
    }

    UFUNCTION()
    private void OnStaged(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        const FCk_Handle InventoryEntity = _Inventory;
        const FCk_Handle StrandedEntity  = _StrandedItem;
        const FCk_Handle HeldEntity      = _HeldItem;

        // Preconditions, so a census that reports nothing cannot pass as "nothing was wrong".
        Assert_True(ck::OwnerEntity(_StrandedItem) == InventoryEntity,
            "PRECONDITION: the staged item should be a lifetime child of the inventory");
        Assert_Equals_Int(_Inventory.Get_NumItems(), 1,
            "PRECONDITION: only the control item should be in the record");

        const auto Orphans = UCk_Utils_Inventory_UE::Get_OrphanedItems(_Self);

        auto FoundStranded = false;
        auto FoundHeld = false;
        for (auto Orphan : Orphans)
        {
            const FCk_Handle ReportedItem = Orphan.Get_Item();

            if (ReportedItem == StrandedEntity)
            {
                FoundStranded = true;
                const FCk_Handle ReportedUnder = Orphan.Get_StrandedUnder();
                Assert_True(ReportedUnder == InventoryEntity,
                    "a stranded orphan must name the inventory still holding its lifetime - a migration has nothing else to log or to reason about");
            }

            if (ReportedItem == HeldEntity)
            { FoundHeld = true; }
        }

        Assert_True(FoundStranded,
            "the census must see an item parented to an inventory that does not list it - that is the shape a pre-fix save carries");
        Assert_False(FoundHeld,
            "the census must NOT report a properly-held item; a migration destroys what this returns");

        FinishSuccess();
    }
}
