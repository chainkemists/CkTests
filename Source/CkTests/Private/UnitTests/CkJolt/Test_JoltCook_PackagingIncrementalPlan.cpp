#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "CkJoltEditor/Cook/CkJoltCook_Types.h"

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_jolt_packaging_incremental_plan
{
    using namespace ck::jolt::cook;

    static auto Make_Cooked(const TCHAR* InName, const TCHAR* InLevel, uint64 InHash, FIntPoint InCell)
        -> FCk_Jolt_IncrementalCookedActor
    {
        auto Actor = FCk_Jolt_IncrementalCookedActor{};
        Actor._ActorName = FName{InName};
        Actor._OwningLevelPackage = FName{InLevel};
        Actor._SourceHash = InHash;
        Actor._CellId = InCell;
        return Actor;
    }

    static auto Make_Present(const FCk_Jolt_IncrementalCookedActor& InCooked)
        -> FCk_Jolt_IncrementalPresentActor
    {
        auto Actor = FCk_Jolt_IncrementalPresentActor{};
        Actor._ActorName = InCooked._ActorName;
        Actor._OwningLevelPackage = InCooked._OwningLevelPackage;
        Actor._SourceHash = InCooked._SourceHash;
        Actor._CurrentCellId = InCooked._CellId;
        Actor._HasBodies = true;
        return Actor;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_JoltCook_PackagingIncrementalPlan,
    "Ck.Jolt.Cook.PackagingIncrementalPlan",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkTest_JoltCook_PackagingIncrementalPlan::RunTest(const FString& Parameters)
{
    using namespace ck::jolt::cook;
    using namespace ck_test_jolt_packaging_incremental_plan;

    const auto CellA = FIntPoint{0, 0};
    const auto CellB = FIntPoint{1, 0};
    const auto MainActor = Make_Cooked(TEXT("MainWall"), TEXT("/Game/Maps/Main"), 11, CellA);
    const auto ExcludedActor = Make_Cooked(TEXT("GymWall"), TEXT("/Game/Maps/GYMs/Metrics"), 22, CellA);
    const auto UnloadedActor = Make_Cooked(TEXT("SubWall"), TEXT("/Game/Maps/Sublevel"), 33, CellA);
    const auto ExcludedKey = FCk_Jolt_CookedActorKey{ExcludedActor._OwningLevelPackage, ExcludedActor._ActorName};
    const auto UnloadedKey = FCk_Jolt_CookedActorKey{UnloadedActor._OwningLevelPackage, UnloadedActor._ActorName};

    // Freshness checks plan no writes for unchanged data, including an unloaded eligible sublevel.
    auto Input = FCk_Jolt_IncrementalPlanInput{};
    Input._Cooked = {MainActor, UnloadedActor};
    Input._Present = {Make_Present(MainActor)};
    Input._LoadedLevelPackages = {MainActor._OwningLevelPackage};
    Input._ExcludedLevelPackagePaths = {TEXT("Maps/GYMs/")};
    const auto Unchanged = ComputeIncrementalPlan(Input);
    TestTrue(TEXT("unchanged map schedules no dirty-cell writes"), Unchanged._DirtyCellIds.IsEmpty());
    TestEqual(TEXT("unchanged present actor counted"), Unchanged._NumUnchangedActors, 1);
    TestEqual(TEXT("eligible unloaded actor remains preserved"), Unchanged._NumPreservedUnloadedActors, 1);

    // An exclusion must remove old baked data even when that level is absent from the live world.
    Input._Cooked.Add(ExcludedActor);
    const auto Pruned = ComputeIncrementalPlan(Input);
    TestTrue(TEXT("excluded unloaded actor is removed"), Pruned._RemovedActorKeys.Contains(ExcludedKey));
    TestTrue(TEXT("excluded actor dirties its old cell"), Pruned._DirtyCellIds.Contains(CellA));
    TestFalse(TEXT("unloaded actor sharing the dirty cell is retained"), Pruned._RemovedActorKeys.Contains(UnloadedKey));
    TestEqual(TEXT("only the eligible unloaded actor is preserved"), Pruned._NumPreservedUnloadedActors, 1);

    // Loading the excluded child cannot turn its baked data into an unchanged, reusable actor.
    Input._Present.Add(Make_Present(ExcludedActor));
    const auto LoadedExcluded = ComputeIncrementalPlan(Input);
    TestTrue(TEXT("excluded present actor is still removed"), LoadedExcluded._RemovedActorKeys.Contains(ExcludedKey));
    TestEqual(TEXT("excluded present actor is not counted current"), LoadedExcluded._NumUnchangedActors, 1);
    TestEqual(TEXT("excluded present actor is not added"), LoadedExcluded._NumAddedActors, 0);

    // After rewriting that cell without the excluded actor, the next run becomes a no-op.
    Input._Cooked = {MainActor, UnloadedActor};
    const auto SecondRun = ComputeIncrementalPlan(Input);
    TestTrue(TEXT("second run after pruning schedules no writes"), SecondRun._DirtyCellIds.IsEmpty());
    TestTrue(TEXT("second run has no further removal"), SecondRun._RemovedActorKeys.IsEmpty());

    // Moving an eligible actor must dirty both sides even with exclusions enabled.
    Input._Present[0]._SourceHash = 44;
    Input._Present[0]._CurrentCellId = CellB;
    const auto Moved = ComputeIncrementalPlan(Input);
    TestEqual(TEXT("moved eligible actor dirties two cells"), Moved._DirtyCellIds.Num(), 2);
    TestTrue(TEXT("vacated cell dirtied"), Moved._DirtyCellIds.Contains(CellA));
    TestTrue(TEXT("destination cell dirtied"), Moved._DirtyCellIds.Contains(CellB));

    // Existing editor callers supply no scope and retain their prior unloaded-level behavior.
    Input._ExcludedLevelPackagePaths.Reset();
    Input._Cooked = {ExcludedActor};
    Input._Present.Reset();
    Input._LoadedLevelPackages.Reset();
    const auto DefaultScope = ComputeIncrementalPlan(Input);
    TestTrue(TEXT("default scope preserves unloaded cooked data"), DefaultScope._DirtyCellIds.IsEmpty());
    TestEqual(TEXT("default scope preserved actor count"), DefaultScope._NumPreservedUnloadedActors, 1);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
