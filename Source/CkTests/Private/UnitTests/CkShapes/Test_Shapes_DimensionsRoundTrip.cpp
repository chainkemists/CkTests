// Unit tests for CkShapes Dimensions structs and the FCk_AnyShape variant.
// Pure-data round-trip checks — pin the constructor + getter contracts so
// the refactor can't silently rename / reorder the parameter list.

#include "Misc/AutomationTest.h"

#include "CkShapes/Box/CkShapeBox_Fragment_Data.h"
#include "CkShapes/Capsule/CkShapeCapsule_Fragment_Data.h"
#include "CkShapes/Cylinder/CkShapeCylinder_Fragment_Data.h"
#include "CkShapes/Sphere/CkShapeSphere_Fragment_Data.h"
#include "CkShapes/CkShapes_Common.h"

// --------------------------------------------------------------------------------------------------------------------

namespace
{
    constexpr auto kShapesUnitTestFlags =
        EAutomationTestFlags::EditorContext |
        EAutomationTestFlags::ClientContext |
        EAutomationTestFlags::ProductFilter;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_ShapeSphere_Dimensions_ConstructAndGetRadius,
    "CkTests.UnitTests.CkShapes.ShapeSphere_Dimensions.ConstructAndGetRadius",
    kShapesUnitTestFlags)

bool FCkTest_ShapeSphere_Dimensions_ConstructAndGetRadius::RunTest(const FString& Parameters)
{
    const auto Dim = FCk_ShapeSphere_Dimensions{50.0f};
    TestEqual(TEXT("Sphere radius round-trips via Get_Radius"), Dim.Get_Radius(), 50.0f);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_ShapeBox_Dimensions_ConstructAndGetHalfExtents,
    "CkTests.UnitTests.CkShapes.ShapeBox_Dimensions.ConstructAndGetHalfExtents",
    kShapesUnitTestFlags)

bool FCkTest_ShapeBox_Dimensions_ConstructAndGetHalfExtents::RunTest(const FString& Parameters)
{
    const auto Extents = FVector{10.0f, 20.0f, 30.0f};
    const auto Dim = FCk_ShapeBox_Dimensions{Extents};
    TestEqual(TEXT("Box HalfExtents round-trip via Get_HalfExtents"), Dim.Get_HalfExtents(), Extents);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_ShapeCapsule_Dimensions_ConstructAndGetFields,
    "CkTests.UnitTests.CkShapes.ShapeCapsule_Dimensions.ConstructAndGetFields",
    kShapesUnitTestFlags)

bool FCkTest_ShapeCapsule_Dimensions_ConstructAndGetFields::RunTest(const FString& Parameters)
{
    const auto Dim = FCk_ShapeCapsule_Dimensions{60.0f, 30.0f};
    TestEqual(TEXT("Capsule HalfHeight"), Dim.Get_HalfHeight(), 60.0f);
    TestEqual(TEXT("Capsule Radius"),     Dim.Get_Radius(),     30.0f);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_ShapeCylinder_Dimensions_ConstructAndGetFields,
    "CkTests.UnitTests.CkShapes.ShapeCylinder_Dimensions.ConstructAndGetFields",
    kShapesUnitTestFlags)

bool FCkTest_ShapeCylinder_Dimensions_ConstructAndGetFields::RunTest(const FString& Parameters)
{
    const auto Dim = FCk_ShapeCylinder_Dimensions{75.0f, 25.0f};
    TestEqual(TEXT("Cylinder HalfHeight"), Dim.Get_HalfHeight(), 75.0f);
    TestEqual(TEXT("Cylinder Radius"),     Dim.Get_Radius(),     25.0f);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_ShapeBox_Dimensions_CompareEquality,
    "CkTests.UnitTests.CkShapes.ShapeBox_Dimensions.CompareEquality",
    kShapesUnitTestFlags)

bool FCkTest_ShapeBox_Dimensions_CompareEquality::RunTest(const FString& Parameters)
{
    const auto A = FCk_ShapeBox_Dimensions{FVector{10.0f, 20.0f, 30.0f}};
    const auto B = FCk_ShapeBox_Dimensions{FVector{10.0f, 20.0f, 30.0f}};
    const auto C = FCk_ShapeBox_Dimensions{FVector{10.0f, 20.0f, 99.0f}};

    TestTrue (TEXT("Identical extents compare equal"),       A == B);
    TestFalse(TEXT("Different extents compare not-equal"),   A == C);
    TestTrue (TEXT("operator!= negates operator=="),         A != C);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_AnyShape_MakeBox_ReportsBoxType,
    "CkTests.UnitTests.CkShapes.AnyShape.MakeBox_ReportsBoxType",
    kShapesUnitTestFlags)

bool FCkTest_AnyShape_MakeBox_ReportsBoxType::RunTest(const FString& Parameters)
{
    const auto Extents = FVector{10.0f, 20.0f, 30.0f};
    const auto Any = FCk_AnyShape{FCk_ShapeBox_Dimensions{Extents}};

    TestEqual(TEXT("AnyShape constructed from Box reports ShapeType=Box"),
        Any.Get_ShapeType(), ECk_Shape_Type::Box);
    TestEqual(TEXT("AnyShape preserves Box HalfExtents"),
        Any.Get_Box().Get_HalfExtents(), Extents);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_AnyShape_MakeSphere_ReportsSphereTypeAndRadius,
    "CkTests.UnitTests.CkShapes.AnyShape.MakeSphere_ReportsSphereTypeAndRadius",
    kShapesUnitTestFlags)

bool FCkTest_AnyShape_MakeSphere_ReportsSphereTypeAndRadius::RunTest(const FString& Parameters)
{
    const auto Any = FCk_AnyShape{FCk_ShapeSphere_Dimensions{50.0f}};

    TestEqual(TEXT("AnyShape constructed from Sphere reports ShapeType=Sphere"),
        Any.Get_ShapeType(), ECk_Shape_Type::Sphere);
    TestEqual(TEXT("AnyShape preserves Sphere radius"),
        Any.Get_Sphere().Get_Radius(), 50.0f);

    return true;
}
