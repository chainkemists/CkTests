#include "CkTests/Net/CkAutoTest_EntityTagSeedProbe.h"

#include "CkEntityTag/CkEntityTag_Utils.h"

// --------------------------------------------------------------------------------------------------------------------

namespace ck::auto_test::entity_tag_seed
{
    auto
        Get_ConstructSeedTag()
        -> FName
    {
        return FName{TEXT("EntityTag.Parity.ConstructSeed")};
    }
}

// --------------------------------------------------------------------------------------------------------------------

auto
    UCk_AutoTest_EntityTagSeed_EntityScript_UE::
    Construct(
        FCk_Handle& InHandle,
        const FInstancedStruct& InSpawnParams)
    -> ECk_EntityScript_ConstructionFlow
{
    // Super composes the M2b probe's replicated features + the actor<->entity bridge (needed for the respawn path).
    const auto Flow = Super::Construct(InHandle, InSpawnParams);

    // Seed exactly one EntityTag in Construct. This deferred Add re-runs on every v3 rebuild, so it is the fixture the
    // parity gate needs: the seed and the HydrationApply-restored set converge on the same entity on load, where a
    // broken applier would MERGE (inflate) rather than REPLACE. When the seed is the entity's only tag and gets removed
    // pre-save, Produce emits UNSET and this same Add resurrects it on load (documented "absence is ambiguous").
    UCk_Utils_EntityTag_UE::Add(InHandle, ck::auto_test::entity_tag_seed::Get_ConstructSeedTag());

    return Flow;
}

// --------------------------------------------------------------------------------------------------------------------

ACk_AutoTest_EntityTagSeedProbe::
    ACk_AutoTest_EntityTagSeedProbe()
{
    // Reuse ACk_AutoTest_NetSubject_M2bProbe's non-replicated respawn wiring; only swap in the seed entity-script.
    _EntityScriptClass = UCk_AutoTest_EntityTagSeed_EntityScript_UE::StaticClass();
}

// --------------------------------------------------------------------------------------------------------------------

ACk_AutoTest_EntityTagResurrectProbe::
    ACk_AutoTest_EntityTagResurrectProbe()
{
    _EntityScriptClass = UCk_AutoTest_EntityTagSeed_EntityScript_UE::StaticClass();
}

// --------------------------------------------------------------------------------------------------------------------
