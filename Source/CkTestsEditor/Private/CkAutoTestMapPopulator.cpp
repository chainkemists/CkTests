#include "CkAutoTestMapPopulator.h"

#include "CkAutoTestMapConfig.h"
#include "CkTestsEditor/CkTestsEditor_Log.h"

#include "CkAutoTestRunner.h"

#include "CkCore/Ensure/CkEnsure.h"
#include "CkCore/Format/CkFormat.h"

#include <AssetRegistry/AssetRegistryModule.h>
#include <Containers/Ticker.h>
#include <Editor.h>
#include <Editor/EditorEngine.h>
#include <Engine/Level.h>
#include <Engine/World.h>
#include <ExternalPackageHelper.h>
#include <FileHelpers.h>
#include <HAL/FileManager.h>
#include <HAL/PlatformFileManager.h>
#include <Misc/App.h>
#include <HAL/IConsoleManager.h>
#include <Interfaces/IPluginManager.h>
#include <ISourceControlModule.h>
#include <Misc/App.h>
#include <Misc/PackageName.h>
#include <Misc/Paths.h>
#include <PackageSourceControlHelper.h>
#include <SourceControlHelpers.h>
#include <UObject/MetaData.h>
#include <UObject/Package.h>
#include <UObject/UObjectIterator.h>

#if WITH_ANGELSCRIPT_CK
#include <AngelscriptCodeModule.h>
#include "ClassGenerator/ASClass.h"
#endif

// --------------------------------------------------------------------------------------------------------------------

namespace ck_autotest_map_populator
{
    static TAutoConsoleVariable<int32> GCleanupUnloadableWrappers(
        TEXT("Ck.AutoTest.Populator.CleanupUnloadableWrappers"),
        0,
        TEXT("Opt in to deleting unloadable stale AutoTest external-actor packages discovered by the map populator. ")
        TEXT("Default is preview-only because these packages can be tracked binary assets."),
        ECVF_Default);

    // The bounded escape hatch for the wipe floor.
    //
    // Deliberately NOT bInForceFullSync. "Force" means "do the real load-and-sync
    // instead of trusting the cheap pre-check" -- a statement about which PATH to take,
    // which every console invocation makes and which says nothing about authorising
    // destruction. Reusing it as the authorisation would leave the console path, the
    // more dangerous of the two, permanently unfloored: `Ck.SyncAutoTestMaps` typed by
    // someone who just wanted a resync would carry the authority to delete the corpus.
    //
    // Separate CVar, default off, matching the GCleanupUnloadableWrappers precedent
    // directly above: destructive-by-default is opt-in, once, out loud.
    static TAutoConsoleVariable<int32> GAllowUnrecognizedWipe(
        TEXT("Ck.AutoTest.Populator.AllowUnrecognizedWipe"),
        0,
        TEXT("Authorise the AutoTest map populator to remove EVERY wrapper belonging to a map when it ")
        TEXT("discovers no test classes at all. Default is to refuse: an empty wanted set is far more ")
        TEXT("likely to mean discovery broke than that every test was deleted at once."),
        ECVF_Default);

    static FAutoConsoleCommand GSyncCommand(
        TEXT("Ck.SyncAutoTestMaps"),
        TEXT("Force a sync of every UCkAutoTestMapConfig against the currently-open editor world."),
        FConsoleCommandDelegate::CreateLambda([]()
        {
            if (NOT GEditor)
            { return; }
            if (auto* Subsystem = GEditor->GetEditorSubsystem<UCkAutoTestMapPopulator>();
                ck::IsValid(Subsystem, ck::IsValid_Policy_NullptrOnly{}))
            {
                Subsystem->Sync_AllConfigs();
            }
        }));
}

// --------------------------------------------------------------------------------------------------------------------

auto
    UCkAutoTestMapPopulator::
    Initialize(
        FSubsystemCollectionBase& Collection)
    -> void
{
    Super::Initialize(Collection);

    ck::tests_editor::Log(TEXT("[CkAutoTest Populator] Subsystem initialized."));

#if WITH_ANGELSCRIPT_CK
    _PostAngelscriptCompileHandle = FAngelscriptCodeModule::GetPostCompile().AddLambda(
        [this]() { OnAngelscriptPostCompile(); });
#endif

    // Initial sync waits for the asset registry's first scan to complete — that's both the
    // earliest point we can actually discover UCkAutoTestMapConfig assets AND a safe moment
    // to use the editor timer manager. Subscribing to GEditor->GetTimerManager() any earlier
    // (e.g. straight from Initialize) tripped a check inside ToSharedRef because the timer
    // manager isn't constructed until later in UEditorEngine startup.
    auto& AssetRegistry = FAssetRegistryModule::GetRegistry();
    if (AssetRegistry.IsLoadingAssets())
    {
        _AssetRegistryFilesLoadedHandle = AssetRegistry.OnFilesLoaded().AddUObject(
            this, &UCkAutoTestMapPopulator::OnAssetRegistryFilesLoaded);
    }
    else
    {
        // Already loaded (e.g. on hot-reload of this subsystem) — sync at next opportunity.
        Defer_SyncToNextTick(/*bInForceFullSync=*/false);
    }
}

auto
    UCkAutoTestMapPopulator::
    Deinitialize()
    -> void
{
#if WITH_ANGELSCRIPT_CK
    if (_PostAngelscriptCompileHandle.IsValid())
    {
        FAngelscriptCodeModule::GetPostCompile().Remove(_PostAngelscriptCompileHandle);
        _PostAngelscriptCompileHandle.Reset();
    }
#endif

    if (_AssetRegistryFilesLoadedHandle.IsValid())
    {
        if (auto* Module = FModuleManager::GetModulePtr<FAssetRegistryModule>(TEXT("AssetRegistry")))
        {
            Module->Get().OnFilesLoaded().Remove(_AssetRegistryFilesLoadedHandle);
        }
        _AssetRegistryFilesLoadedHandle.Reset();
    }

    Super::Deinitialize();
}

auto
    UCkAutoTestMapPopulator::
    OnAssetRegistryFilesLoaded()
    -> void
{
    // Boot path. Not forced: if the maps on disk already match the discovered test
    // classes there is nothing to do, and loading them to find that out is the 4.89 s
    // this deferral used to cost every editor boot.
    Defer_SyncToNextTick(/*bInForceFullSync=*/false);
}

auto
    UCkAutoTestMapPopulator::
    Defer_SyncToNextTick(
        bool bInForceFullSync)
    -> void
{
    // FTSTicker is always available regardless of editor init state, unlike
    // GEditor->GetTimerManager() which trips a check inside ToSharedRef if called
    // before the timer manager has been constructed (early in UEditorEngine::Init).
    auto WeakSelf = TWeakObjectPtr<UCkAutoTestMapPopulator>{this};
    FTSTicker::GetCoreTicker().AddTicker(FTickerDelegate::CreateLambda(
        [WeakSelf, bInForceFullSync](float /*DeltaSeconds*/)
        {
            if (auto* Self = WeakSelf.Get();
                ck::IsValid(Self, ck::IsValid_Policy_NullptrOnly{}))
            {
                Self->Sync_AllConfigs_Internal(bInForceFullSync);
            }
            return false; // one-shot — don't re-tick
        }));
}

// --------------------------------------------------------------------------------------------------------------------

auto
    UCkAutoTestMapPopulator::
    OnAngelscriptPostCompile()
    -> void
{
    // Defer to next tick — calling SpawnActor / SavePackages from inside the AS engine's
    // post-compile callback risks re-entrancy issues, and deferring also coalesces bursts
    // of compiles into a single sync pass.
    //
    // Not forced. A recompile that changed the test-class set is exactly what the
    // asset-registry pre-check detects (the wanted set no longer matches what is on
    // disk), so it falls through to the full pass on its own; a recompile that changed
    // something else no longer drags two maps into memory.
    Defer_SyncToNextTick(/*bInForceFullSync=*/false);
}

// --------------------------------------------------------------------------------------------------------------------

void UCkAutoTestMapPopulator::Sync_AllConfigs()
{
    // Public entry point == explicit request (console command, Blueprint). Force the
    // full pass; the caller asked for the real thing.
    Sync_AllConfigs_Internal(/*bInForceFullSync=*/true);
}

auto
    UCkAutoTestMapPopulator::
    Sync_AllConfigs_Internal(
        bool bInForceFullSync)
    -> void
{
    ck::tests_editor::Log(TEXT("[CkAutoTest Populator] === Sync_AllConfigs (force={}) ==="),
        bInForceFullSync ? FString{TEXT("yes")} : FString{TEXT("no")});

    const auto Configs = Discover_AllConfigs();
    if (Configs.Num() == 0)
    {
        ck::tests_editor::Log(TEXT("[CkAutoTest Populator] No UCkAutoTestMapConfig assets found in the project."));
        return;
    }

    auto TotalSpawned = int32{0};
    auto TotalRemoved = int32{0};
    auto TotalRelabeled = int32{0};
    auto TotalSkipped = int32{0};
    auto TotalRefused = int32{0};

    for (auto* Config : Configs)
    {
        const auto Result = Sync_Config_Internal(Config, bInForceFullSync);
        TotalSpawned += Result.Spawned;
        TotalRemoved += Result.Removed;
        TotalRelabeled += Result.Relabeled;
        if (Result.bSkipped) { ++TotalSkipped; }
        if (Result.bRefused) { ++TotalRefused; }
    }

    // Refusals are counted separately and NOT folded into "skipped". The summary line is
    // the only trace of this pass a headless log keeps, and a refused wipe reported as a
    // skip reads as "nothing to do" -- the untruth the third outcome exists to prevent.
    ck::tests_editor::Log(
        TEXT("[CkAutoTest Populator] Done — {} configs, {} spawned, {} removed, {} relabeled, {} skipped, ")
        TEXT("{} REFUSED."),
        Configs.Num(), TotalSpawned, TotalRemoved, TotalRelabeled, TotalSkipped, TotalRefused);
}

FCkAutoTestSyncResult UCkAutoTestMapPopulator::Sync_Config(UCkAutoTestMapConfig* InConfig)
{
    // Public entry point == explicit request. See Sync_AllConfigs.
    return Sync_Config_Internal(InConfig, /*bInForceFullSync=*/true);
}

// --------------------------------------------------------------------------------------------------------------------

auto
    UCkAutoTestMapPopulator::
    Get_WouldWipeUnrecognizedWrappers(
        int32 InNumWantedClasses,
        int32 InNumAssociatedWrappers)
    -> bool
{
    // See the header for why this is `wanted == 0` and not a ratio.
    return InNumWantedClasses == 0 && InNumAssociatedWrappers > 0;
}

auto
    UCkAutoTestMapPopulator::
    DoReport_Refusal(
        UCkAutoTestMapConfig*                InConfig,
        const FCk_AutoTestWipeFloorVerdict&  InVerdict)
    -> void
{
    // Latched per config per editor session, on the same reasoning as the stale-wrapper
    // preview above: the boot runs Sync_AllConfigs TWICE back to back and the automatic
    // sync re-runs on every AngelScript post-compile, so an unlatched toast would stack up
    // several deep for one unchanged condition and train the reader to dismiss it.
    //
    // Only the NOTIFICATION is latched. The refusal itself, Result.bRefused, and the
    // "N REFUSED" count in the summary line happen on every pass -- so the machine-readable
    // record stays complete while the human-facing alarm fires once.
    const auto Key = InConfig->Get_DisplayName();
    if (_WipeRefusalReported.Contains(Key))
    {
        ck::tests_editor::Log(TEXT("{} (already reported this session)"), InVerdict.Explanation);
        return;
    }
    _WipeRefusalReported.Add(Key);

    ck::tests_editor::Notify_Error_Detailed(InVerdict.Headline, InVerdict.Explanation);
}

auto
    UCkAutoTestMapPopulator::
    Get_WipeAuthorisation(
        bool bInIsForcedPass)
    -> bool
{
    // The CVar is read HERE, once; the rule itself lives in Get_IsWipeAuthorised so it can
    // be tested without touching global console state.
    return Get_IsWipeAuthorised(
        ck_autotest_map_populator::GAllowUnrecognizedWipe.GetValueOnGameThread() != 0,
        bInIsForcedPass);
}

auto
    UCkAutoTestMapPopulator::
    Get_IsWipeAuthorised(
        bool bInCVarSet,
        bool bInIsForcedPass)
    -> bool
{
    // BOTH, deliberately. See the header: a CVar can outlive the intent that set it, and
    // forcing is a statement about which path to take, not consent to destruction.
    return bInCVarSet && bInIsForcedPass;
}

auto
    UCkAutoTestMapPopulator::
    Evaluate_WipeFloor(
        const FString& InConfigDisplayName,
        const FString& InMapPackageName,
        int32          InNumWantedClasses,
        int32          InNumAssociatedWrappers,
        int32          InNumResidentWrapperActors,
        bool           bInWipeAuthorised)
    -> FCk_AutoTestWipeFloorVerdict
{
    auto Verdict = FCk_AutoTestWipeFloorVerdict{};

    if (NOT Get_WouldWipeUnrecognizedWrappers(InNumWantedClasses, InNumAssociatedWrappers))
    {
        // Explicit, not defaulted: the default is NotEvaluated so that only a verdict this
        // function actually produced can satisfy a destructive site.
        Verdict.Decision = ECk_AutoTestWipeFloorDecision::Proceed;
        return Verdict;
    }

    // What a sync would ACTUALLY have done, branched on residency rather than asserted.
    //
    // Only a resident wrapper class produces an actor the orphan sweep can destroy and a
    // package it can source-control-delete. When the classes are ABSENT -- the state the
    // on-disk count exists to cover -- a sync would have removed nothing at all: no actors
    // for the sweep, the unloadable cleanup is preview-only unless separately authorised,
    // and the stranded pass cannot see a package that never loaded an object.
    //
    // Saying "this would have deleted your files" in that second state would be a scarier
    // sentence than the truth, and a refusal that overstates its own stakes is no more
    // trustworthy than one that hides them.
    const auto ClassesAreResident = InNumResidentWrapperActors > 0;

    const auto WouldHaveDone = ClassesAreResident
        ? ck::Format_UE(
            TEXT("Syncing would have removed all {} of them from the level and source-control-deleted "
                 "their files."), InNumResidentWrapperActors)
        : FString{TEXT("None of their classes are resident, so a sync would not have deleted them today "
                       "-- but it also cannot repopulate the map, and the moment those classes load "
                       "again the orphan sweep would remove every one of them.")};

    // Deliberately does NOT tell the reader to check whether AngelScript compiled. It
    // cannot produce this state: a failed initial compile blocks engine init or exits, and
    // a failed hot reload keeps the old code and never broadcasts PostCompile, so the
    // populator is not called at all. An earlier version of this message said otherwise
    // and would have sent whoever hit it to look in the one place that is provably fine.
    const auto LikelyCause =
        TEXT("This almost always means DISCOVERY broke rather than that the tests were deleted -- check "
             "that this config's ClassScanRoot still matches the on-disk source path of its test classes, "
             "and that the plugin holding them has not been renamed or moved.");

    if (bInWipeAuthorised)
    {
        Verdict.Decision = ECk_AutoTestWipeFloorDecision::ProceedAuthorised;
        Verdict.Reason = ck::Format_UE(
            TEXT("authorised wipe of {} wrapper(s) for '{}' with no discovered test classes"),
            InNumAssociatedWrappers, InMapPackageName);
        Verdict.Explanation = ck::Format_UE(
            TEXT("[CkAutoTest Populator] [{}] Ck.AutoTest.Populator.AllowUnrecognizedWipe is SET and this "
                 "is a forced pass -- PROCEEDING to remove all {} AutoTest wrapper(s) belonging to '{}' "
                 "even though discovery found no test classes."),
            InConfigDisplayName, InNumAssociatedWrappers, InMapPackageName);
        return Verdict;
    }

    Verdict.Decision = ECk_AutoTestWipeFloorDecision::Refuse;
    Verdict.Reason = ck::Format_UE(
        TEXT("discovery found NO test classes for this config while {} AutoTest wrapper(s) belong to '{}'"),
        InNumAssociatedWrappers, InMapPackageName);
    // Toast: what happened, that nothing was lost, and where the rest is. No CVar name,
    // no recipe -- see FCk_AutoTestWipeFloorVerdict::Headline.
    //
    // Short NAME, not the package path: the toast is a narrow column, and
    // "/Game/BusterBlock/Map/AutoTests/AutoTests_BB_MAP" spends about a quarter of the
    // readable line on a prefix identical for every config. The full path is in the
    // explanation, where width costs nothing.
    Verdict.Headline = ck::Format_UE(
        TEXT("[CkAutoTest Populator] REFUSED to sync '{}': no test classes discovered, but {} "
             "wrappers belong to it. Nothing was changed - see the Output Log."),
        FPackageName::GetShortName(InMapPackageName), InNumAssociatedWrappers);

    Verdict.Explanation = ck::Format_UE(
        TEXT("[CkAutoTest Populator] [{}] REFUSED to sync: discovery found no test classes at all, but {} "
             "AutoTest wrapper(s) belong to '{}'. {} Nothing was changed. {} If every test really was "
             "deleted on purpose, set Ck.AutoTest.Populator.AllowUnrecognizedWipe=1 AND run "
             "`Ck.SyncAutoTestMaps` -- both are required, so a CVar left in an .ini can never make an "
             "automatic boot sync do this."),
        InConfigDisplayName, InNumAssociatedWrappers, InMapPackageName, WouldHaveDone, LikelyCause);

    return Verdict;
}

auto
    UCkAutoTestMapPopulator::
    Get_WrapperPackageKind(
        const FAssetData& InAsset)
    -> ECk_AutoTestWrapperPackageKind
{
    auto SavedActorMetaDataClass = FString{};
    if (NOT InAsset.GetTagValue(TEXT("ActorMetaDataClass"), SavedActorMetaDataClass))
    { return ECk_AutoTestWrapperPackageKind::UnreadableMetadata; }

    // Resolved and tested with IsChildOf rather than string-compared to
    // ACk_AutoTestRunner's exact path: ActorMetaDataClass records the nearest NATIVE
    // parent, so an exact match would stop recognising every wrapper the day someone
    // adds a native ACk_AutoTestRunner subclass.
    //
    // A recorded class that no longer resolves is NotAWrapper rather than
    // UnreadableMetadata: the metadata was perfectly readable, it just names a class this
    // build does not have. Calling that "unreadable" would send the pre-check down the
    // full-pass path forever for a package it can already describe.
    const auto* SavedNativeClass = FindObject<UClass>(nullptr, *SavedActorMetaDataClass);
    return SavedNativeClass != nullptr && SavedNativeClass->IsChildOf(ACk_AutoTestRunner::StaticClass())
        ? ECk_AutoTestWrapperPackageKind::Wrapper
        : ECk_AutoTestWrapperPackageKind::NotAWrapper;
}

auto
    UCkAutoTestMapPopulator::
    Count_WrapperPackagesOnDisk(
        const FString& InMapPackageName)
    -> int32
{
    const auto ExternalActorRoot = ULevel::GetExternalActorsPath(InMapPackageName);
    if (ExternalActorRoot.IsEmpty())
    { return 0; }

    auto& AssetRegistry = FAssetRegistryModule::GetRegistry();
    AssetRegistry.ScanSynchronous({ExternalActorRoot}, {});

    auto ExternalActorAssets = TArray<FAssetData>{};
    AssetRegistry.GetAssetsByPath(*ExternalActorRoot, ExternalActorAssets,
        /*bRecursive=*/true, /*bIncludeOnlyOnDiskAssets=*/true);

    const auto RootPrefix = ExternalActorRoot + TEXT("/");

    auto Count = int32{0};
    for (const FAssetData& Asset : ExternalActorAssets)
    {
        if (NOT Asset.PackageName.ToString().StartsWith(RootPrefix, ESearchCase::CaseSensitive))
        { continue; }

        // UnreadableMetadata counts. This number exists to answer "is there anything here
        // that a wipe would destroy", and a package under an AutoTests map's external-actor
        // root whose metadata will not read is exactly the case where guessing "no" is the
        // expensive guess. Counting it can only make the floor refuse where it might have
        // proceeded, and the escape hatch covers that.
        switch (Get_WrapperPackageKind(Asset))
        {
            case ECk_AutoTestWrapperPackageKind::Wrapper:
            case ECk_AutoTestWrapperPackageKind::UnreadableMetadata:
                ++Count;
                break;
            case ECk_AutoTestWrapperPackageKind::NotAWrapper:
                break;
        }
    }

    return Count;
}

// --------------------------------------------------------------------------------------------------------------------

auto
    UCkAutoTestMapPopulator::
    Discover_AllConfigs()
    -> TArray<UCkAutoTestMapConfig*>
{
    auto Result = TArray<UCkAutoTestMapConfig*>{};

    auto& AssetRegistry = FAssetRegistryModule::GetRegistry();

    auto AssetData = TArray<FAssetData>{};
    AssetRegistry.GetAssetsByClass(UCkAutoTestMapConfig::StaticClass()->GetClassPathName(), AssetData, /*bSearchSubClasses=*/true);

    for (const auto& Data : AssetData)
    {
        if (auto* Config = Cast<UCkAutoTestMapConfig>(Data.GetAsset());
            ck::IsValid(Config, ck::IsValid_Policy_NullptrOnly{}))
        {
            Result.Add(Config);
        }
    }

    return Result;
}

// --------------------------------------------------------------------------------------------------------------------

auto
    UCkAutoTestMapPopulator::
    Sync_Config_Internal(
        UCkAutoTestMapConfig* InConfig,
        bool                  bInForceFullSync)
    -> FCkAutoTestSyncResult
{
    auto Result = FCkAutoTestSyncResult{};

    if (ck::Is_NOT_Valid(InConfig, ck::IsValid_Policy_NullptrOnly{}))
    {
        Result.bSkipped = true;
        Result.SkipReason = TEXT("Null config");
        return Result;
    }

    if (InConfig->TargetMap.IsNull())
    {
        ck::tests_editor::Warning(
            TEXT("[CkAutoTest Populator] [{}] Skipping — TargetMap is unset."),
            InConfig->Get_DisplayName());
        Result.bSkipped = true;
        Result.SkipReason = TEXT("TargetMap is unset");
        return Result;
    }

    // ---- Pre-check: can we answer "already correct" without loading the map? --------
    //
    // Loading the target map IS the cost of a populator pass (BusterBlock: 4.89 s of
    // blocked game-thread time across two configs, every editor boot, to report no
    // changes). Explicit requests skip the pre-check and always do the real thing.
    //
    // This wanted set is scoped to the pre-check DELIBERATELY, and the real sync below
    // recomputes its own after the world is resolved. Discover_TestClasses answers from
    // the classes currently in memory, and loading the target map can ADD one: a
    // Blueprint subclass of ACk_AutoTestRunner has no generated class until its package
    // is loaded, which for a placed wrapper happens as part of the level load. Reusing a
    // pre-load snapshot for the real sync would classify such a wrapper as unwanted and
    // DELETE it, external package and all. (The project forbids Blueprint tests, but a
    // policy is not a guard, and the failure mode here destroys a tracked asset.) In the
    // pre-check the same blind spot is harmless and self-correcting: the class shows up
    // as an on-disk orphan, which falls through to the full pass, which then sees it.
    if (NOT bInForceFullSync)
    {
        const auto PrecheckWantedClasses = Discover_TestClasses(InConfig);

        // ---- WIPE FLOOR, before the pre-check and before any load -------------------
        //
        // Same DECISION as the full pass below -- Evaluate_WipeFloor owns it -- asked here
        // as well because reaching the full pass costs a map load. Broken discovery is not
        // a one-shot event: the automatic sync re-runs on boot AND on every AngelScript
        // post-compile, and the boot itself runs Sync_AllConfigs twice back to back, so
        // "load two maps, then refuse" would be a 4.9 s tax per pass on the developer
        // already fighting whatever broke discovery. Refusing from disk evidence costs one
        // cached registry query.
        //
        // The full pass keeps the same check regardless. That one is the authoritative
        // floor: it sits above every destructive site, it sees the loaded actors as well as
        // the packages (so it covers a non-OFPA map, whose actors live in the .umap and are
        // invisible here), and it is the ONLY floor on the forced path, which does not run
        // this branch at all.
        //
        // Note this site can never AUTHORISE a wipe: Get_WipeAuthorisation requires a
        // forced pass, and this branch is the unforced one. So the verdict here is only
        // ever Proceed or Refuse, and an authorised wipe always goes through the full pass
        // -- which is what stops an authorised unforced pass falling through into the
        // pre-check with an empty wanted set and reporting "Already in sync".
        if (const auto TargetWorldPath = InConfig->TargetMap.ToSoftObjectPath().GetLongPackageName();
            NOT TargetWorldPath.IsEmpty())
        {
            // Resident-actor count is 0 by construction: nothing is loaded yet. That is not
            // a guess the message has to make -- it is what "before any load" means, and
            // Evaluate_WipeFloor words the consequence accordingly.
            const auto Verdict = Evaluate_WipeFloor(
                InConfig->Get_DisplayName(),
                TargetWorldPath,
                PrecheckWantedClasses.Num(),
                Count_WrapperPackagesOnDisk(TargetWorldPath),
                /*InNumResidentWrapperActors=*/0,
                Get_WipeAuthorisation(/*bInIsForcedPass=*/false));

            if (Verdict.Decision == ECk_AutoTestWipeFloorDecision::Refuse)
            {
                Result.bRefused = true;
                Result.RefusalReason = Verdict.Reason;
                DoReport_Refusal(InConfig, Verdict);
                return Result;
            }
        }

        auto ReasonToLoad = FString{};
        if (Is_AlreadyInSync_FromAssetRegistry(InConfig, PrecheckWantedClasses, ReasonToLoad))
        {
            ck::tests_editor::Log(
                TEXT("[CkAutoTest Populator] [{}] Already in sync on disk — {} wrapper(s) verified ")
                TEXT("from the asset registry, target map not loaded. Run `Ck.SyncAutoTestMaps` to ")
                TEXT("force the full load-and-sync pass."),
                InConfig->Get_DisplayName(), PrecheckWantedClasses.Num());

            Result.AlreadyPresent = PrecheckWantedClasses.Num();
            return Result;
        }

        // Not silent: whichever condition sent us to the slow path is named, so a 5-second
        // boot pause is always attributable to a stated reason rather than looking like
        // the pre-check simply does not work.
        ck::tests_editor::Log(
            TEXT("[CkAutoTest Populator] [{}] Loading the target map — {}"),
            InConfig->Get_DisplayName(), ReasonToLoad);
    }

    // Resolve the world to sync against. If the target map is the currently-open
    // editor world, we operate on it live (path A). Otherwise we load the package
    // off-disk and edit the unloaded UWorld in place (path B). Either way, the
    // downstream sync logic is identical.
    auto bWasLoadedFresh = false;
    auto LoadSkipReason = FString{};
    auto* CurrentWorld = Find_OrLoad_TargetWorld(InConfig, bWasLoadedFresh, LoadSkipReason);
    if (NOT ck::IsValid(CurrentWorld, ck::IsValid_Policy_NullptrOnly{}))
    {
        Result.bSkipped = true;
        Result.SkipReason = LoadSkipReason;
        return Result;
    }

    auto* Package = CurrentWorld->GetPackage();
    if (NOT ck::IsValid(Package, ck::IsValid_Policy_NullptrOnly{}))
    {
        Result.bSkipped = true;
        Result.SkipReason = TEXT("World has no package");
        return Result;
    }

    // Snapshot dirty state BEFORE we make changes.
    //
    // For path A (currently-open editor world): catches unrelated user edits in
    // flight. We must NOT silently commit those.
    //
    // For path B (freshly loaded off-disk): catches dirty state induced by the
    // *load itself* — e.g. UE drops unresolved actor references when the level
    // file points at a class that no longer exists, and that drop sets the dirty
    // flag. If we don't save in that case, the on-disk .umap retains the dead
    // reference until the next manual save, and the load-time warning fires every
    // time the level is opened.
    const auto WasDirtyOnEntry = Package->IsDirty();

    // ---- Build "wanted" set --------------------------------------------------------
    //
    // Computed HERE, after the world is resolved, not reused from the pre-check above —
    // see the comment there for why a pre-load snapshot must never drive a deletion.
    const auto WantedClasses = Discover_TestClasses(InConfig);
    auto WantedSet = TSet<UClass*>{};
    WantedSet.Append(WantedClasses);

    // ---- Inventory currently-placed wrapper actors ----------------------------------
    auto CurrentByClass = TMap<UClass*, TArray<AActor*>>{};
    if (ck::IsValid(CurrentWorld->PersistentLevel.Get(), ck::IsValid_Policy_NullptrOnly{}))
    {
        for (AActor* Actor : CurrentWorld->PersistentLevel->Actors)
        {
            if (NOT ck::IsValid(Actor, ck::IsValid_Policy_NullptrOnly{}))
            { continue; }

            if (NOT Actor->IsA(ACk_AutoTestRunner::StaticClass()))
            { continue; }

            CurrentByClass.FindOrAdd(Actor->GetClass()).Add(Actor);
        }
    }

    // ---- WIPE FLOOR: refuse a pass that recognises nothing --------------------------
    //
    // Four sites below this line destroy something: the duplicate removal, the orphan
    // sweep, the unloadable-wrapper cleanup (separately CVar-gated) and the
    // stranded-external cleanup (ungated). Three of them decide what to destroy by
    // subtracting the wanted set from what exists, so an EMPTY wanted set makes all three
    // conclude "destroy everything"; the fourth is wanted-driven and inert when nothing is
    // wanted, but it is below the floor too and that is the point -- the guard is placed
    // by position, not by enumerating which sites happen to be dangerous today.
    //
    // Refusing once, above all of them, rather than guarding each: a floor repeated N
    // times is N chances to drift apart, and the N+1th destructive site would arrive
    // unguarded.
    //
    // Counting BOTH evidence sources is also load-bearing. On-disk packages alone read
    // zero for a non-OFPA level, whose actors live inside the .umap. Loaded actors alone
    // read zero for a map whose wrapper classes are absent -- and while that state cannot
    // currently destroy anything (a class that did not load leaves no actor for the sweep
    // and no object for the stranded pass), it is still a state in which this pass must
    // not claim the map is in sync, and it is reachable on a host built without
    // AngelScript or with AS roots that exclude the plugin holding the tests. The floor
    // takes the larger of the two so it is true above the union.
    const auto NumPlacedWrapperActors = [&]()
    {
        auto Count = int32{0};
        for (const auto& Pair : CurrentByClass)
        { Count += Pair.Value.Num(); }
        return Count;
    }();

    // Both inputs are computed unconditionally, not lazily behind the predicate's own
    // first clause. The registry scan is a no-op against cached data (the registry's
    // initial scan has completed before any sync runs) and the full pass repeats it a few
    // hundred lines below regardless, so there is nothing to save -- while a lazily-zeroed
    // input would silently defeat any future widening of the predicate.
    const auto NumAssociatedWrappers = FMath::Max(
        NumPlacedWrapperActors,
        Count_WrapperPackagesOnDisk(Package->GetName()));

    const auto Verdict = Evaluate_WipeFloor(
        InConfig->Get_DisplayName(),
        Package->GetName(),
        WantedClasses.Num(),
        NumAssociatedWrappers,
        NumPlacedWrapperActors,
        Get_WipeAuthorisation(bInForceFullSync));

    switch (Verdict.Decision)
    {
        case ECk_AutoTestWipeFloorDecision::Refuse:
        {
            Result.bRefused = true;
            Result.RefusalReason = Verdict.Reason;
            DoReport_Refusal(InConfig, Verdict);
            return Result;
        }
        case ECk_AutoTestWipeFloorDecision::ProceedAuthorised:
        {
            // Announced at the moment of USE, not just of setting. Warning rather than
            // Notify_Error: a human asked for this on this very command, so it is a record,
            // not an alarm.
            ck::tests_editor::Warning(TEXT("{}"), Verdict.Explanation);
            break;
        }
        case ECk_AutoTestWipeFloorDecision::Proceed:
        { break; }
    }

    // WHAT PROTECTS THE DESTRUCTIVE HALF, and -- as important -- what does not.
    //
    // It used to be POSITION: the floor sat above the destructive sites and that was the whole
    // guarantee. Nothing enforces position, and two attempts to enforce it failed:
    //
    //   1. Nothing at all. A refactor could move a destructive site above the floor and no test
    //      would notice -- the predicate, the decision and the classifier are each covered, and
    //      every one of those tests stays green.
    //   2. Per-site ensures asserting the verdict. The natural response to the compile error
    //      they raise -- hoist the declaration, assign later -- satisfied them too (closed by
    //      the NotEvaluated default), and they never covered the N+1 case at all: a site added
    //      above the floor, or one not naming the verdict, inherited nothing.
    //
    // What actually fixed it is CONTAINMENT, not the guard: every destructive line now lives in
    // DoApply_Sync and nothing else does. A line added anywhere inside it inherits the entry
    // check with nothing to remember, and there is no floor inside that body to move below.
    //
    // A move-only clearance token was built here first and then REMOVED. It claimed the type
    // system enforced "the floor ran"; review established it enforced only "an expression of
    // this type was passed" -- the minting function was public and the verdict's decision field
    // is public, so it was a public constructor with extra steps. It cost ~120 lines of comments
    // asserting a guarantee the code did not have. The verdict parameter names the authorisation
    // in the signature; the entry ensure is the guard; the containment is the guarantee.

    // Hand the destructive half the verdict and everything it needs.
    auto Context = FCk_AutoTestSyncContext{};
    Context.World            = CurrentWorld;
    Context.Package          = Package;
    Context.WantedClasses    = WantedClasses;
    Context.WantedSet        = WantedSet;
    Context.CurrentByClass   = CurrentByClass;
    Context.bWasLoadedFresh  = bWasLoadedFresh;
    Context.bWasDirtyOnEntry = WasDirtyOnEntry;

    DoApply_Sync(Verdict, InConfig, Context, Result);

    return Result;
}

// --------------------------------------------------------------------------------------------------------------------

auto
    UCkAutoTestMapPopulator::
    Get_IsPositiveDecision(
        ECk_AutoTestWipeFloorDecision InDecision)
    -> bool
{
    return InDecision == ECk_AutoTestWipeFloorDecision::Proceed ||
           InDecision == ECk_AutoTestWipeFloorDecision::ProceedAuthorised;
}

// --------------------------------------------------------------------------------------------------------------------

auto
    UCkAutoTestMapPopulator::
    DoApply_Sync(
        const FCk_AutoTestWipeFloorVerdict& InVerdict,
        UCkAutoTestMapConfig*               InConfig,
        const FCk_AutoTestSyncContext& InContext,
        FCkAutoTestSyncResult&         InOutResult)
    -> void
{
    // THE guard. Everything destructive is below it, and this is the only way in.
    //
    // A non-positive verdict reaches here only if the floor above was bypassed or its
    // Refuse-return deleted -- so refuse, and say so in the RECORD as well as the log, or the
    // summary reports "0 REFUSED" for a pass that refused.
    //
    // PRESERVES a reason the floor already set rather than overwriting it: the floor knows why
    // it refused and this function does not, and replacing a specific reason with a generic one
    // is a quieter version of the untruth the third outcome exists to prevent.
    CK_ENSURE_IF_NOT(Get_IsPositiveDecision(InVerdict.Decision),
        TEXT("[CkAutoTest Populator] [{}] The destructive half was entered with a verdict that "
             "authorises nothing. Refusing every pass below."),
        InConfig->Get_DisplayName())
    {
        InOutResult.bRefused = true;
        if (InOutResult.RefusalReason.IsEmpty())
        { InOutResult.RefusalReason = TEXT("destructive half entered without a positive wipe-floor verdict"); }
        return;
    }

    // Aliases, so the moved body below is textually what it was before the split. The diff for
    // this change should read as a MOVE, not as six hundred lines of rewrite -- that is what
    // makes it reviewable at all.
    auto*       CurrentWorld    = InContext.World;
    auto*       Package         = InContext.Package;
    const auto& WantedClasses   = InContext.WantedClasses;
    const auto& WantedSet       = InContext.WantedSet;
    const auto& CurrentByClass  = InContext.CurrentByClass;
    const auto  bWasLoadedFresh = InContext.bWasLoadedFresh;
    const auto  WasDirtyOnEntry = InContext.bWasDirtyOnEntry;
    auto&       Result          = InOutResult;

    // ---- Spawn missing classes + relabel stale ones ---------------------------------
    //
    // The expected Outliner label is the wrapper's class name with the conventional
    // "_Actor" suffix stripped — e.g. `ACk_AutoTest_Foo_Bar_Actor` -> "Ck_AutoTest_
    // Foo_Bar". This is what Session Frontend displays in its tree row. Existing
    // actors that were placed manually before the populator existed (or that got
    // their labels reset somehow) get rewritten here, so the level converges to a
    // uniform display state without a separate maintenance pass.
    const auto Compute_ExpectedLabel = [](const UClass* InClass) -> FString
    {
        return Compute_ExpectedLabelForClass(InClass);
    };

    // ---- Pre-flight: bail with a loud notification if the .umap is locked ------------
    //
    // Predict whether any spawn/remove/relabel would happen this pass. If we'd produce
    // a delta AND the underlying .umap is read-only on disk AND the .umap actually
    // needs to be written, attempt an SCC checkout; if that also fails, surface the
    // failure unmissably and skip.
    //
    // The "actually needs to be written" qualifier matters for OFPA-enabled levels:
    // adding a new external actor doesn't mutate the .umap header (the level discovers
    // externals at load time via AssetRegistry scan of __ExternalActors__/, not from a
    // manifest in the .umap). So for adds-only deltas on OFPA targets, the .umap lock
    // is irrelevant — we'll save only the new external .uasset and leave the .umap
    // alone. Removes/relabels still mutate the level's actor list and require .umap
    // write access regardless.
    //
    // The predict pass returns a struct so the save-flow branch downstream can make
    // the same adds-vs-mutations distinction without re-walking the wanted/current
    // sets.
    struct FPredictedDelta
    {
        bool bSpawnNeeded         = false;  // any spawns to do
        bool bMapMutationNeeded   = false;  // any duplicate-remove / relabel / orphan-remove
    };
    const auto Predict_Delta = [&]() -> FPredictedDelta
    {
        auto Out = FPredictedDelta{};
        for (auto* Class : WantedClasses)
        {
            const auto* ExistingActors = CurrentByClass.Find(Class);
            if (ExistingActors == nullptr || ExistingActors->Num() == 0)
            { Out.bSpawnNeeded = true; continue; }
            if (ExistingActors->Num() > 1)
            { Out.bMapMutationNeeded = true; continue; }
            if (auto* Keeper = (*ExistingActors)[0];
                ck::IsValid(Keeper, ck::IsValid_Policy_NullptrOnly{}))
            {
                if (Keeper->GetActorLabel() != Compute_ExpectedLabel(Class))
                { Out.bMapMutationNeeded = true; }
            }
        }
        for (const auto& Pair : CurrentByClass)
        {
            if (NOT WantedSet.Contains(Pair.Key))
            { Out.bMapMutationNeeded = true; }
        }
        return Out;
    };

    const auto bIsOFPA =
        ck::IsValid(CurrentWorld->PersistentLevel.Get(), ck::IsValid_Policy_NullptrOnly{}) &&
        CurrentWorld->PersistentLevel->IsUsingExternalActors();
    const auto Predicted    = Predict_Delta();
    const auto bHasAnyDelta = Predicted.bSpawnNeeded || Predicted.bMapMutationNeeded;
    // The .umap on disk only needs a write when the level isn't OFPA. Under OFPA,
    // every kind of actor mutation (adds, removes/strand-cleanup, relabels) is
    // persisted via the per-actor external .uasset files; the level header has
    // nothing actor-related to store, so the .umap never has to change. Aligned
    // with the post-execution bUmapNeedsSave predicate below.
    const auto bUmapNeedsWrite = NOT bIsOFPA;

    if (bHasAnyDelta && bUmapNeedsWrite)
    {
        auto MapFilePath = FString{};
        const auto bResolvedPath = FPackageName::TryConvertLongPackageNameToFilename(
            Package->GetName(), MapFilePath, FPackageName::GetMapPackageExtension());

        if (bResolvedPath &&
            FPaths::FileExists(MapFilePath) &&
            IFileManager::Get().IsReadOnly(*MapFilePath))
        {
            // Collapses all SCC failure subkinds (no provider, server unreachable,
            // locked-by-someone-else) into one outcome — we surface the toast
            // regardless of the failure subkind.
            auto bMadeWritable = false;
            if (ISourceControlModule::Get().IsEnabled())
            {
                bMadeWritable = USourceControlHelpers::CheckOutOrAddFile(MapFilePath);
            }

            // Unattended (automation) sessions have no SCC provider and no user to act on the
            // toast below — and the read-only bit here is typically the residue of THIS
            // populator's own previous headless save (the editor's not-checked-out convention).
            // Clear it directly so headless runs never require a manual `attrib -r` ritual.
            // Interactive sessions keep the toast + skip behavior.
            if (NOT bMadeWritable && FApp::IsUnattended())
            {
                bMadeWritable = FPlatformFileManager::Get().GetPlatformFile().SetReadOnly(*MapFilePath, false);
                if (bMadeWritable)
                {
                    ck::tests_editor::Notify_Info(
                        TEXT("[CkAutoTest Populator] [{}] AutoTests map was read-only on disk; cleared the ")
                        TEXT("attribute directly (unattended session, no source-control provider): '{}'"),
                        InConfig->Get_DisplayName(), MapFilePath);
                }
            }

            if (NOT bMadeWritable)
            {
                ck::tests_editor::Notify_Error(
                    TEXT("[CkAutoTest Populator] [{}] AutoTests map is read-only on disk: '{}'. ")
                    TEXT("New test wrappers were not added. Make the file writable ")
                    TEXT("(git unlock / p4 checkout / `attrib -r`) and run `Ck.SyncAutoTestMaps`."),
                    InConfig->Get_DisplayName(), MapFilePath);

                Result.bSkipped = true;
                Result.SkipReason = ck::Format_UE(
                    TEXT("Target map is read-only on disk: {}"), MapFilePath);
                return;
            }

            // Auto-checkout succeeded — SCC silently cleared the read-only bit
            // and we're about to apply test placement edits. Surface this so the
            // user knows their working tree was modified on their behalf (and
            // that they own committing/submitting the result).
            //
            // No explicit throttle needed: the file's read-only state IS the
            // throttle. After this call clears read-only, every subsequent
            // populator pass sees IsReadOnly == false and short-circuits before
            // ever reaching this branch. The next time we get here is after the
            // user reverts/commits via SCC, which restores the read-only bit —
            // i.e. a genuine "back to locked, now newly auto-checked-out again"
            // state transition, exactly the moment a fresh toast is warranted.
            ck::tests_editor::Notify_Info(
                TEXT("[CkAutoTest Populator] [{}] AutoTests map was read-only on disk and has been ")
                TEXT("auto-checked-out via source control to apply test placement: '{}'. ")
                TEXT("The .umap is now in your working tree as modified — remember to commit/submit it."),
                InConfig->Get_DisplayName(), MapFilePath);
        }
    }

    for (auto* Class : WantedClasses)
    {
        const auto* ExistingActors = CurrentByClass.Find(Class);
        if (ExistingActors != nullptr && ExistingActors->Num() > 0)
        {
            ++Result.AlreadyPresent;

            // Relabel the keeper if its current label drifted from the convention.
            if (auto* Keeper = (*ExistingActors)[0];
                ck::IsValid(Keeper, ck::IsValid_Policy_NullptrOnly{}))
            {
                const auto ExpectedLabel = Compute_ExpectedLabel(Class);
                if (Keeper->GetActorLabel() != ExpectedLabel)
                {
                    Keeper->SetActorLabel(ExpectedLabel, /*bMarkDirty=*/true);
                    ++Result.Relabeled;
                }
            }

            // Remove all but the first if duplicates exist.
            for (auto Index = int32{1}; Index < ExistingActors->Num(); ++Index)
            {
                if (auto* Duplicate = (*ExistingActors)[Index];
                    ck::IsValid(Duplicate, ck::IsValid_Policy_NullptrOnly{}))
                {
                    CurrentWorld->DestroyActor(Duplicate);
                    ++Result.Removed;
                }
            }
            continue;
        }

        auto SpawnParams = FActorSpawnParameters{};
        SpawnParams.ObjectFlags |= RF_Transactional;
        SpawnParams.OverrideLevel = CurrentWorld->PersistentLevel;

        auto* NewActor = CurrentWorld->SpawnActor<ACk_AutoTestRunner>(Class, FTransform::Identity, SpawnParams);
        if (NOT ck::IsValid(NewActor, ck::IsValid_Policy_NullptrOnly{}))
        {
            ck::tests_editor::Error(
                TEXT("[CkAutoTest Populator] Failed to spawn wrapper actor for class '{}'"),
                Class->GetName());
            continue;
        }

        NewActor->SetActorLabel(Compute_ExpectedLabel(Class), /*bMarkDirty=*/true);

        ++Result.Spawned;
    }

    // ---- Remove orphaned actors -----------------------------------------------------
    //
    // For OFPA-stored actors, DestroyActor strips the actor from the level manifest
    // but the underlying external __ExternalActors__/<...>/<Guid>.uasset file is
    // NOT physically deleted — UE's level save just stops referencing it, leaving a
    // stranded file on disk. Without explicit cleanup these accumulate over time:
    // every test deletion leaves dead bytes in the repo, pointing at classes that
    // no longer exist.
    //
    // The canonical UE workflow is FPackageSourceControlHelper::Delete, which:
    //   - SCC enabled (GitLink/Perforce): reverts pending edits, marks for SCC
    //     delete via FDelete, removes from disk. Refuses to delete files locked by
    //     someone else (we'll see the failure logged and surface a toast).
    //   - SCC disabled: clears read-only and deletes from disk.
    //   - Calls ResetLoaders() first to release file handles.
    //
    // Capture external packages BEFORE DestroyActor — GetExternalPackage() returns
    // null after the actor is gone. Non-OFPA actors leave the list empty (the call
    // no-ops), preserving the original behavior for that path.

    auto OrphanedExternalPackages = TArray<UPackage*>{};
    auto ExternalPackagesQueuedForDeletion = TSet<FName>{};
    for (const auto& Pair : CurrentByClass)
    {
        if (WantedSet.Contains(Pair.Key))
        { continue; }

        for (auto* Actor : Pair.Value)
        {
            if (NOT ck::IsValid(Actor, ck::IsValid_Policy_NullptrOnly{}))
            { continue; }

            if (auto* ExternalPackage = Actor->GetExternalPackage();
                ck::IsValid(ExternalPackage, ck::IsValid_Policy_NullptrOnly{}))
            {
                OrphanedExternalPackages.AddUnique(ExternalPackage);
                ExternalPackagesQueuedForDeletion.Add(ExternalPackage->GetFName());
            }

            CurrentWorld->DestroyActor(Actor);
            ++Result.Removed;
        }
    }

    if (NOT OrphanedExternalPackages.IsEmpty())
    {
        auto SccHelper = FPackageSourceControlHelper{};
        if (NOT SccHelper.Delete(OrphanedExternalPackages))
        {
            ck::tests_editor::Notify_Error(
                TEXT("[CkAutoTest Populator] [{}] Removed {} test wrappers from the level but ")
                TEXT("could not clean up all of their external .uasset files on disk. The level ")
                TEXT("itself is consistent; remaining stranded files need manual cleanup. ")
                TEXT("Check the Output Log for per-file failure reasons (typical causes: a ")
                TEXT("file is locked by another teammate, or your local copy isn't at HEAD)."),
                InConfig->Get_DisplayName(), OrphanedExternalPackages.Num());
        }
    }

    // ---- Unloadable wrapper cleanup (OFPA only) ------------------------------------
    //
    // A deleted AS wrapper cannot be represented by an AActor, so the normal orphan
    // pass above never sees it. Do NOT treat every unassociated external package as a
    // test orphan: maps may legitimately contain arbitrary external actors that failed
    // to load for unrelated reasons. Instead, use the Asset Registry's saved class
    // path and ActorLabel as durable package evidence. A package is eligible only when
    // all of the following hold:
    //   1. it lives below this exact target map's canonical external-actor root;
    //   2. its saved ActorMetaDataClass is exactly ACk_AutoTestRunner;
    //   3. its saved class name follows the generated AutoTest wrapper convention;
    //   4. its saved ActorLabel is exactly the label this populator assigns that class;
    //   5. that wrapper class is not in this config's desired live-wrapper set; and
    //   6. no live actor currently owns the package.
    //
    // The conjunction is intentionally conservative. In particular, an unreadable
    // external package with no usable Asset Registry metadata remains untouched.
    if (bIsOFPA)
    {

        auto LiveExternalPackageNames = TSet<FName>{};
        if (auto* Level = CurrentWorld->PersistentLevel.Get();
            ck::IsValid(Level, ck::IsValid_Policy_NullptrOnly{}))
        {
            for (AActor* Actor : Level->Actors)
            {
                if (NOT ck::IsValid(Actor, ck::IsValid_Policy_NullptrOnly{}))
                { continue; }
                if (auto* ExtPkg = Actor->GetExternalPackage();
                    ck::IsValid(ExtPkg, ck::IsValid_Policy_NullptrOnly{}))
                { LiveExternalPackageNames.Add(ExtPkg->GetFName()); }
            }
        }

        auto DesiredWrapperClassPaths = TSet<FTopLevelAssetPath>{};
        for (const UClass* Class : WantedClasses)
        {
            if (ck::IsValid(Class, ck::IsValid_Policy_NullptrOnly{}))
            { DesiredWrapperClassPaths.Add(Class->GetClassPathName()); }
        }

        const auto ExternalActorRoot = ULevel::GetExternalActorsPath(Package->GetName());
        if (NOT ExternalActorRoot.IsEmpty())
        {
            auto& AssetRegistry = FAssetRegistryModule::GetRegistry();
            AssetRegistry.ScanSynchronous({ExternalActorRoot}, {});

            auto ExternalActorAssets = TArray<FAssetData>{};
            AssetRegistry.GetAssetsByPath(*ExternalActorRoot, ExternalActorAssets,
                /*bRecursive=*/true, /*bIncludeOnlyOnDiskAssets=*/true);

            auto UnloadableWrapperPackages = TArray<FString>{};
            const auto RootPrefix = ExternalActorRoot + TEXT("/");
            const auto AutoTestRunnerNativeClassPath = ACk_AutoTestRunner::StaticClass()->GetPathName();
            for (const FAssetData& Asset : ExternalActorAssets)
            {
                const auto PackageName = Asset.PackageName.ToString();
                if (NOT PackageName.StartsWith(RootPrefix, ESearchCase::CaseSensitive) ||
                    LiveExternalPackageNames.Contains(Asset.PackageName) ||
                    ExternalPackagesQueuedForDeletion.Contains(Asset.PackageName))
                { continue; }

                auto SavedActorMetaDataClass = FString{};
                if (NOT Asset.GetTagValue(TEXT("ActorMetaDataClass"), SavedActorMetaDataClass) ||
                    SavedActorMetaDataClass != AutoTestRunnerNativeClassPath)
                { continue; }

                const auto WrapperClassName = Asset.AssetClassPath.GetAssetName().ToString();
                if (NOT WrapperClassName.Contains(TEXT("_AutoTest_"), ESearchCase::CaseSensitive) ||
                    NOT WrapperClassName.EndsWith(TEXT("_Actor"), ESearchCase::CaseSensitive) ||
                    DesiredWrapperClassPaths.Contains(Asset.AssetClassPath))
                { continue; }

                const auto ExpectedLabel = Compute_ExpectedLabelForClassName(WrapperClassName);

                auto SavedActorLabel = FString{};
                if (NOT Asset.GetTagValue(TEXT("ActorLabel"), SavedActorLabel) ||
                    SavedActorLabel != ExpectedLabel)
                { continue; }

                UnloadableWrapperPackages.AddUnique(PackageName);
            }

            if (NOT UnloadableWrapperPackages.IsEmpty())
            {
                const auto CleanupIsExplicitlyEnabled =
                    ck_autotest_map_populator::GCleanupUnloadableWrappers.GetValueOnGameThread() != 0;
                if (NOT CleanupIsExplicitlyEnabled)
                {
                    ck::tests_editor::Warning(
                        TEXT("[CkAutoTest Populator] [{}] Preview: identified {} unloadable stale AutoTest wrapper packages under '{}'. ")
                        TEXT("No files were deleted. Explicitly set Ck.AutoTest.Populator.CleanupUnloadableWrappers=1 and rerun ")
                        TEXT("Ck.SyncAutoTestMaps to authorize cleanup."),
                        InConfig->Get_DisplayName(), UnloadableWrapperPackages.Num(), ExternalActorRoot);
                }
                else
                {
                    ck::tests_editor::Log(
                        TEXT("[CkAutoTest Populator] [{}] Explicit cleanup enabled for {} unloadable stale AutoTest wrapper packages under '{}'."),
                        InConfig->Get_DisplayName(), UnloadableWrapperPackages.Num(), ExternalActorRoot);

                    auto SccHelper = FPackageSourceControlHelper{};
                    if (NOT SccHelper.Delete(UnloadableWrapperPackages))
                    {
                        ck::tests_editor::Notify_Error(
                            TEXT("[CkAutoTest Populator] [{}] Identified {} stale AutoTest wrapper packages but could not delete them. ")
                            TEXT("The map remains consistent; check the Output Log for source-control failure details."),
                            InConfig->Get_DisplayName(), UnloadableWrapperPackages.Num());
                    }
                    else
                    {
                        for (const auto& DeletedPackage : UnloadableWrapperPackages)
                        { ExternalPackagesQueuedForDeletion.Add(FName{DeletedPackage}); }
                        Result.Removed += UnloadableWrapperPackages.Num();
                    }
                }
            }
        }

        // Preserve the established cleanup for packages that UE did load but that
        // no longer have a live actor. This is deliberately separate from the scan
        // above: GetExternalPackages() cannot identify a wrapper whose deleted class
        // prevented the package from loading in the first place.
        auto StrandedExternals = TArray<UPackage*>{};
        for (auto* ExtPkg : Package->GetExternalPackages())
        {
            if (ck::IsValid(ExtPkg, ck::IsValid_Policy_NullptrOnly{}) &&
                NOT LiveExternalPackageNames.Contains(ExtPkg->GetFName()) &&
                NOT ExternalPackagesQueuedForDeletion.Contains(ExtPkg->GetFName()))
            { StrandedExternals.AddUnique(ExtPkg); }
        }

        if (NOT StrandedExternals.IsEmpty())
        {
            ck::tests_editor::Log(
                TEXT("[CkAutoTest Populator] [{}] Cleaning {} stranded loaded external actor files (no matching actor in level)."),
                InConfig->Get_DisplayName(), StrandedExternals.Num());

            auto SccHelper = FPackageSourceControlHelper{};
            if (NOT SccHelper.Delete(StrandedExternals))
            {
                ck::tests_editor::Notify_Error(
                    TEXT("[CkAutoTest Populator] [{}] Found {} stranded loaded external .uasset files but ")
                    TEXT("could not clean up all of them. Manual cleanup may be needed for the ")
                    TEXT("remaining ones; check the Output Log for per-file failure reasons."),
                    InConfig->Get_DisplayName(), StrandedExternals.Num());
            }
            else
            {
                Result.Removed += StrandedExternals.Num();
            }
        }
    }

    // Two control-flow signals drive whether the sync proceeds into the save block:
    //   1. Our sync logic produced a delta (spawn/remove/relabel). Standard case.
    //   2. Path B's LoadPackage induced dirty state without our help — typically the
    //      level file referenced a class that no longer exists, UE silently dropped
    //      the actor entry, and marked the package dirty. The level on disk still
    //      contains the dead reference until we save here.
    const auto bHasMyDelta = Result.Has_Delta();
    const auto bLoadInducedDirty = bWasLoadedFresh && WasDirtyOnEntry;

    // Under OFPA, the .umap NEVER needs to be saved for actor mutations of any kind:
    // adds, removes (including strand-cleanup), and relabels all live in the actor's
    // external .uasset package. The level loads its actor set by AssetRegistry scan
    // of __ExternalActors__/<MapName>/, not from a manifest in the .umap, so there
    // is nothing actor-related the .umap header has to persist. This is OFPA's
    // headline promise — "teammate has the .umap LFS-locked, I can still
    // add/remove/relabel tests" applies uniformly to every mutation shape.
    //
    // Two cases still force a .umap save:
    //   1. Non-OFPA levels — the actor data lives IN the .umap package itself, so
    //      the save is the only persistence path. Without this, adds/removes silently
    //      drop on the floor.
    //   2. Path B's LoadPackage induced dirty state — e.g. the level referenced a
    //      class that no longer exists and UE silently dropped the entry. The level
    //      on disk still contains the dead reference until we save here. (Rare under
    //      OFPA since the .umap doesn't carry actor refs, but kept defensively for
    //      any non-actor class references like WorldSettings.)
    //
    const auto bUmapNeedsSave = bLoadInducedDirty || NOT bIsOFPA;

    if (bHasMyDelta)
    {
        if (bUmapNeedsSave)
        { Package->MarkPackageDirty(); }

        ck::tests_editor::Log(
            TEXT("[CkAutoTest Populator] [{}] {} spawned, {} removed, {} relabeled, {} already present."),
            InConfig->Get_DisplayName(),
            Result.Spawned, Result.Removed, Result.Relabeled, Result.AlreadyPresent);
    }
    else if (bLoadInducedDirty)
    {
        ck::tests_editor::Log(
            TEXT("[CkAutoTest Populator] [{}] No actor delta, but load dropped stale references — saving to clean up disk state."),
            InConfig->Get_DisplayName());
    }
    else
    {
        ck::tests_editor::VeryVerbose(
            TEXT("[CkAutoTest Populator] [{}] No changes — {} wrappers in sync."),
            InConfig->Get_DisplayName(), Result.AlreadyPresent);
        return;
    }

    // ---- Auto-save guard ------------------------------------------------------------
    if (NOT InConfig->bAutoSaveOnSync)
    {
        ck::tests_editor::Log(TEXT("[CkAutoTest Populator] Auto-save disabled by config — leaving map dirty for manual save."));
        return;
    }

    // Path A's safety check: don't silently commit a user's in-flight edits.
    // Path B doesn't trip this — the only dirty source is the load itself, which
    // we explicitly want to persist.
    if (NOT bWasLoadedFresh && WasDirtyOnEntry)
    {
        ck::tests_editor::Warning(
            TEXT("[CkAutoTest Populator] [{}] Map was dirty before sync — leaving for manual save (unrelated edits would be silently committed otherwise)."),
            InConfig->Get_DisplayName());
        return;
    }

    auto bSaved = false;
    if (bUmapNeedsSave)
    {
        // Standard path: save the level package; UE saves its dirty external packages
        // along with it.
        auto PackagesToSave = TArray<UPackage*>{Package};
        bSaved = UEditorLoadingAndSavingUtils::SavePackages(PackagesToSave, /*bOnlyDirty=*/true);
    }
    else
    {
        // OFPA path (every shape of actor mutation — adds, removes/strand-cleanup,
        // relabels): save only the level's dirty external .uasset packages. The
        // .umap header stays at HEAD content on disk. UE's level-open flow
        // discovers external actors via AssetRegistry scan of
        // __ExternalActors__/<MapName>/, not from a manifest in the .umap, so the
        // new external set is correctly reflected on next load.
        //
        // Strand-cleanup deletes are persisted by the FPackageSourceControlHelper
        // Delete call earlier in this function (which removes the .uasset from disk
        // and from source control); nothing further is needed here for them.
        //
        // Critical: clear the level package's in-memory dirty flag after saving the
        // externals, otherwise the user gets a persistent "save the level?" prompt
        // on every Ctrl+S — confusing because the on-disk .umap doesn't need a save.
        auto DirtyExternals = TArray<UPackage*>{};
        for (auto* ExtPkg : Package->GetExternalPackages())
        {
            if (ck::IsValid(ExtPkg, ck::IsValid_Policy_NullptrOnly{}) && ExtPkg->IsDirty())
            { DirtyExternals.Add(ExtPkg); }
        }

        if (DirtyExternals.IsEmpty())
        {
            // No dirty externals to save. Two normal cases land here:
            //   1. A removes/relabels-only sync where the persistent changes were
            //      already committed by SCC Delete (strand-cleanup) — nothing left.
            //   2. An adds sync where UE auto-saved the externals out from under us
            //      mid-sync.
            // Less commonly: spawned actors weren't actually attached to OFPA
            // storage. Either way, count it as success.
            ck::tests_editor::VeryVerbose(
                TEXT("[CkAutoTest Populator] [{}] OFPA path: no dirty external packages to save."),
                InConfig->Get_DisplayName());
            bSaved = true;
        }
        else
        {
            bSaved = UEditorLoadingAndSavingUtils::SavePackages(DirtyExternals, /*bOnlyDirty=*/true);
        }

        // Drop the level's in-memory dirty flag — the .umap on disk hasn't changed
        // and won't change as a result of this sync. Without this, the user sees
        // "Save level?" prompts on every subsequent Ctrl+S even though there's
        // nothing for the level to persist.
        Package->SetDirtyFlag(false);
    }
    Result.bSaved = bSaved;

    if (bSaved)
    {
        ck::tests_editor::Log(TEXT("[CkAutoTest Populator] [{}] Auto-saved."), InConfig->Get_DisplayName());
    }
    else
    {
        // Backstop for whatever the pre-flight didn't catch: a race where the file
        // became read-only between pre-flight and save, an SCC provider that lied
        // about the checkout result, a permission flap from antivirus, etc.
        // Re-probe IsReadOnly so the user sees an actionable diagnosis rather than
        // a generic "save failed".
        auto MapFilePath = FString{};
        const auto bResolvedPath = FPackageName::TryConvertLongPackageNameToFilename(
            Package->GetName(), MapFilePath, FPackageName::GetMapPackageExtension());
        const auto bLockedNow = bResolvedPath &&
            FPaths::FileExists(MapFilePath) &&
            IFileManager::Get().IsReadOnly(*MapFilePath);

        if (bLockedNow)
        {
            ck::tests_editor::Notify_Error(
                TEXT("[CkAutoTest Populator] [{}] Auto-save failed — AutoTests map is read-only on disk: '{}'. ")
                TEXT("Make the file writable (git unlock / p4 checkout / `attrib -r`) and run `Ck.SyncAutoTestMaps`."),
                InConfig->Get_DisplayName(), MapFilePath);
        }
        else
        {
            ck::tests_editor::Notify_Error(
                TEXT("[CkAutoTest Populator] [{}] Auto-save failed for '{}' — map left dirty. ")
                TEXT("Check the Output Log for the SavePackages reason and save manually with Ctrl+S."),
                InConfig->Get_DisplayName(),
                bResolvedPath ? MapFilePath : Package->GetName());
        }
    }

    return;
}

// --------------------------------------------------------------------------------------------------------------------

auto
    UCkAutoTestMapPopulator::
    Compute_ExpectedLabelForClassName(
        const FString& InClassName)
    -> FString
{
    auto Label = InClassName;
    if (Label.EndsWith(TEXT("_Actor"), ESearchCase::IgnoreCase))
    { Label.LeftChopInline(FString(TEXT("_Actor")).Len(), EAllowShrinking::No); }
    return Label;
}

auto
    UCkAutoTestMapPopulator::
    Compute_ExpectedLabelForClass(
        const UClass* InClass)
    -> FString
{
    if (ck::Is_NOT_Valid(InClass, ck::IsValid_Policy_NullptrOnly{}))
    { return FString{}; }

    return Compute_ExpectedLabelForClassName(InClass->GetName());
}

// --------------------------------------------------------------------------------------------------------------------

auto
    UCkAutoTestMapPopulator::
    Is_AlreadyInSync_FromAssetRegistry(
        UCkAutoTestMapConfig*  InConfig,
        const TArray<UClass*>& InWantedClasses,
        FString&               OutReasonToLoad)
    -> bool
{
    OutReasonToLoad.Reset();

    if (ck::Is_NOT_Valid(InConfig, ck::IsValid_Policy_NullptrOnly{}))
    {
        OutReasonToLoad = TEXT("null config");
        return false;
    }

    const auto TargetWorldPath = InConfig->TargetMap.ToSoftObjectPath().GetLongPackageName();
    if (TargetWorldPath.IsEmpty())
    {
        OutReasonToLoad = TEXT("target map path could not be resolved");
        return false;
    }

    // The live editor world, and any already-resident copy of the target package, are
    // authoritative over what is on disk -- they may carry unsaved edits the registry
    // cannot see. Both are also nearly free to sync (Path A does no load; Path B's
    // LoadPackage returns the resident package), so there is nothing to win by guessing.
    if (ck::IsValid(GEditor, ck::IsValid_Policy_NullptrOnly{}))
    {
        if (const auto* EditorWorld = GEditor->GetEditorWorldContext().World();
            ck::IsValid(EditorWorld, ck::IsValid_Policy_NullptrOnly{}) &&
            EditorWorld->GetPackage()->GetName().Equals(TargetWorldPath, ESearchCase::IgnoreCase))
        {
            OutReasonToLoad = TEXT("target map is the open editor world (in-memory state is authoritative)");
            return false;
        }
    }

    if (FindPackage(nullptr, *TargetWorldPath) != nullptr)
    {
        OutReasonToLoad = TEXT("target map is already resident in memory (no load cost, and it may hold unsaved edits)");
        return false;
    }

    const auto ExternalActorRoot = ULevel::GetExternalActorsPath(TargetWorldPath);
    if (ExternalActorRoot.IsEmpty())
    {
        OutReasonToLoad = TEXT("no external-actor root could be derived for the target map");
        return false;
    }

    // One folder scan, not a package load. The registry's initial scan has already
    // completed by the time any sync runs (the boot path is triggered off
    // OnFilesLoaded), so this is normally a no-op against cached data.
    auto& AssetRegistry = FAssetRegistryModule::GetRegistry();
    AssetRegistry.ScanSynchronous({ExternalActorRoot}, {});

    auto ExternalActorAssets = TArray<FAssetData>{};
    AssetRegistry.GetAssetsByPath(*ExternalActorRoot, ExternalActorAssets,
        /*bRecursive=*/true, /*bIncludeOnlyOnDiskAssets=*/true);

    if (ExternalActorAssets.IsEmpty())
    {
        // Either the level does not use external actors (its actors live inside the .umap,
        // which the registry cannot enumerate per-actor), or it has never been populated.
        // Both need the real pass, and both are one-time costs rather than the every-boot
        // steady state this pre-check exists to remove.
        OutReasonToLoad = ck::Format_UE(
            TEXT("no external-actor packages under '{}' (non-OFPA level, or not yet populated)"),
            ExternalActorRoot);
        return false;
    }

    const auto AutoTestRunnerNativeClassPath = ACk_AutoTestRunner::StaticClass()->GetPathName();
    const auto RootPrefix                    = ExternalActorRoot + TEXT("/");

    // Placed wrapper classes, counted so duplicates are detected the same way
    // Predict_Delta detects them in the loaded world.
    auto PlacedCountByClassPath = TMap<FTopLevelAssetPath, int32>{};
    auto PlacedLabelByClassPath = TMap<FTopLevelAssetPath, FString>{};

    for (const FAssetData& Asset : ExternalActorAssets)
    {
        if (NOT Asset.PackageName.ToString().StartsWith(RootPrefix, ESearchCase::CaseSensitive))
        { continue; }

        // Classification is Get_WrapperPackageKind's job, not this loop's -- see its header
        // comment. What differs here is only what each answer MEANS to the pre-check.
        const auto Kind = Get_WrapperPackageKind(Asset);

        if (Kind == ECk_AutoTestWrapperPackageKind::UnreadableMetadata)
        {
            // A package under this map's root whose class metadata we cannot read. The
            // full pass has an opinion about these (the unloadable-wrapper preview), so
            // we must not skip past one silently.
            OutReasonToLoad = ck::Format_UE(
                TEXT("external-actor package '{}' has no readable ActorMetaDataClass"),
                Asset.PackageName.ToString());
            return false;
        }

        // Not an AutoTest wrapper (the level's floor, lights, whatever else it holds).
        // Only the wrapper population is the populator's business.
        if (Kind == ECk_AutoTestWrapperPackageKind::NotAWrapper)
        { continue; }

        ++PlacedCountByClassPath.FindOrAdd(Asset.AssetClassPath);

        auto SavedActorLabel = FString{};
        Asset.GetTagValue(TEXT("ActorLabel"), SavedActorLabel);
        PlacedLabelByClassPath.Add(Asset.AssetClassPath, SavedActorLabel);
    }

    if (PlacedCountByClassPath.IsEmpty())
    {
        OutReasonToLoad = TEXT("no AutoTest wrapper packages found on disk for this map");
        return false;
    }

    // NOTE: an EMPTY InWantedClasses never reaches here, and the reason is structural
    // rather than a rule someone has to remember. The only caller is Sync_Config_Internal's
    // UNFORCED branch, which floors that case first; and the floor cannot be waived on that
    // branch, because Get_WipeAuthorisation requires a forced pass. (An earlier version of
    // this note was FALSE for exactly that reason -- the authorisation was a bare CVar, so
    // setting it in an .ini let an empty wanted set reach this function, which then returned
    // TRUE and made the caller log "Already in sync on disk — 0 wrapper(s) verified" about a
    // map holding hundreds of them.)
    //
    // What it protects: reaching this point with nothing wanted falls through to the
    // unloadable-wrapper preview below, which asserts those packages "point at classes that
    // no longer exist" -- a cause it has not established when discovery simply found
    // nothing -- and then hands out the recipe that DELETES them all.

    // ---- Wanted vs placed ----------------------------------------------------------
    for (const UClass* Class : InWantedClasses)
    {
        if (ck::Is_NOT_Valid(Class, ck::IsValid_Policy_NullptrOnly{}))
        {
            OutReasonToLoad = TEXT("a discovered test class was invalid");
            return false;
        }

        const auto  ClassPath = Class->GetClassPathName();
        const auto* Count     = PlacedCountByClassPath.Find(ClassPath);

        if (Count == nullptr)
        {
            OutReasonToLoad = ck::Format_UE(TEXT("test '{}' has no wrapper on disk (needs spawning)"),
                Class->GetName());
            return false;
        }

        if (*Count != 1)
        {
            OutReasonToLoad = ck::Format_UE(TEXT("test '{}' has {} wrappers on disk (needs de-duplicating)"),
                Class->GetName(), *Count);
            return false;
        }

        // IgnoreCase, matching the full pass. The relabel test at :535 compares with FString
        // operator!=, which is case-INsensitive, so a CaseSensitive test here would report
        // "needs relabelling" on a label differing only by case (a case-only test rename keeps
        // the FName's display case) while the full pass then relabels nothing -- loading the
        // map every boot, forever. Same permanent-load shape as the unloadable-wrapper bug
        // above. One label rule means one COMPARISON rule too.
        const auto ExpectedLabel = Compute_ExpectedLabelForClass(Class);
        if (const auto* SavedLabel = PlacedLabelByClassPath.Find(ClassPath);
            SavedLabel == nullptr || NOT SavedLabel->Equals(ExpectedLabel, ESearchCase::IgnoreCase))
        {
            OutReasonToLoad = ck::Format_UE(
                TEXT("wrapper for '{}' has label '{}', expected '{}' (needs relabelling)"),
                Class->GetName(), SavedLabel != nullptr ? *SavedLabel : FString{}, ExpectedLabel);
            return false;
        }
    }

    // Anything placed that is no longer wanted -- a deleted or renamed test -- is an
    // orphan the full pass removes.
    auto WantedClassPaths = TSet<FTopLevelAssetPath>{};
    for (const UClass* Class : InWantedClasses)
    {
        if (ck::IsValid(Class, ck::IsValid_Policy_NullptrOnly{}))
        { WantedClassPaths.Add(Class->GetClassPathName()); }
    }

    auto UnloadableStalePackages = TArray<FString>{};

    for (const auto& Pair : PlacedCountByClassPath)
    {
        if (WantedClassPaths.Contains(Pair.Key))
        { continue; }

        // Two very different things reach here, and the dividing line is exactly "will the
        // level be able to construct this actor", because that is what decides whether the
        // full pass can act on it at all.
        //
        //  1. The class is RESIDENT (FindObject finds it). The linker will construct the
        //     actor, it enters Level->Actors, and the full pass's orphan sweep destroys it
        //     and deletes its external package. Genuinely actionable -- load the map.
        //
        //     Note this is deliberately NOT `Is_LiveTestRunnerSubclass`. That predicate is
        //     the WANTED-set filter and is strictly narrower: it also rejects a bare
        //     ACk_AutoTestRunner placed by hand (Blueprintable, not abstract), a
        //     CLASS_Deprecated subclass, and a class whose AS source file is gone. Every one
        //     of those still constructs, so the full pass still deletes it. Using the
        //     narrower predicate here made the pre-check claim "unloadable" -- and skip --
        //     for packages the full pass would have removed. Resident is the right test.
        //
        //  2. The class is ABSENT. The actor cannot be constructed -- this is the
        //     `Failed to load Actor for External Actor Package` error on every load of this
        //     map -- so it never enters Level->Actors and the orphan sweep structurally
        //     cannot see it. The only code that can is the unloadable-wrapper pass, and that
        //     is PREVIEW-ONLY unless Ck.AutoTest.Populator.CleanupUnloadableWrappers is set.
        //
        // Treating (2) as a reason to load makes the load PERMANENT: the map is loaded every
        // boot to reach a preview that changes nothing, and the stale package is never
        // cleaned, so the condition never clears. So (2) does not force a load while cleanup
        // is off -- but the preview is still emitted below, because losing the diagnostic
        // would be the silent early-return the tenets forbid.
        //
        // WHERE THESE ORPHANS ACTUALLY COME FROM (an earlier version of this comment, and of
        // the commit message, asserted a mechanism that is false -- corrected in review):
        // AngelScript does NOT rename a replaced class with a timestamp. The two offenders on
        // this project, `Ck_AutoTestProbeLockTolerance260514215407` and `...215550`, are
        // scratch classes minted by `CkAuto/AutoTestProbes/_probe_lock_tolerance.ps1` (which
        // timestamps its class name deliberately, to avoid AS collisions) and committed by
        // accident in `0e50da296`. `docs/campaigns/item-entity-migration/PROGRESS.md` had
        // already identified them as stale probe artifacts months earlier.
        //
        // So the real class of failure is broader and worth stating plainly: **deleting a
        // test never cleans up its wrapper package.** In-session the removed class is often
        // still resident, so it still looks wanted; after a restart the class is gone and
        // cleanup is preview-only. Nothing closes the loop, which is why an orphan can sit
        // in the tree for months. Fixing that is a separate change -- the probe script should
        // delete what it mints, and the preview needs to be something a human acts on.
        const auto bClassIsResident = FindObject<UClass>(Pair.Key) != nullptr;

        if (bClassIsResident)
        {
            OutReasonToLoad = ck::Format_UE(
                TEXT("wrapper class '{}' is on disk but not wanted by this config (needs removing)"),
                Pair.Key.ToString());
            return false;
        }

        if (ck_autotest_map_populator::GCleanupUnloadableWrappers.GetValueOnGameThread() != 0)
        {
            // Cleanup is authorized, so the full pass CAN act on this. Load.
            OutReasonToLoad = ck::Format_UE(
                TEXT("unloadable stale wrapper '{}' on disk and cleanup is enabled (needs deleting)"),
                Pair.Key.ToString());
            return false;
        }

        UnloadableStalePackages.Add(Pair.Key.ToString());
    }

    // Latched on the CONTENTS, not just the config name. The set can change within one
    // editor session -- a test deleted while the editor is open moves its wrapper from
    // "resident, still wanted" to "absent, unloadable" -- and a name-only latch would
    // swallow the first report of a newly-orphaned package.
    auto StaleFingerprint = InConfig->Get_DisplayName();
    for (const auto& Pkg : UnloadableStalePackages)
    { StaleFingerprint += TEXT("|") + Pkg; }

    if (NOT UnloadableStalePackages.IsEmpty() &&
        NOT _StaleWrapperPreviewReported.Contains(StaleFingerprint))
    {
        _StaleWrapperPreviewReported.Add(StaleFingerprint);

        // Display, not Warning, and once per config per editor session.
        //
        // Not Warning: this reports a property of what is on disk, not a fault in the run,
        // and UE's automation framework promotes warnings emitted during a test run into a
        // yellow result attributed to whichever test happened to be ticking -- the exact
        // hazard Plugins/GitLink/CLAUDE.md documents for EIK's TickTracker warning. The
        // populator's pass lands in editor frame 1, alongside "Ready to start automation",
        // so a Warning here would randomly yellow an unrelated test on every lane of every
        // suite run. Display is visible in a headless log and carries no such promotion.
        //
        // Once per session: the pre-check runs again on every AngelScript post-compile, and
        // the condition cannot change between passes without the map being edited.
        //
        // Note this preview is NEW information, not a relocation of the full pass's own --
        // that one additionally requires the class name to contain "_AutoTest_", which the
        // offender on this project (`Ck_AutoTestProbeLockTolerance...`) does not, so it was
        // never reported at all and the `Failed to load Actor` errors went unexplained.
        ck::tests_editor::Display(
            TEXT("[CkAutoTest Populator] [{}] Preview: {} unloadable stale AutoTest wrapper package(s) ")
            TEXT("under '{}' point at classes that no longer exist (first: '{}'). They cannot be ")
            TEXT("represented by an actor, so no sync pass can remove them implicitly. Set ")
            TEXT("Ck.AutoTest.Populator.CleanupUnloadableWrappers=1 and run `Ck.SyncAutoTestMaps` to ")
            TEXT("authorize deleting them. Until then they are also the cause of the ")
            TEXT("`Failed to load Actor for External Actor Package` errors on every load of this map."),
            InConfig->Get_DisplayName(), UnloadableStalePackages.Num(), ExternalActorRoot,
            UnloadableStalePackages[0]);
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

auto
    UCkAutoTestMapPopulator::
    Discover_TestClasses(
        UCkAutoTestMapConfig* InConfig) const
    -> TArray<UClass*>
{
    auto Result = TArray<UClass*>{};

    auto* RunnerBase = ACk_AutoTestRunner::StaticClass();

    // Effective scope for this config: explicit override > auto-derived owner scope.
    // The owner scope is "/<PluginName>/" for both AS-defined and on-disk configs, so
    // a config authored in CkTests scopes to /CkTests/ automatically with no fields set.
    auto EffectiveScanRoot = InConfig->ClassScanRoot;
    if (EffectiveScanRoot.IsEmpty())
    { EffectiveScanRoot = Get_OwnerScopeForConfig(InConfig); }

    for (TObjectIterator<UClass> It; It; ++It)
    {
        auto* Class = *It;
        if (NOT Is_LiveTestRunnerSubclass(Class, RunnerBase))
        { continue; }

        if (NOT EffectiveScanRoot.IsEmpty())
        {
            const auto SourcePath = Get_AssertedSourcePathForClass(Class);
            if (NOT SourcePath.Contains(EffectiveScanRoot, ESearchCase::IgnoreCase))
            { continue; }
        }

        Result.Add(Class);
    }

    Result.Sort([](const UClass& A, const UClass& B)
    {
        return A.GetPathName() < B.GetPathName();
    });

    return Result;
}

// --------------------------------------------------------------------------------------------------------------------

auto
    UCkAutoTestMapPopulator::
    Is_LiveTestRunnerSubclass(
        UClass* InClass,
        UClass* InRunnerBase)
    -> bool
{
    if (ck::Is_NOT_Valid(InClass, ck::IsValid_Policy_NullptrOnly{}))
    { return false; }

    if (InClass == InRunnerBase)
    { return false; }

    if (NOT InClass->IsChildOf(InRunnerBase))
    { return false; }

    constexpr auto DisqualifyingFlags =
        CLASS_Abstract | CLASS_Deprecated | CLASS_NewerVersionExists;

    if (InClass->HasAnyClassFlags(DisqualifyingFlags))
    { return false; }

    if (InClass->IsUnreachable() ||
        InClass->HasAnyFlags(RF_BeginDestroyed | RF_FinishDestroyed))
    { return false; }

#if WITH_ANGELSCRIPT_CK
    // Same staleness checks as the wrapper generator: an AS class whose source file
    // has been deleted, or whose newer version replaced this slot, is dead and must
    // not be placed in the level.
    if (auto* ASClass = UASClass::GetFirstASClass(InClass))
    {
        if (ASClass->NewerVersion != nullptr)
        { return false; }

        const auto SourcePath = ASClass->GetSourceFilePath();
        if (NOT SourcePath.IsEmpty() && NOT FPaths::FileExists(SourcePath))
        { return false; }
    }
#endif

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

auto
    UCkAutoTestMapPopulator::
    Get_AssertedSourcePathForClass(
        UClass* InClass)
    -> FString
{
#if WITH_ANGELSCRIPT_CK
    if (auto* ASClass = UASClass::GetFirstASClass(InClass))
    {
        const auto Path = ASClass->GetSourceFilePath();
        if (NOT Path.IsEmpty())
        {
            auto Normalized = FPaths::ConvertRelativePathToFull(Path);
            FPaths::NormalizeFilename(Normalized);
            return Normalized;
        }
    }
#endif

    // Fallback for C++ classes (no AS source): use the package path so users can
    // still scope by `/Script/CkTests` or similar.
    return InClass->GetOutermost()->GetName();
}

// --------------------------------------------------------------------------------------------------------------------

namespace ck_autotest_map_populator
{
    // Mirrors FCkAutoTestWrapperGenerator's plugin-prefix matcher: walk every enabled
    // plugin's BaseDir and pick the longest one that prefixes the input path. Used to
    // resolve an AS asset's source .as file to its owning plugin.
    auto Find_PluginByPathPrefix(const FString& InPath) -> TSharedPtr<IPlugin>
    {
        if (InPath.IsEmpty())
        { return nullptr; }

        auto NormalizedPath = FPaths::ConvertRelativePathToFull(InPath);
        FPaths::NormalizeFilename(NormalizedPath);

        TSharedPtr<IPlugin> BestMatch = nullptr;
        auto BestMatchLen = int32{0};

        for (const auto& Plugin : IPluginManager::Get().GetEnabledPlugins())
        {
            auto PluginDir = FPaths::ConvertRelativePathToFull(Plugin->GetBaseDir());
            FPaths::NormalizeDirectoryName(PluginDir);

            if (NormalizedPath.StartsWith(PluginDir, ESearchCase::IgnoreCase))
            {
                if (PluginDir.Len() > BestMatchLen)
                {
                    BestMatch = Plugin;
                    BestMatchLen = PluginDir.Len();
                }
            }
        }
        return BestMatch;
    }
}

auto
    UCkAutoTestMapPopulator::
    Get_OwnerScopeForConfig(
        UCkAutoTestMapConfig* InConfig)
    -> FString
{
    if (NOT ck::IsValid(InConfig, ck::IsValid_Policy_NullptrOnly{}))
    { return FString{}; }

    auto* Package = InConfig->GetPackage();
    if (NOT ck::IsValid(Package, ck::IsValid_Policy_NullptrOnly{}))
    { return FString{}; }

    // ---- AS-defined assets ---------------------------------------------------------
    // AS-UE writes the source .as filename into the asset package's metadata under
    // ScriptAssetFilename when the asset is materialized at module load time
    // (Bind_UObject.cpp:466). For configs authored as `asset Name of UClass { ... }`
    // this is the most reliable identity — package mount-point alone is "/Script/
    // AngelscriptAssets/" for every AS asset and doesn't tell us which plugin authored it.
    {
#if WITH_EDITOR
        const auto AsFilename = Package->GetMetaData().GetValue(InConfig, TEXT("ScriptAssetFilename"));
        if (NOT AsFilename.IsEmpty())
        {
            // First try: the .as file lives under a plugin's BaseDir.
            if (auto Plugin = ck_autotest_map_populator::Find_PluginByPathPrefix(AsFilename);
                Plugin.IsValid())
            {
                return FString::Printf(TEXT("/%s/"), *Plugin->GetName());
            }

            // Fallback: project-side AS asset (the project itself is not a plugin,
            // so IPluginManager doesn't enumerate it). Compare the .as path against
            // FPaths::ProjectDir() — if it lives under there, derive a scope rooted
            // at the project's own Script/ directory.
            //
            // Scope to the project's own Script/ tree via the ABSOLUTE project
            // directory, not a reconstructed "/<ProjectName>/". Two reasons:
            //   1. A bare project-name scope ("/BusterBlock/") over-matches: the
            //      project name also appears ABOVE the Plugins/ folder
            //      (".../BusterBlock/Plugins/CkTests/Script/...as" contains
            //      "/BusterBlock/"), so it would bleed into every nested plugin's tests.
            //   2. The project FOLDER name can differ from the .uproject name — e.g.
            //      a secondary git worktree checked out at "BusterBlock_alt/" still has
            //      FApp::GetProjectName() == "BusterBlock". Reconstructing
            //      "<ProjectName>/Script/" then fails to match the real on-disk path
            //      ".../BusterBlock_alt/Script/...", so NOTHING is discovered and the
            //      populator removes every placed test as orphaned.
            // Anchoring to the absolute ProjectDir + "/Script" matches the real path in
            // any worktree while still excluding ".../<dir>/Plugins/..." (plugin paths
            // go through "<dir>/Plugins/" instead). Project-side C++ tests under Source/
            // are still NOT auto-scoped; set ClassScanRoot explicitly if needed.
            auto NormalizedAsFilename = FPaths::ConvertRelativePathToFull(AsFilename);
            FPaths::NormalizeFilename(NormalizedAsFilename);

            auto ProjectDir = FPaths::ConvertRelativePathToFull(FPaths::ProjectDir());
            FPaths::NormalizeDirectoryName(ProjectDir);

            if (NOT ProjectDir.IsEmpty() &&
                NormalizedAsFilename.StartsWith(ProjectDir, ESearchCase::IgnoreCase))
            {
                auto ProjectScriptScope = ProjectDir;
                ProjectScriptScope /= TEXT("Script");
                FPaths::NormalizeFilename(ProjectScriptScope);
                return ProjectScriptScope;
            }
        }
#endif
    }

    // ---- On-disk .uasset configs ---------------------------------------------------
    // Use the package mount-point: e.g., a config at `/CkTests/AutoTests/Foo` lives
    // in the CkTests plugin and scopes to "/CkTests/".
    {
        const auto MountPoint = FPackageName::GetPackageMountPoint(Package->GetName()).ToString();
        if (NOT MountPoint.IsEmpty())
        {
            return FString::Printf(TEXT("/%s/"), *MountPoint);
        }
    }

    return FString{};
}

// --------------------------------------------------------------------------------------------------------------------

auto
    UCkAutoTestMapPopulator::
    Find_OrLoad_TargetWorld(
        UCkAutoTestMapConfig* InConfig,
        bool& OutWasLoadedFresh,
        FString& OutSkipReason) const
    -> UWorld*
{
    OutWasLoadedFresh = false;
    OutSkipReason.Reset();

    if (NOT ck::IsValid(InConfig, ck::IsValid_Policy_NullptrOnly{}))
    {
        OutSkipReason = TEXT("Null config");
        return nullptr;
    }

    const auto TargetWorldPath = InConfig->TargetMap.ToSoftObjectPath().GetLongPackageName();
    if (TargetWorldPath.IsEmpty())
    {
        OutSkipReason = TEXT("Target map path is empty");
        return nullptr;
    }

    // Helper: ensure OFPA external actors are loaded AND attached to the level's
    // Actors array. We need this in BOTH Path A (active editor world) and Path B
    // (off-disk LoadPackage) because the editor's normal map-open flow can complete
    // before all external actors are registered with the level, AND between
    // populator syncs the GC can drop the level's refs to OFPA actor instances
    // while keeping the packages loaded. Without an explicit re-attach in both
    // paths, a subsequent sync sees Actors empty, predicts a full re-spawn, and
    // duplicates every actor on disk — corrupting the map (observed in v0.x of
    // the populator code, fixed there for Path B only; Path A regressed with the
    // same shape until this helper was applied to both).
    //
    // Idempotent: on a fresh load the actor is already in Actors (PostLoad added
    // it) and the Contains check short-circuits. Non-OFPA maps have no external
    // packages so the call is a cheap no-op.
    const auto Ensure_ExternalActorsAttached = [](UWorld* InWorld)
    {
        if (NOT ck::IsValid(InWorld, ck::IsValid_Policy_NullptrOnly{}))
        { return; }

        if (auto* Level = InWorld->PersistentLevel.Get();
            ck::IsValid(Level, ck::IsValid_Policy_NullptrOnly{}))
        {
            FExternalPackageHelper::LoadObjectsFromExternalPackages<AActor>(
                Level,
                [Level](AActor* Actor)
                {
                    if (ck::IsValid(Actor, ck::IsValid_Policy_NullptrOnly{}) &&
                        NOT Level->Actors.Contains(Actor))
                    { Level->Actors.Add(Actor); }
                });
        }
    };

    // ---- Path A: target IS the currently-active editor world -----------------------
    // Preferred when it applies — edits become visible to the user immediately, and
    // saves go through the normal Ctrl+S / dirty-state machinery they're used to.
    if (ck::IsValid(GEditor, ck::IsValid_Policy_NullptrOnly{}))
    {
        if (auto* EditorWorld = GEditor->GetEditorWorldContext().World();
            ck::IsValid(EditorWorld, ck::IsValid_Policy_NullptrOnly{}))
        {
            const auto EditorWorldPath = EditorWorld->GetPackage()->GetName();
            if (EditorWorldPath.Equals(TargetWorldPath, ESearchCase::IgnoreCase))
            {
                // Same re-attach the off-disk path needs — see helper comment.
                // Without this, a Path A sync after editor-side GC drops the
                // OFPA actor refs would duplicate the entire test suite.
                Ensure_ExternalActorsAttached(EditorWorld);

                ck::tests_editor::VeryVerbose(
                    TEXT("[CkAutoTest Populator] [{}] Path A — target map is the active editor world."),
                    InConfig->Get_DisplayName());
                OutWasLoadedFresh = false;
                return EditorWorld;
            }
        }
    }

    // ---- Path B: load the unopened target package off-disk -------------------------
    // The package may already be in memory from a previous sync (we don't unload it
    // after first use, by design); LoadPackage returns the existing UPackage in that
    // case and is essentially free.
    auto* Package = LoadPackage(nullptr, *TargetWorldPath, LOAD_None);
    if (NOT ck::IsValid(Package, ck::IsValid_Policy_NullptrOnly{}))
    {
        OutSkipReason = FString::Printf(TEXT("LoadPackage failed for '%s'"), *TargetWorldPath);
        ck::tests_editor::Warning(
            TEXT("[CkAutoTest Populator] [{}] {}"),
            InConfig->Get_DisplayName(), OutSkipReason);
        return nullptr;
    }

    auto* World = UWorld::FindWorldInPackage(Package);
    if (NOT ck::IsValid(World, ck::IsValid_Policy_NullptrOnly{}))
    {
        OutSkipReason = FString::Printf(TEXT("Package '%s' has no UWorld inside"), *TargetWorldPath);
        ck::tests_editor::Warning(
            TEXT("[CkAutoTest Populator] [{}] {}"),
            InConfig->Get_DisplayName(), OutSkipReason);
        return nullptr;
    }

    // Same re-attach the editor-world path needs — see helper comment above.
    // Without this, a subsequent Path B sync after GC drops the level's refs to
    // already-loaded OFPA actor instances would see Actors empty and duplicate
    // the entire test suite.
    Ensure_ExternalActorsAttached(World);

    ck::tests_editor::VeryVerbose(
        TEXT("[CkAutoTest Populator] [{}] Path B — loaded target map off-disk: '{}'."),
        InConfig->Get_DisplayName(), TargetWorldPath);

    OutWasLoadedFresh = true;
    return World;
}

// --------------------------------------------------------------------------------------------------------------------
