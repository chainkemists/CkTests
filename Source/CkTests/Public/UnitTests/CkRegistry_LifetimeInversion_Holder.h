#pragma once

#include "UObject/Object.h"

#include "CkEcs/Registry/CkRegistry_Handle.h"

#include "CkRegistry_LifetimeInversion_Holder.generated.h"

// --------------------------------------------------------------------------------------------------------------------
// Synthetic UObject mirroring UCk_Processor_Script_Base_UE's pattern: a
// UPROPERTY field holding a registry-bound handle that the test can deliberately
// leave dangling past the registry's destruction. Used only by the
// lifetime-inversion test.
//
// During Phase 1 of the generational-handle migration this only carries the
// raw FCk_RegistryHandle — characterizing the slot-table-level invariant. Once
// FCk_Handle is migrated (Phase 2+), this struct will be extended (or replaced)
// with a full FCk_Handle field to exercise the higher-level handle dtor.
//
// Field is intentionally a public UPROPERTY: this is a test-only fixture, and
// the project's _-prefix-with-CK_PROPERTY-accessor convention applies to
// USTRUCTs (which carry CK_GENERATED_BODY), not UCLASSes.
// --------------------------------------------------------------------------------------------------------------------

UCLASS()
class CKTESTS_API UCk_LifetimeInversion_Holder : public UObject
{
    GENERATED_BODY()

public:
    UPROPERTY()
    FCk_RegistryHandle SlotHandle;
};
