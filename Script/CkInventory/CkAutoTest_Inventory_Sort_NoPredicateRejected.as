// Language=angelscript

//============================================================================
// CK INVENTORY — AUTOMATION TEST: SORT WITH NO PREDICATE IS REJECTED
//============================================================================
//
// Request_Sort carrying no sort predicate (neither native nor dynamic bound)
// is a malformed request, not a bad inventory — it must complete with
// Failed_NoPredicate.
//============================================================================

class UCk_AutoTest_Inventory_Sort_NoPredicateRejected : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 4.0f;

    private FCk_Handle_Inventory_DataOnly _Inventory;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto Params = utils_inventory_data_only::Make_Params_Bounded(
            utils_gameplay_tag::ResolveGameplayTag(n"Inventory.AutoTest_SortNoPredicate"), 5,
            FCk_Delegate_Inventory_CustomCanAcceptItem_Dynamic(),
            FCk_Delegate_Inventory_CustomCanStackItems_Dynamic());
        _Inventory = utils_inventory_data_only::Add(LocalHandle, Params, ECk_Replication::DoesNotReplicate);

        _Inventory.Request_Sort(FCk_Request_Inventory_Sort(),
            FCk_Delegate_Inventory_OnOperationResult_Sort(this, n"OnSortResult"));
    }

    UFUNCTION()
    private void OnSortResult(
        FCk_Handle_Inventory InInventory,
        ECk_Inventory_OperationResult_Sort InResult)
    {
        if (IsFinished()) { return; }

        Assert_True(InResult == ECk_Inventory_OperationResult_Sort::Failed_NoPredicate,
            f"Request_Sort with no predicate must return Failed_NoPredicate (got {InResult})");

        FinishSuccess();
    }
}
