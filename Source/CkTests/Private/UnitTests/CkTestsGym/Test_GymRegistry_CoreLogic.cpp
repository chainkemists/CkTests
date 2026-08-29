// C++ unit tests for the gym registry's pure arithmetic — the travel-index wrap and the recents
// fold. Both feed user-visible behavior (Ck_Gym_GoTo lands somewhere sane for any int; the
// switchboard's recents section stays deduped and capped), and both are trivially testable without
// a GameInstance, which is why they live as statics on UCkGym_Registry_Subsystem.
//
// Surface in Session Frontend: CkTests.UnitTests.CkTestsGym.GymRegistry.<scenario>

#include "Misc/AutomationTest.h"

#include "CkGym_Registry.h"
#include "CkGym_StartupSettings.h"

#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GymRegistry_WrappedIndex,
    "CkTests.UnitTests.CkTestsGym.GymRegistry.WrappedIndex",
    kCkUnitTestFlags)

bool FCkTest_GymRegistry_WrappedIndex::RunTest(const FString& Parameters)
{
    TestEqual(TEXT("in-range index is unchanged"),
        UCkGym_Registry_Subsystem::Get_WrappedIndex(3, 10), 3);
    TestEqual(TEXT("index == num wraps to 0"),
        UCkGym_Registry_Subsystem::Get_WrappedIndex(10, 10), 0);
    TestEqual(TEXT("large index wraps modulo"),
        UCkGym_Registry_Subsystem::Get_WrappedIndex(23, 10), 3);
    TestEqual(TEXT("-1 wraps to last"),
        UCkGym_Registry_Subsystem::Get_WrappedIndex(-1, 10), 9);
    TestEqual(TEXT("large negative wraps into range"),
        UCkGym_Registry_Subsystem::Get_WrappedIndex(-23, 10), 7);
    TestEqual(TEXT("single-entry registry always lands on 0"),
        UCkGym_Registry_Subsystem::Get_WrappedIndex(-5, 1), 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GymRegistry_RecentsFold,
    "CkTests.UnitTests.CkTestsGym.GymRegistry.RecentsFold",
    kCkUnitTestFlags)

bool FCkTest_GymRegistry_RecentsFold::RunTest(const FString& Parameters)
{
    constexpr auto Cap = UCkGym_StartupSettings::RecentGymsCap;

    {
        const auto Result = UCkGym_Registry_Subsystem::Get_RecentsAfterVisit({}, TEXT("A"), Cap);
        TestEqual(TEXT("first visit: single entry"), Result, TArray<FString>{TEXT("A")});
    }

    {
        const auto Result = UCkGym_Registry_Subsystem::Get_RecentsAfterVisit(
            {TEXT("A"), TEXT("B")}, TEXT("C"), Cap);
        TestEqual(TEXT("new visit prepends"), Result,
            TArray<FString>{TEXT("C"), TEXT("A"), TEXT("B")});
    }

    {
        const auto Result = UCkGym_Registry_Subsystem::Get_RecentsAfterVisit(
            {TEXT("A"), TEXT("B"), TEXT("C")}, TEXT("B"), Cap);
        TestEqual(TEXT("re-visit moves to front without duplicating"), Result,
            TArray<FString>{TEXT("B"), TEXT("A"), TEXT("C")});
    }

    {
        auto Full = TArray<FString>{};
        for (auto Index = 0; Index < Cap; ++Index)
        { Full.Add(FString::Printf(TEXT("G%d"), Index)); }

        const auto Result = UCkGym_Registry_Subsystem::Get_RecentsAfterVisit(Full, TEXT("New"), Cap);
        TestEqual(TEXT("full list stays capped"), Result.Num(), static_cast<int32>(Cap));
        TestEqual(TEXT("newest is front"), Result[0], FString{TEXT("New")});
        TestEqual(TEXT("oldest fell off"), Result.Last(), FString::Printf(TEXT("G%d"), Cap - 2));
    }

    return true;
}
