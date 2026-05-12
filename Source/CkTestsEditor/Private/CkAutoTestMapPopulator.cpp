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
#include <HAL/IConsoleManager.h>
#include <Interfaces/IPluginManager.h>
#include <ISourceControlModule.h>
#include <Misc/App.h>
#include <Misc/PackageName.h>
#include <Misc/Paths.h>
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
    // a delta AND the underlying .umap is read-only on disk, attempt an SCC checkout;
    // if that also fails, surface the failure unmissably and skip. Without this, the
    // populator's downstream loops would mutate the in-memory world, then SavePackages
    // would fail silently against the locked file — exactly the silent failure mode
    // this work item exists to eliminate.
    //
    // The predict pass is precise (mirrors the spawn-loop conditions) so we don't fire
    // a notification on every AS recompile when the locked file happens to already be
    // in sync.
    const auto Predict_HasDelta = [&]() -> bool
    {
        for (auto* Class : WantedClasses)
        {
            const auto* ExistingActors = CurrentByClass.Find(Class);
            if (ExistingActors == nullptr || ExistingActors->Num() == 0)
            { return true; }
            if (ExistingActors->Num() > 1)
            { return true; }
            if (auto* Keeper = (*ExistingActors)[0];
                ck::IsValid(Keeper, ck::IsValid_Policy_NullptrOnly{}))
            {
                if (Keeper->GetActorLabel() != Compute_ExpectedLabel(Class))
                { return true; }
            }
        }
        for (const auto& Pair : CurrentByClass)
        {
            if (NOT WantedSet.Contains(Pair.Key))
            { return true; }
        }
        return false;
    };

    if (Predict_HasDelta())
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
    for (const auto& Pair : CurrentByClass)
    {
        if (WantedSet.Contains(Pair.Key))
        { continue; }

        for (auto* Actor : Pair.Value)
        {
            if (NOT ck::IsValid(Actor, ck::IsValid_Policy_NullptrOnly{}))
            { continue; }
            CurrentWorld->DestroyActor(Actor);
            ++Result.Removed;
        }
    }

    // Compose the "needs save" signal from two sources:
    //   1. Our sync logic produced a delta (spawn/remove/relabel). Standard case.
    //   2. Path B's LoadPackage induced dirty state without our help — typically the
    //      level file referenced a class that no longer exists, UE silently dropped
    //      the actor entry, and marked the package dirty. The level on disk still
    //      contains the dead reference until we save here.
    const auto bHasMyDelta = Result.Has_Delta();
    const auto bLoadInducedDirty = bWasLoadedFresh && WasDirtyOnEntry;

    if (bHasMyDelta)
    {
        Package->MarkPackageDirty();
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

    auto PackagesToSave = TArray<UPackage*>{Package};
    const auto bSaved = UEditorLoadingAndSavingUtils::SavePackages(PackagesToSave, /*bOnlyDirty=*/true);
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
            // We deliberately do NOT use just "/<ProjectName>/" the way the plugin
            // branch uses "/<PluginName>/": the project name appears in the path
            // ABOVE the Plugins/ folder (e.g. "D:/Repos/BusterBlock/Plugins/CkTests/
            // Script/...as" contains "/BusterBlock/"), so a bare project-name scope
            // would over-match into every nested plugin's tests. Anchoring to
            // "<ProjectName>/Script/" keeps the match scoped to the project's own
            // source tree because plugin paths go through "<ProjectName>/Plugins/"
            // instead. Note this means project-side C++ tests under Source/ are NOT
            // auto-scoped; if a project ever needs that, set ClassScanRoot explicitly.
            auto NormalizedAsFilename = FPaths::ConvertRelativePathToFull(AsFilename);
            FPaths::NormalizeFilename(NormalizedAsFilename);

            auto ProjectDir = FPaths::ConvertRelativePathToFull(FPaths::ProjectDir());
            FPaths::NormalizeDirectoryName(ProjectDir);

            if (NOT ProjectDir.IsEmpty() &&
                NormalizedAsFilename.StartsWith(ProjectDir, ESearchCase::IgnoreCase))
            {
                return FString::Printf(TEXT("%s/Script/"), FApp::GetProjectName());
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

    // Load external-actor packages into the level. With One File Per Actor (OFPA)
    // enabled on a map, each placed actor lives in its own __ExternalActors__/<...>/Guid.uasset
    // package, NOT in the .umap's persistent-level actor list. LoadPackage of the
    // .umap alone leaves PersistentLevel->Actors empty for OFPA maps, which would
    // cause the populator to treat every existing wrapper as missing-from-map
    // (duplicate spawn) and every newly-emitted wrapper as orphan (delete-then-
    // respawn churn on the external .uasset files). The editor's normal map-open
    // flow loads external actors implicitly; off-disk loads need to do it
    // explicitly. The callback is intentionally empty — we just need the side
    // effect of population, not per-actor work.
    if (auto* Level = World->PersistentLevel.Get();
        ck::IsValid(Level, ck::IsValid_Policy_NullptrOnly{}))
    {
        FExternalPackageHelper::LoadObjectsFromExternalPackages<AActor>(
            Level, [](AActor*) {});
    }

    ck::tests_editor::VeryVerbose(
        TEXT("[CkAutoTest Populator] [{}] Path B — loaded target map off-disk: '{}'."),
        InConfig->Get_DisplayName(), TargetWorldPath);

    OutWasLoadedFresh = true;
    return World;
}

// --------------------------------------------------------------------------------------------------------------------
