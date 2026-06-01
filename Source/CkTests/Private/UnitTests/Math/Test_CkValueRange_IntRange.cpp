// Reference C++ unit test for the CkAutoTest framework.
//
// Use this shape for tests that DO NOT need a ticking world: pure math,
// formatting, algorithm helpers, fragment data shape, etc. For anything
// that needs processors / signals / entities, use the AS harness instead
// (see CkAutoTest_CreationSpecification.txt section 2).
//
// Subject under test: FCk_IntRange — pure-data clamp / containment helpers.
// Surface in Session Frontend: CkTests.UnitTests.Math.IntRange.<scenario>

#include "Misc/AutomationTest.h"

#include "CkCore/Enums/CkEnums.h"
#include "CkCore/Math/ValueRange/CkValueRange.h"

#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

// Standard automation flags for editor-context unit tests, shared via CkUnitTest_Common.h
// (hoisted out of a file-local anonymous namespace to avoid unity-build redefinition).
using ck::tests::kCkUnitTestFlags;

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_IntRange_Clamping,
    "CkTests.UnitTests.Math.IntRange.Clamping",
    kCkUnitTestFlags)

bool FCkTest_IntRange_Clamping::RunTest(const FString& Parameters)
{
    const auto Range = FCk_IntRange{0, 100};

    TestEqual(TEXT("Value below min clamps to min"),  Range.Get_ClampedValue(-50), 0);
    TestEqual(TEXT("Value above max clamps to max"),  Range.Get_ClampedValue(200), 100);
    TestEqual(TEXT("Value at min stays at min"),      Range.Get_ClampedValue(0),   0);
    TestEqual(TEXT("Value at max stays at max"),      Range.Get_ClampedValue(100), 100);
    TestEqual(TEXT("Value mid-range passes through"), Range.Get_ClampedValue(42),  42);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_IntRange_Containment,
    "CkTests.UnitTests.Math.IntRange.Containment",
    kCkUnitTestFlags)

bool FCkTest_IntRange_Containment::RunTest(const FString& Parameters)
{
    const auto Range = FCk_IntRange{0, 100};

    // Inclusive: closed interval [Min, Max] — both endpoints count.
    TestTrue (TEXT("Inclusive: min is inside"),     Range.Get_IsWithinInclusive(0));
    TestTrue (TEXT("Inclusive: max is inside"),     Range.Get_IsWithinInclusive(100));
    TestTrue (TEXT("Inclusive: midpoint is inside"),Range.Get_IsWithinInclusive(50));
    TestFalse(TEXT("Inclusive: below min is out"),  Range.Get_IsWithinInclusive(-1));
    TestFalse(TEXT("Inclusive: above max is out"),  Range.Get_IsWithinInclusive(101));

    // "Exclusive" here is max-exclusive — a half-open interval [Min, Max),
    // matching FMath::IsWithin semantics (UE convention for loop bounds).
    // Min IS included; Max is NOT.
    //
    // NOTE: the name `Get_IsWithinExclusive` is misleading — these assertions
    // may need updating if the API is renamed. Likely future shape:
    //   Get_IsWithin           — half-open [Min, Max)  (current Exclusive)
    //   Get_IsWithinInclusive  — closed [Min, Max]    (unchanged)
    //   Get_IsWithinExclusive  — open (Min, Max)      (new, doesn't exist yet)
    TestTrue (TEXT("Exclusive: min is inside (half-open)"),  Range.Get_IsWithinExclusive(0));
    TestFalse(TEXT("Exclusive: max is out (half-open)"),     Range.Get_IsWithinExclusive(100));
    TestTrue (TEXT("Exclusive: midpoint is inside"),         Range.Get_IsWithinExclusive(50));
    TestFalse(TEXT("Exclusive: below min is out"),           Range.Get_IsWithinExclusive(-1));
    TestFalse(TEXT("Exclusive: above max is out"),           Range.Get_IsWithinExclusive(101));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_IntRange_AccessorInclusiveness,
    "CkTests.UnitTests.Math.IntRange.AccessorInclusiveness",
    kCkUnitTestFlags)

bool FCkTest_IntRange_AccessorInclusiveness::RunTest(const FString& Parameters)
{
    const auto Range = FCk_IntRange{0, 100};

    TestEqual(TEXT("Inclusive Get_Min returns stored min"), Range.Get_Min(ECk_Inclusiveness::Inclusive), 0);
    TestEqual(TEXT("Inclusive Get_Max returns stored max"), Range.Get_Max(ECk_Inclusiveness::Inclusive), 100);
    TestEqual(TEXT("Exclusive Get_Min returns stored min + 1"), Range.Get_Min(ECk_Inclusiveness::Exclusive), 1);
    TestEqual(TEXT("Exclusive Get_Max returns stored max - 1"), Range.Get_Max(ECk_Inclusiveness::Exclusive), 99);

    return true;
}
