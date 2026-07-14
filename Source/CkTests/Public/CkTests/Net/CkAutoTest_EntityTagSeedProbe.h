#pragma once

#include "CoreMinimal.h"

#include "CkTests/Net/CkAutoTest_NetSubject_M2bProbe.h"

#include "CkAutoTest_EntityTagSeedProbe.generated.h"

// --------------------------------------------------------------------------------------------------------------------
//
// EntityTag-parity gate fixtures. Both probes reuse the M2b-1 level-reload machinery (bReplicates=false,
// Get_IsSnapshotRespawnable -> true) but their Construct SEEDS one EntityTag tag — the property the plain M2b probe
// deliberately lacks. That construct-seed is what makes them the fixture for the merge-bug: on a v3 load the rebuilt
// entity re-runs Construct (re-Adding the seed via a deferred request) at the same time HydrationApply reconstitutes
// the saved set, so a broken applier would MERGE (inflate) the seed instead of REPLACING.
//
// Two actor classes, one shared seed entity-script, so the parity gate can find each instance unambiguously by class
// (the base ACk_AutoTest_NetSubject::Find assumes one subject per world). They differ only in identity + which runtime
// mutations the spec drives on them:
//   - SeedProbe     : keeps its seed alongside runtime tags -> exercises no-inflation across TWO save/load cycles.
//   - ResurrectProbe: has its seed runtime-removed pre-save (Produce UNSET) -> exercises construct-seed resurrection.
//
// --------------------------------------------------------------------------------------------------------------------

namespace ck::auto_test::entity_tag_seed
{
    // The single EntityTag both probes' Construct seeds. Referenced by the parity gate so the production seed and the
    // test's assertions can never drift. A raw FName — EntityTag::Add takes any non-None FName, no ini registration.
    CKTESTS_API auto Get_ConstructSeedTag() -> FName;
}

// --------------------------------------------------------------------------------------------------------------------

UCLASS()
class CKTESTS_API UCk_AutoTest_EntityTagSeed_EntityScript_UE : public UCk_AutoTest_NetSubject_M2bProbe_EntityScript_UE
{
    GENERATED_BODY()

public:
    virtual auto
    Construct(
        FCk_Handle& InHandle,
        const FInstancedStruct& InSpawnParams) -> ECk_EntityScript_ConstructionFlow override;
};

// --------------------------------------------------------------------------------------------------------------------

UCLASS(BlueprintType)
class CKTESTS_API ACk_AutoTest_EntityTagSeedProbe : public ACk_AutoTest_NetSubject_M2bProbe
{
    GENERATED_BODY()

public:
    ACk_AutoTest_EntityTagSeedProbe();
};

// --------------------------------------------------------------------------------------------------------------------

UCLASS(BlueprintType)
class CKTESTS_API ACk_AutoTest_EntityTagResurrectProbe : public ACk_AutoTest_NetSubject_M2bProbe
{
    GENERATED_BODY()

public:
    ACk_AutoTest_EntityTagResurrectProbe();
};

// --------------------------------------------------------------------------------------------------------------------
