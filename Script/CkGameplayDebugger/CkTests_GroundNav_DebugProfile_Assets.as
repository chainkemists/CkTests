// Language=angelscript

//============================================================================
// CK TESTS - GROUND NAV GAMEPLAY DEBUGGER PROFILE
//============================================================================
//
// The debug profile that carries the GroundNav submenu and the filter that
// decides which actors it is pointed at. A profile is how the
// gameplay-debugger bridge learns which submenus exist at all - it walks the
// loaded profile's list every draw - so a submenu nothing lists is a submenu
// nothing ever runs, and a profile whose FILTER list is empty never reaches
// the submenus it does list.
//
//----------------------------------------------------------------------------
// WHY BOTH ARE BUILT HERE RATHER THAN NAMED
//----------------------------------------------------------------------------
//
// Both lists hold INSTANCES, not classes, so each entry is an object made with
// this profile as its outer. The writes themselves only compile inside an
// asset body: the lists are EditDefaultsOnly + BlueprintReadOnly, which
// AngelScript exposes as edit access - writable in the initialiser an asset
// block compiles to, and read-only everywhere else.
//
//----------------------------------------------------------------------------
// WHAT A MAINTAINER STILL HAS TO DO - ONE THING, OUTSIDE THIS FILE
//----------------------------------------------------------------------------
//
//   SELECT IT. Nothing selects a profile by existing. It is chosen by
//   Project Settings -> Plugins -> Gameplay Debugger -> "Project Default
//   Debug Profile", or per-user by the "User Override Debug Profile" in
//   Editor Preferences. Point one of those at
//   /Script/AngelscriptAssets.CkTests_GroundNav_DebugProfile.
//
// The shipped default profile is a .uasset and cannot be extended from script:
// an asset block initialises the object it declares and nothing else, so
// adding this submenu to that profile is an edit of that asset, not a line
// here.
//============================================================================

asset CkTests_GroundNav_DebugProfile of UCk_GameplayDebugger_DebugProfile_PDA
{
    auto GroundNavSubmenu = Cast<UCk_GroundNav_DebugSubmenu>(NewObject(this, UCk_GroundNav_DebugSubmenu));

    // Assigned whole rather than appended to: the edit-access setter an asset body gets replaces the
    // list, and mutating what a getter answered would write to a copy.
    TArray<TObjectPtr<UCk_GameplayDebugger_DebugSubmenu_UE>> Submenus;
    Submenus.Add(GroundNavSubmenu);

    _Submenus = Submenus;

    // The filter, listed the same way and for a load-bearing reason: the bridge picks the debug actor
    // through the profile's current filter and stops before choosing one while this list is empty, so
    // a profile with submenus and no filter never reaches a single one of them.
    auto GroundNavFilter = Cast<UCk_GroundNav_DebugFilter>(NewObject(this, UCk_GroundNav_DebugFilter));

    TArray<TObjectPtr<UCk_GameplayDebugger_DebugFilter_UE>> Filters;
    Filters.Add(GroundNavFilter);

    _Filters = Filters;
}
