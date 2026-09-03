// The neutral area-policy registry is what a provider without UNavArea has to go on. These pin the
// two properties that make it usable: it answers for every area tag Recast can paint, and exactly
// one of those areas means "not walkable" rather than "expensive". Both registries seed themselves
// from parked registrars on first read, so reading them here is also the coverage that the seeding
// actually runs.

#include "CkCrowd/CkCrowd_NavGameplayTags.h"

#include "CkNavigation/NavSurface/CkNavSurface_AreaPolicy.h"
#include "CkNavigation/NavSurface/CkNavSurface_GameplayTags.h"
#include "CkNavigation/NavSurface/Recast/CkNavSurface_RecastAdapter.h"

#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_nav_surface_area_policy
{
    auto Get_WalkabilityAreaTags() -> TArray<FGameplayTag>
    {
        auto WalkabilityTags = TArray<FGameplayTag>{};

        for (const auto& AreaTag : ck::nav_surface_recast::Get_RegisteredAreaTags())
        {
            const auto Policy = ck::nav_surface::TryGet_AreaPolicy(AreaTag);

            if (NOT Policy.IsSet())
            { continue; }

            if (Policy->Get_Kind() == ECk_NavSurface_AreaPolicyKind::Walkability)
            { WalkabilityTags.Add(AreaTag); }
        }

        return WalkabilityTags;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_NavSurface_AreaPolicy_EveryRecastAreaTagHasAPolicy,
    "CkTests.UnitTests.CkNavigation.NavSurfaceAreaPolicy.EveryRecastAreaTagHasAPolicy",
    kCkUnitTestFlags)

bool FCkTest_NavSurface_AreaPolicy_EveryRecastAreaTagHasAPolicy::RunTest(const FString& Parameters)
{
    const auto RecastAreaTags = ck::nav_surface_recast::Get_RegisteredAreaTags();

    TestTrue(TEXT("the Recast area table seeded at least one area tag"), RecastAreaTags.Num() > 0);

    for (const auto& AreaTag : RecastAreaTags)
    {
        const auto Policy = ck::nav_surface::TryGet_AreaPolicy(AreaTag);

        TestTrue(*FString::Printf(
            TEXT("area tag [%s] resolves to a provider-neutral policy"), *AreaTag.ToString()),
            Policy.IsSet());
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_NavSurface_AreaPolicy_ImpassableIsTheOnlyWalkabilityArea,
    "CkTests.UnitTests.CkNavigation.NavSurfaceAreaPolicy.ImpassableIsTheOnlyWalkabilityArea",
    kCkUnitTestFlags)

bool FCkTest_NavSurface_AreaPolicy_ImpassableIsTheOnlyWalkabilityArea::RunTest(const FString& Parameters)
{
    const auto ImpassablePolicy = ck::nav_surface::TryGet_AreaPolicy(TAG_Nav_Area_Impassable);

    TestTrue(TEXT("the impassable area registered a policy"), ImpassablePolicy.IsSet());

    if (ImpassablePolicy.IsSet())
    {
        TestEqual(TEXT("the impassable area means walkability, not cost"),
            ImpassablePolicy->Get_Kind(), ECk_NavSurface_AreaPolicyKind::Walkability);
    }

    const auto WalkabilityTags = ck_test_nav_surface_area_policy::Get_WalkabilityAreaTags();

    TestEqual(TEXT("exactly one registered area removes walkability"), WalkabilityTags.Num(), 1);

    if (WalkabilityTags.Num() == 1)
    {
        TestEqual(TEXT("and that area is the impassable one"),
            WalkabilityTags[0].ToString(), TAG_Nav_Area_Impassable.GetTag().ToString());
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_NavSurface_AreaPolicy_UnregisteredTagYieldsUnset,
    "CkTests.UnitTests.CkNavigation.NavSurfaceAreaPolicy.UnregisteredTagYieldsUnset",
    kCkUnitTestFlags)

bool FCkTest_NavSurface_AreaPolicy_UnregisteredTagYieldsUnset::RunTest(const FString& Parameters)
{
    // A real, live tag that names a query FILTER rather than an area — so this asks the registry
    // about something it genuinely has no answer for, not about a malformed tag it rejects early.
    const auto FilterPolicy = ck::nav_surface::TryGet_AreaPolicy(TAG_Nav_Filter_Crowd_AvoidStandingCrowds);

    TestFalse(TEXT("a tag that names no area resolves to no policy"), FilterPolicy.IsSet());

    const auto EmptyTagPolicy = ck::nav_surface::TryGet_AreaPolicy(FGameplayTag{});

    TestFalse(TEXT("an empty tag resolves to no policy"), EmptyTagPolicy.IsSet());

    return true;
}
