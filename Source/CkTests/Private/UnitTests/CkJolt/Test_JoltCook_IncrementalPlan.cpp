#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "CkJoltEditor/Cook/CkJoltCook_Types.h"

// --------------------------------------------------------------------------------------------------------------------
// The pure half of the incremental map cook. Every case below is one way it can silently lose
// collision — a missing ActorLookup entry is not an error at runtime, it is "never baked".
// The world-facing half (extraction, serialization, asset writes) needs a booted world.
// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_jolt_cook_incremental_plan
{
    constexpr auto kTestFlags = EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter;

    using namespace ck::jolt::cook;

    static auto Make_Cooked(
        const TCHAR* InActorName,
        uint64 InSourceHash,
        FIntPoint InCellId,
        const TCHAR* InLevelPackage) -> FCk_Jolt_IncrementalCookedActor
    {
        auto Cooked = FCk_Jolt_IncrementalCookedActor{};
        Cooked._ActorName = FName{InActorName};
        Cooked._SourceHash = InSourceHash;
        Cooked._CellId = InCellId;
        Cooked._OwningLevelPackage = FName{InLevelPackage};
        return Cooked;
    }

    static auto Make_Present(
        const TCHAR* InActorName,
        uint64 InSourceHash,
        FIntPoint InCellId,
        bool InHasBodies) -> FCk_Jolt_IncrementalPresentActor
    {
        auto Present = FCk_Jolt_IncrementalPresentActor{};
        Present._ActorName = FName{InActorName};
        Present._SourceHash = InSourceHash;
        Present._CurrentCellId = InCellId;
        Present._HasBodies = InHasBodies;
        return Present;
    }

    static auto Make_ActorRef(int32 InCellIndex, int32 InGroupIndex) -> FCk_Jolt_CookedActorRef
    {
        return FCk_Jolt_CookedActorRef{}.Set_CellIndex(InCellIndex).Set_GroupIndex(InGroupIndex);
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_JoltCook_IncrementalPlan,
    "Ck.Jolt.Cook.IncrementalPlan",
    ck_test_jolt_cook_incremental_plan::kTestFlags)

bool FCkTest_JoltCook_IncrementalPlan::RunTest(const FString& Parameters)
{
    using namespace ck::jolt::cook;
    using namespace ck_test_jolt_cook_incremental_plan;

    const auto CellA = FIntPoint{0, 0};
    const auto CellB = FIntPoint{1, 0};
    const auto LevelMain = TEXT("/Game/Maps/Main");
    const auto LevelSub = TEXT("/Game/Maps/Main_Gameplay");

    // ---- Nothing changed -----------------------------------------------------------------------------
    {
        auto Input = FCk_Jolt_IncrementalPlanInput{};
        Input._Cooked = {Make_Cooked(TEXT("Wall"), 111, CellA, LevelMain)};
        Input._Present = {Make_Present(TEXT("Wall"), 111, CellA, true)};
        Input._LoadedLevelPackages = {FName{LevelMain}};

        const auto Plan = ComputeIncrementalPlan(Input);

        TestEqual(TEXT("unchanged: no cell is dirty"), Plan._DirtyCellIds.Num(), 0);
        TestEqual(TEXT("unchanged: counted as unchanged"), Plan._NumUnchangedActors, 1);
        TestEqual(TEXT("unchanged: nothing removed"), Plan._RemovedActorNames.Num(), 0);
    }

    // ---- Changed in place ----------------------------------------------------------------------------
    {
        auto Input = FCk_Jolt_IncrementalPlanInput{};
        Input._Cooked = {Make_Cooked(TEXT("Wall"), 111, CellA, LevelMain)};
        Input._Present = {Make_Present(TEXT("Wall"), 222, CellA, true)};
        Input._LoadedLevelPackages = {FName{LevelMain}};

        const auto Plan = ComputeIncrementalPlan(Input);

        TestEqual(TEXT("changed in place: exactly its own cell is dirty"), Plan._DirtyCellIds.Num(), 1);
        TestTrue(TEXT("changed in place: that cell is A"), Plan._DirtyCellIds.Contains(CellA));
        TestEqual(TEXT("changed in place: counted as changed"), Plan._NumChangedActors, 1);
    }

    // ---- Moved across a cell boundary ----------------------------------------------------------------
    {
        auto Input = FCk_Jolt_IncrementalPlanInput{};
        Input._Cooked = {Make_Cooked(TEXT("Wall"), 111, CellA, LevelMain)};
        Input._Present = {Make_Present(TEXT("Wall"), 222, CellB, true)};
        Input._LoadedLevelPackages = {FName{LevelMain}};

        const auto Plan = ComputeIncrementalPlan(Input);

        TestEqual(TEXT("moved: BOTH the vacated and the joined cell are dirty"), Plan._DirtyCellIds.Num(), 2);
        TestTrue(TEXT("moved: vacated cell A is dirty"), Plan._DirtyCellIds.Contains(CellA));
        TestTrue(TEXT("moved: joined cell B is dirty"), Plan._DirtyCellIds.Contains(CellB));
        TestEqual(TEXT("moved: not reported as removed"), Plan._RemovedActorNames.Num(), 0);
    }

    // ---- Added ---------------------------------------------------------------------------------------
    {
        auto Input = FCk_Jolt_IncrementalPlanInput{};
        Input._Present = {Make_Present(TEXT("NewWall"), 333, CellB, true)};
        Input._LoadedLevelPackages = {FName{LevelMain}};

        const auto Plan = ComputeIncrementalPlan(Input);

        TestEqual(TEXT("added: its cell is dirty"), Plan._DirtyCellIds.Num(), 1);
        TestTrue(TEXT("added: that cell is B"), Plan._DirtyCellIds.Contains(CellB));
        TestEqual(TEXT("added: counted as added"), Plan._NumAddedActors, 1);
    }

    // ---- Present but not bakeable --------------------------------------------------------------------
    {
        auto Input = FCk_Jolt_IncrementalPlanInput{};
        Input._Present = {Make_Present(TEXT("Pawn"), 444, CellA, false)};
        Input._LoadedLevelPackages = {FName{LevelMain}};

        const auto Plan = ComputeIncrementalPlan(Input);

        TestEqual(TEXT("filtered-out actor: dirties nothing"), Plan._DirtyCellIds.Num(), 0);
        TestEqual(TEXT("filtered-out actor: not counted as added"), Plan._NumAddedActors, 0);
    }

    // ---- Lost its collision --------------------------------------------------------------------------
    {
        auto Input = FCk_Jolt_IncrementalPlanInput{};
        Input._Cooked = {Make_Cooked(TEXT("Wall"), 111, CellA, LevelMain)};
        Input._Present = {Make_Present(TEXT("Wall"), 222, FIntPoint::ZeroValue, false)};
        Input._LoadedLevelPackages = {FName{LevelMain}};

        const auto Plan = ComputeIncrementalPlan(Input);

        TestEqual(TEXT("de-collided: only the vacated cell is dirty"), Plan._DirtyCellIds.Num(), 1);
        TestTrue(TEXT("de-collided: vacated cell A is dirty"), Plan._DirtyCellIds.Contains(CellA));
        TestTrue(TEXT("de-collided: reported as removed"),
            Plan._RemovedActorNames.Contains(FName{TEXT("Wall")}));
    }

    // ---- Deleted, level loaded -----------------------------------------------------------------------
    {
        auto Input = FCk_Jolt_IncrementalPlanInput{};
        Input._Cooked = {Make_Cooked(TEXT("Wall"), 111, CellA, LevelMain)};
        Input._LoadedLevelPackages = {FName{LevelMain}};

        const auto Plan = ComputeIncrementalPlan(Input);

        TestEqual(TEXT("deleted: its cell is dirty"), Plan._DirtyCellIds.Num(), 1);
        TestTrue(TEXT("deleted: reported as removed"), Plan._RemovedActorNames.Contains(FName{TEXT("Wall")}));
        TestEqual(TEXT("deleted: not counted as preserved"), Plan._NumPreservedUnloadedActors, 0);
    }

    // ---- Absent because its SUBLEVEL is not loaded ----------------------------------------------------
    {
        auto Input = FCk_Jolt_IncrementalPlanInput{};
        Input._Cooked = {
            Make_Cooked(TEXT("MainWall"), 111, CellA, LevelMain),
            Make_Cooked(TEXT("SubWall"), 222, CellB, LevelSub)};
        Input._Present = {Make_Present(TEXT("MainWall"), 111, CellA, true)};
        Input._LoadedLevelPackages = {FName{LevelMain}};

        const auto Plan = ComputeIncrementalPlan(Input);

        TestEqual(TEXT("unloaded sublevel: its cell is NOT dirtied"), Plan._DirtyCellIds.Num(), 0);
        TestFalse(TEXT("unloaded sublevel: its actor is NOT treated as deleted"),
            Plan._RemovedActorNames.Contains(FName{TEXT("SubWall")}));
        TestEqual(TEXT("unloaded sublevel: counted as preserved"), Plan._NumPreservedUnloadedActors, 1);
    }

    // ---- Cooked data with no recorded level (older cooks) ---------------------------------------------
    {
        auto Input = FCk_Jolt_IncrementalPlanInput{};
        Input._Cooked = {Make_Cooked(TEXT("Wall"), 111, CellA, TEXT(""))};
        Input._LoadedLevelPackages = {FName{LevelMain}};

        const auto Plan = ComputeIncrementalPlan(Input);

        TestEqual(TEXT("unattributable cooked actor: preserved rather than deleted"),
            Plan._NumPreservedUnloadedActors, 1);
        TestEqual(TEXT("unattributable cooked actor: dirties nothing"), Plan._DirtyCellIds.Num(), 0);
    }

    // ---- A changed actor and an unloaded one sharing one cell ------------------------------------------
    {
        auto Input = FCk_Jolt_IncrementalPlanInput{};
        Input._Cooked = {
            Make_Cooked(TEXT("MainWall"), 111, CellA, LevelMain),
            Make_Cooked(TEXT("SubWall"), 222, CellA, LevelSub)};
        Input._Present = {Make_Present(TEXT("MainWall"), 999, CellA, true)};
        Input._LoadedLevelPackages = {FName{LevelMain}};

        const auto Plan = ComputeIncrementalPlan(Input);

        TestTrue(TEXT("shared cell: dirtied by the changed actor"), Plan._DirtyCellIds.Contains(CellA));
        TestEqual(TEXT("shared cell: the unloaded actor is still preserved"),
            Plan._NumPreservedUnloadedActors, 1);
        TestFalse(TEXT("shared cell: the unloaded actor is not removed"),
            Plan._RemovedActorNames.Contains(FName{TEXT("SubWall")}));
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_JoltCook_IndexRemap,
    "Ck.Jolt.Cook.IndexRemap",
    ck_test_jolt_cook_incremental_plan::kTestFlags)

bool FCkTest_JoltCook_IndexRemap::RunTest(const FString& Parameters)
{
    using namespace ck::jolt::cook;
    using namespace ck_test_jolt_cook_incremental_plan;

    const auto Cell0 = FIntPoint{0, 0};
    const auto Cell1 = FIntPoint{1, 0};
    const auto Cell2 = FIntPoint{2, 0};

    // ---- Nothing dirty: the index is unchanged ---------------------------------------------------------
    {
        auto Input = FCk_Jolt_IndexRemapInput{};
        Input._ExistingCellIdsByCellIndex = {Cell0, Cell1};
        Input._ExistingActorLookup = {
            {FName{TEXT("A")}, Make_ActorRef(0, 0)},
            {FName{TEXT("B")}, Make_ActorRef(1, 0)}};

        const auto Remap = ComputeIndexRemap(Input);

        TestEqual(TEXT("clean: cell 0 keeps index 0"), Remap._NewCellIndexByOldCellIndex[0], 0);
        TestEqual(TEXT("clean: cell 1 keeps index 1"), Remap._NewCellIndexByOldCellIndex[1], 1);
        TestEqual(TEXT("clean: every actor survives"), Remap._ActorLookup.Num(), 2);
        TestEqual(TEXT("clean: B still points at cell 1"),
            Remap._ActorLookup[FName{TEXT("B")}].Get_CellIndex(), 1);
    }

    // ---- The middle cell is rewritten: kept cells compact, the rewritten one moves to the end ----------
    {
        auto Input = FCk_Jolt_IndexRemapInput{};
        Input._ExistingCellIdsByCellIndex = {Cell0, Cell1, Cell2};
        Input._DirtyCellIds = {Cell1};
        Input._WrittenCellIds = {Cell1};
        Input._ExistingActorLookup = {
            {FName{TEXT("A")}, Make_ActorRef(0, 0)},
            {FName{TEXT("B")}, Make_ActorRef(1, 0)},
            {FName{TEXT("C")}, Make_ActorRef(2, 0)}};
        Input._WrittenActorNamesByCell = {{Cell1, {FName{TEXT("B")}, FName{TEXT("D")}}}};

        const auto Remap = ComputeIndexRemap(Input);

        TestEqual(TEXT("rewrite: kept cell 0 stays at 0"), Remap._NewCellIndexByOldCellIndex[0], 0);
        TestEqual(TEXT("rewrite: dirty cell 1 has no kept index"),
            Remap._NewCellIndexByOldCellIndex[1], int32{INDEX_NONE});
        TestEqual(TEXT("rewrite: kept cell 2 compacts from 2 to 1"), Remap._NewCellIndexByOldCellIndex[2], 1);
        TestEqual(TEXT("rewrite: the rewritten cell is appended at 2"),
            Remap._NewCellIndexByWrittenCellId[Cell1], 2);

        TestEqual(TEXT("rewrite: C follows its compacted cell"),
            Remap._ActorLookup[FName{TEXT("C")}].Get_CellIndex(), 1);
        TestEqual(TEXT("rewrite: B is re-registered against the rewritten cell"),
            Remap._ActorLookup[FName{TEXT("B")}].Get_CellIndex(), 2);
        TestEqual(TEXT("rewrite: B takes its NEW group index"),
            Remap._ActorLookup[FName{TEXT("B")}].Get_GroupIndex(), 0);
        TestEqual(TEXT("rewrite: the newly-added D lands at group 1"),
            Remap._ActorLookup[FName{TEXT("D")}].Get_GroupIndex(), 1);
        TestEqual(TEXT("rewrite: A/B/C/D all present"), Remap._ActorLookup.Num(), 4);

        // The cooker SIZES its cell array from this and places refs at the indices above; a count
        // that disagreed would either truncate the array or leave a hole an actor points into.
        TestEqual(TEXT("rewrite: the new cell array is sized for kept + written"),
            Remap._NumNewCells, 3);
    }

    // ---- A dirty cell that produced no asset is dropped, and so are its actors -------------------------
    {
        auto Input = FCk_Jolt_IndexRemapInput{};
        Input._ExistingCellIdsByCellIndex = {Cell0, Cell1};
        Input._DirtyCellIds = {Cell1};
        Input._ExistingActorLookup = {
            {FName{TEXT("A")}, Make_ActorRef(0, 0)},
            {FName{TEXT("Deleted")}, Make_ActorRef(1, 0)}};

        const auto Remap = ComputeIndexRemap(Input);

        TestEqual(TEXT("emptied cell: only the kept cell survives"), Remap._NewCellIndexByOldCellIndex[0], 0);
        TestEqual(TEXT("emptied cell: it has no new index"),
            Remap._NewCellIndexByOldCellIndex[1], int32{INDEX_NONE});
        TestEqual(TEXT("emptied cell: its actor is dropped from the lookup"), Remap._ActorLookup.Num(), 1);
        TestFalse(TEXT("emptied cell: the deleted actor is gone"),
            Remap._ActorLookup.Contains(FName{TEXT("Deleted")}));
        TestEqual(TEXT("emptied cell: the new cell array shrinks to 1"), Remap._NumNewCells, 1);
    }

    // ---- Every actor lands on a slot the cell array actually has -------------------------------------
    {
        auto Input = FCk_Jolt_IndexRemapInput{};
        Input._ExistingCellIdsByCellIndex = {Cell0, Cell1, Cell2};
        Input._DirtyCellIds = {Cell0, Cell2};
        Input._WrittenCellIds = {Cell2, Cell0};
        Input._ExistingActorLookup = {
            {FName{TEXT("A")}, Make_ActorRef(0, 0)},
            {FName{TEXT("B")}, Make_ActorRef(1, 0)},
            {FName{TEXT("C")}, Make_ActorRef(2, 0)}};
        Input._WrittenActorNamesByCell = {
            {Cell0, {FName{TEXT("A")}}},
            {Cell2, {FName{TEXT("C")}}}};

        const auto Remap = ComputeIndexRemap(Input);

        TestEqual(TEXT("slot coverage: three cells survive"), Remap._NumNewCells, 3);

        auto ClaimedSlots = TSet<int32>{};
        for (const auto& NewCellIndex : Remap._NewCellIndexByOldCellIndex)
        {
            if (NewCellIndex != INDEX_NONE)
            { ClaimedSlots.Add(NewCellIndex); }
        }
        for (const auto& [WrittenCellId, NewCellIndex] : Remap._NewCellIndexByWrittenCellId)
        { ClaimedSlots.Add(NewCellIndex); }

        TestEqual(TEXT("slot coverage: every slot below _NumNewCells is claimed exactly once"),
            ClaimedSlots.Num(), Remap._NumNewCells);

        for (const auto& [ActorName, ActorRef] : Remap._ActorLookup)
        {
            TestTrue(FString::Printf(TEXT("slot coverage: %s points inside the cell array"), *ActorName.ToString()),
                ActorRef.Get_CellIndex() >= 0 && ActorRef.Get_CellIndex() < Remap._NumNewCells);
        }
    }

    // ---- An actor moving between two rewritten cells ends up in exactly one ---------------------------
    {
        auto Input = FCk_Jolt_IndexRemapInput{};
        Input._ExistingCellIdsByCellIndex = {Cell0, Cell1};
        Input._DirtyCellIds = {Cell0, Cell1};
        Input._WrittenCellIds = {Cell0, Cell1};
        Input._ExistingActorLookup = {{FName{TEXT("Mover")}, Make_ActorRef(0, 0)}};
        Input._WrittenActorNamesByCell = {
            {Cell0, {}},
            {Cell1, {FName{TEXT("Mover")}}}};

        const auto Remap = ComputeIndexRemap(Input);

        TestEqual(TEXT("cross-cell move: the mover is registered once"), Remap._ActorLookup.Num(), 1);
        TestEqual(TEXT("cross-cell move: against the cell it joined"),
            Remap._ActorLookup[FName{TEXT("Mover")}].Get_CellIndex(),
            Remap._NewCellIndexByWrittenCellId[Cell1]);
    }

    // ---- A lookup entry pointing outside the cell array is dropped, not trusted ------------------------
    {
        auto Input = FCk_Jolt_IndexRemapInput{};
        Input._ExistingCellIdsByCellIndex = {Cell0};
        Input._ExistingActorLookup = {{FName{TEXT("Corrupt")}, Make_ActorRef(7, 0)}};

        const auto Remap = ComputeIndexRemap(Input);

        TestEqual(TEXT("out-of-range cell index: entry dropped"), Remap._ActorLookup.Num(), 0);
    }

    return true;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
