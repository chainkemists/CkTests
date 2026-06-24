// Language=angelscript

//============================================================================
// CK INVENTORY — AUTOMATION TEST: FILL-STACKS RESPECTS CanStackWith
//============================================================================
//
// Regression guard (sibling to CkAutoTest_Inventory_FillStacks_RespectsCustom-
// StackValidation, which covers the custom-hook gate on the SAME function).
//
// Request_FillExistingStacks matched existing stacks by DEFINITION only and
// skipped the trait-level CanStackWith() gate that the explicit StackItems path
// applies via Get_CanStackItems. So two same-definition items that a trait
// distinguishes by runtime state (the Tags trait — e.g. a rewound vs unrewound
// VHS tape in BusterBlock) silently MERGED on the transfer/AddByDefinition
// pre-fill, even though StackItems would refuse them.
//
// Repro — fails without the fix, passes with it:
//   1. Target (DataOnly, unbounded) holds Potion x1, UNTAGGED.
//   2. Source (DataOnly, unbounded) holds Potion x1, carrying a RUNTIME tag
//      (NOT part of the Potion definition, so it differs from the target's).
//   3. Transfer the tagged source Potion into the target with PreferStacking
//      (the default — the pickup/loot policy that pre-fills existing stacks).
//   4. The pre-fill must SKIP the untagged stack (CanStackWith == false) and the
//      unit must land as its OWN entry → 2 entries, 1 unit each.
//
// Without the fix the tagged unit merges into the untagged stack → 1 entry of
// count 2 (the tag silently laundered away).
//============================================================================

// Runtime marker tag, registered at AS load (no INI write at test time). NOT
// part of the Potion definition, so only the source instance carries it.
namespace Ck
{
    asset Asset_InvCanStackWithTest_Tags of UCk_GameplayTags
    {
        GameplayTags.Add(n"Inventory.AutoTest.CanStackWithMark");
    }
}

class UCk_AutoTest_Inventory_FillStacks_RespectsCanStackWith : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;

    private FCk_Handle_Inventory_DataOnly _Source;
    private FCk_Handle_Inventory_DataOnly _Target;
    private FCk_Handle_Item _TaggedItem;
    private FGameplayTag _RuntimeTag;
    private int _SettleTries = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;

        _RuntimeTag = utils_gameplay_tag::ResolveGameplayTag(n"Inventory.AutoTest.CanStackWithMark");

        auto SourceParams = utils_inventory_data_only::Make_Params(
            utils_gameplay_tag::ResolveGameplayTag(n"Inventory.AutoTest_CanStackWith_Source"),
            FCk_Delegate_Inventory_CustomCanAcceptItem_Dynamic(),
            FCk_Delegate_Inventory_CustomCanStackItems_Dynamic());
        _Source = utils_inventory_data_only::Add(LocalHandle, SourceParams, ECk_Replication::DoesNotReplicate);

        auto TargetParams = utils_inventory_data_only::Make_Params(
            utils_gameplay_tag::ResolveGameplayTag(n"Inventory.AutoTest_CanStackWith_Target"),
            FCk_Delegate_Inventory_CustomCanAcceptItem_Dynamic(),
            FCk_Delegate_Inventory_CustomCanStackItems_Dynamic());
        _Target = utils_inventory_data_only::Add(LocalHandle, TargetParams, ECk_Replication::DoesNotReplicate);

        // Target gets an UNTAGGED Potion stack (the "rewound" analogue).
        auto Request = FCk_Request_Inventory_AddItemByDefinition(inv_gym_items::Potion(), 1);
        _Target.Request_AddItemByDefinition(Request,
            FCk_Delegate_Inventory_OnOperationResult_AddByDefinition(this, n"OnTargetStocked"));
    }

    UFUNCTION()
    private void OnTargetStocked(
        FCk_Handle_Inventory InInventory,
        ECk_Inventory_OperationResult_AddByDefinition InResult,
        int InAmountAdded,
        const TArray<FCk_Handle_Item>&in InItemsCreated)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_Target.Get_NumItems(), 1, "Target seeded with one untagged Potion");

        // Source gets a Potion that we then tag (the "unrewound" analogue).
        auto Request = FCk_Request_Inventory_AddItemByDefinition(inv_gym_items::Potion(), 1);
        _Source.Request_AddItemByDefinition(Request,
            FCk_Delegate_Inventory_OnOperationResult_AddByDefinition(this, n"OnSourceStocked"));
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
        { FinishFailure(f"Expected one source Potion, got {InItemsCreated.Num()}"); return; }
        _TaggedItem = InItemsCreated[0];

        utils_item_trait_tags::Request_AddTag(_TaggedItem, _RuntimeTag);
        WaitOneFrame(n"OnSourceTagSettled");
    }

    UFUNCTION()
    private void OnSourceTagSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        if (utils_item_trait_tags::HasTag(_TaggedItem, _RuntimeTag) == false && _SettleTries < 40)
        { _SettleTries++; WaitOneFrame(n"OnSourceTagSettled"); return; }
        _SettleTries = 0;

        Assert_True(utils_item_trait_tags::HasTag(_TaggedItem, _RuntimeTag),
            "Source Potion carries the runtime tag before the transfer");

        // PreferStacking is the default transfer policy AND the pickup/loot policy
        // that pre-fills existing same-definition stacks. This is the bug path.
        auto Request = FCk_Request_Inventory_TransferItem_ToDataOnly(_TaggedItem, _Target);
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

        Assert_True(InResult == ECk_Inventory_OperationResult_Transfer::Success,
            f"Tagged Potion should transfer as a NEW entry (got {InResult})");
        WaitOneFrame(n"OnSettled");
    }

    UFUNCTION()
    private void OnSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        // THE REGRESSION ASSERT — without the fix the tagged unit merges into the
        // untagged stack and the target holds a single entry of count 2.
        Assert_Equals_Int(_Target.Get_NumItems(), 2,
            "Differing-tag same-definition Potions must NOT merge (two separate entries)");

        int Tagged = 0;
        int Untagged = 0;
        for (auto Item : _Target.Get_Items())
        {
            Assert_Equals_Int(utils_item_trait_stackable::Get_StackCount(Item), 1,
                "Each target entry keeps stack count 1 (no unit absorbed across the tag boundary)");
            if (utils_item_trait_tags::HasTag(Item, _RuntimeTag)) { Tagged += 1; }
            else { Untagged += 1; }
        }

        Assert_Equals_Int(Tagged, 1, "Exactly one tagged entry in the target");
        Assert_Equals_Int(Untagged, 1, "Exactly one untagged entry in the target");

        FinishSuccess();
    }
}
