// Language=angelscript

//============================================================================
// INVENTORY GYM - ITEM DEFINITION ASSETS
//============================================================================
//
// Item definitions declared inline using the Angelscript `asset` keyword.
// Each becomes a real UObject in /Script/AngelscriptAssets at module load,
// discoverable by the asset registry — no .uasset files needed.
//
//============================================================================

asset ItemDef_InvGym_Potion of UCk_InventoryItem_Definition
{
    _CoreInfo = FCk_InventoryItem_CoreInfo(FText::FromString("Potion"));

    auto Stackable = Cast<UCk_ItemTrait_Stackable>(NewObject(this, UCk_ItemTrait_Stackable));
    Stackable._InitialCount = 1;
    Stackable._HasMaxStackSize = true;
    Stackable._MaxStackSize = 10;
    _ItemTraits.Add(Stackable);

    auto TagsTrait = Cast<UCk_ItemTrait_Tags>(NewObject(this, UCk_ItemTrait_Tags));
    auto PotionTags = FGameplayTagContainer();
    PotionTags.AddTag(utils_gameplay_tag::ResolveGameplayTag(n"Item.Consumable"));
    PotionTags.AddTag(utils_gameplay_tag::ResolveGameplayTag(n"Item.Potion"));
    TagsTrait._Tags = PotionTags;
    _ItemTraits.Add(TagsTrait);
}

asset ItemDef_InvGym_Arrow of UCk_InventoryItem_Definition
{
    _CoreInfo = FCk_InventoryItem_CoreInfo(FText::FromString("Arrow"));

    auto Stackable = Cast<UCk_ItemTrait_Stackable>(NewObject(this, UCk_ItemTrait_Stackable));
    Stackable._InitialCount = 1;
    Stackable._HasMaxStackSize = true;
    Stackable._MaxStackSize = 99;
    _ItemTraits.Add(Stackable);

    auto TagsTrait = Cast<UCk_ItemTrait_Tags>(NewObject(this, UCk_ItemTrait_Tags));
    auto ArrowTags = FGameplayTagContainer();
    ArrowTags.AddTag(utils_gameplay_tag::ResolveGameplayTag(n"Item.Consumable"));
    ArrowTags.AddTag(utils_gameplay_tag::ResolveGameplayTag(n"Item.Ammo"));
    TagsTrait._Tags = ArrowTags;
    _ItemTraits.Add(TagsTrait);
}

asset ItemDef_InvGym_Sword of UCk_InventoryItem_Definition
{
    _CoreInfo = FCk_InventoryItem_CoreInfo(FText::FromString("Sword"));

    auto Dims = Cast<UCk_ItemTrait_Dimensions>(NewObject(this, UCk_ItemTrait_Dimensions));
    Dims._Dimensions = FIntPoint(3, 1);
    _ItemTraits.Add(Dims);

    auto TagsTrait = Cast<UCk_ItemTrait_Tags>(NewObject(this, UCk_ItemTrait_Tags));
    auto SwordTags = FGameplayTagContainer();
    SwordTags.AddTag(utils_gameplay_tag::ResolveGameplayTag(n"Item.Weapon"));
    SwordTags.AddTag(utils_gameplay_tag::ResolveGameplayTag(n"Item.Melee"));
    TagsTrait._Tags = SwordTags;
    _ItemTraits.Add(TagsTrait);
}

asset ItemDef_InvGym_Shield of UCk_InventoryItem_Definition
{
    _CoreInfo = FCk_InventoryItem_CoreInfo(FText::FromString("Shield"));

    auto TagsTrait = Cast<UCk_ItemTrait_Tags>(NewObject(this, UCk_ItemTrait_Tags));
    auto ShieldTags = FGameplayTagContainer();

    auto Dims = Cast<UCk_ItemTrait_Dimensions>(NewObject(this, UCk_ItemTrait_Dimensions));
    Dims._Dimensions = FIntPoint(1, 1);
    _ItemTraits.Add(Dims);

    ShieldTags.AddTag(utils_gameplay_tag::ResolveGameplayTag(n"Item.Equipment"));
    ShieldTags.AddTag(utils_gameplay_tag::ResolveGameplayTag(n"Item.Defense"));
    TagsTrait._Tags = ShieldTags;
    _ItemTraits.Add(TagsTrait);
}

asset ItemDef_InvGym_Key of UCk_InventoryItem_Definition
{
    _CoreInfo = FCk_InventoryItem_CoreInfo(FText::FromString("Key"));

    auto TagsTrait = Cast<UCk_ItemTrait_Tags>(NewObject(this, UCk_ItemTrait_Tags));
    auto KeyTags = FGameplayTagContainer();
    KeyTags.AddTag(utils_gameplay_tag::ResolveGameplayTag(n"Item.Quest"));
    TagsTrait._Tags = KeyTags;
    _ItemTraits.Add(TagsTrait);
}

//============================================================================
// ITEM DEFINITION ACCESSORS
//============================================================================

namespace inv_gym_items
{
    UCk_InventoryItem_Definition Potion() { return ItemDef_InvGym_Potion; }
    UCk_InventoryItem_Definition Arrow()  { return ItemDef_InvGym_Arrow;  }
    UCk_InventoryItem_Definition Sword()  { return ItemDef_InvGym_Sword;  }
    UCk_InventoryItem_Definition Shield() { return ItemDef_InvGym_Shield; }
    UCk_InventoryItem_Definition Key()    { return ItemDef_InvGym_Key;    }
}
