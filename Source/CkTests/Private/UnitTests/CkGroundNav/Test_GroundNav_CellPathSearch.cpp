// Strict dynamic overlays use the cell graph after normal end resolution. These checks exercise
// the real Bake -> Begin -> Continue path rather than manufacturing a route for postprocess.

#include "CkGroundNav/Query/CkGroundNav_Query_DynamicObstacles.h"
#include "CkGroundNav/Backend/CkGroundNav_GeometryBackend_Stub.h"
#include "CkGroundNav/Bake/CkGroundNav_LinkTypes.h"
#include "CkGroundNav/Field/CkGroundNav_Field.h"
#include "CkGroundNav/Query/CkGroundNav_Query_CellStep.h"
#include "CkGroundNav/Query/CkGroundNav_QueryCore.h"
#include "CkGroundNav/Search/CkGroundNav_PathPostProcess.h"
#include "CkGroundNav/Search/CkGroundNav_PathSearch.h"

#include "../CkUnitTest_Common.h"
#include "Test_GroundNav_QueryFixtures.h"

#include <CoreMinimal.h>
#include <NativeGameplayTags.h>

using ck::tests::kCkUnitTestFlags;

UE_DEFINE_GAMEPLAY_TAG_STATIC(TAG_CkTests_GroundNav_CellPathSearch_ForcedLink, "CkTests.GroundNav.CellPathSearch.ForcedLink");

namespace ck_test_groundnav_cellpathsearch
{
    using ck::groundnav::ECk_GroundNav_CellRouteEdgeKind;
    using ck::groundnav::ECk_GroundNav_DynamicUnionEdge;
    using ck::groundnav::ECk_GroundNav_PathRouteKind;
    using ck::groundnav::ECk_GroundNav_LinkWaypointRole;
    using ck::groundnav::FCk_GroundNav_DynamicObstacleDisc;
    using ck::groundnav::FCk_GroundNav_DynamicObstacleObb;
    using ck::groundnav::FCk_GroundNav_Field;
    using ck::groundnav::FCk_GroundNav_PathQuery;
    using ck::groundnav::FCk_GroundNav_PathPostParams;
    using ck::groundnav::FCk_GroundNav_PathSearch;
    using ck::groundnav::FCk_GroundNav_PathSliceParams;
    using ck::groundnav::Get_DynamicUnionEdge;
    using ck::groundnav::Get_PathPlan;
    using ck::groundnav::Try_MakeDynamicObstacleSnapshot;

    using ck_test_groundnav_queryfixtures::Bake_FlatScene;
    using ck_test_groundnav_queryfixtures::Bake;
    using ck_test_groundnav_queryfixtures::kGroundZ;
    using ck_test_groundnav_queryfixtures::kStepHeight;
    using ck_test_groundnav_queryfixtures::Make_FlatParams;
    using ck_test_groundnav_queryfixtures::Make_QueryParams;

    const auto kStart = FVector{100.0, 100.0, kGroundZ};
    const auto kGoal = FVector{700.0, 100.0, kGroundZ};

    auto BakeLinkedBarrier(const FCk_GroundNav_LinkRecord& InLink,
        ck::groundnav::FCk_GroundNav_FieldPtr& OutField) -> bool
    {
        auto Boxes = TArray<FBox>{};
        Boxes.Emplace(FBox{FVector{-400.0, -400.0, -10.0}, FVector{1200.0, 1200.0, kGroundZ}});
        Boxes.Emplace(FBox{FVector{350.0, -400.0, 0.0}, FVector{450.0, 500.0, 300.0}});
        auto Params = Make_FlatParams();
        Params._Links = {InLink};
        auto Field = MakeShared<FCk_GroundNav_Field>();
        if (NOT Bake(Boxes, Params, *Field)) { return false; }
        OutField = Field;
        return true;
    }

    // A wall covers the complete one-tile field from rim to rim. The two rooms have no ordinary
    // crossing, so rejecting this link cannot quietly pass by taking the detour used by the older
    // barrier fixture.
    auto BakeForcedLinkedBarrier(const FCk_GroundNav_LinkRecord& InLink,
        ck::groundnav::FCk_GroundNav_FieldPtr& OutField) -> bool
    {
        auto Boxes = TArray<FBox>{};
        Boxes.Emplace(FBox{FVector{-400.0, -400.0, -10.0}, FVector{1200.0, 1200.0, kGroundZ}});
        Boxes.Emplace(FBox{FVector{350.0, -400.0, 0.0}, FVector{450.0, 1200.0, 300.0}});
        auto Params = Make_FlatParams();
        Params._Links = {InLink};
        auto Field = MakeShared<FCk_GroundNav_Field>();
        if (NOT Bake(Boxes, Params, *Field)) { return false; }
        OutField = Field;
        return true;
    }

    // Tile 0 contains overlapping decks, joined by a ramp that finishes before the X=800 seam.
    // Tile 1 contains the elevated deck. A route from the lower deck must therefore use a local
    // cross-layer portal before crossing an elevated published seam. Layer indices are tile-local
    // allocation slots, so the test speaks in surface and plate identities rather than their numbers.
    auto BakeLayeredSeamField(FCk_GroundNav_Field& OutField) -> bool
    {
        auto Backend = ck::groundnav::FCk_GroundNav_GeometryBackend_Stub{};
        const auto Surface = ck::groundnav::ECk_GroundNav_BodyKind::Surface;
        Backend.Add_Panel(FVector{0.0, 0.0, 0.0}, FVector{800.0, 0.0, 0.0},
            FVector{800.0, 300.0, 0.0}, FVector{0.0, 300.0, 0.0}, Surface);
        Backend.Add_Panel(FVector{0.0, 0.0, 300.0}, FVector{1600.0, 0.0, 300.0},
            FVector{1600.0, 300.0, 300.0}, FVector{0.0, 300.0, 300.0}, Surface);
        Backend.Add_Panel(FVector{0.0, 300.0, 0.0}, FVector{800.0, 300.0, 300.0},
            FVector{800.0, 800.0, 300.0}, FVector{0.0, 800.0, 0.0}, Surface);
        return ck::groundnav::DoBake_Field(Backend, Make_QueryParams(),
            ck::groundnav::FCk_GroundNav_Epoch{1}, OutField).Get_IsCompleted();
    }

    auto MakeDisc(const FVector& InCentre, float InRadiusUu, float InHalfHeightUu = 50.0f) -> FCk_GroundNav_DynamicObstacleDisc
    {
        auto Disc = FCk_GroundNav_DynamicObstacleDisc{};
        Disc._Centre = InCentre;
        Disc._RadiusUu = InRadiusUu;
        Disc._VerticalHalfExtentUu = InHalfHeightUu;
        return Disc;
    }

    auto MakeSnapshot(TConstArrayView<FCk_GroundNav_DynamicObstacleDisc> InDiscs) -> ck::groundnav::FCk_GroundNav_DynamicObstacleSnapshot
    {
        const auto Snapshot = Try_MakeDynamicObstacleSnapshot(
            InDiscs, TConstArrayView<ck::groundnav::FCk_GroundNav_DynamicObstacleObb>{});
        return Snapshot.IsSet() ? Snapshot.GetValue() : ck::groundnav::FCk_GroundNav_DynamicObstacleSnapshot{};
    }

    auto MakeSnapshot(TConstArrayView<FCk_GroundNav_DynamicObstacleObb> InObbs) -> ck::groundnav::FCk_GroundNav_DynamicObstacleSnapshot
    {
        const auto Snapshot = Try_MakeDynamicObstacleSnapshot(
            TConstArrayView<ck::groundnav::FCk_GroundNav_DynamicObstacleDisc>{}, InObbs);
        return Snapshot.IsSet() ? Snapshot.GetValue() : ck::groundnav::FCk_GroundNav_DynamicObstacleSnapshot{};
    }

    auto MakeQueryForSnapshot(const FVector& InStart, const FVector& InGoal,
        ck::groundnav::FCk_GroundNav_DynamicObstacleSnapshot InSnapshot) -> FCk_GroundNav_PathQuery
    {
        auto Query = FCk_GroundNav_PathQuery{};
        Query._Start = InStart;
        Query._Goal = InGoal;
        Query._VerticalToleranceUu = kStepHeight;
        Query._DynamicObstacles = MoveTemp(InSnapshot);
        return Query;
    }

    auto MakeQuery(float InDiscRadiusUu) -> FCk_GroundNav_PathQuery
    {
        const auto Disc = MakeDisc(FVector{400.0, 100.0, kGroundZ}, InDiscRadiusUu);
        return MakeQueryForSnapshot(kStart, kGoal,
            MakeSnapshot(TConstArrayView<FCk_GroundNav_DynamicObstacleDisc>{&Disc, 1}));
    }

    auto RunToTerminal(FCk_GroundNav_PathSearch& InOutSearch, int32 InSliceIterations) -> ECk_GroundNav_PathStatus
    {
        auto Slice = FCk_GroundNav_PathSliceParams{};
        Slice._MaxIterations = InSliceIterations;
        for (auto Index = 0; Index < 20'000 && NOT InOutSearch.Get_IsTerminal(); ++Index)
        { InOutSearch.ContinueSearch(Slice); }
        return InOutSearch.Get_Status();
    }

    auto Get_ResolvedSurfaceZ(
        const FCk_GroundNav_Field& InField,
        const ck::groundnav::FCk_GroundNav_SurfaceRef& InSurface,
        float& OutZUu) -> bool
    {
        auto Address = ck::groundnav::FCk_GroundNav_CellAddress{};
        Address._TileIndex = InSurface._TileIndex;
        Address._CellX = InSurface._CellX;
        Address._CellY = InSurface._CellY;

        auto Resolved = ck::groundnav::FCk_GroundNav_SurfaceRef{};
        auto ClearanceUu = 0.0f;
        return ck::groundnav::Get_SurfaceAt(
            InField, Address, InSurface._LayerIndex, Resolved, OutZUu, ClearanceUu) && Resolved == InSurface;
    }

    auto Get_IsPublishedStep(
        const FCk_GroundNav_Field& InField,
        const ck::groundnav::FCk_GroundNav_SurfaceRef& InFrom,
        const ck::groundnav::FCk_GroundNav_SurfaceRef& InTo) -> bool
    {
        for (auto Direction = 0; Direction < ck::groundnav::kDirectionCount; ++Direction)
        {
            auto ResolvedTo = ck::groundnav::FCk_GroundNav_SurfaceRef{};
            auto SurfaceZUu = 0.0f;
            auto ClearanceUu = 0.0f;
            auto Cost = ck::groundnav::FCk_GroundNav_QueryCost{};
            if (ck::groundnav::Get_StepAcross(InField, InFrom, Direction,
                    ck::groundnav::FCk_GroundNav_QueryAgent{}, ResolvedTo, SurfaceZUu, ClearanceUu, Cost) ==
                    ck::groundnav::ECk_GroundNav_StepVerdict::Admitted &&
                ResolvedTo == InTo)
            { return true; }
        }

        return false;
    }

    auto Get_IsPublishedSeamPair(
        const FCk_GroundNav_Field& InField,
        const ck::groundnav::FCk_GroundNav_SurfaceRef& InFrom,
        const ck::groundnav::FCk_GroundNav_SurfaceRef& InTo) -> bool
    {
        return InField._SeamPortals.ContainsByPredicate([&](const auto& Seam)
        {
            return Seam._TileIndexA == InFrom._TileIndex && Seam._PlateA == InFrom._PlateIndex &&
                   Seam._TileIndexB == InTo._TileIndex && Seam._PlateB == InTo._PlateIndex;
        });
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_CellPathSearch_DiscDetoursWithExactTerminalEndpoints,
    "CkTests.UnitTests.CkGroundNav.Path.CellSearch.DiscDetoursWithExactTerminalEndpoints",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_CellPathSearch_DiscDetoursWithExactTerminalEndpoints::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_cellpathsearch;
    auto Field = MakeShared<FCk_GroundNav_Field>();
    if (NOT TestTrue(TEXT("the flat scene bakes"), Bake_FlatScene(*Field))) { return false; }

    auto Search = FCk_GroundNav_PathSearch{};
    TestEqual(TEXT("the strict graph begins"), Search.Request_Begin(Field, MakeQuery(90.0f)), ECk_GroundNav_PathStatus::InProgress);
    if (NOT TestEqual(TEXT("the strict graph resolves"), RunToTerminal(Search, 0), ECk_GroundNav_PathStatus::Ready)) { return false; }

    const auto& Result = Search.Get_Result();
    TestEqual(TEXT("the populated snapshot selected cell routing"), Result._RouteKind, ECk_GroundNav_PathRouteKind::StrictCell);
    TestTrue(TEXT("the obstruction caused a multi-leg detour"), Result._CellRoute.Num() > 2);
    TestEqual(TEXT("the first edge starts at the exact request point"), Result._CellRoute[0]._FromPoint, kStart);
    TestEqual(TEXT("the final edge ends at the exact request point"), Result._CellRoute.Last()._ToPoint, kGoal);
    for (auto Index = 0; Index < Result._CellRoute.Num(); ++Index)
    {
        const auto& Edge = Result._CellRoute[Index];
        if (Edge._Kind != ECk_GroundNav_CellRouteEdgeKind::Link)
        {
            TestEqual(TEXT("every ordinary strict edge stays outside the dynamic union"),
                Get_DynamicUnionEdge(Result._DynamicObstacles, Edge._FromPoint, Edge._ToPoint).GetValue(),
                ECk_GroundNav_DynamicUnionEdge::Clear);
        }
        if (Index > 0) { TestEqual(TEXT("predecessor rows remain geometrically continuous"), Edge._FromPoint, Result._CellRoute[Index - 1]._ToPoint); }
    }
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_CellPathSearch_SlicedParityAndExpansionCap,
    "CkTests.UnitTests.CkGroundNav.Path.CellSearch.SlicedParityAndExpansionCap",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_CellPathSearch_SlicedParityAndExpansionCap::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_cellpathsearch;
    auto Field = MakeShared<FCk_GroundNav_Field>();
    if (NOT TestTrue(TEXT("the flat scene bakes"), Bake_FlatScene(*Field))) { return false; }

    auto OneShot = FCk_GroundNav_PathSearch{};
    auto Sliced = FCk_GroundNav_PathSearch{};
    const auto Query = MakeQuery(90.0f);
    OneShot.Request_Begin(Field, Query);
    Sliced.Request_Begin(Field, Query);
    if (NOT TestEqual(TEXT("the one-shot route resolves"), RunToTerminal(OneShot, 0), ECk_GroundNav_PathStatus::Ready) ||
        NOT TestEqual(TEXT("the one-node slices resolve"), RunToTerminal(Sliced, 1), ECk_GroundNav_PathStatus::Ready)) { return false; }
    TestEqual(TEXT("slicing preserves strict expansion count"), Sliced.Get_Result()._ExpansionCount, OneShot.Get_Result()._ExpansionCount);
    TestEqual(TEXT("slicing preserves strict route rows"), Sliced.Get_Result()._CellRoute.Num(), OneShot.Get_Result()._CellRoute.Num());

    auto CappedQuery = Query;
    CappedQuery._MaxExpansions = 1;
    auto Capped = FCk_GroundNav_PathSearch{};
    Capped.Request_Begin(Field, CappedQuery);
    TestEqual(TEXT("a cell-search expansion cap stays native BudgetExceeded"),
        RunToTerminal(Capped, 1), ECk_GroundNav_PathStatus::BudgetExceeded);
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_CellPathSearch_InitialUnionEscapesOnceAndTerminalBypassesCoveredCell,
    "CkTests.UnitTests.CkGroundNav.Path.CellSearch.InitialUnionEscapesOnceAndTerminalBypassesCoveredCell",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_CellPathSearch_InitialUnionEscapesOnceAndTerminalBypassesCoveredCell::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_cellpathsearch;
    auto Field = MakeShared<FCk_GroundNav_Field>();
    if (NOT TestTrue(TEXT("the flat scene bakes"), Bake_FlatScene(*Field))) { return false; }

    // The first disc covers several cells around the source. The separated second disc makes a
    // re-entry route illegal after the search has reached genuinely clear ground.
    const auto EscapeDiscs = TArray<FCk_GroundNav_DynamicObstacleDisc>{
        MakeDisc(kStart, 110.0f), MakeDisc(FVector{425.0, 100.0, kGroundZ}, 85.0f)};
    auto Escape = FCk_GroundNav_PathSearch{};
    Escape.Request_Begin(Field, MakeQueryForSnapshot(kStart, kGoal, MakeSnapshot(EscapeDiscs)));
    if (NOT TestEqual(TEXT("the covered source escapes through a detour"), RunToTerminal(Escape, 1), ECk_GroundNav_PathStatus::Ready)) { return false; }

    auto HasExited = false;
    for (const auto& Edge : Escape.Get_Result()._CellRoute)
    {
        if (Edge._Kind == ECk_GroundNav_CellRouteEdgeKind::Link) { continue; }
        const auto Union = Get_DynamicUnionEdge(Escape.Get_Result()._DynamicObstacles, Edge._FromPoint, Edge._ToPoint).GetValue();
        const auto WasEscaped = HasExited;
        if (Union == ECk_GroundNav_DynamicUnionEdge::ExitsOnce) { HasExited = true; }
        if (WasEscaped) { TestEqual(TEXT("escaped routes never re-enter either dynamic footprint"), Union, ECk_GroundNav_DynamicUnionEdge::Clear); }
    }
    TestTrue(TEXT("the graph recorded an actual monotonic escape"), HasExited);

    // This tiny disc touches the goal cell's far corner but not the exact cardinal source-goal
    // segment. A centre-only graph would reject that conservatively covered cell; the goal terminal
    // is allowed to use the exact clear segment.
    const auto NearGoal = MakeDisc(FVector{699.0, 124.0, kGroundZ}, 2.0f);
    const auto TerminalStart = FVector{651.0, 101.0, kGroundZ};
    const auto TerminalGoal = FVector{676.0, 101.0, kGroundZ};
    auto Terminal = FCk_GroundNav_PathSearch{};
    Terminal.Request_Begin(Field, MakeQueryForSnapshot(TerminalStart, TerminalGoal,
        MakeSnapshot(TConstArrayView<FCk_GroundNav_DynamicObstacleDisc>{&NearGoal, 1})));
    if (NOT TestEqual(TEXT("the exact goal terminal bypasses only the covered cell-centre requirement"),
        RunToTerminal(Terminal, 0), ECk_GroundNav_PathStatus::Ready)) { return false; }
    TestEqual(TEXT("the terminal row ends at the exact partially covered goal"), Terminal.Get_Result()._CellRoute.Last()._ToPoint, TerminalGoal);
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_CellPathSearch_FiniteZAndFilterCostPolicies,
    "CkTests.UnitTests.CkGroundNav.Path.CellSearch.FiniteZAndFilterCostPolicies",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_CellPathSearch_FiniteZAndFilterCostPolicies::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_cellpathsearch;
    auto Field = MakeShared<FCk_GroundNav_Field>();
    if (NOT TestTrue(TEXT("the flat scene bakes"), Bake_FlatScene(*Field))) { return false; }

    const auto HighDisc = MakeDisc(FVector{400.0, 100.0, 150.0}, 120.0f, 10.0f);
    const auto HighQuery = MakeQueryForSnapshot(kStart, kGoal,
        MakeSnapshot(TConstArrayView<FCk_GroundNav_DynamicObstacleDisc>{&HighDisc, 1}));
    auto HighSearch = FCk_GroundNav_PathSearch{};
    HighSearch.Request_Begin(Field, HighQuery);
    if (NOT TestEqual(TEXT("an out-of-Z footprint does not block ground"), RunToTerminal(HighSearch, 0), ECk_GroundNav_PathStatus::Ready)) { return false; }

    const auto FlatPlate = 0;
    auto DeniedQuery = HighQuery;
    DeniedQuery._Cost._DeniedPlates.Add(FlatPlate);
    auto Denied = FCk_GroundNav_PathSearch{};
    Denied.Request_Begin(Field, DeniedQuery);
    TestEqual(TEXT("the normal plate filter still applies in the strict graph"),
        RunToTerminal(Denied, 0), ECk_GroundNav_PathStatus::Unreachable);

    auto DearQuery = HighQuery;
    DearQuery._Cost._PlateCostMultipliers.Add(FlatPlate, 2.0f);
    auto Dear = FCk_GroundNav_PathSearch{};
    Dear.Request_Begin(Field, DearQuery);
    if (NOT TestEqual(TEXT("the dear strict route resolves"), RunToTerminal(Dear, 0), ECk_GroundNav_PathStatus::Ready)) { return false; }
    TestTrue(TEXT("the ordinary policy multiplier contributes to strict-cell leg pricing"),
        Dear.Get_Result()._SearchCost > HighSearch.Get_Result()._SearchCost);

    // This wall divides the field while leaving both terminal cells clear. The strict search must
    // expand the reachable left-hand frontier before exhausting it; unlike the old disc, it cannot
    // conservatively cover the source cell and terminate before a partial corridor exists.
    auto Barrier = FCk_GroundNav_DynamicObstacleObb{};
    Barrier._YawTransform = FTransform{FQuat::Identity, FVector{400.0, 400.0, kGroundZ}};
    Barrier._WorldHalfExtents = FVector{25.0, 400.0, 50.0};
    const auto FieldMinY = Field->_Params._OriginXY.Y;
    const auto FieldMaxY = FieldMinY + Field->_Params._Config.Get_TileSizeUu();
    if (NOT TestEqual(TEXT("the wall begins at the baked field's south rim"),
        Barrier._YawTransform.GetLocation().Y - Barrier._WorldHalfExtents.Y, FieldMinY)) { return false; }
    if (NOT TestEqual(TEXT("the wall ends at the baked field's north rim"),
        Barrier._YawTransform.GetLocation().Y + Barrier._WorldHalfExtents.Y, FieldMaxY)) { return false; }
    if (NOT TestTrue(TEXT("the partial source remains west of the wall"),
        kStart.X < Barrier._YawTransform.GetLocation().X - Barrier._WorldHalfExtents.X)) { return false; }
    if (NOT TestTrue(TEXT("the partial goal remains east of the wall"),
        kGoal.X > Barrier._YawTransform.GetLocation().X + Barrier._WorldHalfExtents.X)) { return false; }
    auto PartialQuery = MakeQueryForSnapshot(kStart, kGoal,
        MakeSnapshot(TConstArrayView<FCk_GroundNav_DynamicObstacleObb>{&Barrier, 1}));
    PartialQuery._AllowPartialPath = ECk_EnableDisable::Enable;
    auto Partial = FCk_GroundNav_PathSearch{};
    Partial.Request_Begin(Field, PartialQuery);
    if (NOT TestEqual(TEXT("an exhausted strict graph returns the existing Partial status when requested"),
        RunToTerminal(Partial, 1), ECk_GroundNav_PathStatus::Partial)) { return false; }
    TestTrue(TEXT("the partial answer contains the reachable strict frontier"),
        Partial.Get_Result()._CellRoute.Num() > 0);
    TestTrue(TEXT("the partial answer stops before the blocked goal"),
        NOT Partial.Get_Result()._GoalPoint.Equals(kGoal, KINDA_SMALL_NUMBER));
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_CellPathSearch_AuthoredLinkKeepsIdentityAndMayCrossInteriorBlocker,
    "CkTests.UnitTests.CkGroundNav.Path.CellSearch.AuthoredLinkKeepsIdentityAndMayCrossInteriorBlocker",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_CellPathSearch_AuthoredLinkKeepsIdentityAndMayCrossInteriorBlocker::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_cellpathsearch;
    const auto LinkRecord = FCk_GroundNav_LinkRecord{17, FVector{300.0, 200.0, kGroundZ}, FVector{500.0, 200.0, kGroundZ}};
    auto Field = ck::groundnav::FCk_GroundNav_FieldPtr{};
    if (NOT TestTrue(TEXT("the linked barrier scene bakes"), BakeLinkedBarrier(LinkRecord, Field))) { return false; }

    // The footprint blocks the middle of the authored span but leaves both resolved endpoint cells
    // clear. Link traversal is a jump/teleport semantic and must retain its authored edge instead of
    // being rejected by the ordinary-union test used for ground legs.
    const auto MidSpan = MakeDisc(FVector{400.0, 200.0, kGroundZ}, 30.0f);
    const auto Query = MakeQueryForSnapshot(FVector{200.0, 200.0, kGroundZ}, FVector{600.0, 200.0, kGroundZ},
        MakeSnapshot(TConstArrayView<FCk_GroundNav_DynamicObstacleDisc>{&MidSpan, 1}));
    auto Search = FCk_GroundNav_PathSearch{};
    Search.Request_Begin(Field, Query);
    if (NOT TestEqual(TEXT("the clear-endpoint link remains a legal strict route"), RunToTerminal(Search, 0), ECk_GroundNav_PathStatus::Ready)) { return false; }
    const auto* Link = Search.Get_Result()._CellRoute.FindByPredicate([](const auto& Edge)
    { return Edge._Kind == ECk_GroundNav_CellRouteEdgeKind::Link; });
    if (NOT TestNotNull(TEXT("the strict route retains the authored link row"), Link)) { return false; }
    TestEqual(TEXT("the link row preserves the stable identity"), Link->_LinkStableId, 17);

    auto DeniedQuery = Query;
    DeniedQuery._Cost._DeniedLinkIds.Add(17);
    auto Denied = FCk_GroundNav_PathSearch{};
    Denied.Request_Begin(Field, DeniedQuery);
    if (NOT TestEqual(TEXT("a denied authored link falls back to the static detour"),
        RunToTerminal(Denied, 0), ECk_GroundNav_PathStatus::Ready)) { return false; }
    TestTrue(TEXT("a denied authored link is not flattened into an ordinary crossing"),
        Denied.Get_Result()._CellRoute.FindByPredicate([](const auto& Edge)
        { return Edge._Kind == ECk_GroundNav_CellRouteEdgeKind::Link; }) == nullptr);

    auto ForwardRecord = LinkRecord;
    ForwardRecord.Set_Direction(ECk_GroundNav_LinkDirection::Forward);
    auto ForwardField = ck::groundnav::FCk_GroundNav_FieldPtr{};
    if (NOT TestTrue(TEXT("the forward-only linked barrier bakes"), BakeLinkedBarrier(ForwardRecord, ForwardField))) { return false; }
    auto Reverse = FCk_GroundNav_PathSearch{};
    Reverse.Request_Begin(ForwardField, MakeQueryForSnapshot(FVector{600.0, 200.0, kGroundZ}, FVector{200.0, 200.0, kGroundZ},
        MakeSnapshot(TConstArrayView<FCk_GroundNav_DynamicObstacleDisc>{&MidSpan, 1})));
    if (NOT TestEqual(TEXT("the reverse one-way query takes the detour"), RunToTerminal(Reverse, 0), ECk_GroundNav_PathStatus::Ready)) { return false; }
    TestTrue(TEXT("the reverse strict route contains no forward-only link row"),
        Reverse.Get_Result()._CellRoute.FindByPredicate([](const auto& Edge)
        { return Edge._Kind == ECk_GroundNav_CellRouteEdgeKind::Link; }) == nullptr);

    auto NarrowRecord = LinkRecord;
    NarrowRecord.Set_ClearanceUu(10.0f);
    auto NarrowField = ck::groundnav::FCk_GroundNav_FieldPtr{};
    if (NOT TestTrue(TEXT("the narrow linked barrier bakes"), BakeLinkedBarrier(NarrowRecord, NarrowField))) { return false; }
    auto WideQuery = Query;
    WideQuery._Agent._RadiusUu = 20.0f;
    auto Wide = FCk_GroundNav_PathSearch{};
    Wide.Request_Begin(NarrowField, WideQuery);
    if (NOT TestEqual(TEXT("a body wider than the authored link takes the detour"), RunToTerminal(Wide, 0), ECk_GroundNav_PathStatus::Ready)) { return false; }
    TestTrue(TEXT("link clearance is enforced before minting the strict traversal row"),
        Wide.Get_Result()._CellRoute.FindByPredicate([](const auto& Edge)
        { return Edge._Kind == ECk_GroundNav_CellRouteEdgeKind::Link; }) == nullptr);
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_CellPathSearch_RotatedObbUsesStrictCellAdmission,
    "CkTests.UnitTests.CkGroundNav.Path.CellSearch.RotatedObbUsesStrictCellAdmission",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_CellPathSearch_RotatedObbUsesStrictCellAdmission::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_cellpathsearch;
    auto Field = MakeShared<FCk_GroundNav_Field>();
    if (NOT TestTrue(TEXT("the flat scene bakes"), Bake_FlatScene(*Field))) { return false; }

    auto Obb = FCk_GroundNav_DynamicObstacleObb{};
    Obb._YawTransform = FTransform{FQuat{FVector::UpVector, FMath::DegreesToRadians(45.0f)},
        FVector{400.0, 100.0, kGroundZ}, FVector::OneVector};
    Obb._WorldHalfExtents = FVector{105.0, 35.0, 50.0};
    const auto Snapshot = Try_MakeDynamicObstacleSnapshot(
        TConstArrayView<FCk_GroundNav_DynamicObstacleDisc>{},
        TConstArrayView<FCk_GroundNav_DynamicObstacleObb>{&Obb, 1});
    if (NOT TestTrue(TEXT("the yaw-only OBB snapshot validates"), Snapshot.IsSet())) { return false; }
    auto Search = FCk_GroundNav_PathSearch{};
    Search.Request_Begin(Field, MakeQueryForSnapshot(kStart, kGoal, Snapshot.GetValue()));
    if (NOT TestEqual(TEXT("the rotated footprint produces a strict route"), RunToTerminal(Search, 1), ECk_GroundNav_PathStatus::Ready)) { return false; }
    TestTrue(TEXT("the rotated footprint prevents the direct terminal chord"), Search.Get_Result()._CellRoute.Num() > 1);
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_CellPathSearch_LocalAndSeamStepsUsePublishedTopology,
    "CkTests.UnitTests.CkGroundNav.Path.CellSearch.LocalAndSeamStepsUsePublishedTopology",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_CellPathSearch_LocalAndSeamStepsUsePublishedTopology::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_cellpathsearch;
    auto Field = MakeShared<FCk_GroundNav_Field>();
    const auto Floor = TArray<FBox>{FBox{FVector{-400.0, -400.0, -10.0}, FVector{2000.0, 2000.0, kGroundZ}}};
    if (NOT TestTrue(TEXT("the two-tile flat field bakes"), Bake(Floor, Make_QueryParams(), *Field))) { return false; }

    // The non-empty snapshot selects strict mode while its finite Z span leaves the ground clear.
    const auto HighDisc = MakeDisc(FVector{800.0, 400.0, 150.0}, 100.0f, 10.0f);
    auto Search = FCk_GroundNav_PathSearch{};
    Search.Request_Begin(Field, MakeQueryForSnapshot(FVector{400.0, 400.0, kGroundZ}, FVector{1200.0, 400.0, kGroundZ},
        MakeSnapshot(TConstArrayView<FCk_GroundNav_DynamicObstacleDisc>{&HighDisc, 1})));
    if (NOT TestEqual(TEXT("the strict route crosses the composed seam"), RunToTerminal(Search, 1), ECk_GroundNav_PathStatus::Ready)) { return false; }
    TestTrue(TEXT("the strict corridor records both tiles' flat plates"), Search.Get_Result()._PlateCorridor.Num() >= 2);
    TestTrue(TEXT("the route contains many local cardinal cell steps before and after the seam"), Search.Get_Result()._CellRoute.Num() > 20);
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_CellPathSearch_LayeredPortalsAndSeamsPreservePublishedSurfaces,
    "CkTests.UnitTests.CkGroundNav.Path.CellSearch.LayeredPortalsAndSeamsPreservePublishedSurfaces",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_CellPathSearch_LayeredPortalsAndSeamsPreservePublishedSurfaces::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_cellpathsearch;
    auto Field = MakeShared<FCk_GroundNav_Field>();
    if (NOT TestTrue(TEXT("the layered ramp-and-seam fixture bakes"), BakeLayeredSeamField(*Field))) { return false; }

    // A non-intersecting snapshot selects strict cell routing without inventing an obstacle in the
    // authored topology. The lower and upper decks overlap in XY, so their route can only succeed
    // by using the ramp's published cross-layer connectivity.
    const auto HighDisc = MakeDisc(FVector{1500.0, 1500.0, 150.0}, 20.0f, 10.0f);
    auto Search = FCk_GroundNav_PathSearch{};
    Search.Request_Begin(Field, MakeQueryForSnapshot(FVector{400.0, 100.0, kGroundZ},
        FVector{1400.0, 100.0, 300.0},
        MakeSnapshot(TConstArrayView<FCk_GroundNav_DynamicObstacleDisc>{&HighDisc, 1})));
    if (NOT TestEqual(TEXT("the layered strict route resolves"), RunToTerminal(Search, 1), ECk_GroundNav_PathStatus::Ready)) { return false; }

    auto HasPublishedLocalPortal = false;
    auto HasElevatedPublishedSeam = false;
    for (const auto& Edge : Search.Get_Result()._CellRoute)
    {
        if (Edge._Kind != ECk_GroundNav_CellRouteEdgeKind::Ordinary) { continue; }
        const auto HasFullPublishedStep = Edge._FromSurface.Get_IsValid() && Edge._ToSurface.Get_IsValid() &&
                                          Get_IsPublishedStep(*Field, Edge._FromSurface, Edge._ToSurface);
        HasPublishedLocalPortal |= HasFullPublishedStep &&
                                   Edge._FromSurface._TileIndex == Edge._ToSurface._TileIndex &&
                                   Edge._FromSurface._LayerIndex != Edge._ToSurface._LayerIndex;

        auto FromZUu = 0.0f;
        auto ToZUu = 0.0f;
        HasElevatedPublishedSeam |= HasFullPublishedStep &&
                                   Edge._FromSurface._TileIndex != Edge._ToSurface._TileIndex &&
                                   Get_IsPublishedSeamPair(*Field, Edge._FromSurface, Edge._ToSurface) &&
                                   Get_ResolvedSurfaceZ(*Field, Edge._FromSurface, FromZUu) &&
                                   Get_ResolvedSurfaceZ(*Field, Edge._ToSurface, ToZUu) &&
                                   FMath::IsNearlyEqual(FromZUu, 300.0f) && FMath::IsNearlyEqual(ToZUu, 300.0f);
    }
    if (NOT HasPublishedLocalPortal || NOT HasElevatedPublishedSeam)
    {
        AddInfo(FString::Printf(TEXT("[LAYERED-SURFACE-DIAG] localPortal=%d elevatedSeam=%d routeEdges=%d"),
            HasPublishedLocalPortal, HasElevatedPublishedSeam, Search.Get_Result()._CellRoute.Num()));
    }
    TestTrue(TEXT("the route contains a published ordinary local portal between distinct layer slots"), HasPublishedLocalPortal);
    TestTrue(TEXT("the route crosses a published seam between exact elevated surface references"), HasElevatedPublishedSeam);
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_CellPathSearch_ForcedLinkVetoAndPlanMetadata,
    "CkTests.UnitTests.CkGroundNav.Path.CellSearch.ForcedLinkVetoAndPlanMetadata",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_CellPathSearch_ForcedLinkVetoAndPlanMetadata::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_cellpathsearch;
    constexpr auto LinkId = 71;
    const auto LinkStart = FVector{300.0, 400.0, kGroundZ};
    const auto LinkEnd = FVector{500.0, 400.0, kGroundZ};
    auto Record = FCk_GroundNav_LinkRecord{LinkId, LinkStart, LinkEnd};
    Record.Set_Direction(ECk_GroundNav_LinkDirection::Forward);
    Record.Set_UserTypeTag(TAG_CkTests_GroundNav_CellPathSearch_ForcedLink);

    auto Field = ck::groundnav::FCk_GroundNav_FieldPtr{};
    if (NOT TestTrue(TEXT("the forced-link barrier bakes"), BakeForcedLinkedBarrier(Record, Field))) { return false; }

    const auto Start = FVector{200.0, 400.0, kGroundZ};
    const auto Goal = FVector{600.0, 400.0, kGroundZ};
    const auto HighDisc = MakeDisc(FVector{700.0, 700.0, 150.0}, 20.0f, 10.0f);
    const auto Query = MakeQueryForSnapshot(Start, Goal,
        MakeSnapshot(TConstArrayView<FCk_GroundNav_DynamicObstacleDisc>{&HighDisc, 1}));

    auto Allowed = FCk_GroundNav_PathSearch{};
    Allowed.Request_Begin(Field, Query);
    if (NOT TestEqual(TEXT("the only legal crossing uses the forward authored link"),
        RunToTerminal(Allowed, 1), ECk_GroundNav_PathStatus::Ready)) { return false; }
    const auto* RouteLink = Allowed.Get_Result()._CellRoute.FindByPredicate([](const auto& Edge)
    { return Edge._Kind == ECk_GroundNav_CellRouteEdgeKind::Link; });
    if (NOT TestNotNull(TEXT("the forced crossing remains an authored route row"), RouteLink)) { return false; }
    TestEqual(TEXT("the route row keeps its stable id"), RouteLink->_LinkStableId, LinkId);
    TestEqual(TEXT("the route row keeps its traversal direction"), RouteLink->_LinkDirection, ECk_GroundNav_LinkDirection::Forward);

    auto Post = FCk_GroundNav_PathPostParams{};
    Post._AgentLocation = Start;
    Post._VerticalToleranceUu = kStepHeight;
    const auto Plan = Get_PathPlan(Allowed.Get_Result(), *Field, Post);
    if (NOT TestTrue(TEXT("the finished plan contains the authored traversal"), Plan._Waypoints.Num() >= 2)) { return false; }
    const auto* Entry = Plan._Waypoints.FindByPredicate([](const auto& Waypoint)
    { return Waypoint._LinkRole == ECk_GroundNav_LinkWaypointRole::Entry; });
    const auto* Exit = Plan._Waypoints.FindByPredicate([](const auto& Waypoint)
    { return Waypoint._LinkRole == ECk_GroundNav_LinkWaypointRole::Exit; });
    if (NOT TestNotNull(TEXT("the finished plan preserves the link entry"), Entry) ||
        NOT TestNotNull(TEXT("the finished plan preserves the link exit"), Exit)) { return false; }
    TestEqual(TEXT("the entry carries the stable authored id"), Entry->_LinkId, LinkId);
    TestEqual(TEXT("the exit carries the stable authored id"), Exit->_LinkId, LinkId);
    TestEqual(TEXT("the entry keeps its forward direction"), Entry->_LinkEntryDirection, ECk_GroundNav_LinkDirection::Forward);
    TestEqual(TEXT("the exit keeps its forward direction"), Exit->_LinkEntryDirection, ECk_GroundNav_LinkDirection::Forward);
    TestTrue(TEXT("the plan's distance increases across the authored span"), Exit->_DistanceFromStart > Entry->_DistanceFromStart);
    TestTrue(TEXT("the plan's cost increases across the authored span"), Exit->_CostFromStart > Entry->_CostFromStart);
    TestEqual(TEXT("the published length is the final waypoint distance"), Plan._LengthUu, Plan._Waypoints.Last()._DistanceFromStart);

    auto DeniedTag = Query;
    DeniedTag._Cost._DeniedLinkUserTypeTags.AddTag(TAG_CkTests_GroundNav_CellPathSearch_ForcedLink);
    auto TagVeto = FCk_GroundNav_PathSearch{};
    TagVeto.Request_Begin(Field, DeniedTag);
    TestEqual(TEXT("a denied user-type tag makes the forced crossing unreachable"),
        RunToTerminal(TagVeto, 1), ECk_GroundNav_PathStatus::Unreachable);

    const auto LandingDisc = MakeDisc(LinkEnd, 30.0f);
    auto BlockedLanding = FCk_GroundNav_PathSearch{};
    BlockedLanding.Request_Begin(Field, MakeQueryForSnapshot(Start, Goal,
        MakeSnapshot(TConstArrayView<FCk_GroundNav_DynamicObstacleDisc>{&LandingDisc, 1})));
    TestEqual(TEXT("a covered authored landing cannot admit a forced link"),
        RunToTerminal(BlockedLanding, 1), ECk_GroundNav_PathStatus::Unreachable);
    return true;
}
