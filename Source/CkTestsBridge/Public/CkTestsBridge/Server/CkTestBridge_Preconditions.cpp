#include "CkTestBridge_Preconditions.h"

#include "CkTestsBridge_Log.h"

#include "CkCore/Ensure/CkEnsure.h"
#include "CkCore/Format/CkFormat.h"
#include "CkCore/Macros/CkMacros.h"

#include <Editor.h>
#include <Engine/Engine.h>
#include <Engine/World.h>
#include <HAL/PlatformProcess.h>
#include <UObject/Package.h>
#include <UObject/UObjectGlobals.h>
#include <UObject/UObjectIterator.h>

#if WITH_ANGELSCRIPT_CK
#include "AngelscriptManager.h"
#endif

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_bridge_preconditions
{
    static auto
    Is_PieActive()
        -> bool
    {
        // A run must never take over an interactive PIE session. GEditor->PlayWorld is the live PIE world (null
        // when not playing); IsPlaySessionInProgress() also covers the request/teardown edges.
        if (GEditor == nullptr)
        { return false; }

        return GEditor->PlayWorld != nullptr || GEditor->IsPlaySessionInProgress();
    }

    static auto
    Collect_DirtyPackages(
        TArray<FString>& OutDirtyPackages)
        -> void
    {
        const auto* TransientPackage = GetTransientPackage();

        for (auto PackageIt = TObjectIterator<UPackage>{}; PackageIt; ++PackageIt)
        {
            auto* Package = *PackageIt;
            if (Package == nullptr || Package == TransientPackage)
            { continue; }

            if (NOT Package->IsDirty())
            { continue; }

            const auto Name = Package->GetName();

            // Script and transient packages are never on-disk work the user could lose.
            if (Name.StartsWith(TEXT("/Script")) || Name.StartsWith(TEXT("/Engine/Transient")))
            { continue; }

            OutDirtyPackages.Add(Name);
        }
    }

    // The automation map-load is safe when the only unsaved work IS the AutoTests map automation would open.
    // [VERIFY] host-agnostic proxy: package name contains "AutoTests" (BB's map is AutoTests_BB_MAP). A host with a
    // differently-named automation map would need this widened.
    static auto
    Are_AllDirtyPackagesTheAutoTestsMap(
        const TArray<FString>& InDirtyPackages)
        -> bool
    {
        if (InDirtyPackages.Num() == 0)
        { return true; }

        for (const auto& Name : InDirtyPackages)
        {
            if (NOT Name.Contains(TEXT("AutoTests")))
            { return false; }
        }
        return true;
    }
}

// --------------------------------------------------------------------------------------------------------------------

auto
    FCk_TestBridge_Preconditions::
    Evaluate(
        bool InAllowDirtyWorld,
        bool InBusy,
        FCk_TestBridge_Env& OutEnv)
    -> TOptional<FString>
{
    using namespace ck_test_bridge_preconditions;

    OutEnv = FCk_TestBridge_Env{};
    OutEnv.Live      = true;
    OutEnv.EditorPid = static_cast<int32>(FPlatformProcess::GetCurrentProcessId());

#if WITH_ANGELSCRIPT_CK
    if (FAngelscriptManager::IsInitialized())
    {
        const auto& Manager = FAngelscriptManager::Get();

        // [VERIFY] Public members on FAngelscriptManager (5.7.4 fork, AngelscriptManager.h:343-347). Semantics
        // inferred from names, NOT runtime-confirmed:
        //   FileChangesDetectedForReload / FileDeletionsDetectedForReload — .as edits noticed on disk but not yet
        //     hot-reloaded => a run would exercise stale bytecode.
        //   bDidInitialCompileSucceed — false after a compile error.
        // If a run ever proceeds against known-stale AS, revisit whether QueuedFullReloadFiles (private) or a
        // per-module bCompileError scan is the truer signal.
        OutEnv.AsPendingFullReload =
            Manager.FileChangesDetectedForReload.Num() > 0 ||
            Manager.FileDeletionsDetectedForReload.Num() > 0;
        OutEnv.AsCompileErrors = NOT Manager.bDidInitialCompileSucceed;
    }
#endif

    Collect_DirtyPackages(OutEnv.DirtyPackages);

    if (InBusy)
    { return FString{TEXT("busy")}; }

    if (Is_PieActive())
    { return FString{TEXT("pieActive")}; }

    if (OutEnv.AsPendingFullReload)
    { return FString{TEXT("asPendingFullReload")}; }

    if (OutEnv.AsCompileErrors)
    { return FString{TEXT("asCompileError")}; }

    if (NOT InAllowDirtyWorld && NOT Are_AllDirtyPackagesTheAutoTestsMap(OutEnv.DirtyPackages))
    { return FString{TEXT("dirtyWorld")}; }

    return {};
}

// --------------------------------------------------------------------------------------------------------------------
