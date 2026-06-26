#pragma once

#include "CkEcs/Handle/CkHandle.h"

#include "Test_Snapshot_DynamicFragment_Fixtures.generated.h"

// --------------------------------------------------------------------------------------------------------------------

// Test-only USTRUCT used AS a dynamic fragment (the same mechanism AngelScript fragments use): a UScriptStruct
// wrapped in an FInstancedStruct and added via UCk_Utils_DynamicFragment_UE::Add_Fragment. Mirrors the shape of a
// real AS fragment such as FBb_Fragment_QuickUseSelector — scalar data plus a cross-entity handle. The companion
// test (Test_Snapshot_DynamicFragment_HandleRemap_RoundTrip.cpp) uses it to prove whether a dynamic fragment
// survives a CkSnapshot round-trip AND whether its handle is remapped to the restored entity.
USTRUCT()
struct FCk_Test_DynFrag_WithHandle
{
    GENERATED_BODY()

    // Plain scalar — verifies the fragment's non-handle data round-trips. SaveGame is the real CPF_SaveGame
    // specifier (NOT meta=(SaveGame), which only writes a metadata string — see the SaveKey round-trip test).
    UPROPERTY(SaveGame)
    int32 Marker = 0;

    // Cross-entity handle — verifies single-handle remap on restore (the entity it points at gets a new id post-wipe).
    UPROPERTY(SaveGame)
    FCk_Handle TargetHandle;

    // Array of cross-entity handles — mirrors FBb_Fragment_QuickUseSelector's TArray<FCk_Handle_Inventory>.
    // Verifies that handles inside a container remap (and that the array length round-trips so save/load stay aligned).
    UPROPERTY(SaveGame)
    TArray<FCk_Handle> TargetArray;
};
