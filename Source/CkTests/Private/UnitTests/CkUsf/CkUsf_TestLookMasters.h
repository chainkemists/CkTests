#pragma once

// Where the CkUsf generation tests put the masters they generate.
//
// NOT the shipped /CkFoundation/CkUsf/GeneratedLooks/: the toolbox spreads a real-RHI run over concurrent
// headless editors, and two of them SavePackage-ing the same .uasset takes both processes down with
// appError(ERROR_ALREADY_EXISTS). The process id makes the root unique per lane, so no two lanes can ever
// target the same file, and a test run never rewrites shipped content.
//
// The rule this encodes: NO test may generate into the shipped root. A new generation test passes
// Get_TestPackageRoot() to ck::usf_editor::Generate_* and deletes its masters with the helper below.

#if WITH_EDITOR

#include "CoreMinimal.h"

#include "HAL/FileManager.h"
#include "HAL/PlatformProcess.h"
#include "Misc/PackageName.h"
#include "Misc/Paths.h"

#include "CkCore/Macros/CkMacros.h"

#include "CkUsf/LookDefinition/CkUsf_LookDefinition_Naming.h"

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_usf
{
    inline auto Get_TestPackageRoot() -> FString
    {
        return FString::Printf(TEXT("/CkFoundation/CkUsf/GeneratedLooksTest/P%u"),
            FPlatformProcess::GetCurrentProcessId());
    }

    // Generated masters are real packages on disk. Test subjects are fixtures, not content, so the file is
    // removed again; the in-memory package stays and the generator's idempotent refresh path handles a
    // second run inside the same editor session.
    inline auto Delete_TestGeneratedMaster(const FName InLookName) -> bool
    {
        const auto FileName = FPackageName::LongPackageNameToFilename(
            ck::usf::Get_GeneratedMasterPackagePath(InLookName, Get_TestPackageRoot()),
            FPackageName::GetAssetPackageExtension());

        if (NOT IFileManager::Get().FileExists(*FileName))
        { return true; }

        constexpr auto RequireExists = false;
        constexpr auto EvenIfReadOnly = true;
        const auto Deleted = IFileManager::Get().Delete(*FileName, RequireExists, EvenIfReadOnly);

        // Succeeds only once the lane's directory is empty, which is exactly when it should go.
        constexpr auto DirectoryRequireExists = false;
        constexpr auto DeleteTree = false;
        IFileManager::Get().DeleteDirectory(*FPaths::GetPath(FileName), DirectoryRequireExists, DeleteTree);

        return Deleted;
    }
}

// --------------------------------------------------------------------------------------------------------------------

#endif // WITH_EDITOR
