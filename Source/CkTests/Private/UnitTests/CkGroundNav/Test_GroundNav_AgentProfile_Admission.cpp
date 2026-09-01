// Agent-profile admission.
//
// An invalid profile TERMINATES a bake with a status; it is never silently clamped into range. That
// is the whole point of these cases: a clamped profile bakes a field that quietly disagrees with
// what the caller asked for, and every downstream query then answers confidently and wrongly.
//
// Pure value logic, so this needs no world, no registry and no physics.

#include "CkGroundNav/Bake/CkGroundNav_AgentProfile.h"

#include "CkShapes/Capsule/CkShapeCapsule_Fragment_Data.h"

#include "../CkUnitTest_Common.h"

#include <limits>

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_groundnav_profile
{
    using ck::groundnav::EProfileRejection;

    // A human-sized standing capsule. Every admissible profile needs one: without a standing shape the
    // agent has no height, and headroom cannot be decided.
    auto Make_ValidProfile() -> FCk_GroundNav_AgentProfile
    {
        return FCk_GroundNav_AgentProfile{
            FCk_AnyShape{FCk_ShapeCapsule_Dimensions{56.0f, 34.0f}}};
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_AgentProfile_NeedsAStandingShape,
    "CkTests.UnitTests.CkGroundNav.Bake.AgentProfile_NeedsAStandingShape",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_AgentProfile_NeedsAStandingShape::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_profile;

    TestTrue(TEXT("a profile with an authored standing shape is admissible"),
        ck::groundnav::Get_ProfileRejection(Make_ValidProfile()) == EProfileRejection::None);

    TestEqual(TEXT("and its standing height is the capsule's full height"),
        Make_ValidProfile().Get_StandingHeightUu(), 180.0f);

    // No shape means no height. Rejected rather than skipped: a bake that waived the headroom test
    // would report every crawlspace as walkable.
    TestTrue(TEXT("a profile with NO standing shape is rejected"),
        ck::groundnav::Get_ProfileRejection(FCk_GroundNav_AgentProfile{})
            == EProfileRejection::MissingStandingExtents);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_AgentProfile_InvalidIsRejectedNotClamped,
    "CkTests.UnitTests.CkGroundNav.Bake.AgentProfile_InvalidIsRejectedNotClamped",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_AgentProfile_InvalidIsRejectedNotClamped::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_profile;

    const auto Check = [&](
        const TCHAR*                             InWhat,
        const FCk_GroundNav_AgentProfile&        InProfile,
        EProfileRejection                        InExpected) -> void
    {
        const auto Actual = ck::groundnav::Get_ProfileRejection(InProfile);

        TestTrue(FString::Printf(TEXT("%s is rejected with the expected reason"), InWhat),
            Actual == InExpected);
    };

    // ---- slope ---------------------------------------------------------------------------------------
    {
        auto Profile = Make_ValidProfile();
        Profile.Set_MaxSlopeDegrees(90.0f);
        Check(TEXT("a 90-degree max slope (the surface is a wall)"), Profile, EProfileRejection::SlopeOutOfRange);
    }
    {
        auto Profile = Make_ValidProfile();
        Profile.Set_MaxSlopeDegrees(-1.0f);
        Check(TEXT("a negative max slope"), Profile, EProfileRejection::SlopeOutOfRange);
    }
    {
        auto Profile = Make_ValidProfile();
        Profile.Set_MaxSlopeDegrees(89.9f);

        TestTrue(TEXT("89.9 degrees is still admissible — the bound is exclusive at 90"),
            ck::groundnav::Get_ProfileRejection(Profile) == EProfileRejection::None);
    }

    // ---- slope change --------------------------------------------------------------------------------
    {
        auto Profile = Make_ValidProfile();
        Profile.Set_MaxSlopeChangeDegrees(90.0f);
        Check(TEXT("a 90-degree max slope change"), Profile, EProfileRejection::SlopeChangeOutOfRange);
    }

    // ---- step height ---------------------------------------------------------------------------------
    {
        auto Profile = Make_ValidProfile();
        Profile.Set_StepHeightUu(-1.0f);
        Check(TEXT("a negative step height"), Profile, EProfileRejection::NegativeStepHeight);
    }

    // ---- rough perch ---------------------------------------------------------------------------------
    {
        auto Profile = Make_ValidProfile();
        Profile.Set_RoughPerchToleranceUu(-0.5f);
        Check(TEXT("a negative rough-perch tolerance"), Profile, EProfileRejection::NegativeRoughPerchTolerance);
    }

    // ---- ledge sensitivity ---------------------------------------------------------------------------
    {
        auto Profile = Make_ValidProfile();
        Profile.Set_LedgeSensitivity(-0.25f);
        Check(TEXT("a negative ledge sensitivity"), Profile, EProfileRejection::NegativeLedgeSensitivity);
    }

    // ---- non-finite ----------------------------------------------------------------------------------
    {
        auto Profile = Make_ValidProfile();
        Profile.Set_StepHeightUu(std::numeric_limits<float>::quiet_NaN());
        Check(TEXT("a NaN step height"), Profile, EProfileRejection::NonFiniteValue);
    }
    {
        auto Profile = Make_ValidProfile();
        Profile.Set_LedgeSensitivity(std::numeric_limits<float>::infinity());
        Check(TEXT("an infinite ledge sensitivity"), Profile, EProfileRejection::NonFiniteValue);
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_AgentProfile_ValidationLeavesNoPartialState,
    "CkTests.UnitTests.CkGroundNav.Bake.AgentProfile_ValidationLeavesNoPartialState",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_AgentProfile_ValidationLeavesNoPartialState::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_profile;

    // Admission is PURE: rejecting a profile must not "helpfully" repair it on the way out, because a
    // repaired profile would then bake successfully under values the caller never asked for.
    auto Profile = Make_ValidProfile();
    Profile.Set_StepHeightUu(-42.0f);

    const auto Rejection = ck::groundnav::Get_ProfileRejection(Profile);

    TestTrue(TEXT("the invalid profile is rejected"),
        Rejection == EProfileRejection::NegativeStepHeight);

    TestEqual(TEXT("the rejected value is left exactly as the caller set it, not clamped"),
        Profile.Get_StepHeightUu(), -42.0f);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
