#pragma once

#include "Misc/AutomationTest.h"

// --------------------------------------------------------------------------------------------------------------------

namespace ck::tests
{
    // Shared automation flags for editor-context CkTests C++ unit tests.
    //
    // Hoisted into this header (was copy-pasted as a file-local `namespace { constexpr ... }`
    // in each test .cpp) because two such anonymous-namespace constants collide under unity
    // build: UBT concatenates several .cpp into one translation unit, the anonymous namespaces
    // fuse, and a second `kCkUnitTestFlags` becomes a redefinition (C2374 / C2086 / C2371 —
    // hit when Test_Camera_POV.cpp and Test_CkValueRange_IntRange.cpp landed in the same unity
    // blob). An `inline constexpr` in a named namespace has a single definition across all TUs,
    // so any number of test files may include it safely. A test needing different flags should
    // declare its own uniquely-named constant rather than re-defining this one.
    inline constexpr auto kCkUnitTestFlags =
        EAutomationTestFlags::EditorContext |
        EAutomationTestFlags::ClientContext |
        EAutomationTestFlags::ProductFilter;
}
