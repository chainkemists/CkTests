#pragma once

#include "UObject/Object.h"

#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/Registry/CkRegistry_Handle.h"

#include "CkRegistry_LifetimeInversion_Holder.generated.h"

// --------------------------------------------------------------------------------------------------------------------
// Synthetic UObject mirroring UCk_Processor_Script_Base_UE's pattern: a
// UPROPERTY field holding a registry-bound handle that the test can deliberately
// leave dangling past the registry's destruction. Used only by the
// lifetime-inversion test.
//
// Two fields exercise two layers of the migration's safety claim:
//   * SlotHandle (FCk_RegistryHandle, 12-byte POD) — the slot-table layer.
//     Trivial dtor; characterizes the storage-side invariant.
//   * Handle (FCk_Handle) — the high-level handle layer. Non-trivial dtor
//     because of TWeakObjectPtr fields. Characterizes the actual UObject
//     UPROPERTY pattern that triggered the original lifetime-inversion bug
//     (a UObject's handle field outliving the registry). The migration's
//     load-bearing claim is that this dtor is now safe even if the slot has
//     been Free'd before GC reaches the holder.
//
// Fields are intentionally public UPROPERTYs: this is a test-only fixture,
// and the project's _-prefix-with-CK_PROPERTY-accessor convention applies to
// USTRUCTs (which carry CK_GENERATED_BODY), not UCLASSes.
// --------------------------------------------------------------------------------------------------------------------

UCLASS()
class CKTESTS_API UCk_LifetimeInversion_Holder : public UObject
{
    GENERATED_BODY()

public:
    UPROPERTY()
    FCk_RegistryHandle SlotHandle;

    UPROPERTY()
    FCk_Handle Handle;
};
