// Unit tests for FCk_ScopedStat — the AngelScript-facing RAII scope-cycle guard.
// Exercises the runtime construct/destruct path and the per-name TStatId cache
// directly in C++ (no PIE / no AngelScript VM). The AngelScript *binding* is
// validated separately by CkAutoTest_Profile_ScopedStat.as, which compiles and
// runs FCk_ScopedStat through script at editor startup.

#include "Misc/AutomationTest.h"

#include "CkProfile/Stats/CkScopedStat.h"

// --------------------------------------------------------------------------------------------------------------------

namespace
{
    constexpr auto kProfileUnitTestFlags =
        EAutomationTestFlags::EditorContext |
        EAutomationTestFlags::ClientContext |
        EAutomationTestFlags::ProductFilter;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_ScopedStat_ConstructDestruct_DoesNotCrash,
    "CkTests.UnitTests.CkProfile.ScopedStat.ConstructDestruct_DoesNotCrash",
    kProfileUnitTestFlags)

bool FCkTest_ScopedStat_ConstructDestruct_DoesNotCrash::RunTest(const FString& Parameters)
{
    // Nested scopes drive the full guard lifecycle: the first entry resolves +
    // caches a new stat id, the second entry with the same name hits the cache,
    // and a third distinct name takes the miss path again.
    {
        const FCk_ScopedStat Stat{TEXT("CkTests::ScopedStat::Alpha")};
    }
    {
        const FCk_ScopedStat Stat{TEXT("CkTests::ScopedStat::Alpha")};
    }
    {
        const FCk_ScopedStat Stat{TEXT("CkTests::ScopedStat::Beta")};
    }

    TestTrue(TEXT("FCk_ScopedStat constructs and destructs across scopes without crashing"), true);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

#if STATS
IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_ScopedStat_StatIdCache_ResolvesValidIds,
    "CkTests.UnitTests.CkProfile.ScopedStat.StatIdCache_ResolvesValidIds",
    kProfileUnitTestFlags)

bool FCkTest_ScopedStat_StatIdCache_ResolvesValidIds::RunTest(const FString& Parameters)
{
    const auto Name = FString{TEXT("CkTests::ScopedStat::CacheKey")};

    // First call: cache miss -> CreateStatId. Second call: cache hit. Both must
    // hand back a usable stat id.
    const auto IdMiss = ck::Get_ScopedStat_StatId(Name);
    const auto IdHit  = ck::Get_ScopedStat_StatId(Name);

    TestTrue(TEXT("Cache-miss resolution yields a valid stat id"), IdMiss.IsValidStat());
    TestTrue(TEXT("Cache-hit resolution yields a valid stat id"),  IdHit.IsValidStat());

    return true;
}
#endif
