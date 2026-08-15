#include "CkJolt/CkJolt_Utils.h"
#include "CkJolt/StaticWorld/CkJoltBakeExtraction.h"

#include <Misc/AutomationTest.h>

#include <Jolt/Jolt.h>
#include <Jolt/Core/TempAllocator.h>
#include <Jolt/Physics/Collision/RayCast.h>
#include <Jolt/Physics/Collision/CastResult.h>
#include <Jolt/Physics/Collision/Shape/Shape.h>

// --------------------------------------------------------------------------------------------------------------------
// Pins the runtime DEFORMATION path on a heightfield: rect planning, in-place region edits, holes,
// and the encodable-range refusal.
//
// The single likeliest way to get this wrong is the ROW FLIP. Creation maps UE row y onto Jolt row
// N-1-y; a region update must apply the SAME flip exactly once. Applied twice (or zero times) the
// edit lands mirrored — which on symmetric test data looks perfectly correct. Hence the asymmetric
// surface h(x,y) = 10x + 100y and deliberately OFF-CENTER rects: a mirrored update moves cells the
// probes then catch.
//
// The plan function is pure integer math, so its expectations below are hand-derived from the
// creation mapping (N=8, B=2 unless stated) rather than recorded from a run.
// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_jolt_heightfield_update
{
    constexpr auto kTestFlags =
        EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::ProductFilter;

    constexpr int32 SampleCount = 8;
    constexpr double ScaleXY = 100.0;

    // Jolt quantizes sample heights over the encodable range, so probes allow a few uu of slack.
    constexpr double HeightTolerance = 5.0;

    static auto Get_SurfaceHeight(int32 InX, int32 InY) -> float
    {
        return 10.0f * InX + 100.0f * InY;
    }

    static auto Make_Surface() -> TArray<float>
    {
        auto Heights = TArray<float>{};
        Heights.SetNumUninitialized(SampleCount * SampleCount);

        for (auto Y = 0; Y < SampleCount; ++Y)
        {
            for (auto X = 0; X < SampleCount; ++X)
            { Heights[Y * SampleCount + X] = Get_SurfaceHeight(X, Y); }
        }

        return Heights;
    }

    // Shape space == the UE-aligned body-local frame (the shape embeds the axis correction).
    static auto CastDownAt(const JPH::Shape& InShape, double InX, double InY) -> TOptional<double>
    {
        const auto RayStart = JPH::Vec3{static_cast<float>(InX), static_cast<float>(InY), 5000.0f};
        const auto RayDirection = JPH::Vec3{0.0f, 0.0f, -10000.0f};

        const auto Ray = JPH::RayCast{RayStart, RayDirection};
        auto Hit = JPH::RayCastResult{};

        if (NOT InShape.CastRay(Ray, JPH::SubShapeIDCreator{}, Hit))
        { return {}; }

        return 5000.0 - 10000.0 * Hit.mFraction;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_JoltHeightField_RegionPlan_MappingAndAlignment,
    "Ck.Jolt.HeightField.RegionPlan.MappingAndAlignment",
    ck_test_jolt_heightfield_update::kTestFlags)

bool FCkTest_JoltHeightField_RegionPlan_MappingAndAlignment::RunTest(const FString& Parameters)
{
    using namespace ck::jolt::bake;

    constexpr auto N = 8;
    constexpr auto M = 8;
    constexpr auto B = 2;

    const auto Check_Plan = [&](const TCHAR* InWhat, int32 InX, int32 InY, int32 InSizeX, int32 InSizeY,
        int32 InExpectedX, int32 InExpectedY, int32 InExpectedSizeX, int32 InExpectedSizeY) -> void
    {
        const auto Plan = ComputeHeightFieldRegionPlan(N, M, B, InX, InY, InSizeX, InSizeY);

        if (NOT TestTrue(ck::Format_UE(TEXT("{}: plan is produced"), InWhat), Plan.IsSet()))
        { return; }

        TestEqual(ck::Format_UE(TEXT("{}: jolt x"), InWhat), Plan->_JoltX, InExpectedX);
        TestEqual(ck::Format_UE(TEXT("{}: jolt y"), InWhat), Plan->_JoltY, InExpectedY);
        TestEqual(ck::Format_UE(TEXT("{}: size x"), InWhat), Plan->_SizeX, InExpectedSizeX);
        TestEqual(ck::Format_UE(TEXT("{}: size y"), InWhat), Plan->_SizeY, InExpectedSizeY);
    };

    // Whole surface: rows [0,8) reverse to [0,8), already aligned.
    Check_Plan(TEXT("full surface"), 0, 0, 8, 8, 0, 0, 8, 8);

    // Aligned inner rect: UE rows [2,4) reverse to [8-2-2, 8-2) = [4,6) — already block-aligned.
    Check_Plan(TEXT("aligned inner rect"), 2, 2, 2, 2, 2, 4, 2, 2);

    // Unaligned: UE cols [1,4) -> aligned [0,4); UE rows [1,4) reverse to [8-1-3, 8-1) = [4,7),
    // which expands outward to [4,8).
    Check_Plan(TEXT("unaligned rect"), 1, 1, 3, 3, 0, 4, 4, 4);

    // Touching the far UE row: rows [6,8) reverse to [0,2) — the flip must not run off the bottom.
    Check_Plan(TEXT("far row edge"), 0, 6, 2, 2, 0, 0, 2, 2);

    // Single cell at the origin: UE row 0 lives at jolt row 7, expanding to [6,8).
    Check_Plan(TEXT("single origin cell"), 0, 0, 1, 1, 0, 6, 2, 2);

    // Odd logical count (N=9) with a padded shape (M=10): a rect touching UE row 0 aligns its top
    // edge into the shape's PADDING row, which is legal because the shape is block-rounded.
    {
        const auto Plan = ComputeHeightFieldRegionPlan(9, 10, B, 0, 0, 1, 1);

        if (TestTrue(TEXT("odd N: plan is produced"), Plan.IsSet()))
        {
            TestEqual(TEXT("odd N: jolt y"), Plan->_JoltY, 8);
            TestEqual(TEXT("odd N: size y"), Plan->_SizeY, 2);
        }
    }

    // Rejections — the caller diagnoses, so these report "unset" rather than clamping.
    TestFalse(TEXT("a rect running past the far edge is rejected"),
        ComputeHeightFieldRegionPlan(N, M, B, 7, 7, 3, 3).IsSet());

    TestFalse(TEXT("a zero-size rect is rejected"),
        ComputeHeightFieldRegionPlan(N, M, B, 2, 2, 0, 2).IsSet());

    TestFalse(TEXT("a negative origin is rejected"),
        ComputeHeightFieldRegionPlan(N, M, B, -1, 2, 2, 2).IsSet());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_JoltHeightField_Update_RegionEditRoundTrip,
    "Ck.Jolt.HeightField.Update.RegionEditRoundTrip",
    ck_test_jolt_heightfield_update::kTestFlags)

bool FCkTest_JoltHeightField_Update_RegionEditRoundTrip::RunTest(const FString& Parameters)
{
    using namespace ck::jolt::bake;
    using namespace ck_test_jolt_heightfield_update;

    ck::jolt::Request_GlobalJoltInit();
    ON_SCOPE_EXIT { ck::jolt::Request_GlobalJoltShutdown(); };

    auto TempAllocator = JPH::TempAllocatorImpl{4 * 1024 * 1024};

    // Envelope declared wide enough to both pile above and dig below the initial surface.
    const auto Envelope = FFloatInterval{-500.0f, 1500.0f};
    const auto Updatable = CreateHeightFieldShape_Updatable(Make_Surface(), SampleCount,
        FVector2D{ScaleXY, ScaleXY}, Envelope);

    if (NOT TestNotNull(TEXT("updatable heightfield is created"), Updatable._Shape.GetPtr()))
    { return false; }

    if (NOT TestNotNull(TEXT("the inner heightfield is exposed for editing"), Updatable._HeightField.GetPtr()))
    { return false; }

    // Off-center 3x3 raised to a flat plateau — a mirrored update would move a different block.
    {
        constexpr auto PlateauHeight = 900.0f;
        auto Region = TArray<float>{};
        Region.Init(PlateauHeight, 3 * 3);

        const auto Result = ApplyHeightFieldRegionUpdate(*Updatable._HeightField, SampleCount,
            2, 2, 3, 3, Region, TempAllocator);

        TestTrue(TEXT("the raise is applied"), Result == ECk_Jolt_HeightFieldRegionUpdateResult::Applied);

        // Inside the edited rect (UE cell 2,2 .. 4,4): probe the middle cell.
        const auto InsideZ = CastDownAt(*Updatable._Shape, 3.0 * ScaleXY, 3.0 * ScaleXY);

        if (TestTrue(TEXT("down-ray inside the raised region hits"), InsideZ.IsSet()))
        {
            TestTrue(ck::Format_UE(TEXT("the raised region reads ~{} (got {})"), PlateauHeight, *InsideZ),
                FMath::Abs(*InsideZ - PlateauHeight) <= HeightTolerance);
        }

        // Far from the edit, the original surface must be untouched: h(6,6) = 660.
        const auto OutsideZ = CastDownAt(*Updatable._Shape, 6.0 * ScaleXY, 6.0 * ScaleXY);

        if (TestTrue(TEXT("down-ray outside the raised region hits"), OutsideZ.IsSet()))
        {
            TestTrue(ck::Format_UE(TEXT("untouched surface still reads ~660 (got {})"), *OutsideZ),
                FMath::Abs(*OutsideZ - 660.0) <= HeightTolerance);
        }
    }

    // Now dig the same cells BELOW the original surface — only an explicit envelope makes this
    // representable at all.
    {
        constexpr auto CraterHeight = -300.0f;
        auto Region = TArray<float>{};
        Region.Init(CraterHeight, 3 * 3);

        const auto Result = ApplyHeightFieldRegionUpdate(*Updatable._HeightField, SampleCount,
            2, 2, 3, 3, Region, TempAllocator);

        TestTrue(TEXT("the dig is applied"), Result == ECk_Jolt_HeightFieldRegionUpdateResult::Applied);

        const auto InsideZ = CastDownAt(*Updatable._Shape, 3.0 * ScaleXY, 3.0 * ScaleXY);

        if (TestTrue(TEXT("down-ray inside the crater hits"), InsideZ.IsSet()))
        {
            TestTrue(ck::Format_UE(TEXT("the crater reads ~{} (got {})"), CraterHeight, *InsideZ),
                FMath::Abs(*InsideZ - CraterHeight) <= HeightTolerance);
        }
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_JoltHeightField_Update_HolePunchAndSurvival,
    "Ck.Jolt.HeightField.Update.HolePunchAndSurvival",
    ck_test_jolt_heightfield_update::kTestFlags)

bool FCkTest_JoltHeightField_Update_HolePunchAndSurvival::RunTest(const FString& Parameters)
{
    using namespace ck::jolt::bake;
    using namespace ck_test_jolt_heightfield_update;

    ck::jolt::Request_GlobalJoltInit();
    ON_SCOPE_EXIT { ck::jolt::Request_GlobalJoltShutdown(); };

    auto TempAllocator = JPH::TempAllocatorImpl{4 * 1024 * 1024};

    // A hole authored at CREATION, at UE cell (5,5).
    auto Heights = Make_Surface();
    Heights[5 * SampleCount + 5] = HeightFieldNoCollisionValue();

    const auto Updatable = CreateHeightFieldShape_Updatable(Heights, SampleCount,
        FVector2D{ScaleXY, ScaleXY}, FFloatInterval{-500.0f, 1500.0f});

    if (NOT TestNotNull(TEXT("holed heightfield is created"), Updatable._Shape.GetPtr()))
    { return false; }

    TestFalse(TEXT("the authored hole misses before any edit"),
        CastDownAt(*Updatable._Shape, 5.0 * ScaleXY, 5.0 * ScaleXY).IsSet());

    // Edit a rect whose ALIGNED expansion covers the hole cell while the caller's own rect does
    // NOT. This is the read-modify-write guarantee: expansion must not erase a hole it never
    // addressed. UE rows [6,8) reverse to jolt rows [0,2); the hole at UE row 5 sits at jolt row 2,
    // and UE col 5 is inside the aligned column span [4,8).
    {
        auto Region = TArray<float>{};
        Region.Init(50.0f, 4 * 2);

        const auto Result = ApplyHeightFieldRegionUpdate(*Updatable._HeightField, SampleCount,
            4, 6, 4, 2, Region, TempAllocator);

        TestTrue(TEXT("the neighboring edit is applied"),
            Result == ECk_Jolt_HeightFieldRegionUpdateResult::Applied);

        TestFalse(TEXT("the authored hole SURVIVES an edit that only expanded over it"),
            CastDownAt(*Updatable._Shape, 5.0 * ScaleXY, 5.0 * ScaleXY).IsSet());

        const auto EditedZ = CastDownAt(*Updatable._Shape, 5.0 * ScaleXY, 6.5 * ScaleXY);

        if (TestTrue(TEXT("the edited cells hit"), EditedZ.IsSet()))
        {
            TestTrue(ck::Format_UE(TEXT("the edited cells read ~50 (got {})"), *EditedZ),
                FMath::Abs(*EditedZ - 50.0) <= HeightTolerance);
        }
    }

    // Punching a NEW hole through the update path: the sentinel is a legal incoming value.
    {
        auto Region = TArray<float>{};
        Region.Init(HeightFieldNoCollisionValue(), 2 * 2);

        const auto Result = ApplyHeightFieldRegionUpdate(*Updatable._HeightField, SampleCount,
            2, 2, 2, 2, Region, TempAllocator);

        TestTrue(TEXT("the hole punch is applied"),
            Result == ECk_Jolt_HeightFieldRegionUpdateResult::Applied);

        TestFalse(TEXT("the punched cell misses"),
            CastDownAt(*Updatable._Shape, 2.5 * ScaleXY, 2.5 * ScaleXY).IsSet());

        TestTrue(TEXT("a cell outside the punch still hits"),
            CastDownAt(*Updatable._Shape, 6.5 * ScaleXY, 1.5 * ScaleXY).IsSet());
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_JoltHeightField_Update_EnvelopeExceededRejected,
    "Ck.Jolt.HeightField.Update.EnvelopeExceededRejected",
    ck_test_jolt_heightfield_update::kTestFlags)

bool FCkTest_JoltHeightField_Update_EnvelopeExceededRejected::RunTest(const FString& Parameters)
{
    using namespace ck::jolt::bake;
    using namespace ck_test_jolt_heightfield_update;

    ck::jolt::Request_GlobalJoltInit();
    ON_SCOPE_EXIT { ck::jolt::Request_GlobalJoltShutdown(); };

    auto TempAllocator = JPH::TempAllocatorImpl{4 * 1024 * 1024};

    // NO envelope: the encodable range is exactly the initial samples' [0, 770].
    const auto Updatable = CreateHeightFieldShape_Updatable(Make_Surface(), SampleCount,
        FVector2D{ScaleXY, ScaleXY}, {});

    if (NOT TestNotNull(TEXT("heightfield is created without an envelope"), Updatable._Shape.GetPtr()))
    { return false; }

    const auto BaselineZ = CastDownAt(*Updatable._Shape, 3.0 * ScaleXY, 3.0 * ScaleXY);

    if (NOT TestTrue(TEXT("baseline probe hits"), BaselineZ.IsSet()))
    { return false; }

    // Above what the samples can encode: Jolt would CLAMP this silently, so the whole request is
    // refused instead.
    {
        auto Region = TArray<float>{};
        Region.Init(9000.0f, 2 * 2);

        const auto Result = ApplyHeightFieldRegionUpdate(*Updatable._HeightField, SampleCount,
            2, 2, 2, 2, Region, TempAllocator);

        TestTrue(TEXT("a height above the encodable range is refused"),
            Result == ECk_Jolt_HeightFieldRegionUpdateResult::OutOfEnvelope);

        const auto AfterZ = CastDownAt(*Updatable._Shape, 3.0 * ScaleXY, 3.0 * ScaleXY);

        if (TestTrue(TEXT("probe still hits after the refusal"), AfterZ.IsSet()))
        {
            TestTrue(ck::Format_UE(TEXT("the surface is UNCHANGED by a refused request (was {}, now {})"),
                *BaselineZ, *AfterZ), FMath::Abs(*AfterZ - *BaselineZ) <= HeightTolerance);
        }
    }

    // Out of bounds is a distinct outcome from out of envelope — callers branch on them differently.
    {
        auto Region = TArray<float>{};
        Region.Init(100.0f, 3 * 3);

        const auto Result = ApplyHeightFieldRegionUpdate(*Updatable._HeightField, SampleCount,
            7, 7, 3, 3, Region, TempAllocator);

        TestTrue(TEXT("a rect running past the edge is refused as out of bounds"),
            Result == ECk_Jolt_HeightFieldRegionUpdateResult::OutOfBounds);
    }

    // A mismatched payload cannot be applied to the named rect.
    {
        auto Region = TArray<float>{};
        Region.Init(100.0f, 3);

        const auto Result = ApplyHeightFieldRegionUpdate(*Updatable._HeightField, SampleCount,
            2, 2, 2, 2, Region, TempAllocator);

        TestTrue(TEXT("a payload that does not match the rect is refused"),
            Result == ECk_Jolt_HeightFieldRegionUpdateResult::OutOfBounds);
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
