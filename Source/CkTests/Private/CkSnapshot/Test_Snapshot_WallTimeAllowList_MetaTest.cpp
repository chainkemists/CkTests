// T-C6-10 — reading WALL time is a claim, and the claim is on a list.
//
// A load freezes game time for its whole duration: global time dilation is held at its floor, so GetTimeSeconds
// stops, every actor tick's delta becomes ~0, and every reader UE has freezes with it. That is the mechanism, and
// it makes gameplay-paced code correct by DEFAULT — nothing to edit, nothing to opt into.
//
// The corollary is the thing this fence guards. A handful of things must keep running while the game is frozen:
// the per-payload apply watchdog, its net-dispatcher mirror, the kernel's replication-retry backoff, the loading
// screen's own timers, and profiling. Each of those reads WALL time, and each such read is a claim — "this code
// must keep running while the game is frozen". The allow-list below is the set of things that have made that
// claim. It may only shrink.
//
// Deliberately NOT fenced: Get_WorldTime and GetTimeSeconds. Under the freeze a world-time read is CORRECT, so
// fencing it would fence the whole codebase.
//
// Two halves, and both matter:
//   (i)  every wall-time read is on the list, and no file gains reads. A ratchet.
//   (ii) the four watchdogs the design MOVED to wall time still read it. Without this the fence is one-way: a
//        watchdog quietly moved back to game time would lower a count, which a ratchet reads as an improvement,
//        while in fact it re-creates the bug that made the timeout unable to expire inside the window it bounds.
//
// Comment lines and #includes are skipped: neither is a read, and a doc block that names FPlatformTime::Seconds
// while explaining why it is used must not move a number.
// Surface in Session Frontend: Ck.Snapshot.Meta.WallTimeReadsAreAllowListed

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "HAL/FileManager.h"
#include "Interfaces/IPluginManager.h"
#include "Misc/FileHelper.h"
#include "Misc/Paths.h"

namespace ck_test_walltime_fence
{
    // Every file with at least one wall-time read, and how many it has today. Grouped by why they made the claim.
    auto Get_WallTimeAllowList() -> const TMap<FString, int32>&
    {
        static const TMap<FString, int32> AllowList =
        {
            // ---- The load's own watchdogs. PERMANENT: a watchdog measured in game time cannot expire inside the
            // window it exists to bound, because that window is exactly when game time does not advance. -------
            {TEXT("CkEcs/Public/CkEcs/Persistence/CkPersistenceHydration_Processor.cpp"), 1},
            {TEXT("CkEcs/Public/CkEcs/Net/ReplicatedFragmentContainer/CkReplicatedFragmentContainer_Processor.cpp"), 1},
            {TEXT("CkEcs/Public/CkEcs/Net/EntityReplicationDriver/CkEntityReplicationDriver_Processor.cpp"), 1},
            // The kernel's replication-retry backoff. A retry watchdog that freezes with the world it is retrying
            // against is a wedge, so both its arm and its elapsed read are pinned to RealTime.
            {TEXT("CkEcs/Public/CkEcs/EntityScript/CkEntityScript_Processor.cpp"), 2},

            // ---- The loading screen. It is what the player looks at WHILE the game is frozen, so freezing it
            // would be the one thing that could turn a long load into a hang. -----------------------------------
            {TEXT("CkLoadingScreen/Public/CkLoadingScreen/LoadingProcess/CkLoadingProcess_Task.cpp"), 2},
            {TEXT("CkLoadingScreen/Public/CkLoadingScreen/Subsystem/CkLoadingScreen_Subsystem.cpp"), 3},

            // ---- Profiling and diagnostics. Measuring how long something took is a wall-clock question by
            // definition, and none of it paces gameplay. -------------------------------------------------------
            {TEXT("CkEcs/Public/CkEcs/Scheduler/CkProcessorScheduler.cpp"), 7},
            {TEXT("CkEcs/Public/CkEcs/Scheduler/CkProcessorGraph.cpp"), 2},
            {TEXT("CkJolt/Public/CkJolt/World/CkJoltWorld_Processor.cpp"), 2},
            {TEXT("CkProfile/Public/CkProfile/Stats/CkStats_Utils.cpp"), 2},
            {TEXT("CkWatermark/Public/CkWatermark/CkWatermark_Panel_Widget.cpp"), 2},
            {TEXT("CkWatermark/Public/CkWatermark/Stats/CkWatermarkStat_Time_Widget.cpp"), 1},
            {TEXT("CkNavigation/Public/CkNavigation/Nav/CkNav_Algorithm.cpp"), 2},
            {TEXT("CkStateMachine/Public/CkStateMachine/Debug/CkStateMachine_Debug_Processor.cpp"), 3},

            // ---- Deferral and trouble-report stamps: "how long has this been stuck", which is a question about
            // the process rather than about the simulation. ----------------------------------------------------
            {TEXT("CkNavigation/Public/CkNavigation/Nav/CkNav_Processor.cpp"), 3},
            {TEXT("CkCrowd/Public/CkCrowd/Agent/CkCrowdAgent_DrawNavStatus_Processor.cpp"), 1},
            {TEXT("CkCrowd/Public/CkCrowd/Agent/CkCrowdAgent_OnPathResolved_Processor.cpp"), 1},
            {TEXT("CkCrowd/Public/CkCrowd/Agent/CkCrowdAgent_OnRouteResolved_Processor.cpp"), 1},
            {TEXT("CkCrowd/Public/CkCrowd/Agent/CkCrowdAgent_OnVoxelPathResolved_Processor.cpp"), 1},
            {TEXT("CkStateMachine/Public/CkStateMachine/StateMachine/CkStateMachine_Processor.cpp"), 2},
            {TEXT("CkStateMachine/Public/CkStateMachine/StateMachine/CkStateMachine_Utils.cpp"), 2},
            {TEXT("CkStateMachine/Public/CkStateMachine/State/CkSmState_Utils.cpp"), 2},

            // ---- Frame-budgeted work slices and debounces. The budget IS a wall-clock budget: a slice that
            // measured itself in game time would run forever on a frozen frame. --------------------------------
            {TEXT("CkVoxelNav/Public/CkVoxelNav/Octree/CkVoxelNav_Octree_Build.cpp"), 6},
            {TEXT("CkVoxelNav/Public/CkVoxelNav/Octree/CkVoxelNav_Octree_Repair.cpp"), 6},
            {TEXT("CkCue/Public/CkCue/CkCueDiscovery_Subsystem.cpp"), 6},
            {TEXT("CkCue/Public/CkCue/CkCueExecutor_Subsystem.cpp"), 1},
            {TEXT("CkCue/Public/CkCue/CkCueSubsystem_Base.h"), 1},
            {TEXT("CkGameSettings/Public/CkGameSettings/Subsystem/CkGameSettings_Subsystem.cpp"), 4},

            // ---- Wall time by intent, at the API boundary: the one place a caller ASKS for the real clock. ----
            {TEXT("CkCore/Public/CkCore/Time/CkTime_Utils.cpp"), 1},
            {TEXT("CkCore/Public/CkCore/Engine/CkPlayerState.cpp"), 1},

            // ---- Editor and tooling. None of it runs inside a load, or inside a game at all. ------------------
            {TEXT("CkAngelscriptGenerator/Assets/CkAssetRegistrySubsystem.cpp"), 2},
            {TEXT("CkAngelscriptGenerator/Commandlets/CkAngelscriptGenerator_DriftCommandlet.cpp"), 2},
            {TEXT("CkAngelscriptGenerator/SelfHeal/CkAngelscriptGenerator_Dispatcher.cpp"), 2},
            {TEXT("CkAnimationEditor/Public/CkAnimationEditor/Toolbox/CkAnimationToolbox.cpp"), 1},
            {TEXT("CkAssetExporter/Public/CkAssetExporter/Server/CkAssetExporter_RequestLoop.cpp"), 2},
            {TEXT("CkVoxelNavEditor/Private/Preview/CkVoxelNavPreview_EditorSubsystem.cpp"), 2},
            {TEXT("CkParticlesEditor/Tests/Test_CkParticles_HlslProbe.cpp"), 4},
            {TEXT("CkParticlesEditor/Tests/Test_CkParticles_PrewarmTemplates.cpp"), 4},
        };
        return AllowList;
    }

    // Sum of the allow-list. Monotonically non-increasing: a new wall-time read anywhere must drive this number
    // down, never up. Raising it is a deliberate act that says a new piece of code has to keep running while the
    // game is frozen.
    constexpr auto WallTimeCeiling = 89;

    // (ii) The four watchdogs the C6 design MOVED onto the wall clock, with the minimum each must keep. This is
    // the half a ratchet cannot express: silently reverting one of these LOWERS a count.
    auto Get_RequiredWallTimeWatchdogs() -> const TMap<FString, int32>&
    {
        static const TMap<FString, int32> Required =
        {
            {TEXT("CkEcs/Public/CkEcs/Persistence/CkPersistenceHydration_Processor.cpp"), 1},
            {TEXT("CkEcs/Public/CkEcs/Net/ReplicatedFragmentContainer/CkReplicatedFragmentContainer_Processor.cpp"), 1},
            {TEXT("CkEcs/Public/CkEcs/Net/EntityReplicationDriver/CkEntityReplicationDriver_Processor.cpp"), 1},
            {TEXT("CkEcs/Public/CkEcs/EntityScript/CkEntityScript_Processor.cpp"), 2},
        };
        return Required;
    }

    // ----------------------------------------------------------------------------------------------------------------

    struct FScanHit
    {
        FString RelativePath;
        int32   Line = 0;
        FString Text;
    };

    auto Get_SourceRoot() -> FString
    {
        const auto Plugin = IPluginManager::Get().FindPlugin(TEXT("CkFoundation"));
        if (NOT Plugin.IsValid())
        { return {}; }

        return FPaths::ConvertRelativePathToFull(Plugin->GetBaseDir() / TEXT("Source"));
    }

    auto Get_RelativePath(const FString& InSourceRoot, const FString& InAbsolutePath) -> FString
    {
        auto Relative = FPaths::ConvertRelativePathToFull(InAbsolutePath);
        FPaths::MakePathRelativeTo(Relative, *(InSourceRoot / TEXT("")));
        return Relative.Replace(TEXT("\\"), TEXT("/"));
    }

    // Deliberately literal: the point is a reviewable diff, not a parser. Get_WorldTime and GetTimeSeconds are
    // absent from the set by design — under the freeze they are the CORRECT thing to read.
    auto Get_IsWallTimeReadLine(const FString& InLine) -> bool
    {
        const auto Trimmed = InLine.TrimStart();

        // Neither a comment nor an include is a READ. Excluding them keeps a doc block that explains WHY a
        // watchdog is wall-clocked — and the include that watchdog needs — from standing in for the read itself,
        // which would let the required-watchdog half below pass on a file whose actual read was reverted.
        if (Trimmed.StartsWith(TEXT("//")) || Trimmed.StartsWith(TEXT("#include")))
        { return false; }

        if (InLine.Contains(TEXT("FPlatformTime::Seconds"))
            || InLine.Contains(TEXT("FDateTime::Now"))
            || InLine.Contains(TEXT("GetRealTimeSeconds"))
            || InLine.Contains(TEXT("FApp::GetDeltaTime"))
            || InLine.Contains(TEXT("FApp::GetCurrentTime")))
        { return true; }

        // The world-time API's own opt-in to the real clock, which is how a caller asks for wall time without
        // touching FPlatformTime at all.
        return InLine.Contains(TEXT("Set_TimeType(")) && InLine.Contains(TEXT("RealTime"));
    }

    auto Scan(
        const FString& InSourceRoot,
        const TArray<FString>& InAbsoluteFiles) -> TArray<FScanHit>
    {
        auto Hits = TArray<FScanHit>{};

        for (const auto& AbsolutePath : InAbsoluteFiles)
        {
            auto Lines = TArray<FString>{};
            if (NOT FFileHelper::LoadFileToStringArray(Lines, *AbsolutePath))
            { continue; }

            const auto Relative = Get_RelativePath(InSourceRoot, AbsolutePath);

            for (auto Index = 0; Index < Lines.Num(); ++Index)
            {
                if (NOT Get_IsWallTimeReadLine(Lines[Index]))
                { continue; }

                Hits.Emplace(FScanHit{Relative, Index + 1, Lines[Index].TrimStartAndEnd()});
            }
        }

        return Hits;
    }

    auto Get_CountsByFile(const TArray<FScanHit>& InHits) -> TMap<FString, int32>
    {
        auto Counts = TMap<FString, int32>{};
        for (const auto& Hit : InHits)
        { ++Counts.FindOrAdd(Hit.RelativePath); }
        return Counts;
    }

    auto Get_ArtifactPath() -> FString
    {
        return FPaths::ProjectSavedDir() / TEXT("CkSnapshot") / TEXT("WallTimeFence.csv");
    }

    auto Write_Artifact(const TArray<FScanHit>& InHits) -> void
    {
        auto Csv = FString{TEXT("RelativePath,Line,Text\n")};
        for (const auto& Hit : InHits)
        {
            Csv += FString::Printf(TEXT("%s,%d,\"%s\"\n"),
                *Hit.RelativePath, Hit.Line, *Hit.Text.Replace(TEXT("\""), TEXT("'")));
        }
        FFileHelper::SaveStringToFile(Csv, *Get_ArtifactPath());
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_WallTimeReadsAreAllowListed_MetaTest,
    "Ck.Snapshot.Meta.WallTimeReadsAreAllowListed",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::ProductFilter)

bool FCk_Snapshot_WallTimeReadsAreAllowListed_MetaTest::RunTest(const FString& /*Parameters*/)
{
    using namespace ck_test_walltime_fence;

    const auto SourceRoot = Get_SourceRoot();
    if (NOT TestTrue(TEXT("CkFoundation's Source directory resolves"),
        NOT SourceRoot.IsEmpty() && IFileManager::Get().DirectoryExists(*SourceRoot)))
    { return false; }

    auto AllFiles = TArray<FString>{};
    IFileManager::Get().FindFilesRecursive(AllFiles, *SourceRoot, TEXT("*.*"), /*Files=*/true, /*Directories=*/false);

    auto ScanFiles = TArray<FString>{};
    for (const auto& AbsolutePath : AllFiles)
    {
        if (AbsolutePath.EndsWith(TEXT(".cpp")) || AbsolutePath.EndsWith(TEXT(".h")))
        { ScanFiles.Emplace(AbsolutePath); }
    }

    // The enumeration is the load-bearing half: a fence that scanned nothing would pass silently.
    if (NOT TestTrue(
        FString::Printf(TEXT("the scan found CkFoundation translation units to fence (found %d)"), ScanFiles.Num()),
        ScanFiles.Num() > 1000))
    { return false; }

    const auto Hits = Scan(SourceRoot, ScanFiles);
    const auto Counts = Get_CountsByFile(Hits);
    const auto& AllowList = Get_WallTimeAllowList();

    Write_Artifact(Hits);

    auto AllGood = TestTrue(
        FString::Printf(
            TEXT("wall-time reads are at or below their ceiling (found %d, ceiling %d) — see %s"),
            Hits.Num(), WallTimeCeiling, *Get_ArtifactPath()),
        Hits.Num() <= WallTimeCeiling);

    for (const auto& Entry : Counts)
    {
        const auto* Allowed = AllowList.Find(Entry.Key);

        AllGood &= TestTrue(
            FString::Printf(
                TEXT("[%s] reads WALL time %d time(s). A load freezes GAME time for its whole duration, so a "
                     "wall-time read is a claim that this code must keep running while the game is frozen. If that "
                     "is true, add it to the allow-list with the reason; if it is not, read world time instead and "
                     "get the freeze for free."),
                *Entry.Key, Entry.Value),
            Allowed != nullptr);

        if (Allowed == nullptr)
        { continue; }

        AllGood &= TestTrue(
            FString::Printf(TEXT("[%s] gained wall-time reads (%d, was %d)"), *Entry.Key, Entry.Value, *Allowed),
            Entry.Value <= *Allowed);
    }

    // (ii) The positive control. A ratchet alone reads a reverted watchdog as an improvement.
    for (const auto& Entry : Get_RequiredWallTimeWatchdogs())
    {
        const auto* Found = Counts.Find(Entry.Key);
        const auto Actual = Found != nullptr ? *Found : 0;

        AllGood &= TestTrue(
            FString::Printf(
                TEXT("[%s] still measures itself on the WALL clock (found %d, needs at least %d). This is a load "
                     "watchdog: a timeout measured in game time cannot expire inside the very window it exists to "
                     "bound, because that window is exactly when game time does not advance."),
                *Entry.Key, Actual, Entry.Value),
            Actual >= Entry.Value);
    }

    return AllGood;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------
