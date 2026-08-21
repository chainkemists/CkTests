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
        Defer_SyncToNextTick();
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
    Defer_SyncToNextTick();
}

auto
    UCkAutoTestMapPopulator::
    Defer_SyncToNextTick()
    -> void
{
    // FTSTicker is always available regardless of editor init state, unlike
    // GEditor->GetTimerManager() which trips a check inside ToSharedRef if called
    // before the timer manager has been constructed (early in UEditorEngine::Init).
    auto WeakSelf = TWeakObjectPtr<UCkAutoTestMapPopulator>{this};
    FTSTicker::GetCoreTicker().AddTicker(FTickerDelegate::CreateLambda(
        [WeakSelf](float /*DeltaSeconds*/)
        {
            if (auto* Self = WeakSelf.Get();
                ck::IsValid(Self, ck::IsValid_Policy_NullptrOnly{}))
            {
                Self->Sync_AllConfigs();
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
    Defer_SyncToNextTick();
}

// --------------------------------------------------------------------------------------------------------------------

void UCkAutoTestMapPopulator::Sync_AllConfigs()
{
    ck::tests_editor::Log(TEXT("[CkAutoTest Populator] === Sync_AllConfigs ==="));

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

    for (auto* Config : Configs)
    {
        const auto Result = Sync_Config_Internal(Config);
        TotalSpawned += Result.Spawned;
        TotalRemoved += Result.Removed;
        TotalRelabeled += Result.Relabeled;
        if (Result.bSkipped) { ++TotalSkipped; }
    }

    ck::tests_editor::Log(
        TEXT("[CkAutoTest Populator] Done — {} configs, {} spawned, {} removed, {} relabeled, {} skipped."),
        Configs.Num(), TotalSpawned, TotalRemoved, TotalRelabeled, TotalSkipped);
}

FCkAutoTestSyncResult UCkAutoTestMapPopulator::Sync_Config(UCkAutoTestMapConfig* InConfig)
{
    return Sync_Config_Internal(InConfig);
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
        UCkAutoTestMapConfig* InConfig)
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
        auto Label = InClass->GetName();
        if (Label.EndsWith(TEXT("_Actor"), ESearchCase::IgnoreCase))
        { Label.LeftChopInline(FString(TEXT("_Actor")).Len(), EAllowShrinking::No); }
        return Label;
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
                return Result;
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

                auto ExpectedLabel = WrapperClassName;
                ExpectedLabel.LeftChopInline(FString(TEXT("_Actor")).Len(), EAllowShrinking::No);

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
        return Result;
    }

    // ---- Auto-save guard ------------------------------------------------------------
    if (NOT InConfig->bAutoSaveOnSync)
    {
        ck::tests_editor::Log(TEXT("[CkAutoTest Populator] Auto-save disabled by config — leaving map dirty for manual save."));
        return Result;
    }

    // Path A's safety check: don't silently commit a user's in-flight edits.
    // Path B doesn't trip this — the only dirty source is the load itself, which
    // we explicitly want to persist.
    if (NOT bWasLoadedFresh && WasDirtyOnEntry)
    {
        ck::tests_editor::Warning(
            TEXT("[CkAutoTest Populator] [{}] Map was dirty before sync — leaving for manual save (unrelated edits would be silently committed otherwise)."),
            InConfig->Get_DisplayName());
        return Result;
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

    return Result;
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
