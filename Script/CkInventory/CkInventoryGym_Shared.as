// Language=angelscript

//============================================================================
// INVENTORY GYM - SHARED SPAWN PARAMS, MESSAGES & HELPERS
//============================================================================
//
// Item definitions live in CkInventoryGym_Assets.as (the _Assets.as convention).
// This file contains spawn params, messages, and shared display helpers.
//
//============================================================================

//============================================================================
// SPAWN PARAMS
//============================================================================

USTRUCT()
struct FInventoryGymSpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FInventoryGymSpawnParams(FTransform InTransform)
    {
        InitialTransform = InTransform;
    }
}

//============================================================================
// MESSAGES - PlayerController -> Station entities
//============================================================================

USTRUCT()
struct FCk_Message_InvGym_AddItemByDef
{
    UPROPERTY()
    FString DefName;

    UPROPERTY()
    int32 Amount;

    FCk_Message_InvGym_AddItemByDef(FString InDefName = "", int32 InAmount = 1)
    {
        DefName = InDefName;
        Amount = InAmount;
    }
}

USTRUCT()
struct FCk_Message_InvGym_AddItemAt
{
    UPROPERTY()
    FString DefName;

    UPROPERTY()
    FIntPoint Coordinate;

    FCk_Message_InvGym_AddItemAt(FString InDefName = "", FIntPoint InCoord = FIntPoint(-1, -1))
    {
        DefName = InDefName;
        Coordinate = InCoord;
    }
}

USTRUCT()
struct FCk_Message_InvGym_RemoveFirst
{
    FCk_Message_InvGym_RemoveFirst() {}
}

USTRUCT()
struct FCk_Message_InvGym_OverrideBounds
{
    UPROPERTY()
    int32 NewBound;

    FCk_Message_InvGym_OverrideBounds(int32 InNewBound = -1)
    {
        NewBound = InNewBound;
    }
}

USTRUCT()
struct FCk_Message_InvGym_StackFirstTwo
{
    FCk_Message_InvGym_StackFirstTwo() {}
}

USTRUCT()
struct FCk_Message_InvGym_SplitFirst
{
    UPROPERTY()
    int32 SplitCount;

    FCk_Message_InvGym_SplitFirst(int32 InCount = 1)
    {
        SplitCount = InCount;
    }
}

USTRUCT()
struct FCk_Message_InvGym_AddTag
{
    UPROPERTY()
    FGameplayTag Tag;

    FCk_Message_InvGym_AddTag(FGameplayTag InTag = FGameplayTag())
    {
        Tag = InTag;
    }
}

USTRUCT()
struct FCk_Message_InvGym_RemoveTag
{
    UPROPERTY()
    FGameplayTag Tag;

    FCk_Message_InvGym_RemoveTag(FGameplayTag InTag = FGameplayTag())
    {
        Tag = InTag;
    }
}

USTRUCT()
struct FCk_Message_InvGym_SortInventory
{
    FCk_Message_InvGym_SortInventory() {}
}

//============================================================================
// SHELF LOOT/STOCK MESSAGES (desync repro station)
//============================================================================

USTRUCT()
struct FCk_Message_InvGym_ShelfStock
{
    FCk_Message_InvGym_ShelfStock() {}
}

USTRUCT()
struct FCk_Message_InvGym_ShelfLoot
{
    FCk_Message_InvGym_ShelfLoot() {}
}

USTRUCT()
struct FCk_Message_InvGym_ShelfLoop
{
    UPROPERTY()
    int32 Iterations;

    FCk_Message_InvGym_ShelfLoop(int32 InIterations = 10)
    {
        Iterations = InIterations;
    }
}

USTRUCT()
struct FCk_Message_InvGym_ShelfReset
{
    FCk_Message_InvGym_ShelfReset() {}
}

//============================================================================
// SHARED HELPERS (inventory-specific display utilities)
//============================================================================

namespace inv_gym_helpers
{
    UCk_InventoryItem_Definition ResolveDefByName(FString InName)
    {
        if (InName == "Potion") { return inv_gym_items::Potion(); }
        if (InName == "Arrow")  { return inv_gym_items::Arrow();  }
        if (InName == "Sword")  { return inv_gym_items::Sword();  }
        if (InName == "Shield") { return inv_gym_items::Shield(); }
        if (InName == "Key")    { return inv_gym_items::Key();    }
        return nullptr;
    }

    FString GetItemDisplayName(FCk_Handle_Item InItem)
    {
        auto Def = utils_item::Get_Definition(InItem);
        if (Def == nullptr) { return "<no def>"; }
        if (Def == inv_gym_items::Potion()) { return "Potion"; }
        if (Def == inv_gym_items::Arrow())  { return "Arrow";  }
        if (Def == inv_gym_items::Sword())  { return "Sword";  }
        if (Def == inv_gym_items::Shield()) { return "Shield"; }
        if (Def == inv_gym_items::Key())    { return "Key";    }
        return "<unknown>";
    }

    FString TagsToString(FGameplayTagContainer InTags)
    {
        if (InTags.IsEmpty()) { return "(none)"; }

        auto Num = InTags.Num();
        auto First = InTags.First();
        auto Summary = f"{Num} tag(s), first={First.ToString()}";

        auto Rare = utils_gameplay_tag::ResolveGameplayTag(n"Item.Rarity.Rare");
        auto Legendary = utils_gameplay_tag::ResolveGameplayTag(n"Item.Rarity.Legendary");
        if (InTags.HasTag(Rare))      { Summary = f"{Summary} [RARE]"; }
        if (InTags.HasTag(Legendary)) { Summary = f"{Summary} [LEGENDARY]"; }
        return Summary;
    }
}
