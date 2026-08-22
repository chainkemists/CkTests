// The fence around the hydration quarantine, held at source level because the alternative cannot be held at all.
//
// A load holds every restored entity out of every non-kernel processor's view until its payloads have applied, and
// that guarantee is worth exactly as much as the number of ways around it. There are three, and each gets its own
// clause below:
//
//   (i)   a processor that builds its OWN view instead of going through TProcessorBase::MakeProcessorView. The
//         helper is the single place the exclusion is appended, so a hand-rolled view simply does not carry it.
//   (ii)  a processor that never builds a view at all and reaches an entity BY ID — the exclusion is a view
//         filter, not a memory barrier, so id resolution walks straight past it. The two physics contact routers
//         are the known cases and are in scope here alongside the processors.
//   (iii) a persistence handler that waits on the feature's own Setup marker. That one is not a bypass but its
//         mirror image: the handler waits for a processor the load is holding the entity away from, so the wait
//         cannot end and the payload is dropped at the apply timeout instead. Setup runs AFTER hydration by
//         design; a handler that inverts that is a contract violation.
//         Its scope is every file that CALLS FCk_PersistenceHandlerRegistry::Register (plus the Persistence
//         headers that hold the templated bodies), never a filename pattern: registration is an ordinary
//         function call and six registrars today live outside the _Fragment.cpp the house rule names, so a
//         name-derived scope left this clause holding the only blind spot.
//
//         This clause used to say it had NO allow-list. It now says something narrower and true: NAMED
//         EXEMPTIONS WITH REASONS, MONOTONIC. Widening the scope to the registration call brought in a file
//         where the marker read is on the live-REPLICATION path, deciding what to do because Setup has not run,
//         while the hydration path in the same handler correctly does not read it at all. The predicate is a
//         line scanner and cannot tell those two apart; a parser could, at the cost of the reviewability this
//         whole fence trades on. So the exemption is written down next to its reason and ratcheted like (i) and
//         (ii). Zero is still the target: an exemption says the SCANNER cannot see the difference, never that
//         the defect would be tolerable.
//
// A ratchet is only as good as its predicate, and clause (i)'s was over-broad: it counted every Get_RegistryView(),
// including the spelling that reaches a registry CONTEXT rather than an entity view. Thirteen such lines were on the
// list. Narrowing the predicate (not raising the ceiling) took clause (i) from 46/44 to 33/33 and dropped five files
// that never held an entity view at all. The rule that produced that choice is worth keeping: when a fence reds on
// code that is provably not the hazard, the fence is what is wrong, and re-baselining it hides the next real one.
//
// All three are ratchets, not prohibitions: the counts below are what the code has today, they may only ever go
// down, and a new site in a listed file reds just as loudly as a new file. (iii)'s ceiling is 1 and the other two
// are what they were; a regeneration artifact is written next to the posture ratchet's so lowering a ceiling is a
// copy rather than a hand count.
// Surface in Session Frontend: Ck.Snapshot.Meta.NoProcessorBypassesQuarantine

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "HAL/FileManager.h"
#include "Interfaces/IPluginManager.h"
#include "Misc/FileHelper.h"
#include "Misc/Paths.h"

namespace ck_test_quarantine_fence
{
    // ----------------------------------------------------------------------------------------------------------------
    // (i) View construction outside MakeProcessorView, over *_Processor.{cpp,h,inl.h}. Counted per LINE, because a
    // line is what a reviewer diffs. The allow-list is the state of the code the fence was commissioned against.

    auto Get_ViewConstructionAllowList() -> const TMap<FString, int32>&
    {
        static const TMap<FString, int32> AllowList =
        {
            {TEXT("CkAudio/Public/CkAudio/AudioTrack/CkAudioTrack_Processor.cpp"), 1},
            {TEXT("CkCompass/Public/CkCompass/CkCompass_Processor.cpp"), 1},
            {TEXT("CkCrowd/Public/CkCrowd/Agent/CkCrowdAgent_PathRefresh_Processor.cpp"), 4},
            {TEXT("CkEcs/Public/CkEcs/EntityLifetime/CkEntityLifetime_Processor.cpp"), 1},
            // KERNEL entry, permanent. The hydration apply processor is the one this whole fence exists to
            // protect, and it is exempt by construction; the line reaches a registry CONTEXT (the apply-outcome
            // accumulator) and constructs no view over entities, so it cannot observe a quarantined one. Spelled
            // Get_RegistryView because that is what its two sibling context reads in CkEntityLifetime_Utils.cpp
            // spell — renaming it to dodge a text scan would leave the fence silent on the construct it lists.
            // It survives the TryGetContext narrowing below only because it is written in TWO steps (bind the
            // registry to a local, then read the context off it), which no line predicate can follow.
            {TEXT("CkEcs/Public/CkEcs/Persistence/CkPersistenceHydration_Processor.cpp"), 1},
            {TEXT("CkEcsExt/Public/CkEcsExt/Transform/CkTransform_Processor.cpp"), 2},
            // Two-step context read, same shape as the KERNEL entry above: the registry is bound to a local and
            // then asked only for DIRTY-MARKER VERSIONS (Get_DirtyMarkerVersion) so the query can skip a pass
            // whose inputs have not moved. It enumerates no entities and holds no view, so a quarantined entity
            // is not reachable from it. dev's, arrived with the tag-version debounce.
            {TEXT("CkEntityTag/Public/CkEntityTag/Query/CkEntityTagQuery_Processor.cpp"), 1},
            {TEXT("CkGraphics/Public/CkGraphics/RenderStatus/CkRenderStatus_Processor.cpp"), 4},
            {TEXT("CkInput/Public/CkInput/CkInputLayer_Processor.cpp"), 2},
            {TEXT("CkIntent/Public/CkIntent/CkIntentMatcher_Processor.cpp"), 1},
            // Two-step again, and the one entry here whose loop DOES reach entities — by id, out of the Jolt
            // activation-event drain. The registry local is used only for a LIVENESS test (RegView.IsValid) on a
            // queued id that a load may have killed. The write that follows is clause (ii)'s territory, and it is
            // handled there correctly: the loop tests ck::FTag_Hydration_Quarantine and skips, with a comment
            // naming the exact hazard. Listed rather than excluded because a liveness read is indistinguishable
            // from a view construction to any line scanner.
            {TEXT("CkJolt/Public/CkJolt/Body/CkJoltBody_Processor.cpp"), 1},
            {TEXT("CkLagCompensation/Public/CkLagCompensation/LagCompProjectile/CkLagCompProjectile_Processor.cpp"), 1},
            {TEXT("CkMinimap/Public/CkMinimap/CkMinimap_Processor.cpp"), 1},
            {TEXT("CkOverlapBody/Public/CkOverlapBody/Marker/CkMarker_Processor.cpp"), 1},
            {TEXT("CkOverlapBody/Public/CkOverlapBody/Sensor/CkSensor_Processor.cpp"), 1},
            {TEXT("CkPhysics/Public/CkPhysics/Acceleration/CkAcceleration_Processor.cpp"), 2},
            {TEXT("CkPhysics/Public/CkPhysics/Velocity/CkVelocity_Processor.cpp"), 2},
            {TEXT("CkRelationship/Public/CkRelationship/Team/CkTeam_Processor.cpp"), 4},
            {TEXT("CkSpatialQuery/Public/CkSpatialQuery/Probe/CkProbe_Processor.cpp"), 1},
            {TEXT("CkVoxelNav/Public/CkVoxelNav/Occluder/CkVoxelNavOccluder_Processor.cpp"), 1},
        };
        return AllowList;
    }

    // Sum of the allow-list. The monotonic-decreasing rule governs the NON-KERNEL remainder: a feature processor
    // that starts building its own views must drive this number down, never up. Kernel entries are permanent, so
    // adding one moves the ceiling with it — 43 -> 44 for the hydration apply processor's context read.
    //
    // 44 -> 33 when the predicate stopped counting single-line `Get_RegistryView().TryGetContext<` (see
    // Get_IsViewConstructionLine). That removed THIRTEEN lines, five whole files' worth, none of which could ever
    // have been a bypass. Sharpening the detector rather than raising the bar was the deliberate choice: a ceiling
    // padded with things that are not the hazard is a ceiling that hides the next thing that is.
    constexpr auto ViewConstructionCeiling = 33;

    // ----------------------------------------------------------------------------------------------------------------
    // (ii) Single-entity id resolution, over the same files PLUS the two contact routers — which are subsystem
    // files, not processors, and are exactly where the known by-id writes live.

    auto Get_IdResolutionAllowList() -> const TMap<FString, int32>&
    {
        static const TMap<FString, int32> AllowList =
        {
            {TEXT("CkCompass/Public/CkCompass/CkCompass_Processor.cpp"), 2},
            {TEXT("CkJolt/Public/CkJolt/Body/CkJoltBody_ContactRouter.cpp"), 1},
            {TEXT("CkJolt/Public/CkJolt/Body/CkJoltBody_Processor.cpp"), 2},
            {TEXT("CkMinimap/Public/CkMinimap/CkMinimap_Processor.cpp"), 2},
            {TEXT("CkSpatialQuery/Public/CkSpatialQuery/Subsystem/CkSpatialQuery_Subsystem.cpp"), 1},
            {TEXT("CkVoxelNav/Public/CkVoxelNav/Occluder/CkVoxelNavOccluder_Processor.cpp"), 1},
        };
        return AllowList;
    }

    constexpr auto IdResolutionCeiling = 9;

    // The two files that are in (ii)'s scope without being processors.
    auto Get_RouterFiles() -> const TArray<FString>&
    {
        static const TArray<FString> Files =
        {
            TEXT("CkJolt/Public/CkJolt/Body/CkJoltBody_ContactRouter.cpp"),
            TEXT("CkSpatialQuery/Public/CkSpatialQuery/Subsystem/CkSpatialQuery_Subsystem.cpp"),
        };
        return Files;
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

    auto Get_IsProcessorFile(const FString& InPath) -> bool
    {
        return InPath.EndsWith(TEXT("_Processor.cpp"))
            || InPath.EndsWith(TEXT("_Processor.h"))
            || InPath.EndsWith(TEXT("_Processor.inl.h"));
    }

    // Lines carrying a view/storage construction that did not come from the helper. Deliberately literal: the
    // point is a reviewable diff, not a parser.
    //
    // ONE narrowing, and it is about what the hazard actually is. Get_RegistryView() is the door to the entity
    // database, and it opens onto two different rooms: an ENTITY view (the thing the quarantine filters, and the
    // thing this fence exists to find) and a registry CONTEXT — one shared object hanging off the registry, with
    // no entities in it at all. `Get_RegistryView().TryGetContext<T>()` is unambiguously the second: it reaches a
    // context and cannot enumerate, hold, or observe a single entity, quarantined or otherwise. The KERNEL entry
    // in the allow-list above already says exactly this about its own line; it was simply never true of only that
    // line. Thirteen such lines across five Jolt files plus CkProbe were being counted as potential bypasses, so
    // the ceiling was carrying eleven-and-change of pure noise, and the next REAL bypass would have had to clear
    // that noise before anyone looked at it.
    //
    // Only the single-line spelling is narrowed. A two-step read (bind the registry to a local, then ask it for a
    // context) still counts, because no line predicate can follow the local — those stay on the allow-list with
    // their reason written next to them, which is the honest place for "the scanner cannot see the difference".
    auto Get_IsViewConstructionLine(const FString& InLine) -> bool
    {
        if (InLine.Contains(TEXT("Get_RegistryView().TryGetContext<")))
        { return false; }

        return InLine.Contains(TEXT(".View<"))
            || InLine.Contains(TEXT("template View<"))
            || InLine.Contains(TEXT("Get_RegistryView()"))
            || InLine.Contains(TEXT(".Storage<"))
            || InLine.Contains(TEXT("template Storage<"));
    }

    auto Get_IsIdResolutionLine(const FString& InLine) -> bool
    {
        return InLine.Contains(TEXT("Get_ValidHandle("));
    }

    // Where a persistence handler LIVES. The house rule says the feature's _Fragment.cpp and most obey it, but
    // registration is a plain function call and nothing enforces the filename — today SIX registrars sit in a
    // _Replication.cpp, a _Module.cpp or a subsystem .cpp. A scope derived from the FILENAME therefore has a
    // blind spot, in the one clause whose whole value is that it has no allow-list to absorb one. The scope is
    // the REGISTRATION CALL instead: whatever file makes it is a handler file, wherever it is named.
    const auto HandlerRegistrarCall = FString{TEXT("FCk_PersistenceHandlerRegistry::Register")};

    // ----------------------------------------------------------------------------------------------------------------
    // (iii) exemptions. The predicate is a LINE scanner with no notion of which lambda a line sits in, so it
    // cannot distinguish a handler blocking on Setup (the defect) from a live-replication path deciding what to
    // do BECAUSE Setup has not run (correct, and a different code path entirely). One file is in that position
    // today. It is named here with its reason rather than dodged by narrowing the predicate — a parser would buy
    // precision at the cost of the property this fence trades on, that a reviewer can diff it.
    //
    //   CkRenderTarget_Replication.cpp:21 — `RenderTarget_ShouldStash` reads FTag_RenderTarget_NeedsSetup, and
    //   it is reached ONLY from the handler's .NetApply lambda: a replicated repaint arriving before the target
    //   exists is stashed rather than dropped. The .HydrationApply lambda deliberately does NOT read the marker
    //   — it parks into FFragment_RenderTarget_HydrationReplay and lets FProcessor_RenderTarget_HydrationReplay
    //   do the repaint afterwards, which is exactly the shape this clause's own failure text recommends.
    auto Get_SetupWaitExemptionAllowList() -> const TMap<FString, int32>&
    {
        static const TMap<FString, int32> AllowList =
        {
            {TEXT("CkRenderTarget/Public/CkRenderTarget/Net/CkRenderTarget_Replication.cpp"), 1},
        };
        return AllowList;
    }

    // Sum of the exemptions, and a ratchet like (i) and (ii): it may only ever fall. Zero remains the target —
    // an exemption is a statement that the SCANNER cannot see the difference, never that the defect is tolerable.
    constexpr auto SetupWaitCeiling = 1;

    // A Setup marker read. Both spellings the codebase uses, and both Has shapes.
    auto Get_IsSetupMarkerReadLine(const FString& InLine) -> bool
    {
        const auto NamesAMarker = InLine.Contains(TEXT("NeedsSetup")) || InLine.Contains(TEXT("RequiresSetup"));
        if (NOT NamesAMarker)
        { return false; }

        return InLine.Contains(TEXT("Has<")) || InLine.Contains(TEXT("Has_Any<")) || InLine.Contains(TEXT("Has_All<"));
    }

    auto Scan(
        const FString& InSourceRoot,
        const TArray<FString>& InAbsoluteFiles,
        TFunctionRef<bool(const FString&)> InLinePredicate) -> TArray<FScanHit>
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
                if (NOT InLinePredicate(Lines[Index]))
                { continue; }

                Hits.Emplace(FScanHit{Relative, Index + 1, Lines[Index].TrimStartAndEnd()});
            }
        }

        return Hits;
    }

    // Which files contain a string at all, returned under the absolute path they came in as so the result can
    // be unioned with another file list without two spellings of one path. Whole-file rather than per-line
    // (unlike Scan) because the question is about the FILE and this one runs over every translation unit in the
    // plugin — splitting 60 MB into per-line FStrings to answer a yes/no is the difference between a meta test
    // that costs a second and one that costs a coffee break.
    auto Collect_FilesContaining(
        const TArray<FString>& InAbsoluteFiles,
        const FString& InNeedle) -> TArray<FString>
    {
        auto Matching = TArray<FString>{};

        for (const auto& AbsolutePath : InAbsoluteFiles)
        {
            auto Contents = FString{};
            if (NOT FFileHelper::LoadFileToString(Contents, *AbsolutePath))
            { continue; }

            if (Contents.Contains(InNeedle))
            { Matching.Emplace(AbsolutePath); }
        }

        return Matching;
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
        return FPaths::ProjectSavedDir() / TEXT("CkSnapshot") / TEXT("QuarantineFence.csv");
    }

    auto Write_Artifact(
        const TArray<FScanHit>& InViewHits,
        const TArray<FScanHit>& InIdHits) -> void
    {
        auto Csv = FString{TEXT("Class,RelativePath,Line,Text\n")};

        const auto AppendAll = [&Csv](const TCHAR* InClass, const TArray<FScanHit>& InHits) -> void
        {
            for (const auto& Hit : InHits)
            {
                Csv += FString::Printf(TEXT("%s,%s,%d,\"%s\"\n"),
                    InClass, *Hit.RelativePath, Hit.Line, *Hit.Text.Replace(TEXT("\""), TEXT("'")));
            }
        };

        AppendAll(TEXT("ViewConstruction"), InViewHits);
        AppendAll(TEXT("IdResolution"), InIdHits);

        FFileHelper::SaveStringToFile(Csv, *Get_ArtifactPath());
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_NoProcessorBypassesQuarantine_MetaTest,
    "Ck.Snapshot.Meta.NoProcessorBypassesQuarantine",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::ProductFilter)

bool FCk_Snapshot_NoProcessorBypassesQuarantine_MetaTest::RunTest(const FString& /*Parameters*/)
{
    using namespace ck_test_quarantine_fence;

    const auto SourceRoot = Get_SourceRoot();
    if (NOT TestTrue(TEXT("CkFoundation's Source directory resolves"),
        NOT SourceRoot.IsEmpty() && IFileManager::Get().DirectoryExists(*SourceRoot)))
    { return false; }

    auto AllFiles = TArray<FString>{};
    IFileManager::Get().FindFilesRecursive(AllFiles, *SourceRoot, TEXT("*.*"), /*Files=*/true, /*Directories=*/false);

    // The enumeration is the load-bearing half: a fence that scanned nothing would pass silently.
    if (NOT TestTrue(FString::Printf(TEXT("the scan found CkFoundation source files (found %d)"), AllFiles.Num()),
        AllFiles.Num() > 1000))
    { return false; }

    auto ProcessorFiles = TArray<FString>{};
    auto TranslationUnits = TArray<FString>{};
    auto PersistenceHeaders = TArray<FString>{};

    for (const auto& AbsolutePath : AllFiles)
    {
        if (Get_IsProcessorFile(AbsolutePath))
        { ProcessorFiles.Emplace(AbsolutePath); }

        if (AbsolutePath.EndsWith(TEXT(".cpp")) || AbsolutePath.EndsWith(TEXT(".h")))
        { TranslationUnits.Emplace(AbsolutePath); }

        if (AbsolutePath.EndsWith(TEXT(".h")) && FPaths::GetCleanFilename(AbsolutePath).Contains(TEXT("Persistence")))
        { PersistenceHeaders.Emplace(AbsolutePath); }
    }

    // Every file that registers a handler, found by the CALL rather than by its name — see
    // HandlerRegistrarCall. The templated handler BODIES live in the Persistence headers above, which carry no
    // registration call of their own, so both sets are in (iii)'s scope.
    const auto RegistrarFiles = Collect_FilesContaining(TranslationUnits, HandlerRegistrarCall);

    auto AllGood = TestTrue(
        FString::Printf(TEXT("the scan found processor files to fence (found %d)"), ProcessorFiles.Num()),
        ProcessorFiles.Num() > 100);

    AllGood &= TestTrue(
        FString::Printf(TEXT("the scan found persistence-handler registrars to fence (found %d)"),
            RegistrarFiles.Num()),
        RegistrarFiles.Num() > 20);

    // The positive control for the WIDENING, and the reason this clause no longer keys on a filename. If every
    // registrar the scan finds is a _Fragment.cpp, the scope is indistinguishable from the filename-derived one
    // it replaced — and the escapes that motivated the change (a registrar in a _Replication.cpp, a _Module.cpp,
    // a subsystem .cpp) would be back outside the fence with nothing saying so.
    const auto NonFragmentRegistrars = RegistrarFiles.FilterByPredicate(
        [](const FString& InPath) { return NOT InPath.EndsWith(TEXT("_Fragment.cpp")); });

    AllGood &= TestTrue(
        FString::Printf(
            TEXT("(iii) the handler scope reaches registrars that are NOT named _Fragment.cpp (found %d) — a ")
            TEXT("scope that found none would be the filename-derived one this clause replaced"),
            NonFragmentRegistrars.Num()),
        NonFragmentRegistrars.Num() > 0);

    // ----------------------------------------------------------------------------------------------------------------
    // (i) view construction

    const auto ViewHits = Scan(SourceRoot, ProcessorFiles, &Get_IsViewConstructionLine);
    const auto ViewCounts = Get_CountsByFile(ViewHits);
    const auto& ViewAllowList = Get_ViewConstructionAllowList();

    AllGood &= TestTrue(
        FString::Printf(
            TEXT("(i) view construction outside MakeProcessorView is at or below its ceiling (found %d, ceiling %d) ")
            TEXT("— see %s"),
            ViewHits.Num(), ViewConstructionCeiling, *Get_ArtifactPath()),
        ViewHits.Num() <= ViewConstructionCeiling);

    for (const auto& Entry : ViewCounts)
    {
        const auto* Allowed = ViewAllowList.Find(Entry.Key);

        AllGood &= TestTrue(
            FString::Printf(
                TEXT("(i) [%s] builds %d view(s) of its own — a processor that does not go through ")
                TEXT("MakeProcessorView does not carry the hydration exclusion. Route it through the helper, or ")
                TEXT("add it to the fence's allow-list with a reason."),
                *Entry.Key, Entry.Value),
            Allowed != nullptr);

        if (Allowed == nullptr)
        { continue; }

        AllGood &= TestTrue(
            FString::Printf(TEXT("(i) [%s] gained view constructions (%d, was %d)"), *Entry.Key, Entry.Value, *Allowed),
            Entry.Value <= *Allowed);
    }

    // ----------------------------------------------------------------------------------------------------------------
    // (ii) id resolution

    auto IdScanFiles = ProcessorFiles;
    for (const auto& RouterRelative : Get_RouterFiles())
    {
        const auto Absolute = SourceRoot / RouterRelative;
        AllGood &= TestTrue(
            FString::Printf(TEXT("(ii) the router file [%s] still exists to be fenced"), *RouterRelative),
            IFileManager::Get().FileExists(*Absolute));
        IdScanFiles.AddUnique(Absolute);
    }

    const auto IdHits = Scan(SourceRoot, IdScanFiles, &Get_IsIdResolutionLine);
    const auto IdCounts = Get_CountsByFile(IdHits);
    const auto& IdAllowList = Get_IdResolutionAllowList();

    AllGood &= TestTrue(
        FString::Printf(
            TEXT("(ii) single-entity id resolution is at or below its ceiling (found %d, ceiling %d)"),
            IdHits.Num(), IdResolutionCeiling),
        IdHits.Num() <= IdResolutionCeiling);

    for (const auto& Entry : IdCounts)
    {
        const auto* Allowed = IdAllowList.Find(Entry.Key);

        AllGood &= TestTrue(
            FString::Printf(
                TEXT("(ii) [%s] resolves %d entit(ies) by id — the hydration exclusion is a view filter, so an ")
                TEXT("entity reached this way is not covered by it. Skip entities carrying ")
                TEXT("ck::FTag_Hydration_Quarantine, then add the site to the fence's allow-list."),
                *Entry.Key, Entry.Value),
            Allowed != nullptr);

        if (Allowed == nullptr)
        { continue; }

        AllGood &= TestTrue(
            FString::Printf(TEXT("(ii) [%s] gained id resolutions (%d, was %d)"), *Entry.Key, Entry.Value, *Allowed),
            Entry.Value <= *Allowed);
    }

    // ----------------------------------------------------------------------------------------------------------------
    // (iii) persistence handlers waiting on Setup — named exemptions with reasons, and a ratchet that only falls.

    auto HandlerFiles = RegistrarFiles;
    for (const auto& Header : PersistenceHeaders)
    { HandlerFiles.AddUnique(Header); }

    const auto SetupWaitHits = Scan(SourceRoot, HandlerFiles, &Get_IsSetupMarkerReadLine);
    const auto SetupWaitCounts = Get_CountsByFile(SetupWaitHits);
    const auto& SetupWaitExemptions = Get_SetupWaitExemptionAllowList();

    for (const auto& Hit : SetupWaitHits)
    {
        if (SetupWaitExemptions.Contains(Hit.RelativePath))
        { continue; }

        AllGood &= TestTrue(
            FString::Printf(
                TEXT("(iii) [%s:%d] a persistence handler reads a Setup marker: %s\n")
                TEXT("A load holds a restored entity out of every non-kernel processor's view until its payloads ")
                TEXT("have applied, so waiting for Setup here waits for something that cannot happen and the ")
                TEXT("payload is dropped at the apply timeout. Apply the Durable state unconditionally; Setup runs ")
                TEXT("afterwards and reads it as its input. If the restore needs Setup's OUTPUT, enqueue the ")
                TEXT("feature's own deferred request or park the payload in a fragment a post-Setup processor ")
                TEXT("consumes.\n")
                TEXT("A new exemption is not a local decision: this clause's ceiling only ever falls, so if the ")
                TEXT("read is genuinely on the live-replication path rather than the hydration one, get that ")
                TEXT("ruled and raise Get_SetupWaitExemptionAllowList with the reason written beside it."),
                *Hit.RelativePath, Hit.Line, *Hit.Text),
            false);
    }

    // The ratchet. Exempt hits are counted, never ignored: a second read appearing in an exempted FILE has to
    // move this number, or the exemption would quietly become a per-file amnesty.
    AllGood &= TestTrue(
        FString::Printf(
            TEXT("(iii) Setup-marker reads in handler files are at or below the ceiling (found %d, ceiling %d) — ")
            TEXT("every one of them named in Get_SetupWaitExemptionAllowList with its reason"),
            SetupWaitHits.Num(), SetupWaitCeiling),
        SetupWaitHits.Num() <= SetupWaitCeiling);

    // ...and the exemptions are still EARNED. A named file that no longer contains the pattern means the shape
    // was fixed or moved, and the entry has to go with it — an allow-list that outlives its subject is how a
    // ceiling stops being a ratchet.
    for (const auto& Entry : SetupWaitExemptions)
    {
        const auto* Found = SetupWaitCounts.Find(Entry.Key);

        AllGood &= TestTrue(
            FString::Printf(
                TEXT("(iii) the exemption for [%s] is still earned — no Setup-marker read found there, so delete ")
                TEXT("the entry and lower the ceiling"),
                *Entry.Key),
            Found != nullptr);

        if (Found == nullptr)
        { continue; }

        AllGood &= TestTrue(
            FString::Printf(TEXT("(iii) [%s] gained Setup-marker reads (%d, was %d) — the exemption names one ")
                            TEXT("known line, not the file"),
                *Entry.Key, *Found, Entry.Value),
            *Found <= Entry.Value);
    }

    Write_Artifact(ViewHits, IdHits);

    return AllGood;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------
