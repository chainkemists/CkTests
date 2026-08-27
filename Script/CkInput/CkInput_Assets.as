// Language=angelscript

//============================================================================
// CK INPUT - KEY BINDING TEST CONTENT (script-literal Enhanced Input assets)
//============================================================================
//
// Input Actions and one Input Mapping Context for the CkInput key-binding
// autotests and gym, declared with the AngelScript `asset` keyword so no
// .uasset is involved. Each becomes a real UObject under
// /Script/AngelscriptAssets at module load.
//
// A mapping only becomes player-mappable if its Input Action carries a
// UPlayerMappableKeySettings (FEnhancedActionKeyMapping::IsPlayerMappable), and
// it only reaches the key profile once its context is handed to
// UEnhancedInputUserSettings::RegisterInputMappingContext. Registration is the
// caller's job - nothing here registers itself, so merely referencing these
// assets leaves every player's bindings untouched.
//
// The metadata writes below only compile INSIDE an asset block.
// UPlayerMappableKeySettings::Name / DisplayName / DisplayCategory are
// EditAnywhere + BlueprintReadOnly, which AngelScript exposes as edit-access:
// writable in __Init_* (what an asset body compiles to) and read-only
// everywhere else. That is why the four blocks repeat the same shape instead of
// sharing a helper function.
//
// Categories are load-bearing, not decoration: Get_HasKeyConflicts in
// SameCategory scope only reports a collision when both mappings share a
// DisplayCategory. Jump/Crouch (Movement) therefore collide under either scope,
// while Jump/Interact (Movement vs Interaction) collide only under All.
//============================================================================

namespace input_assets
{
    // Player-mappable rows IMC_CkTests_KeyBinding contributes to the key profile
    // one per MapKey call below. Four mapping names are single-slot, so each
    // contributes exactly one row; CkTests_DualBound is mapped twice (F8 then F12)
    // and contributes two, one per slot. Tests assert Get_AllRemappableKeys
    // against this, so the count and the content cannot drift apart.
    const int32 k_MappableRowCount = 6;

    // ------------------------------------------------------------------------
    // INPUT ACTIONS
    // ------------------------------------------------------------------------

    asset IA_CkTests_Jump of UInputAction
    {
        auto MappableKeySettings = Cast<UPlayerMappableKeySettings>(NewObject(this, UPlayerMappableKeySettings));
        MappableKeySettings.Name = n"CkTests_Jump";
        MappableKeySettings.DisplayName = FText::FromString("Jump");
        MappableKeySettings.DisplayCategory = FText::FromString("Movement");
        PlayerMappableKeySettings = MappableKeySettings;
    }

    asset IA_CkTests_Crouch of UInputAction
    {
        auto MappableKeySettings = Cast<UPlayerMappableKeySettings>(NewObject(this, UPlayerMappableKeySettings));
        MappableKeySettings.Name = n"CkTests_Crouch";
        MappableKeySettings.DisplayName = FText::FromString("Crouch");
        MappableKeySettings.DisplayCategory = FText::FromString("Movement");
        PlayerMappableKeySettings = MappableKeySettings;
    }

    asset IA_CkTests_Interact of UInputAction
    {
        auto MappableKeySettings = Cast<UPlayerMappableKeySettings>(NewObject(this, UPlayerMappableKeySettings));
        MappableKeySettings.Name = n"CkTests_Interact";
        MappableKeySettings.DisplayName = FText::FromString("Interact");
        MappableKeySettings.DisplayCategory = FText::FromString("Interaction");
        PlayerMappableKeySettings = MappableKeySettings;
    }

    asset IA_CkTests_Flashlight of UInputAction
    {
        auto MappableKeySettings = Cast<UPlayerMappableKeySettings>(NewObject(this, UPlayerMappableKeySettings));
        MappableKeySettings.Name = n"CkTests_Flashlight";
        MappableKeySettings.DisplayName = FText::FromString("Flashlight");
        MappableKeySettings.DisplayCategory = FText::FromString("Interaction");
        PlayerMappableKeySettings = MappableKeySettings;
    }

    // The only mapping in this file bound in TWO slots on the same device class.
    // UEnhancedInputUserSettings buckets slots by (mapping name, hardware device
    // type) in MapKey-registration order (EnhancedInputUserSettings.cpp - the
    // engine's own DetermineHardwareDeviceForActionMapping is unoverridden here,
    // so every key falls into one shared bucket) - the FIRST MapKey call below
    // for this action lands in EPlayerMappableKeySlot::First, the SECOND in
    // ::Second. That is what gives the multi-key button-map tests a mapping with
    // a genuine primary and secondary key to exercise, rather than one key bound
    // twice.
    asset IA_CkTests_DualBound of UInputAction
    {
        auto MappableKeySettings = Cast<UPlayerMappableKeySettings>(NewObject(this, UPlayerMappableKeySettings));
        MappableKeySettings.Name = n"CkTests_DualBound";
        MappableKeySettings.DisplayName = FText::FromString("Dual Bound");
        MappableKeySettings.DisplayCategory = FText::FromString("Testing");
        PlayerMappableKeySettings = MappableKeySettings;
    }

    // ------------------------------------------------------------------------
    // MAPPING CONTEXT
    // ------------------------------------------------------------------------

    asset IMC_CkTests_KeyBinding of UInputMappingContext
    {
        // Asset init bodies re-run on every AS recompile (the autotest wrapper
        // generator triggers one), and MapKey APPENDS - without this reset each
        // recompile doubles the mapping list on the live asset object.
        UnmapAll();
        MapKey(IA_CkTests_Jump, EKeys::SpaceBar);
        MapKey(IA_CkTests_Crouch, EKeys::C);
        MapKey(IA_CkTests_Interact, EKeys::E);
        MapKey(IA_CkTests_Flashlight, EKeys::F);
        // Order is load-bearing: the FIRST MapKey call for a mapping name becomes
        // its First slot. F8 is therefore the primary key, F12 the secondary.
        MapKey(IA_CkTests_DualBound, EKeys::F8);
        MapKey(IA_CkTests_DualBound, EKeys::F12);
    }
}
