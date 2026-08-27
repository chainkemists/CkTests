// Language=angelscript

//============================================================================
// CK INPUT KEY-BINDING GYM - SHARED CONTRACT
//============================================================================
//
// Station tags, the mapping names the gym drives, and the read/format helpers
// every station shares.
//
// EVERY PANEL IS A LIST OF COLOURED LINES, never one blob of text. A station
// panel is a UTextRenderComponent per colour run (CkGym_Utils.as), so the whole
// gym speaks in FCkGym_ColoredLine: green means a check matched, red means it
// did not, amber means a value drifted from its authored default, cyan is the
// live step or an instruction to the viewer, and grey is idle. The exec commands
// on the PlayerController report in the same currency, which is what lets a
// station render the last command's outcome without re-colouring it.
//
// WHY THE MUTATIONS LIVE ON THE PLAYER CONTROLLER, NOT THE STATIONS. A key
// profile belongs to the LOCAL PLAYER, not to any station - there is no
// station-scoped binding state to mutate. The stations are read-only displays;
// every remap / swap / reset is either a demo step on the Remap + Conflict
// station's state machine or an exec command on the gym PlayerController, and
// the stations show the result on their next display tick.
//
// LIVE READS, NEVER CACHED. Every station re-reads the profile on its display
// tick instead of snapshotting at construct, so a rebind performed from any
// source shows up without a manual refresh. Glyph brushes in particular MUST
// NOT be cached: both CkInput brush getters read the CommonUI device state at
// call time, so a cached FSlateBrush goes stale the instant the player switches
// keyboard <-> gamepad (the CkInput docs anti-pattern 4).
//
// TEARDOWN IS LAW HERE. SaveKeyBindings writes real user settings under Saved/
// that outlive the PIE session (the CkInput docs anti-pattern 2), so a leaked
// rebind poisons every later run and the next baseline capture. That matters
// more now that the demo runs unattended: leaving the gym mid-cycle would
// otherwise persist whatever step happened to be on screen.
// Request_ResetAllAndSave below is the single teardown call, reached two ways:
// the DoEndPlay of every station that can leave the profile customized, and an
// exec on the PlayerController. The DoEndPlay path is ARMED BY DEFAULT and can
// be suspended for one purpose only - observing a rebind survive a PIE restart,
// which is unobservable if leaving PIE erases it.
//
// Get_ActiveControllerData is deliberately never called from this gym: it
// ENSUREs when no controller data matches the current device, which is a
// legitimate outcome rather than an error (the CkInput docs anti-pattern 4).
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
// One spawn-params shape for all five stations - the field names match the
// UPROPERTY(ExposeOnSpawn) names each station script declares, which is what
// the spawn-params contract keys on (Script/ARCHITECTURE.md 10).
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

//----------------------------------------------------------------------------
// Verdict written by a demo step and rendered by its station on the next tick.
//
// A step state is its own entity script and must not reach into the station
// script's members, so the verdict travels as a fragment. It lands on the
// station SCRIPT entity, found by the private tag that station adds to itself:
// that is the one entity both sides can name without either of them depending
// on how the gym's entity hierarchy happens to resolve context owners.
//----------------------------------------------------------------------------

USTRUCT()
struct FCkInputGym_StepVerdict
{
    UPROPERTY()
    FString StepLabel;

    UPROPERTY()
    TArray<FCkGym_ColoredLine> Lines;
}

//----------------------------------------------------------------------------
// Result of the once-per-construct persistence probe. Recorded before the demo
// loop can move anything, so a PASS can only mean the marker key came off disk.
//----------------------------------------------------------------------------

USTRUCT()
struct FCkInputGym_PersistenceProbe
{
    UPROPERTY()
    bool Checked = false;

    UPROPERTY()
    bool Passed = false;

    UPROPERTY()
    FString ObservedJumpKey;
}

//----------------------------------------------------------------------------
// One row's glyph state, resolved and handed back rather than rendered on the
// spot: how a miss should READ depends on whether any other row resolved, and
// that is only knowable once the whole pass is in.
//----------------------------------------------------------------------------

USTRUCT()
struct FCkInputGym_GlyphRow
{
    UPROPERTY()
    FString KeyText;

    UPROPERTY()
    FColor KeyColour = FColor(255, 255, 255, 255);

    UPROPERTY()
    bool FromKeyResolved = false;

    UPROPERTY()
    FString FromKeyResource;

    UPROPERTY()
    bool FromActionResolved = false;

    UPROPERTY()
    FString FromActionResource;
}

namespace input_gym
{
    // Private per-station tags. The GymStation display entity carries the
    // Gym.Input.* tags; these sit on the station SCRIPT entities so a demo step
    // can find the station it is reporting against, and so the auto toggle can
    // reach the station that owns the demo state machine.
    const FName k_Tag_Inspection       = n"TAG_InputGym_Inspection";
    const FName k_Tag_RemapConflict    = n"TAG_InputGym_RemapConflict";
    const FName k_Tag_ResetPersistence = n"TAG_InputGym_ResetPersistence";
    const FName k_Tag_KeyIcon          = n"TAG_InputGym_KeyIcon";
    const FName k_Tag_ChangeSignal     = n"TAG_InputGym_ChangeSignal";

    // The mapping names authored on the four Input Actions
    // (CkInput_Assets.as:47, 56, 65, 74). Categories are load-bearing:
    // Jump/Crouch are both Movement and Interact/Flashlight are both
    // Interaction, so Jump<->Crouch collides under either conflict scope while
    // Jump<->Interact collides only under All.
    const FName k_Mapping_Jump       = n"CkTests_Jump";
    const FName k_Mapping_Crouch     = n"CkTests_Crouch";
    const FName k_Mapping_Interact   = n"CkTests_Interact";
    const FName k_Mapping_Flashlight = n"CkTests_Flashlight";

    // A key none of the four authored mappings holds - the "rebind to a free
    // key succeeds" case.
    const FKey k_FreeKey = EKeys::J;

    // Second free key. The batch remap lands several rows on it so the conflict
    // view has a multi-holder key to report.
    const FKey k_BatchKey = EKeys::X;

    // Reserved for the persistence check and nothing else. No exec command and
    // no demo step ever assigns it, which is what lets the construct-time probe
    // read "Jump holds this key" as proof the value came off disk rather than
    // from the loop that was running a moment ago.
    const FKey k_PersistMarkerKey = EKeys::Y;

    APlayerController Get_LocalPlayerController()
    {
        return Gameplay::GetPlayerController(0);
    }

    // Hands IMC_CkTests_KeyBinding to the user settings so its player-mappable
    // rows reach the active key profile. Without this the profile is empty and
    // every station renders nothing while appearing to work
    // (CkKeyBinding_Subsystem.cpp:62 makes the same call for scanned contexts).
    // Idempotent - a repeat call on an already-registered context returns false
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
    // watchers see the change (the CkInput docs, Broadcast discipline);
    // SaveKeyBindings then overwrites whatever an earlier remap wrote to disk.
    void Request_ResetAllAndSave(APlayerController InPlayerController)
    {
        if (ck::Is_NOT_Valid(InPlayerController))
        { return; }

        utils_key_binding::ResetAllToDefaults(InPlayerController);
        utils_key_binding::SaveKeyBindings(InPlayerController);
    }

    //------------------------------------------------------------------------
    // VALUE FORMATTING
    //------------------------------------------------------------------------

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
        { return "<none>"; }

        return InBrush.ResourceObject.GetName().ToString();
    }

    // "Crouch [Movement]" - the display name and category authored on the
    // Input Action. Conflict verdicts are stated in these terms because that is
    // what a player sees in a settings screen, not the internal mapping name.
    FString Format_MappingIdentity(const UInputAction InInputAction)
    {
        FCk_KeyBinding_MappableKeyInfo Info;
        if (utils_key_binding::Get_MappableKeyInfoFromInputAction(InInputAction, Info) == false)
        { return "<no player-mappable key settings>"; }

        return f"{Info.Get_DisplayName().ToString()} [{Info.Get_DisplayCategory().ToString()}]";
    }

    FString Format_ConflictHolders(TArray<FCk_KeyBinding_ConflictInfo> InConflicts)
    {
        if (InConflicts.Num() == 0)
        { return "(none)"; }

        auto Text = FString();
        for (auto Index = 0; Index < InConflicts.Num(); Index++)
        {
            auto Conflict = InConflicts[Index];
            auto Identity = f"{Conflict.Get_DisplayName().ToString()} [{Conflict.Get_DisplayCategory().ToString()}]";

            if (Index == 0)
            {
                Text = Identity;
                continue;
            }

            Text = f"{Text}, {Identity}";
        }

        return Text;
    }

    // Who would collide if InMappingName took InNewKey, under the named scope.
    // InMappingName is excluded from its own conflict list - it is the one
    // asking, not a holder.
    TArray<FCk_KeyBinding_ConflictInfo> Get_ConflictsFor(
        APlayerController InPlayerController,
        FName InMappingName,
        FKey InNewKey,
        ECk_KeyConflictScope InScope)
    {
        auto Excluded = TArray<FName>();
        Excluded.Add(InMappingName);

        TArray<FCk_KeyBinding_ConflictInfo> Conflicts;
        utils_key_binding::Get_HasKeyConflicts(InPlayerController, InNewKey, Excluded, Conflicts, InScope);
        return Conflicts;
    }

    FString Format_Bool(bool InValue)
    {
        if (InValue)
        { return "yes"; }

        return "no";
    }

    //------------------------------------------------------------------------
    // COLOURED PANEL BUILDING BLOCKS
    //------------------------------------------------------------------------

    void Add_Line(TArray<FCkGym_ColoredLine>& OutLines, FString InText, FColor InColour)
    {
        OutLines.Add(FCkGym_ColoredLine(InText, InColour));
    }

    // A blank line still belongs to a run, so it carries the colour of whatever
    // it separates rather than starting one of its own.
    void Add_Spacer(TArray<FCkGym_ColoredLine>& OutLines, FColor InColour)
    {
        OutLines.Add(FCkGym_ColoredLine(" ", InColour));
    }

    // InLines is a non-const reference on purpose: AngelScript rejects
    // TArray::Add of a const element, so a by-value (implicitly const)
    // parameter here would not compile. Callers stash a returned array in a
    // local first.
    void Add_Lines(TArray<FCkGym_ColoredLine>& OutLines, TArray<FCkGym_ColoredLine>& InLines)
    {
        for (auto Index = 0; Index < InLines.Num(); Index++)
        {
            OutLines.Add(InLines[Index]);
        }
    }

    FColor Get_VerdictColour(bool InPassed)
    {
        if (InPassed)
        { return gym_palette::Green; }

        return gym_palette::Red;
    }

    // The one self-asserting shape every station on this gym uses. Whatever the
    // check is, it reads the same way: what was expected, what was actually
    // there, and green or red for whether the two agree.
    void Add_Verdict(TArray<FCkGym_ColoredLine>& OutLines, FString InWhat, FString InExpect, FString InGot)
    {
        Add_Line(OutLines, f"  {InWhat}  EXPECT {InExpect} -> GOT {InGot}", Get_VerdictColour(InExpect == InGot));
    }

    FColor Get_DriftColour(bool InMatched)
    {
        if (InMatched)
        { return gym_palette::Green; }

        return gym_palette::Amber;
    }

    // Same shape as Add_Verdict, for a reading that legitimately disagrees while
    // something else is mid-flight. Red on this gym means a check the surface
    // should have passed and did not; a value that is merely following a running
    // demo has not failed anything, so it drifts amber instead.
    void Add_Verdict_AmberOnMismatch(TArray<FCkGym_ColoredLine>& OutLines, FString InWhat, FString InExpect, FString InGot)
    {
        Add_Line(OutLines, f"  {InWhat}  EXPECT {InExpect} -> GOT {InGot}", Get_DriftColour(InExpect == InGot));
    }

    // Live step list, sourced from the state machine's current state the same
    // way gym_sm::FormatAutoSequence sources it, so the panel cannot advertise a
    // step other than the one running.
    void Add_SmSteps(TArray<FCkGym_ColoredLine>& OutLines, const FCkGym_SmConfig&in InConfig, FCk_Handle_StateMachine InSm)
    {
        auto HasCurrent = ck::IsValid(InSm);
        TSubclassOf<UCk_SmState_EntityScript> Current;
        if (HasCurrent)
        { Current = utils_state_machine::Get_CurrentStateClass(InSm); }

        for (auto Index = 0; Index < InConfig.Steps.Num(); Index++)
        {
            auto IsActive = HasCurrent && InConfig.Steps[Index].StateClass == Current;

            if (IsActive)
            {
                Add_Line(OutLines, f"  >> {InConfig.Steps[Index].Description}", gym_palette::Cyan);
                continue;
            }

            Add_Line(OutLines, f"     {InConfig.Steps[Index].Description}", gym_palette::Grey);
        }
    }

    // One line per profile row. Amber names the authored default alongside the
    // live key whenever the two have drifted apart.
    void Add_MappingRows(TArray<FCkGym_ColoredLine>& OutLines, APlayerController InPlayerController)
    {
        auto Rows = utils_key_binding::Get_AllRemappableKeys(InPlayerController);

        if (Rows.Num() == 0)
        {
            Add_Line(OutLines, "  Nothing in the key profile - the mapping context never reached it.", gym_palette::Red);
            return;
        }

        for (auto Index = 0; Index < Rows.Num(); Index++)
        {
            auto Row = Rows[Index];
            auto Current = Format_Key(Row.CurrentKey);
            auto Default = Format_Key(Row.DefaultKey);

            if (Current == Default)
            {
                Add_Line(OutLines, f"  {Row.MappingName} is on {Current}", gym_palette::White);
                continue;
            }

            Add_Line(OutLines, f"  {Row.MappingName} is on {Current} (default {Default})", gym_palette::Amber);
        }
    }

    // The per-Input-Action view: display name, category, and anyone else holding
    // the same key. Complements Add_MappingRows, which reads the raw profile.
    void Add_MappingDetail(TArray<FCkGym_ColoredLine>& OutLines, APlayerController InPlayerController, const UInputAction InInputAction)
    {
        FCk_KeyBinding_MappableKeyInfo Info;
        if (utils_key_binding::Get_MappableKeyInfoFromInputAction(InInputAction, Info) == false)
        {
            Add_Line(OutLines, "  <input action carries no player-mappable key settings>", gym_palette::Red);
            return;
        }

        auto MappingName = Info.Get_MappingName();
        auto CurrentKey = utils_key_binding::Get_KeyForMapping(InPlayerController, MappingName, EPlayerMappableKeySlot::First);

        Add_Line(OutLines, f"  {Format_MappingIdentity(InInputAction)} on {Format_Key(CurrentKey)}", gym_palette::White);

        auto SharedWith = utils_key_binding::Get_MappingNamesForKey(InPlayerController, CurrentKey);
        if (SharedWith.Num() <= 1)
        { return; }

        auto Others = FString();
        for (auto Other : SharedWith)
        {
            if (Other == MappingName)
            { continue; }

            Others = f"{Others} {Other}";
        }

        Add_Line(OutLines, f"    also held by:{Others}", gym_palette::Amber);
    }

    void Add_AllMappingDetails(TArray<FCkGym_ColoredLine>& OutLines, APlayerController InPlayerController)
    {
        Add_MappingDetail(OutLines, InPlayerController, input_assets::IA_CkTests_Jump);
        Add_MappingDetail(OutLines, InPlayerController, input_assets::IA_CkTests_Crouch);
        Add_MappingDetail(OutLines, InPlayerController, input_assets::IA_CkTests_Interact);
        Add_MappingDetail(OutLines, InPlayerController, input_assets::IA_CkTests_Flashlight);
    }

    // What a remap onto InNewKey would collide with, under BOTH scopes, without
    // mutating anything. Two reads rather than one because the difference
    // between them IS what the authored categories exist to demonstrate.
    void Add_ConflictPreview(
        TArray<FCkGym_ColoredLine>& OutLines,
        APlayerController InPlayerController,
        FName InMappingName,
        FKey InNewKey)
    {
        Add_Line(OutLines, f"  if {InMappingName} took {Format_Key(InNewKey)}:", gym_palette::White);

        auto AllScope = Get_ConflictsFor(InPlayerController, InMappingName, InNewKey, ECk_KeyConflictScope::All);
        auto SameCategory = Get_ConflictsFor(InPlayerController, InMappingName, InNewKey, ECk_KeyConflictScope::SameCategory);

        Add_Line(OutLines, f"    any category  -> {Format_ConflictHolders(AllScope)}", gym_palette::White);
        Add_Line(OutLines, f"    same category -> {Format_ConflictHolders(SameCategory)}", gym_palette::White);
    }

    int32 Get_CustomizedRowCount(APlayerController InPlayerController)
    {
        auto Rows = utils_key_binding::Get_AllRemappableKeys(InPlayerController);
        auto Count = 0;

        for (auto Index = 0; Index < Rows.Num(); Index++)
        {
            auto Row = Rows[Index];
            if (Format_Key(Row.CurrentKey) != Format_Key(Row.DefaultKey))
            { Count++; }
        }

        return Count;
    }

    // Device class off the key's own name rather than a device query: the panel
    // is procedural 3D text with no CommonUI subsystem read of its own, and
    // Get_ActiveControllerData ensures on a legitimate miss
    // (the CkInput docs anti-pattern 4).
    bool Get_IsGamepadKey(FKey InKey)
    {
        return Format_Key(InKey).Contains("Gamepad");
    }

    // The profile is the only place a row's authored default is readable - the
    // Input Action itself carries display metadata, not the default key.
    FKey Get_DefaultKeyForMapping(APlayerController InPlayerController, FName InMappingName)
    {
        auto Rows = utils_key_binding::Get_AllRemappableKeys(InPlayerController);

        for (auto Index = 0; Index < Rows.Num(); Index++)
        {
            auto Row = Rows[Index];
            if (Row.MappingName == InMappingName)
            { return Row.DefaultKey; }
        }

        return FKey();
    }

    int32 Get_RowsAtDefaultCount(APlayerController InPlayerController)
    {
        auto Rows = utils_key_binding::Get_AllRemappableKeys(InPlayerController);
        auto Count = 0;

        for (auto Index = 0; Index < Rows.Num(); Index++)
        {
            auto Row = Rows[Index];
            if (Format_Key(Row.CurrentKey) == Format_Key(Row.DefaultKey))
            { Count++; }
        }

        return Count;
    }

    void Add_GlyphVerdict(TArray<FCkGym_ColoredLine>& OutLines, FString InLabel, bool InResolved, FString InResource)
    {
        if (InResolved == false)
        {
            Add_Line(OutLines, f"{InLabel}  NO GLYPH", gym_palette::Red);
            return;
        }

        Add_Line(OutLines, f"{InLabel}  glyph ok ({InResource})", gym_palette::Green);
    }

    // Per-row glyph state. Re-resolved on every call and NOTHING is stored:
    // both brush getters read the live CommonUI device state, so a cached
    // FSlateBrush is stale the moment the player changes device.
    FCkInputGym_GlyphRow Get_GlyphRow(APlayerController InPlayerController, const UInputAction InInputAction)
    {
        auto Row = FCkInputGym_GlyphRow();

        auto MappingName = utils_key_binding::Get_MappingNameFromInputAction(InInputAction);
        auto CurrentKey = utils_key_binding::Get_KeyForInputAction(InPlayerController, InInputAction, EPlayerMappableKeySlot::First);
        auto DefaultKey = Get_DefaultKeyForMapping(InPlayerController, MappingName);

        auto KeyColour = gym_palette::White;
        if (Get_IsGamepadKey(CurrentKey))
        { KeyColour = gym_palette::Cyan; }
        if (Format_Key(CurrentKey) != Format_Key(DefaultKey))
        { KeyColour = gym_palette::Amber; }

        Row.KeyText = f"  {Format_MappingIdentity(InInputAction)} on {Format_Key(CurrentKey)}";
        Row.KeyColour = KeyColour;

        auto ByKey = utils_key_icon::Get_BrushForKey(InPlayerController, CurrentKey);
        auto ByAction = utils_key_icon::Get_BrushForInputAction(InPlayerController, InInputAction);

        Row.FromKeyResolved = ck::IsValid(ByKey.ResourceObject);
        Row.FromKeyResource = Format_BrushResource(ByKey);
        Row.FromActionResolved = ck::IsValid(ByAction.ResourceObject);
        Row.FromActionResource = Format_BrushResource(ByAction);

        return Row;
    }

    int32 Get_ResolvedGlyphCount(TArray<FCkInputGym_GlyphRow>& InRows)
    {
        auto Count = 0;

        for (auto Index = 0; Index < InRows.Num(); Index++)
        {
            if (InRows[Index].FromKeyResolved)
            { Count++; }

            if (InRows[Index].FromActionResolved)
            { Count++; }
        }

        return Count;
    }

    // A pass where EVERY lookup missed is an empty art set, not four failures:
    // a project that configures no CommonUI controller data has nothing for a
    // correctly-wired resolver to hand back, so the panel says that once in
    // amber and drops the per-row verdicts. The moment ONE row resolves the
    // per-row green/red comes back - a miss next to a hit is a real difference,
    // and only the whole pass can tell the two apart.
    void Add_AllGlyphRows(TArray<FCkGym_ColoredLine>& OutLines, APlayerController InPlayerController)
    {
        auto JumpRow = Get_GlyphRow(InPlayerController, input_assets::IA_CkTests_Jump);
        auto CrouchRow = Get_GlyphRow(InPlayerController, input_assets::IA_CkTests_Crouch);
        auto InteractRow = Get_GlyphRow(InPlayerController, input_assets::IA_CkTests_Interact);
        auto FlashlightRow = Get_GlyphRow(InPlayerController, input_assets::IA_CkTests_Flashlight);

        auto Rows = TArray<FCkInputGym_GlyphRow>();
        Rows.Add(JumpRow);
        Rows.Add(CrouchRow);
        Rows.Add(InteractRow);
        Rows.Add(FlashlightRow);

        auto AnyResolved = Get_ResolvedGlyphCount(Rows) > 0;

        if (AnyResolved == false)
        {
            Add_Line(OutLines, "  no key artwork configured in this host project - glyph art ships", gym_palette::Amber);
            Add_Line(OutLines, "  with game projects (e.g. BusterBlock); the resolver wiring is", gym_palette::Amber);
            Add_Line(OutLines, "  exercised, the art set is empty", gym_palette::Amber);
        }

        for (auto Index = 0; Index < Rows.Num(); Index++)
        {
            Add_Line(OutLines, Rows[Index].KeyText, Rows[Index].KeyColour);

            if (AnyResolved == false)
            { continue; }

            Add_GlyphVerdict(OutLines, "    from key   ", Rows[Index].FromKeyResolved, Rows[Index].FromKeyResource);
            Add_GlyphVerdict(OutLines, "    from action", Rows[Index].FromActionResolved, Rows[Index].FromActionResource);
        }
    }

    //------------------------------------------------------------------------
    // STATION LOOKUP + VERDICT TRANSPORT
    //------------------------------------------------------------------------

    // Any entity in the world works as the query anchor - the tag store is
    // world-wide, which is what lets a demo step reach a station it holds no
    // reference to.
    FCk_Handle TryGet_TaggedStation(FCk_Handle InAnyEntity, FName InStationTag)
    {
        if (ck::Is_NOT_Valid(InAnyEntity))
        { return FCk_Handle(); }

        auto Entities = utils_entity_tag::ForEach_Entity(InAnyEntity, InStationTag);
        if (Entities.Num() == 0)
        { return FCk_Handle(); }

        return Entities[0];
    }

    void Write_StepVerdict(FCk_Handle InAnyEntity, FName InStationTag, FString InStepLabel, TArray<FCkGym_ColoredLine>& InLines)
    {
        auto Station = TryGet_TaggedStation(InAnyEntity, InStationTag);
        if (ck::Is_NOT_Valid(Station))
        { return; }

        auto& Verdict = Station.AddOrGet_Fragment(FCkInputGym_StepVerdict);
        Verdict.StepLabel = InStepLabel;
        Verdict.Lines = InLines;
    }
}
