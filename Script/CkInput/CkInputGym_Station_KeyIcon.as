// Language=angelscript

//============================================================================
// CK INPUT KEY-BINDING GYM - KEY ICON STATION
//
// Glyph resolution for every bound row, through Get_BrushForKey and
// Get_BrushForInputAction. Both are re-resolved on the display tick and NOTHING
// is stored: both read the live CommonUI device state at call time, so a cached
// FSlateBrush goes stale the moment the player switches keyboard <-> gamepad
// (the CkInput docs anti-pattern 4). Re-resolving every tick is strictly
// stronger than re-resolving on the device-change event and needs no listener.
//
// WHAT THIS PANEL ASSERTS: every row resolves to a real glyph, when there is an
// art set to resolve against. Green says the brush came back with a resource;
// red says the active device has no artwork for that key while other rows do
// have some - that difference is the finding worth showing. When EVERY lookup
// in the pass misses, the panel says so once in amber and drops the per-row
// verdicts: this host configures no CommonUI controller data at all, so four
// reds would read as four defects rather than an empty art set.
//
// Get_ActiveControllerData is deliberately NOT called here. It ENSUREs when no
// controller data matches the current device - a legitimate miss, not an error
// so a device-agnostic panel that polls it every tick would fire ensures at the
// viewer instead of showing them the glyph state. That is also why the panel
// cannot name the device it is currently resolving against: the only query that
// would answer is the one that ensures.
//
// This station never mutates the profile, so it has no teardown.
//============================================================================

class UCk_EntityScript_InputGym_KeyIcon : UCk_GenericEntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    UPROPERTY(ExposeOnSpawn)
    FString StationTitle;

    UPROPERTY(ExposeOnSpawn)
    FString StationDescription;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow
    DoConstruct(FCk_Handle& InHandle)
    {
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);
        utils_entity_tag::Add(InHandle, input_gym::k_Tag_KeyIcon);
        utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"OnDisplayTick"));

        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    UFUNCTION()
    private void OnDisplayTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        auto PlayerController = input_gym::Get_LocalPlayerController();
        if (ck::Is_NOT_Valid(PlayerController))
        { return; }

        auto Lines = TArray<FCkGym_ColoredLine>();

        input_gym::Add_Line(Lines, "ARTWORK FOR EVERY BOUND KEY", gym_palette::White);
        input_gym::Add_AllGlyphRows(Lines, PlayerController);

        Add_Legend(Lines);
        Add_LastCommand(Lines);

        CkGym_Common::Update_StationDisplay_Colored(
            ck::ToEntity(this), StationTitle, Lines, StationDescription);
    }

    private void Add_Legend(TArray<FCkGym_ColoredLine>& OutLines)
    {
        input_gym::Add_Spacer(OutLines, gym_palette::White);
        input_gym::Add_Line(OutLines, "READING THE ROWS", gym_palette::White);
        input_gym::Add_Line(OutLines, "  white key = keyboard or mouse", gym_palette::White);
        input_gym::Add_Line(OutLines, "  blue key  = gamepad", gym_palette::Cyan);
        input_gym::Add_Line(OutLines, "  amber key = moved off the key it was authored with", gym_palette::Amber);

        input_gym::Add_Spacer(OutLines, gym_palette::White);
        input_gym::Add_Line(OutLines, "  Plug or unplug a controller and press something on it: the", gym_palette::Cyan);
        input_gym::Add_Line(OutLines, "  whole glyph set should flip together on the very next tick.", gym_palette::Cyan);
    }

    private void Add_LastCommand(TArray<FCkGym_ColoredLine>& OutLines)
    {
        input_gym::Add_Spacer(OutLines, gym_palette::White);
        input_gym::Add_Line(OutLines, f"LAST COMMAND - {input_gym_pc::Get_GlyphReportLabel()}", gym_palette::White);

        auto Report = input_gym_pc::Get_GlyphReportLines();
        input_gym::Add_Lines(OutLines, Report);

        input_gym::Add_Spacer(OutLines, gym_palette::White);
        input_gym::Add_Line(OutLines, "TRY IT YOURSELF", gym_palette::Cyan);
        input_gym::Add_Line(OutLines, "  panel [B]    resolve every brush again, now", gym_palette::Cyan);
    }
}
