// Language=angelscript

//============================================================================
// INVENTORY GYM - SHARED SPAWN PARAMS, MESSAGES & ITEM DEFINITION LOADER
//============================================================================
//
// USER SETUP REQUIRED before this gym becomes fully functional:
//
// 1. Create a content folder at:
//      Plugins/CkTests/Content/CkInventory/Items/
//
// 2. Create these UCk_InventoryItem_Definition assets inside it:
//      ItemDef_Potion    (add Stackable trait, max 10; Tags trait: Item.Consumable, Item.Potion)
//      ItemDef_Arrow     (add Stackable trait, max 99; Tags trait: Item.Consumable, Item.Ammo)
//      ItemDef_Sword     (NO Stackable trait;          Tags trait: Item.Weapon,     Item.Melee)
//      ItemDef_Shield    (NO Stackable trait;          Tags trait: Item.Equipment,  Item.Defense)
//      ItemDef_Key       (NO Stackable trait;          Tags trait: Item.Quest)
//
// (Optional) For typesafe accessors, create a UCkAssetRegistryConfig data asset
// pointing at /CkTests/CkInventory/Items and run the asset registry generator.
// This gym currently uses utils_i_o::LoadAssetByName with hardcoded paths so it
// is self-contained and does not require the generator step.
//
//============================================================================

//============================================================================
// ITEM DEFINITION LOADER
//============================================================================

namespace inv_gym_items
{
    UCk_InventoryItem_Definition Get_ItemDef(FString InName)
    {
        auto Path = f"/CkTests/CkInventory/Items/{InName}.{InName}";
        auto LoadResult = utils_i_o::LoadAssetByName(Path, ECk_AssetSearchScope::Plugins);
        auto Asset = Cast<UCk_InventoryItem_Definition>(LoadResult._Asset);
        if (Asset == nullptr)
        {
            ck::Warning(f"[InventoryGym] Missing item definition at [{Path}] — create it in the editor (see CkInventoryGym_Shared.as header).");
        }
        return Asset;
    }

    UCk_InventoryItem_Definition Potion() { return Get_ItemDef("ItemDef_Potion"); }
    UCk_InventoryItem_Definition Arrow()  { return Get_ItemDef("ItemDef_Arrow");  }
    UCk_InventoryItem_Definition Sword()  { return Get_ItemDef("ItemDef_Sword");  }
    UCk_InventoryItem_Definition Shield() { return Get_ItemDef("ItemDef_Shield"); }
    UCk_InventoryItem_Definition Key()    { return Get_ItemDef("ItemDef_Key");    }
}

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
// MESSAGES — PlayerController → Station entities
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
// SHARED HELPERS
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

    // Compares an item's definition pointer to each known gym item def and returns
    // a friendly display name. Used instead of reaching into FCk_InventoryItem_CoreInfo
    // because its accessor is C++-only (CK_PROPERTY_GET doesn't emit a UFUNCTION).
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

    // FGameplayTagContainer::GetGameplayTagArray / ToString are not exposed to Angelscript,
    // so we summarize by count + First() tag + any known rarity overlays.
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
