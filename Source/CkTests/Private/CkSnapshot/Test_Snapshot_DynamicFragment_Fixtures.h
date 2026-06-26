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

// --------------------------------------------------------------------------------------------------------------------

// A SECOND, distinct handle-bearing dynamic-fragment type. Used to prove that MULTIPLE dynamic-fragment types on the
// SAME entity (each in its own named storage) all survive a round-trip -- the core of the named-storage enumeration.
USTRUCT()
struct FCk_Test_DynFrag_OtherHandle
{
    GENERATED_BODY()

    UPROPERTY(SaveGame)
    FCk_Handle OtherTarget;
};

// --------------------------------------------------------------------------------------------------------------------

// A dynamic fragment with NO handles -- isolates the data round-trip from handle remap.
USTRUCT()
struct FCk_Test_DynFrag_PureData
{
    GENERATED_BODY()

    UPROPERTY(SaveGame)
    int32 Count = 0;

    UPROPERTY(SaveGame)
    FString Label;
};

// --------------------------------------------------------------------------------------------------------------------

// A nested struct holding a handle, plus a wrapper that contains it -- exercises the recursive handle walk
// (a handle one struct level deep must still be remapped).
USTRUCT()
struct FCk_Test_DynFrag_Inner
{
    GENERATED_BODY()

    UPROPERTY(SaveGame)
    FCk_Handle InnerHandle;
};

USTRUCT()
struct FCk_Test_DynFrag_Nested
{
    GENERATED_BODY()

    UPROPERTY(SaveGame)
    int32 Tag = 0;

    UPROPERTY(SaveGame)
    FCk_Test_DynFrag_Inner Inner;
};
