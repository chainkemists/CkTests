// What the shadow diagnostics are, held to the claim that they hold nothing.
//
// The fragment and the report are values all the way down, and the point of that is not tidiness:
// it is that a report can be rendered from diagnostics whose producer no longer exists. So the
// central test here builds a fragment, feeds it comparisons, COPIES it, lets the original go out of
// scope, and renders from the copy. If anything in there aliased back into the producer — a pointer,
// a shared reference, a handle — the copy would be reading a corpse, and no static_assert on a leaf
// struct would have caught it.
//
// The report's own contract is the second half. It is a schema meant to be diffed across runs and
// machines, so what is asserted is the schema and not the numbers: the header pinned against a
// literal, one row per fixture with keys sorted rather than iterated, a column count every row
// agrees on, the names of what diverged, and the same bytes on a second reading.
//
// The header literal is deliberately NOT taken from Get_ReportHeader(). Comparing the builder's
// output against the builder asserts nothing — both move together. A column added, removed or
// reordered has to be a deliberate edit here.
//
// Nothing in this file touches a world, a registry, an entity or a navmesh, and that is the whole
// reason it can make the claim it makes.

#include "CkGroundNav/Shadow/CkGroundNav_Shadow_Report.h"

#include "../CkUnitTest_Common.h"

#include <CoreMinimal.h>

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_groundnav_shadow
{
    using ck::FFragment_GroundNav_ShadowDiagnostics;
    using ck::groundnav::ECk_GroundNav_ShadowMetricKind;
    using ck::groundnav::FCk_GroundNav_ShadowComparison;
    using ck::groundnav::FCk_GroundNav_ShadowStats;
    using ck::groundnav::shadow::Accumulate;
    using ck::groundnav::shadow::Get_Report;
    using ck::groundnav::shadow::Get_ReportHeader;

    constexpr auto kSchemaLine = TEXT("[SHADOW-REPORT] schema=1");
    constexpr auto kHeaderLinePrefix = TEXT("[SHADOW-REPORT] header=");
    constexpr auto kRowLinePrefix = TEXT("[SHADOW-REPORT] row=");
    constexpr auto kDivergingLinePrefix = TEXT("[SHADOW-REPORT] diverging=");
    constexpr auto kArtifactLinePrefix = TEXT("[SHADOW-REPORT] artifact=");

    constexpr auto kExpectedColumnCount = 29;

    auto Get_ExpectedHeader() -> FString
    {
        return FString{
            TEXT("fixture|comparisons|both_succeeded|recast_only|groundnav_only|both_failed|")
            TEXT("failreason_agree|failreason_disagree|partial_disagree|containment_escapes|")
            TEXT("len_delta_uu_mean|len_delta_uu_p95~|len_delta_uu_max|")
            TEXT("len_delta_rel_mean|len_delta_rel_p95~|len_delta_rel_max|")
            TEXT("endpoint_uu_mean|endpoint_uu_p95~|endpoint_uu_max|")
            TEXT("wp_delta_mean|wp_delta_p95~|wp_delta_max|")
            TEXT("recast_ms_mean|recast_ms_p95~|recast_ms_max|")
            TEXT("groundnav_ms_mean|groundnav_ms_p95~|groundnav_ms_max|status_pairs")};
    }

    auto Get_Lines(const FString& InReport) -> TArray<FString>
    {
        auto Lines = TArray<FString>{};
        InReport.ParseIntoArray(Lines, TEXT("\n"), /*InCullEmpty=*/true);
        return Lines;
    }

    // Empty cells are KEPT: a column that renders as nothing is still a column, and culling it would
    // let a missing value pass as a matching count.
    auto Get_CellCount(const FString& InLine) -> int32
    {
        auto Cells = TArray<FString>{};
        InLine.ParseIntoArray(Cells, TEXT("|"), /*InCullEmpty=*/false);
        return Cells.Num();
    }

    auto Get_RowLines(const TArray<FString>& InLines) -> TArray<FString>
    {
        auto Rows = TArray<FString>{};

        for (const auto& Line : InLines)
        {
            if (Line.StartsWith(kRowLinePrefix, ESearchCase::CaseSensitive))
            { Rows.Emplace(Line); }
        }

        return Rows;
    }

    auto TryGet_LineWithPrefix(const TArray<FString>& InLines, const TCHAR* InPrefix) -> FString
    {
        for (const auto& Line : InLines)
        {
            if (Line.StartsWith(InPrefix, ESearchCase::CaseSensitive))
            { return Line; }
        }

        return {};
    }

    // ----------------------------------------------------------------------------------------------------------------

    auto Make_Agreeing(
        FName  InQueryId,
        double InRecastLengthUu,
        double InGroundNavLengthUu) -> FCk_GroundNav_ShadowComparison
    {
        auto Comparison = FCk_GroundNav_ShadowComparison{};

        Comparison._QueryId = InQueryId;

        Comparison._RecastStatus = ECk_Nav_PathStatus::Ready;
        Comparison._RecastWaypointCount = 4;
        Comparison._RecastLengthUu = InRecastLengthUu;
        Comparison._RecastEndpoint = FVector{100.0, 0.0, 0.0};
        Comparison._RecastQueryMs = 0.4;

        Comparison._GroundNavStatus = ECk_GroundNav_PathStatus::Ready;
        Comparison._GroundNavWaypointCount = 5;
        Comparison._GroundNavLengthUu = InGroundNavLengthUu;
        Comparison._GroundNavEndpoint = FVector{102.0, 0.0, 0.0};
        Comparison._GroundNavSearchMs = 0.9;

        return Comparison;
    }

    // Recast answered, GroundNav did not. An outcome only one provider reached is a divergence, so
    // the query id has to come back out in the report.
    auto Make_OutcomeDisagreement(
        FName InQueryId) -> FCk_GroundNav_ShadowComparison
    {
        auto Comparison = FCk_GroundNav_ShadowComparison{};

        Comparison._QueryId = InQueryId;

        Comparison._RecastStatus = ECk_Nav_PathStatus::Ready;
        Comparison._RecastWaypointCount = 3;
        Comparison._RecastLengthUu = 500.0;
        Comparison._RecastEndpoint = FVector{500.0, 0.0, 0.0};
        Comparison._RecastQueryMs = 0.3;

        Comparison._GroundNavStatus = ECk_GroundNav_PathStatus::NoStartSurface;
        Comparison._GroundNavFailReason = ECk_Nav_PathFailReason::StartProjectFailed;
        Comparison._GroundNavSearchMs = 0.2;

        return Comparison;
    }

    auto Make_BothFailed(
        FName                  InQueryId,
        ECk_Nav_PathFailReason InRecastReason,
        ECk_Nav_PathFailReason InGroundNavReason) -> FCk_GroundNav_ShadowComparison
    {
        auto Comparison = FCk_GroundNav_ShadowComparison{};

        Comparison._QueryId = InQueryId;

        Comparison._RecastStatus = ECk_Nav_PathStatus::Failed;
        Comparison._RecastFailReason = InRecastReason;
        Comparison._RecastQueryMs = 0.1;

        Comparison._GroundNavStatus = ECk_GroundNav_PathStatus::Unbuilt;
        Comparison._GroundNavFailReason = InGroundNavReason;
        Comparison._GroundNavSearchMs = 0.15;

        return Comparison;
    }

    // Fixtures are named out of alphabetical order on purpose: the report sorts its keys rather than
    // iterating the map, and a set already in order could not tell the two apart.
    auto Fill_Diagnostics(
        FFragment_GroundNav_ShadowDiagnostics& InOutDiagnostics) -> void
    {
        Accumulate(InOutDiagnostics, Make_BothFailed(
            TEXT("Q_Charlie_Agree"), ECk_Nav_PathFailReason::FindPathNoPath, ECk_Nav_PathFailReason::FindPathNoPath),
            TEXT("Charlie"));

        Accumulate(InOutDiagnostics, Make_BothFailed(
            TEXT("Q_Charlie_Disagree"), ECk_Nav_PathFailReason::FindPathNoPath, ECk_Nav_PathFailReason::NoNavData),
            TEXT("Charlie"));

        Accumulate(InOutDiagnostics, Make_Agreeing(TEXT("Q_Alpha_1"), 1000.0, 1012.0), TEXT("Alpha"));
        Accumulate(InOutDiagnostics, Make_Agreeing(TEXT("Q_Alpha_2"), 2000.0, 1990.0), TEXT("Alpha"));

        Accumulate(InOutDiagnostics, Make_OutcomeDisagreement(TEXT("Q_Bravo_1")), TEXT("Bravo"));
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Shadow_ReportOutlivesItsProducer,
    "CkTests.UnitTests.CkGroundNav.Shadow.Report_OutlivesItsProducer",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Shadow_ReportOutlivesItsProducer::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_shadow;

    auto Survivor = FFragment_GroundNav_ShadowDiagnostics{};

    {
        auto Producer = FFragment_GroundNav_ShadowDiagnostics{};
        Fill_Diagnostics(Producer);

        Survivor = Producer;
    }

    // Everything below reads a fragment whose producer no longer exists.
    const auto Report = Get_Report(Survivor, FString{TEXT("test")});
    const auto Lines = Get_Lines(Report);

    if (NOT TestTrue(
        FString::Printf(TEXT("the report renders a schema line, a header line, three rows, the diverging list and the artifact identity (got %d lines)"),
            Lines.Num()),
        Lines.Num() == 7))
    { return false; }

    TestEqual(TEXT("the first line names the schema version"), Lines[0], FString{kSchemaLine});

    TestEqual(TEXT("the header line is the contract every row is read against, and a column added, removed or reordered has to be a deliberate edit to this test"),
        Lines[1], FString{kHeaderLinePrefix} + Get_ExpectedHeader());

    TestEqual(TEXT("Get_ReportHeader names exactly the columns the report emits"),
        Get_ReportHeader(), Get_ExpectedHeader());

    const auto HeaderCellCount = Get_CellCount(Lines[1]);

    TestEqual(TEXT("the header names the expected number of columns"), HeaderCellCount, kExpectedColumnCount);

    const auto Rows = Get_RowLines(Lines);

    if (NOT TestEqual(TEXT("one row per fixture that was written to"), Rows.Num(), 3))
    { return false; }

    // Sorted by name, not by insertion or by map order: two runs that recorded the same fixtures in
    // a different order must produce the same bytes, or the report cannot be diffed.
    const FString ExpectedRowPrefixes[] = {
        FString{kRowLinePrefix} + TEXT("Alpha|2|2|0|0|0|0|0|0|0|"),
        FString{kRowLinePrefix} + TEXT("Bravo|1|0|1|0|0|0|0|0|0|"),
        FString{kRowLinePrefix} + TEXT("Charlie|2|0|0|0|2|1|1|0|0|")};

    for (auto RowIndex = 0; RowIndex < Rows.Num(); ++RowIndex)
    {
        TestTrue(
            FString::Printf(TEXT("row %d is the fixture sorting puts there, carrying the counts it recorded — expected to start '%s', got '%s'"),
                RowIndex, *ExpectedRowPrefixes[RowIndex], *Rows[RowIndex]),
            Rows[RowIndex].StartsWith(ExpectedRowPrefixes[RowIndex], ESearchCase::CaseSensitive));
    }

    for (auto RowIndex = 0; RowIndex < Rows.Num(); ++RowIndex)
    {
        TestEqual(
            FString::Printf(TEXT("row %d carries exactly the columns the header names — a reader lining the two up would otherwise read every value after the gap under the wrong name"),
                RowIndex),
            Get_CellCount(Rows[RowIndex]), HeaderCellCount);
    }

    // The report names what disagreed rather than only counting it: the outcome-only-one-provider
    // -reached comparison and the both-failed-for-different-reasons one, sorted.
    TestEqual(TEXT("the diverging line names every query that disagreed, sorted"),
        TryGet_LineWithPrefix(Lines, kDivergingLinePrefix),
        FString{kDivergingLinePrefix} + TEXT("Q_Bravo_1,Q_Charlie_Disagree"));

    TestEqual(TEXT("the artifact identity is carried through verbatim"),
        TryGet_LineWithPrefix(Lines, kArtifactLinePrefix),
        FString{kArtifactLinePrefix} + TEXT("test"));

    const auto SecondReading = Get_Report(Survivor, FString{TEXT("test")});

    TestTrue(TEXT("two readings of an unchanged fragment render the same bytes"),
        SecondReading.Equals(Report, ESearchCase::CaseSensitive));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Shadow_ReportOfNothingIsStillWellFormed,
    "CkTests.UnitTests.CkGroundNav.Shadow.Report_OfNothingIsStillWellFormed",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Shadow_ReportOfNothingIsStillWellFormed::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_shadow;

    // A run that recorded nothing must still say so in the same shape. A reader diffing two reports
    // cannot tell "no shadow run happened" from "the report builder fell over" if the second one is
    // an empty string.
    const auto Untouched = FFragment_GroundNav_ShadowDiagnostics{};
    const auto Report = Get_Report(Untouched, FString{});
    const auto Lines = Get_Lines(Report);

    if (NOT TestEqual(TEXT("an empty run still renders schema, header, diverging and artifact"), Lines.Num(), 4))
    { return false; }

    TestEqual(TEXT("the first line names the schema version"), Lines[0], FString{kSchemaLine});

    TestEqual(TEXT("the header is emitted whether or not any fixture was written to"),
        Lines[1], FString{kHeaderLinePrefix} + Get_ExpectedHeader());

    TestEqual(TEXT("nothing diverged, and the report says so rather than omitting the line"),
        Lines[2], FString{kDivergingLinePrefix} + TEXT("-"));

    TestEqual(TEXT("an unnamed artifact renders as the empty cell rather than as an empty line"),
        Lines[3], FString{kArtifactLinePrefix} + TEXT("-"));

    TestEqual(TEXT("no fixture was written to, so no row is emitted"), Get_RowLines(Lines).Num(), 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Shadow_P95ApproxIsBoundedAndOrdered,
    "CkTests.UnitTests.CkGroundNav.Shadow.P95Approx_IsBoundedAndOrdered",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Shadow_P95ApproxIsBoundedAndOrdered::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_shadow;

    // The column is labelled approximate, which is a licence to be off by a bucket width — not a
    // licence to be arbitrary. What a reader relies on is exactly this: it lies inside the observed
    // range, it does not fall below the middle of the distribution, and a distribution shifted
    // upwards reports a higher one.
    const auto Empty = FCk_GroundNav_ShadowStats{ECk_GroundNav_ShadowMetricKind::DistanceUu};

    TestEqual(TEXT("a distribution nobody sampled reports zero rather than a stale edge"),
        Empty.Get_P95Approx(), 0.0);

    auto Single = FCk_GroundNav_ShadowStats{ECk_GroundNav_ShadowMetricKind::DistanceUu};
    Single.Add(37.5);

    TestEqual(TEXT("one sample is its own 95th percentile"), Single.Get_P95Approx(), 37.5);

    auto Constant = FCk_GroundNav_ShadowStats{ECk_GroundNav_ShadowMetricKind::DistanceUu};

    for (auto Index = 0; Index < 20; ++Index)
    { Constant.Add(42.0); }

    // The interpolation is bounded by the recorded min and max rather than by the bucket's open
    // edges, so a distribution with no spread must not report the edge it happened to land under.
    TestEqual(TEXT("a distribution with no spread reports its own value, not its bucket edge"),
        Constant.Get_P95Approx(), 42.0);

    auto Spread = FCk_GroundNav_ShadowStats{ECk_GroundNav_ShadowMetricKind::DistanceUu};

    for (auto Index = 1; Index <= 100; ++Index)
    { Spread.Add(static_cast<double>(Index)); }

    TestEqual(TEXT("the mean of 1..100 is 50.5"), Spread.Get_Mean(), 50.5);
    TestEqual(TEXT("the recorded minimum is the smallest sample"), Spread._Min, 1.0);
    TestEqual(TEXT("the recorded maximum is the largest sample"), Spread._Max, 100.0);
    TestEqual(TEXT("every sample landed in a bucket"), Spread._Count, 100);

    const auto SpreadP95 = Spread.Get_P95Approx();

    TestTrue(FString::Printf(TEXT("p95 %f sits inside the observed range [%f, %f]"), SpreadP95, Spread._Min, Spread._Max),
        SpreadP95 >= Spread._Min && SpreadP95 <= Spread._Max);

    TestTrue(FString::Printf(TEXT("p95 %f is at or above the mean %f for a distribution with no left tail"),
        SpreadP95, Spread.Get_Mean()),
        SpreadP95 >= Spread.Get_Mean());

    auto Shifted = FCk_GroundNav_ShadowStats{ECk_GroundNav_ShadowMetricKind::DistanceUu};

    for (auto Index = 1; Index <= 100; ++Index)
    { Shifted.Add(static_cast<double>(Index) + 1000.0); }

    const auto ShiftedP95 = Shifted.Get_P95Approx();

    TestTrue(FString::Printf(TEXT("shifting every sample upwards raises p95 (%f -> %f)"), SpreadP95, ShiftedP95),
        ShiftedP95 > SpreadP95);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
