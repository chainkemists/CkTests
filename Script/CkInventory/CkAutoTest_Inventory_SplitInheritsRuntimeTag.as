// Language=angelscript

//============================================================================
// CK INVENTORY — AUTOMATION TEST: SPLIT INHERITS A RUNTIME-ADDED TAG
//============================================================================
//
// Deterministic regression guard for the "split into a runtime-tag-gated
// inventory" bug (the BusterBlock Rewind Station inbox symptom).
//
// Mechanism: a partial transfer mints a NEW item via DoTransfer's split branch
// and copies the source's runtime tags onto it through a DEFERRED OnSplit
// request. The target's custom CanAcceptItem runs SYNCHRONOUSLY in the same
// call, so before the fix it saw the not-yet-copied tag and refused the split
// EVERY time (only the inbox-style runtime-tag gate is affected; a plain shelf
// accepts the tagless split fine).
//
// Repro shape — fails deterministically without the fix, passes with it:
//   1. Source (DataOnly, unbounded) holds Potion x5 — one stack.
//   2. A RUNTIME tag (NOT part of the Potion definition, so the split copy is
//      born without it) is added to that stack and allowed to commit.
//   3. Target (DataOnly, unbounded) has a CustomCanAcceptItem requiring that
//      runtime tag.
//   4. Transfer COUNT 1 (< stack count) → forces a SPLIT, not a whole-item move.
//   5. Assert the transfer SUCCEEDS, the target holds the split unit, and the
//      split unit ends up carrying the runtime tag.
//
// Without the fix, step 5's transfer settles Failed_RejectedByCustomAcceptanceLogic
// and the target stays empty.
//============================================================================

// Runtime marker tag, declared so it is registered at AS load (no INI write at
// test time, unlike the two-arg ResolveGameplayTag). NOT part of any item
// definition, so a freshly-minted split copy only receives it via OnSplit.
namespace Ck
{
    asset Asset_InvSplitTagTest_Tags of UCk_GameplayTags
    {
        GameplayTags.Add(n"Inventory.AutoTest.SplitRuntimeMark");
    }
}

class UCk_AutoTest_Inventory_SplitInheritsRuntimeTag : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;

    private FCk_Handle_Inventory_DataOnly _Source;
    private FCk_Handle_Inventory_DataOnly _Target;
    private FCk_Handle_Item _SourceItem;
    private FCk_Handle_Item _TargetItem;
    private FGameplayTag _RuntimeTag;
    private int _SettleTries = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        _RuntimeTag = utils_gameplay_tag::ResolveGameplayTag(n"Inventory.AutoTest.SplitRuntimeMark");

        auto SourceParams = utils_inventory_data_only::Make_Params(
            utils_gameplay_tag::ResolveGameplayTag(n"Inventory.AutoTest_SplitTag_Source"),
            FCk_Delegate_Inventory_CustomCanAcceptItem_Dynamic(),
            FCk_Delegate_Inventory_CustomCanStackItems_Dynamic());
        _Source = utils_inventory_data_only::Add(LocalHandle, SourceParams, ECk_Replication::DoesNotReplicate);

        auto AcceptDelegate = FCk_Delegate_Inventory_CustomCanAcceptItem_Dynamic(this, n"OnCanAcceptItem");
        auto TargetParams = utils_inventory_data_only::Make_Params(
            utils_gameplay_tag::ResolveGameplayTag(n"Inventory.AutoTest_SplitTag_Target"),
            AcceptDelegate,
            FCk_Delegate_Inventory_CustomCanStackItems_Dynamic());
        _Target = utils_inventory_data_only::Add(LocalHandle, TargetParams, ECk_Replication::DoesNotReplicate);

        auto Request = FCk_Request_Inventory_AddItemByDefinition(inv_gym_items::Potion(), 5);
        _Source.Request_AddItemByDefinition(Request,
            FCk_Delegate_Inventory_OnOperationResult_AddByDefinition(this, n"OnSourceStocked"));
    }

    // Target accepts only items carrying the runtime marker tag (the inbox-style gate).
    UFUNCTION()
    private void OnCanAcceptItem(FCk_Handle_Inventory InInventory, FCk_Handle_Item InItem, bool& OutCanAccept)
    {
        OutCanAccept = utils_item_trait_tags::HasTag(InItem, _RuntimeTag);
    }

    UFUNCTION()
    private void OnSourceStocked(
        FCk_Handle_Inventory InInventory,
        ECk_Inventory_OperationResult_AddByDefinition InResult,
        int InAmountAdded,
        const TArray<FCk_Handle_Item>&in InItemsCreated)
    {
        if (IsFinished()) { return; }

        if (InItemsCreated.Num() != 1)
        { FinishFailure(f"Expected Potion x5 as one stack, got {InItemsCreated.Num()} items"); return; }
        _SourceItem = InItemsCreated[0];

        // Add the runtime tag (deferred) and let it commit before we read / transfer.
        utils_item_trait_tags::Request_AddTag(_SourceItem, _RuntimeTag);
        WaitOneFrame(n"OnSourceTagSettled");
    }

    UFUNCTION()
    private void OnSourceTagSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        if (utils_item_trait_tags::HasTag(_SourceItem, _RuntimeTag) == false && _SettleTries < 40)
        { _SettleTries++; WaitOneFrame(n"OnSourceTagSettled"); return; }
        _SettleTries = 0;

        Assert_True(utils_item_trait_tags::HasTag(_SourceItem, _RuntimeTag),
            "Source stack should carry the runtime tag before the transfer");
        Assert_Equals_Int(utils_item_trait_stackable::Get_StackCount(_SourceItem), 5,
            "Source stack should hold 5 units before the split");

        // COUNT 1 of a 5-stack → forces the split branch (not an entity-preserving whole move).
        auto Request = FCk_Request_Inventory_TransferItem_ToDataOnly(_SourceItem, _Target);
        Request.Set_Count(1);
        _Source.Request_TransferItem_ToDataOnly(Request,
            FCk_Delegate_Inventory_OnOperationResult_Transfer(this, n"OnTransferResult"));
    }

    UFUNCTION()
    private void OnTransferResult(
        FCk_Handle_Inventory InSourceInventory,
        FCk_Handle_Item InItem,
        FCk_Handle_Inventory InTargetInventory,
        int InCountTransferred,
        FCk_Handle_Item InNewItemInTarget,
        ECk_Inventory_OperationResult_Transfer InResult)
    {
        if (IsFinished()) { return; }

        // THE REGRESSION ASSERT — without the fix this is Failed_RejectedByCustomAcceptanceLogic.
        Assert_True(InResult == ECk_Inventory_OperationResult_Transfer::Success,
            f"Split into a runtime-tag-gated target should SUCCEED (got {InResult})");
        Assert_Equals_Int(InCountTransferred, 1, "Exactly 1 unit should transfer");
        Assert_Equals_Int(_Target.Get_NumItems(), 1, "Target should hold the split-off unit");

        _TargetItem = InNewItemInTarget;
        WaitOneFrame(n"OnCopyTagSettled");
    }

    UFUNCTION()
    private void OnCopyTagSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        if (ck::Is_NOT_Valid(_TargetItem))
        { FinishFailure("Transfer reported no new target item to verify"); return; }

        if (utils_item_trait_tags::HasTag(_TargetItem, _RuntimeTag) == false && _SettleTries < 40)
        { _SettleTries++; WaitOneFrame(n"OnCopyTagSettled"); return; }

        Assert_True(utils_item_trait_tags::HasTag(_TargetItem, _RuntimeTag),
            "Split-off unit should inherit the source's runtime tag (OnSplit copy)");
        Assert_Equals_Int(utils_item_trait_stackable::Get_StackCount(_SourceItem), 4,
            "Source stack should retain 5 - 1 = 4 units");

        FinishSuccess();
    }
}
