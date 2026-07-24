#pragma once

#include "CoreMinimal.h"

#include <Misc/Optional.h>

// --------------------------------------------------------------------------------------------------------------------
// Live-editor gate for a test run. The bridge must NEVER hijack a user's editor into a PIE takeover just because a
// request file appeared — so this refuses when PIE is active, when AngelScript has un-hot-reloaded edits or compile
// errors (a run would exercise stale bytecode), when the editor holds unsaved map/content work (the automation
// map-load would discard or prompt), or when a run is already in flight. The refusal token maps 1:1 to the result
// schema's refusalReason.
// --------------------------------------------------------------------------------------------------------------------

// Environment snapshot mirrored into every result's "env" object, whether the run is accepted or refused.
struct FCk_TestBridge_Env
{
    bool            Live = true;
    int32           EditorPid = 0;
    bool            AsPendingFullReload = false;
    bool            AsCompileErrors = false;
    TArray<FString> DirtyPackages;
};

// --------------------------------------------------------------------------------------------------------------------

class CKTESTSBRIDGE_API FCk_TestBridge_Preconditions
{
public:
    // Always fills OutEnv. Returns the refusal token (pieActive | asPendingFullReload | asCompileError | dirtyWorld
    // | busy), or unset if the run may proceed. InBusy is the processor's own "a run is already active" flag.
    static auto
    Evaluate(
        bool InAllowDirtyWorld,
        bool InBusy,
        FCk_TestBridge_Env& OutEnv) -> TOptional<FString>;
};

// --------------------------------------------------------------------------------------------------------------------
