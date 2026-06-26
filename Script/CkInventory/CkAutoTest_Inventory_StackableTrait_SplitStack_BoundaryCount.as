// Language=angelscript

//============================================================================
// CK INVENTORY — AUTOMATION TEST: SPLIT-STACK BOUNDARY COUNT
//============================================================================
//
// Pins the rejection path of Request_SplitStack when SplitCount equals or
// exceeds the source stack count. The framework treats `Count >= SourceCount`
// as invalid (you must leave at least one unit on the source — splitting the
// entire stack would just be a rename) and must report
// `Failed_InsufficientCount` without creating a new item entity.
//
// Procedure:
//   1. Add Potion x3 with default policy (single stack of count 3, by virtue
//      of the Stackable trait merging on add).
//   2. Request_SplitStack(stack, 3) — exactly equal to current stack count.
//   3. Result delegate must report `Failed_InsufficientCount`, the source
//      stack must retain its full count (3), the inventory must still hold
//      exactly one item, and no new item entity must be created
//      (`InNewItem` invalid).
//
// This is the boundary counterpart to CkAutoTest_Inventory_StackableTrait_SplitStack
// (which covers the success path: split 1 from a stack of 3).
//============================================================================

class UCk_AutoTest_Inventory_StackableTrait_SplitStack_BoundaryCount : UCk_AutoTest_Base
{
    private FCk_Handle_Inventory_DataOnly _Inventory;
    private FCk_Handle_Item _OriginalStack;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto Params = utils_inventory_data_only::Make_Params(
            utils_gameplay_tag::ResolveGameplayTag(n"Inventory.AutoTest_SplitBoundary"),
            FCk_Delegate_Inventory_CustomCanAcceptItem_Dynamic(),
            FCk_Delegate_Inventory_CustomCanStackItems_Dynamic());

        _Inventory = utils_inventory_data_only::Add(LocalHandle, Params, ECk_Replication::DoesNotReplicate);

        // Default add policy (NOT ForceNewItem) so 3 Potions land as a single stack of count 3.
        auto Request = FCk_Request_Inventory_AddItemByDefinition(inv_gym_items::Potion(), 3);
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

        if (InResult != ECk_Inventory_OperationResult_AddByDefinition::Success_AllAdded)
        {
            FinishFailure(f"Pre-split setup: Add(Potion x3) should succeed (got {InResult})");
            return;
        }

        auto Items = _Inventory.Get_Items();
        if (Items.Num() != 1)
        {
            FinishFailure(f"Pre-split setup: expected 1 stack, got {Items.Num()} items");
            return;
        }
        _OriginalStack = Items[0];

        // AddByDefinition's count is a deferred Override modifier — wait one
        // tick so the source's count is actually 3 before we ask the library
        // to split 3 off it (otherwise it sees count=1 and rejects for the
        // wrong reason).
        WaitOneFrame(n"OnPostAddSettled");
    }

    UFUNCTION()
    private void OnPostAddSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(utils_item_trait_stackable::Get_StackCount(_OriginalStack), 3,
            "Pre-split setup: stack should hold count 3 before the boundary-count attempt");

        // Boundary case: SplitCount == CurrentCount. Must be rejected as
        // Failed_InsufficientCount (callers cannot split off the entire
        // stack — that would leave the source empty).
        _Inventory.Request_SplitStack(FCk_Request_Inventory_SplitStack(_OriginalStack, 3),
            FCk_Delegate_Inventory_OnOperationResult_Split(this, n"OnSplitResult"));
    }

    UFUNCTION()
    private void OnSplitResult(
        FCk_Handle_Inventory InInventory,
        FCk_Handle_Item InSource,
        FCk_Handle_Item InNewItem,
        ECk_Inventory_OperationResult_Split InResult)
    {
        if (IsFinished()) { return; }

        Assert_True(InResult == ECk_Inventory_OperationResult_Split::Failed_InsufficientCount,
            f"SplitStack with SplitCount equal to source count must fail with Failed_InsufficientCount (got {InResult})");
        Assert_True(ck::Is_NOT_Valid(InNewItem),
            "No new item entity may be created when the split is rejected");
        Assert_Equals_Int(utils_item_trait_stackable::Get_StackCount(InSource), 3,
            "Source stack count must be unchanged (3) after a rejected split");
        Assert_Equals_Int(_Inventory.Get_NumItems(), 1,
            "Inventory must still hold exactly the original stack (no new item created)");

        FinishSuccess();
    }
}

class ACk_AutoTest_Inventory_StackableTrait_SplitStack_BoundaryCount_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Inventory_StackableTrait_SplitStack_BoundaryCount;

    // The test deliberately attempts SplitStack with Count == SourceCount to
    // pin the boundary contract (must return Failed_InsufficientCount, no new
    // item). The library correctly logs a Warning at that callsite — a real
    // diagnostic for production callers who reached an illegal split. Suppress
    // here so the harness doesn't escalate the intentional warning into a
    // test failure. Library severity unchanged for everyone outside the test.
    UFUNCTION(BlueprintOverride)
    TArray<FString> Get_ExpectedLogErrors() const
    {
        TArray<FString> Out;
        Out.Add("SplitStack: Invalid split count");
        return Out;
    }
}
