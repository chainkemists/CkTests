// Language=angelscript

//============================================================================
// CK GROUND NAV - AUTOMATION TEST: THE REPORT IS A SCHEMA, NOT A PRINTOUT
//============================================================================
//
// The shadow report exists to be diffed - one run against another, one machine
// against another, one week against last week. That only works if the same
// diagnostics render the same bytes and if the columns never move underneath a
// reader, so those are the two things asserted here.
//
// Nothing is dispatched. The report is read twice back to back with no query in
// between and the two must be byte identical: a map iteration order leaking
// into the row order, a %g anywhere, or a locale-sensitive number would all
// show up as two readings of one unchanged fragment disagreeing.
//
// The header is pinned against a LITERAL rather than against
// Get_ReportHeader(), on purpose. Comparing the report's header to the function
// that produced it asserts nothing at all - both move together. The literal is
// the contract, and a column added, removed or reordered has to be a deliberate
// edit to this file.
//
// A fixture is opened and closed without a single comparison landing in it, so
// the run also covers the case the report builder cares most about: a fixture
// that recorded nothing still emits a row, because an absent row and a zero row
// are different results and must not diff the same.
//
// The whole report is logged line by line, so any run carries the divergence
// evidence in its own log rather than only in a pass or fail.
//============================================================================

class UCk_AutoTest_GroundNav_Shadow_ReportSchemaIsStable : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 30.0f;

    private const int32 ExpectedColumnCount = 29;

    private const FString SchemaLine = "[SHADOW-REPORT] schema=1";
    private const FString HeaderLinePrefix = "[SHADOW-REPORT] header=";
    private const FString RowLinePrefix = "[SHADOW-REPORT] row=";
    private const FString DivergingLinePrefix = "[SHADOW-REPORT] diverging=";
    private const FString ArtifactLinePrefix = "[SHADOW-REPORT] artifact=";

    private const FName EmptyFixtureName = n"Shadow_SchemaOnly";

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step("open a fixture that will never record anything", n"Step_Arrange");
        Add_Step("read the report twice and pin its schema",       n"Step_AssertSchema");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // The expected header, spelled out.
    //
    // Built by appending rather than by concatenating literals: AngelScript
    // rejects adjacent string literals, and one 600-character line would hide
    // the very edit this test exists to make visible.
    //------------------------------------------------------------------------

    private FString Get_ExpectedHeader() const
    {
        FString Header = "";

        Header += "fixture|comparisons|both_succeeded|recast_only|groundnav_only|both_failed|";
        Header += "failreason_agree|failreason_disagree|partial_disagree|containment_escapes|";
        Header += "len_delta_uu_mean|len_delta_uu_p95~|len_delta_uu_max|";
        Header += "len_delta_rel_mean|len_delta_rel_p95~|len_delta_rel_max|";
        Header += "endpoint_uu_mean|endpoint_uu_p95~|endpoint_uu_max|";
        Header += "wp_delta_mean|wp_delta_p95~|wp_delta_max|";
        Header += "recast_ms_mean|recast_ms_p95~|recast_ms_max|";
        Header += "groundnav_ms_mean|groundnav_ms_p95~|groundnav_ms_max|status_pairs";

        return Header;
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_Arrange(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        // The world is shared with every other autotest, so the rows are cleared first: this test
        // asserts what the report SAYS about its own fixture, and a leftover row from a run that
        // happened to go before it would make that unreadable.
        utils_ground_nav_shadow::Request_ResetShadowDiagnostics();

        utils_ground_nav_shadow::Request_BeginShadowFixture(EmptyFixtureName);
        utils_ground_nav_shadow::Request_EndShadowFixture();
    }

    UFUNCTION()
    private void Step_AssertSchema(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto First = utils_ground_nav_shadow::Get_ShadowReport();
        const auto Second = utils_ground_nav_shadow::Get_ShadowReport();

        // Equals defaults to case-sensitive; FString's == does not, and "byte identical" is the
        // claim being made.
        Assert_True(First.Len() == Second.Len() && First.Equals(Second),
            "two readings of an unchanged fragment must render the same bytes - a report that cannot be read twice cannot be diffed at all");

        TArray<FString> Lines;
        First.ParseIntoArray(Lines, "\n", true);

        for (int32 Index = 0; Index < Lines.Num(); Index++)
        { ck::nav::Display(Lines[Index]); }

        if (Lines.Num() < 4)
        {
            FinishFailure(f"the report is {Lines.Num()} lines: a schema line, a header line, a diverging line and an artifact line are the minimum, and a fixture row was opened on top of those");
            return;
        }

        const auto ActualSchemaLine = Lines[0];

        Assert_True(ActualSchemaLine.Equals(SchemaLine),
            f"the first line names the schema version: expected '{SchemaLine}', got '{ActualSchemaLine}'");

        const auto ExpectedHeaderLine = HeaderLinePrefix + Get_ExpectedHeader();
        const auto ActualHeaderLine = Lines[1];

        Assert_True(ActualHeaderLine.Equals(ExpectedHeaderLine),
            f"the header line is the contract every row is read against, and it moved. Expected '{ExpectedHeaderLine}', got '{ActualHeaderLine}'. A column added, removed or reordered has to be a deliberate edit to this test.");

        const auto HeaderCellCount = Get_CellCount(Lines[1]);

        Assert_Equals_Int(HeaderCellCount, ExpectedColumnCount,
            "the header names exactly the columns a row carries");

        const auto EmptyFixtureRowPrefix = RowLinePrefix + EmptyFixtureName.ToString() + "|";

        auto RowCount = 0;
        auto FoundEmptyFixtureRow = false;
        auto SawDiverging = false;
        auto SawArtifact = false;

        for (int32 Index = 2; Index < Lines.Num(); Index++)
        {
            const auto Line = Lines[Index];

            if (Line.StartsWith(DivergingLinePrefix))
            {
                SawDiverging = true;
                continue;
            }

            if (Line.StartsWith(ArtifactLinePrefix))
            {
                SawArtifact = true;
                continue;
            }

            if (Line.StartsWith(RowLinePrefix) == false)
            {
                Assert_True(false, f"the report carried a line that is neither a row, the diverging list nor the artifact identity: '{Line}'");
                continue;
            }

            RowCount += 1;

            Assert_Equals_Int(Get_CellCount(Line), HeaderCellCount,
                f"row {RowCount} carries a different number of columns than the header names, so a reader lining the two up would read every value after the gap under the wrong name. Row: '{Line}'");

            if (Line.StartsWith(EmptyFixtureRowPrefix))
            { FoundEmptyFixtureRow = true; }
        }

        Assert_True(SawDiverging, "the report always names what diverged, even when nothing did");
        Assert_True(SawArtifact, "the report always names the artifact the run should be filed under");

        // The claim the report builder is most easily wrong about: opening a fixture is enough to
        // earn a row. A fixture that recorded nothing and a fixture that was never opened are
        // different results, and an absent row cannot say which.
        Assert_True(FoundEmptyFixtureRow,
            f"a fixture that was opened and recorded nothing still owes a row, and no row for '{EmptyFixtureName}' was emitted among {RowCount}");
    }

    //------------------------------------------------------------------------
    // Helpers
    //
    // The line prefix sits on the FIRST cell of both the header line and every
    // row line, so counting separators over the whole line compares like with
    // like without any substring surgery.
    //------------------------------------------------------------------------

    private int32 Get_CellCount(const FString& InLine) const
    {
        TArray<FString> Cells;

        // Empty cells are kept: a column that renders as nothing is still a column, and culling it
        // would let a missing value pass as a matching count.
        InLine.ParseIntoArray(Cells, "|", false);

        return Cells.Num();
    }
}
