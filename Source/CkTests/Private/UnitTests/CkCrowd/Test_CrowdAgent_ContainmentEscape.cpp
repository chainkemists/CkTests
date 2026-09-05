// What the shadow run's per-frame containment counter is allowed to count.
//
// The producer lives at the crowd's single Transform writer and reaches two provider capability
// tables through the neutral facade, so the ACT of counting needs a world, two registered providers
// and a published surface behind each - a PIE fixture, not a bare registry. What is pinned here is
// the DECISION that producer makes, which is a pure function of the two projection verdicts and is
// therefore statable exactly: the pair (active, shadow) is an escape when precisely one of them
// found walkable ground.
//
// The negative half carries the weight. A counter that also rose when both providers agreed the
// agent was in free space would fold the grounding report's own subject - an agent off every
// surface - into a divergence measurement, and every off-mesh walker in a shadow run would read as
// two providers disagreeing when they agree completely.

#include "CkCrowd/Agent/CkCrowdAgent_ConstrainToNavmesh_Processor.h"

#include "CkNavigation/NavSurface/CkNavSurface_Fragment_Data.h"

#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_tests_crowd_containment_escape
{
    // Every status the neutral projection can answer with, listed rather than sampled. The
    // static_assert below is what stops a status quietly joining the enum and being swept as "not
    // ground" by omission: the sweep would still pass, having never asked about the new value, and
    // the one reading it needs is exactly the reading nobody would think to add.
    constexpr ECk_NavSurface_QueryStatus kEveryStatus[] =
    {
        ECk_NavSurface_QueryStatus::Success,
        ECk_NavSurface_QueryStatus::NoSurface,
        ECk_NavSurface_QueryStatus::Unbuilt,
        ECk_NavSurface_QueryStatus::Blocked,
        ECk_NavSurface_QueryStatus::NoProvider
    };

    // Derived from the enum's last enumerator rather than restated, so the count cannot be updated
    // without the enum having moved.
    constexpr auto kQueryStatusCount =
        static_cast<int32>(ECk_NavSurface_QueryStatus::NoProvider) + 1;

    static_assert(static_cast<int32>(UE_ARRAY_COUNT(kEveryStatus)) == kQueryStatusCount,
        "ECk_NavSurface_QueryStatus gained or lost a value - the sweep above no longer covers it");

    auto Get_IsEscape(
        ECk_NavSurface_QueryStatus InActiveStatus,
        ECk_NavSurface_QueryStatus InShadowStatus) -> bool
    {
        return ck::FProcessor_CrowdAgent_ConstrainToNavmesh::Get_IsContainmentEscape(
            InActiveStatus, InShadowStatus);
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Crowd_ContainmentEscape_SplitVerdict,
    "CkTests.UnitTests.CkCrowd.ContainmentEscape.OnlyASplitVerdictCounts",
    kCkUnitTestFlags)

bool FCkTest_Crowd_ContainmentEscape_SplitVerdict::RunTest(const FString& Parameters)
{
    using namespace ck_tests_crowd_containment_escape;

    TestTrue(TEXT("ground under the agent on the active provider and none on the shadow one is an escape"),
        Get_IsEscape(ECk_NavSurface_QueryStatus::Success, ECk_NavSurface_QueryStatus::NoSurface));

    // The other direction is the one a coverage gap in the SHADOW field would never produce, and it
    // is exactly what a shadow field covering ground the active provider does not is: still a
    // disagreement about containment, still counted.
    TestTrue(TEXT("and the same split the other way round is an escape too"),
        Get_IsEscape(ECk_NavSurface_QueryStatus::NoSurface, ECk_NavSurface_QueryStatus::Success));

    TestFalse(TEXT("two providers that both found ground agree, and agreement is never an escape"),
        Get_IsEscape(ECk_NavSurface_QueryStatus::Success, ECk_NavSurface_QueryStatus::Success));

    // An agent genuinely in free space is the grounding report's subject, not the shadow report's.
    TestFalse(TEXT("two providers that both found nothing agree just as completely"),
        Get_IsEscape(ECk_NavSurface_QueryStatus::NoSurface, ECk_NavSurface_QueryStatus::NoSurface));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Crowd_ContainmentEscape_OnlySuccessCountsAsGround,
    "CkTests.UnitTests.CkCrowd.ContainmentEscape.OnlySuccessCountsAsGround",
    kCkUnitTestFlags)

bool FCkTest_Crowd_ContainmentEscape_OnlySuccessCountsAsGround::RunTest(const FString& Parameters)
{
    using namespace ck_tests_crowd_containment_escape;

    // Unbuilt, Blocked and NoProvider are not "no ground here" - they are "this provider cannot
    // answer yet". Treating any of them as ground would make a provider that has not finished
    // building read as containing the agent; treating them as an ESCAPE against a provider that has
    // is worse still, because a whole warm-up window would be counted as divergence. Both are
    // avoided by the same rule: only Success is ground, so a not-yet-answering provider is on the
    // same side of the test as one that answered no surface, and a run whose two providers are both
    // mid-build counts nothing at all.
    for (const auto ActiveStatus : kEveryStatus)
    {
        for (const auto ShadowStatus : kEveryStatus)
        {
            const auto ActiveIsGround = ActiveStatus == ECk_NavSurface_QueryStatus::Success;
            const auto ShadowIsGround = ShadowStatus == ECk_NavSurface_QueryStatus::Success;

            TestTrue(
                *FString::Printf(TEXT("active [%d] against shadow [%d] counts exactly when the two disagree about ground"),
                    static_cast<int32>(ActiveStatus), static_cast<int32>(ShadowStatus)),
                Get_IsEscape(ActiveStatus, ShadowStatus) == (ActiveIsGround != ShadowIsGround));
        }
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
