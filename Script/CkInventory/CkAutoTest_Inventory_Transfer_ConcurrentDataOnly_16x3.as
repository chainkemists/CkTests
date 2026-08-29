// Language=angelscript

//============================================================================
// CK INVENTORY - AUTOMATION TEST: CONCURRENT DATA-ONLY TRANSFERS, 16 x 3
//============================================================================
//
// Sixteen independent data-only source request queues each contribute three
// ForceNew Potion entries to one data-only target. All 48 ordinary
// Request_TransferItem_ToDataOnly calls are dispatched in the same turn.
//
// This is deliberately not a MassTransfer test: it exercises the per-source
// request processors racing to mutate the shared target, including deferred
// stack-count writes. The invariant is conservation (48 target units, zero
// source units) and exactly one successful callback for every source item.
//============================================================================

class UCk_AutoTest_Inventory_Transfer_ConcurrentDataOnly_16x3 : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 30.0f;

    private const int32 k_SourceCount     = 16;
    private const int32 k_ItemsPerSource  = 3;
    private const int32 k_TotalItemCount  = k_SourceCount * k_ItemsPerSource;

    private FCk_Handle_Inventory_DataOnly _Target;
    private TArray<FCk_Handle_Inventory_DataOnly> _Sources;
    private TArray<FCk_Handle_Item> _SeededItems;
    private TArray<int32> _SeedSourceIndices;
    private TArray<FCk_Handle_Item> _CompletedItems;
    private int32 _TransferCallbacks = 0;
    private bool _TransfersDispatched = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto TargetParams = utils_inventory_data_only::Make_Params(
            utils_gameplay_tag::ResolveGameplayTag(n"Inventory.AutoTest_TransferTarget"),
            FCk_Delegate_Inventory_CustomCanAcceptItem_Dynamic(),
            FCk_Delegate_Inventory_CustomCanStackItems_Dynamic());
        _Target = utils_inventory_data_only::Add(LocalHandle, TargetParams, ECk_Replication::DoesNotReplicate);

        auto SourceParams = utils_inventory_data_only::Make_Params(
            utils_gameplay_tag::ResolveGameplayTag(n"Inventory.AutoTest_TransferSource"),
            FCk_Delegate_Inventory_CustomCanAcceptItem_Dynamic(),
            FCk_Delegate_Inventory_CustomCanStackItems_Dynamic());

        for (int SourceIndex = 0; SourceIndex < k_SourceCount; SourceIndex++)
        {
            auto SourceOwner = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
            auto Source = utils_inventory_data_only::Add(SourceOwner, SourceParams, ECk_Replication::DoesNotReplicate);
            _Sources.Add(Source);

            for (int ItemIndex = 0; ItemIndex < k_ItemsPerSource; ItemIndex++)
            {
                auto Add = FCk_Request_Inventory_AddItemByDefinition(inv_gym_items::Potion(), 1);
                Add.Set_Policy(ECk_Inventory_AddPolicy::ForceNewItem);
                Source.Request_AddItemByDefinition(Add,
                    FCk_Delegate_Inventory_OnOperationResult_AddByDefinition(this, n"OnSeeded"));
            }
        }
    }

    UFUNCTION()
    private void OnSeeded(
        FCk_Handle_Inventory InInventory,
        ECk_Inventory_OperationResult_AddByDefinition InResult,
        int InAmountAdded,
        const TArray<FCk_Handle_Item>&in InItemsCreated)
    {
        if (IsFinished()) { return; }

        if (InResult != ECk_Inventory_OperationResult_AddByDefinition::Success_AllAdded ||
            InAmountAdded != 1 || InItemsCreated.Num() != 1)
        {
            FinishFailure(f"Setup: expected one successful ForceNew Potion seed (result={InResult}, amount={InAmountAdded}, items={InItemsCreated.Num()})");
            return;
        }

        auto SourceIndex = FindSourceContaining(InItemsCreated[0]);
        if (SourceIndex < 0)
        {
            FinishFailure("Setup: seeded item is not owned by one of the 16 source inventories");
            return;
        }

        _SeededItems.Add(InItemsCreated[0]);
        _SeedSourceIndices.Add(SourceIndex);
        if (_SeededItems.Num() < k_TotalItemCount || _TransfersDispatched) { return; }

        if (_SeededItems.Num() != k_TotalItemCount || _SeedSourceIndices.Num() != k_TotalItemCount)
        {
            FinishFailure(f"Setup: expected {k_TotalItemCount} seeded source items, got {_SeededItems.Num()}");
            return;
        }

        for (int VerifySourceIndex = 0; VerifySourceIndex < _Sources.Num(); VerifySourceIndex++)
        {
            if (_Sources[VerifySourceIndex].Get_NumItems() != k_ItemsPerSource)
            {
                FinishFailure(f"Setup: source {VerifySourceIndex} must hold {k_ItemsPerSource} ForceNew entries before concurrent transfer");
                return;
            }
        }

        _TransfersDispatched = true;
        for (int ItemIndex = 0; ItemIndex < _SeededItems.Num(); ItemIndex++)
        {
            auto Request = FCk_Request_Inventory_TransferItem_ToDataOnly(_SeededItems[ItemIndex], _Target);
            _Sources[_SeedSourceIndices[ItemIndex]].Request_TransferItem_ToDataOnly(Request,
                FCk_Delegate_Inventory_OnOperationResult_Transfer(this, n"OnTransferResult"));
        }
    }

    UFUNCTION()
    private void OnTransferResult(
        FCk_Handle_Inventory InSource,
        FCk_Handle_Item InSourceItem,
        FCk_Handle_Inventory InTarget,
        int InAmountTransferred,
        FCk_Handle_Item InTargetItem,
        ECk_Inventory_OperationResult_Transfer InResult)
    {
        if (IsFinished()) { return; }

        auto SeededItemIndex = FindSeededItemIndex(InSourceItem);
        if (SeededItemIndex < 0)
        {
            FinishFailure("Transfer callback named an item that this test did not seed");
            return;
        }
        if (_CompletedItems.Contains(InSourceItem))
        {
            FinishFailure("Transfer callback fired more than once for one source item");
            return;
        }

        FCk_Handle_Inventory TargetAsBase = _Target;
        if (InTarget != TargetAsBase || ck::Is_NOT_Valid(InTargetItem))
        {
            FinishFailure("Transfer callback did not identify the shared target and a valid target item");
            return;
        }
        FCk_Handle_Inventory ExpectedSourceAsBase = _Sources[_SeedSourceIndices[SeededItemIndex]];
        if (InSource != ExpectedSourceAsBase)
        {
            FinishFailure("Transfer callback did not identify the source that owns its source item");
            return;
        }
        if (InResult != ECk_Inventory_OperationResult_Transfer::Success || InAmountTransferred != 1)
        {
            FinishFailure(f"Every concurrent one-unit transfer must succeed exactly once (result={InResult}, amount={InAmountTransferred})");
            return;
        }

        _CompletedItems.Add(InSourceItem);
        _TransferCallbacks += 1;
        if (_TransferCallbacks > k_TotalItemCount)
        {
            FinishFailure(f"Observed more than {k_TotalItemCount} transfer callbacks");
            return;
        }
        if (_TransferCallbacks == k_TotalItemCount)
        { WaitUntil(n"Check_AllTransfersSettled", n"OnAllTransfersSettled"); }
    }

    UFUNCTION()
    private void Check_AllTransfersSettled(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        if (_Target.Get_TotalUnits() != k_TotalItemCount)
        {
            Res.Set(false);
            return;
        }

        for (int SourceIndex = 0; SourceIndex < _Sources.Num(); SourceIndex++)
        {
            if (_Sources[SourceIndex].Get_TotalUnits() != 0)
            {
                Res.Set(false);
                return;
            }
        }
        Res.Set(true);
    }

    UFUNCTION()
    private void OnAllTransfersSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_TransferCallbacks, k_TotalItemCount, "All 48 dispatched transfers report exactly one callback");
        Assert_Equals_Int(_CompletedItems.Num(), k_TotalItemCount, "All 48 callback source items are unique");
        Assert_Equals_Int(_Target.Get_TotalUnits(), k_TotalItemCount, "All 48 units are conserved in the shared target");

        for (int SourceIndex = 0; SourceIndex < _Sources.Num(); SourceIndex++)
        {
            Assert_Equals_Int(_Sources[SourceIndex].Get_TotalUnits(), 0,
                f"Source {SourceIndex} is empty after its three transfers settle");
        }

        FinishSuccess();
    }

    private int32 FindSourceContaining(FCk_Handle_Item InItem) const
    {
        for (int SourceIndex = 0; SourceIndex < _Sources.Num(); SourceIndex++)
        {
            if (_Sources[SourceIndex].Get_ContainsItem(InItem))
            { return SourceIndex; }
        }
        return -1;
    }

    private int32 FindSeededItemIndex(FCk_Handle_Item InItem) const
    {
        for (int ItemIndex = 0; ItemIndex < _SeededItems.Num(); ItemIndex++)
        {
            if (_SeededItems[ItemIndex] == InItem)
            { return ItemIndex; }
        }
        return -1;
    }
}
