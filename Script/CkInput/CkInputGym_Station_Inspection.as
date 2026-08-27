// Language=angelscript

//============================================================================
// CK INPUT KEY-BINDING GYM - BINDING INSPECTION STATION
//
// The read half of the key-binding surface, all four query entry points on one
// panel: Get_AllRemappableKeys for the raw profile, Get_KeyForMapping for the
// key each row holds, Get_MappingNamesForKey for who else holds it, and
// Get_MappableKeyInfoFromInputAction for the display name and category the
// Input Action authored.
//
// The panel asserts one thing on its own: the profile has exactly the rows the
// mapping context authored. That check is what separates "nothing is bound" from
// "the mapping context never reached the key profile" - every query in this
// module answers identically in both cases, so a bare row list cannot tell them
// apart.
//
// A ROW OFF ITS DEFAULT IS AMBER, NOT RED. The demo on the Remap + Conflict
// station is customizing rows most of the time; drift from default is the
// expected state here, and the cyan note says so rather than leaving a viewer
// to read amber as a failure.
//
// Everything is read on the display tick and nothing is stored, so a remap made
// from any source - this gym's exec commands, the demo, a settings widget
// appears here without a manual refresh.
//============================================================================

class UCk_EntityScript_InputGym_Inspection : UCk_GenericEntityScript_UE
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
        utils_entity_tag::Add(InHandle, input_gym::k_Tag_Inspection);
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

        Add_RegistrationVerdict(Lines, PlayerController);
        Add_Rows(Lines, PlayerController);
        Add_PerActionView(Lines, PlayerController);
        Add_LastCommand(Lines);

        CkGym_Common::Update_StationDisplay_Colored(
            ck::ToEntity(this), StationTitle, Lines, StationDescription);
    }

    private void Add_RegistrationVerdict(TArray<FCkGym_ColoredLine>& OutLines, APlayerController InPlayerController)
    {
        auto Rows = utils_key_binding::Get_AllRemappableKeys(InPlayerController);
        auto Expected = input_assets::k_MappableRowCount;

        if (Rows.Num() == Expected)
        {
            input_gym::Add_Line(OutLines, f"  {Expected}/{Expected} rows registered", gym_palette::Green);
            return;
        }

        input_gym::Add_Line(OutLines, f"  rows registered  EXPECT {Expected} -> GOT {Rows.Num()}", gym_palette::Red);

        if (Rows.Num() == 0)
        {
            input_gym::Add_Line(OutLines, "  The mapping context never reached the key profile.", gym_palette::Red);
            input_gym::Add_Line(OutLines, "  Nothing below this line means anything until it does.", gym_palette::Red);
        }
    }

    private void Add_Rows(TArray<FCkGym_ColoredLine>& OutLines, APlayerController InPlayerController)
    {
        input_gym::Add_Spacer(OutLines, gym_palette::White);
        input_gym::Add_Line(OutLines, "THE KEY PROFILE", gym_palette::White);
        input_gym::Add_MappingRows(OutLines, InPlayerController);

        if (input_gym::Get_CustomizedRowCount(InPlayerController) == 0)
        { return; }

        input_gym::Add_Line(OutLines, "  Amber rows are off their authored key: the demo is mid-cycle or", gym_palette::Cyan);
        input_gym::Add_Line(OutLines, "  someone remapped by hand. Not a failure.", gym_palette::Cyan);
    }

    private void Add_PerActionView(TArray<FCkGym_ColoredLine>& OutLines, APlayerController InPlayerController)
    {
        input_gym::Add_Spacer(OutLines, gym_palette::White);
        input_gym::Add_Line(OutLines, "WHAT EACH ACTION IS CALLED, AND WHO SHARES ITS KEY", gym_palette::White);
        input_gym::Add_AllMappingDetails(OutLines, InPlayerController);
    }

    private void Add_LastCommand(TArray<FCkGym_ColoredLine>& OutLines)
    {
        input_gym::Add_Spacer(OutLines, gym_palette::White);
        input_gym::Add_Line(OutLines, f"LAST COMMAND - {input_gym_pc::Get_DumpReportLabel()}", gym_palette::White);

        auto Report = input_gym_pc::Get_DumpReportLines();
        input_gym::Add_Lines(OutLines, Report);

        input_gym::Add_Spacer(OutLines, gym_palette::White);
        input_gym::Add_Line(OutLines, "TRY IT YOURSELF", gym_palette::Cyan);
        input_gym::Add_Line(OutLines, "  Ck_GymInput_Dump    print the whole profile here", gym_palette::Cyan);
    }
}
