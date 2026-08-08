// Language=angelscript

//============================================================================
// CK INPUT KEY-BINDING GYM — SHARED CONTRACT
//============================================================================
//
// Station tags, the mapping names the gym drives, and the read/format helpers
// every station shares.
//
// WHY THE MUTATIONS LIVE ON THE PLAYER CONTROLLER, NOT THE STATIONS. A key
// profile belongs to the LOCAL PLAYER, not to any station — there is no
// station-scoped binding state to mutate. The stations are read-only displays;
// every remap / swap / reset is an exec command on the gym PlayerController,
// and the stations show the result on their next display tick.
//
// LIVE READS, NEVER CACHED. Every station re-reads the profile on its display
// tick instead of snapshotting at construct, so a rebind performed from any
// source shows up without a manual refresh. Glyph brushes in particular MUST
// NOT be cached: both CkInput brush getters read the CommonUI device state at
// call time, so a cached FSlateBrush goes stale the instant the player switches
// keyboard <-> gamepad (CkInput/CLAUDE.md anti-pattern 4).
//
// TEARDOWN IS LAW HERE. SaveKeyBindings writes real user settings under Saved/
// that outlive the PIE session (CkInput/CLAUDE.md anti-pattern 2), so a leaked
// rebind poisons every later run and the next baseline capture.
// Request_ResetAllAndSave below is the single teardown call, reached two ways:
// the DoEndPlay of every station that can leave the profile customized, and an
// exec on the PlayerController. The DoEndPlay path is ARMED BY DEFAULT and can
// be suspended for one purpose only — observing a rebind survive a PIE restart,
// which is unobservable if leaving PIE erases it.
//
// Get_ActiveControllerData is deliberately never called from this gym: it
// ENSUREs when no controller data matches the current device, which is a
// legitimate outcome rather than an error (CkInput/CLAUDE.md anti-pattern 4).
// Get_BrushForKey / Get_BrushForInputAction return an empty brush on a miss and
// are the safe pair.
//============================================================================

namespace Ck
{
    asset InputGym_Tags of UCk_GameplayTags
    {
        GameplayTags.Add(n"Gym.Input.Inspection");
        GameplayTags.Add(n"Gym.Input.RemapConflict");
        GameplayTags.Add(n"Gym.Input.ResetPersistence");
        GameplayTags.Add(n"Gym.Input.KeyIcon");
        GameplayTags.Add(n"Gym.Input.ChangeSignal");
    }
}

//----------------------------------------------------------------------------
// One spawn-params shape for all five stations — the field names match the
// UPROPERTY(ExposeOnSpawn) names each station script declares, which is what
// the spawn-params contract keys on (Script/CLAUDE.md 10).
//----------------------------------------------------------------------------

USTRUCT()
struct FCkInputGym_StationSpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    UPROPERTY()
    FString StationTitle;

    UPROPERTY()
    FString StationDescription;
}

namespace input_gym
{
    // The mapping names authored on the four Input Actions
    // (CkInput_Assets.as:47, 56, 65, 74). Categories are load-bearing:
    // Jump/Crouch are both Movement and Interact/Flashlight are both
    // Interaction, so Jump<->Crouch collides under either conflict scope while
    // Jump<->Interact collides only under All.
    const FName k_Mapping_Jump       = n"CkTests_Jump";
    const FName k_Mapping_Crouch     = n"CkTests_Crouch";
    const FName k_Mapping_Interact   = n"CkTests_Interact";
    const FName k_Mapping_Flashlight = n"CkTests_Flashlight";

    // A key none of the four authored mappings holds — the "rebind to a free
    // key succeeds" case.
    const FKey k_FreeKey = EKeys::J;

    // Second free key. The batch remap lands both movement rows on it so the
    // conflict view has a two-holder key to report.
    const FKey k_BatchKey = EKeys::X;

    APlayerController Get_LocalPlayerController()
    {
        return Gameplay::GetPlayerController(0);
    }

    // Hands IMC_CkTests_KeyBinding to the user settings so its player-mappable
    // rows reach the active key profile. Without this the profile is empty and
    // every station renders nothing while appearing to work
    // (CkKeyBinding_Subsystem.cpp:62 makes the same call for scanned contexts).
    // Idempotent — a repeat call on an already-registered context returns false
    // and changes nothing, which is why the result is not treated as a failure.
    bool Request_RegisterMappingContext(APlayerController InPlayerController)
    {
        if (ck::Is_NOT_Valid(InPlayerController))
        { return false; }

        auto UserSettings = utils_key_binding::Get_InputUserSettings(InPlayerController);
        if (ck::Is_NOT_Valid(UserSettings))
        { return false; }

        UserSettings.RegisterInputMappingContext(input_assets::IMC_CkTests_KeyBinding);
        return true;
    }

    // The teardown call. ResetAllToDefaults goes through the settings layer so
    // watchers see the change (CkInput/CLAUDE.md, Broadcast discipline);
    // SaveKeyBindings then overwrites whatever an earlier remap wrote to disk.
    void Request_ResetAllAndSave(APlayerController InPlayerController)
    {
        if (ck::Is_NOT_Valid(InPlayerController))
        { return; }

        utils_key_binding::ResetAllToDefaults(InPlayerController);
        utils_key_binding::SaveKeyBindings(InPlayerController);
    }

    FString Format_Key(FKey InKey)
    {
        if (InKey.IsValid() == false)
        { return "<unbound>"; }

        return InKey.GetKeyName().ToString();
    }

    FString Format_Slot(EPlayerMappableKeySlot InSlot)
    {
        return f"slot{int(InSlot)}";
    }

    FString Format_BrushResource(FSlateBrush InBrush)
    {
        if (ck::Is_NOT_Valid(InBrush.ResourceObject))
        { return "<no glyph for this key on the active device>"; }

        return InBrush.ResourceObject.GetName().ToString();
    }

    // One row of the binding table: the mapping's display metadata off its
    // Input Action, the key it currently holds, and every other mapping sharing
    // that key. Read fresh on every call — see the file header.
    FString Format_MappingRow(APlayerController InPlayerController, const UInputAction InInputAction)
    {
        FCk_KeyBinding_MappableKeyInfo Info;
        auto HasInfo = utils_key_binding::Get_MappableKeyInfoFromInputAction(InInputAction, Info);
        if (HasInfo == false)
        { return "  <input action carries no player-mappable key settings>\n"; }

        auto MappingName = Info.Get_MappingName();
        auto CurrentKey  = utils_key_binding::Get_KeyForMapping(
            InPlayerController, MappingName, EPlayerMappableKeySlot::First);

        auto Row = f"  {Info.Get_DisplayName().ToString()} [{Info.Get_DisplayCategory().ToString()}]\n";
        Row = f"{Row}    name={MappingName}  key={Format_Key(CurrentKey)}\n";

        auto SharedWith = utils_key_binding::Get_MappingNamesForKey(InPlayerController, CurrentKey);
        if (SharedWith.Num() > 1)
        {
            auto Others = FString();
            for (auto Other : SharedWith)
            {
                if (Other == MappingName)
                { continue; }

                Others = f"{Others} {Other}";
            }
            Row = f"{Row}    SHARES KEY WITH:{Others}\n";
        }

        return Row;
    }

    FString Format_AllMappingRows(APlayerController InPlayerController)
    {
        auto Text = Format_MappingRow(InPlayerController, input_assets::IA_CkTests_Jump);
        Text = f"{Text}{Format_MappingRow(InPlayerController, input_assets::IA_CkTests_Crouch)}";
        Text = f"{Text}{Format_MappingRow(InPlayerController, input_assets::IA_CkTests_Interact)}";
        Text = f"{Text}{Format_MappingRow(InPlayerController, input_assets::IA_CkTests_Flashlight)}";
        return Text;
    }

    // The raw profile view — what Get_AllRemappableKeys itself returns, so a
    // row present in the profile but absent from the authored four is visible
    // rather than silently dropped by the per-Input-Action walk above.
    FString Format_ProfileRows(APlayerController InPlayerController)
    {
        auto Rows = utils_key_binding::Get_AllRemappableKeys(InPlayerController);
        auto Text = f"Profile rows: {Rows.Num()} (expected {input_assets::k_MappableRowCount})\n";

        for (auto Index = 0; Index < Rows.Num(); Index++)
        {
            auto Row = Rows[Index];
            Text = f"{Text}  {Row.MappingName} {Format_Slot(Row.Slot)}";
            Text = f"{Text}  current={Format_Key(Row.CurrentKey)}  default={Format_Key(Row.DefaultKey)}\n";
        }

        if (Rows.Num() == 0)
        {
            Text = f"{Text}  EMPTY — IMC_CkTests_KeyBinding never reached the key profile.\n";
            Text = f"{Text}  Nothing below this line is meaningful until it does.\n";
        }

        return Text;
    }

    FString Format_Conflicts(TArray<FCk_KeyBinding_ConflictInfo> InConflicts)
    {
        if (InConflicts.Num() == 0)
        { return "    (no conflicts)\n"; }

        auto Text = FString();
        for (auto Conflict : InConflicts)
        {
            Text = f"{Text}    {Conflict.Get_DisplayName().ToString()}";
            Text = f"{Text} (name={Conflict.Get_MappingName()}, category={Conflict.Get_DisplayCategory().ToString()})";
            Text = f"{Text} holds {Format_Key(Conflict.Get_CurrentKey())} in {Format_Slot(Conflict.Get_Slot())}\n";
        }
        return Text;
    }

    // Reports the conflicts InNewKey would cause for InMappingName under BOTH
    // scopes. Two calls rather than one because the difference between them IS
    // what the authored category design exists to demonstrate.
    FString Format_ConflictReport(APlayerController InPlayerController, FName InMappingName, FKey InNewKey)
    {
        auto Excluded = TArray<FName>();
        Excluded.Add(InMappingName);

        TArray<FCk_KeyBinding_ConflictInfo> AllScope;
        auto HasAll = utils_key_binding::Get_HasKeyConflicts(
            InPlayerController, InNewKey, Excluded, AllScope, ECk_KeyConflictScope::All);

        TArray<FCk_KeyBinding_ConflictInfo> SameCategoryScope;
        auto HasSameCategory = utils_key_binding::Get_HasKeyConflicts(
            InPlayerController, InNewKey, Excluded, SameCategoryScope, ECk_KeyConflictScope::SameCategory);

        auto Text = f"  {InMappingName} -> {Format_Key(InNewKey)}\n";
        Text = f"{Text}  scope=All          conflicts={HasAll}\n";
        Text = f"{Text}{Format_Conflicts(AllScope)}";
        Text = f"{Text}  scope=SameCategory conflicts={HasSameCategory}\n";
        Text = f"{Text}{Format_Conflicts(SameCategoryScope)}";
        return Text;
    }

    // Glyph resolution, re-run on every call. Reports the resolved brush's
    // resource object rather than drawing it — the gym station panel is
    // procedural 3D text, not Slate — which is still enough to watch the row
    // swap between keyboard and gamepad artwork when the device changes.
    FString Format_GlyphRow(APlayerController InPlayerController, const UInputAction InInputAction)
    {
        auto MappingName = utils_key_binding::Get_MappingNameFromInputAction(InInputAction);
        auto CurrentKey  = utils_key_binding::Get_KeyForInputAction(
            InPlayerController, InInputAction, EPlayerMappableKeySlot::First);

        auto ByKey    = utils_key_icon::Get_BrushForKey(InPlayerController, CurrentKey);
        auto ByAction = utils_key_icon::Get_BrushForInputAction(InPlayerController, InInputAction);

        auto Text = f"  {MappingName}  key={Format_Key(CurrentKey)}\n";
        Text = f"{Text}    ForKey    {Format_BrushResource(ByKey)}\n";
        Text = f"{Text}    ForAction {Format_BrushResource(ByAction)}\n";
        return Text;
    }

    FString Format_AllGlyphRows(APlayerController InPlayerController)
    {
        auto Text = Format_GlyphRow(InPlayerController, input_assets::IA_CkTests_Jump);
        Text = f"{Text}{Format_GlyphRow(InPlayerController, input_assets::IA_CkTests_Crouch)}";
        Text = f"{Text}{Format_GlyphRow(InPlayerController, input_assets::IA_CkTests_Interact)}";
        Text = f"{Text}{Format_GlyphRow(InPlayerController, input_assets::IA_CkTests_Flashlight)}";
        return Text;
    }
}
