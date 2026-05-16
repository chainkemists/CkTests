// Unit tests for CkGraphics's pure-data + pure-math surface:
//   - Get_ModifiedColorIntensity arithmetic
//   - FCk_MeshMaterialOverride ctor + getters
//   - ECk_CustomPrimitiveData_Type formatter
//   - FCk_CustomPrimitiveData_Value FloatCount / ConvertToFloatArray per type

#include "Misc/AutomationTest.h"

#include "CkCore/Format/CkFormat.h"
#include "CkGraphics/CkGraphics_Common.h"
#include "CkGraphics/CkGraphics_Utils.h"

// --------------------------------------------------------------------------------------------------------------------

namespace
{
    constexpr auto kGraphicsUnitTestFlags =
        EAutomationTestFlags::EditorContext |
        EAutomationTestFlags::ClientContext |
        EAutomationTestFlags::ProductFilter;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Graphics_ModifiedColorIntensity_OneIsIdentity,
    "CkTests.UnitTests.CkGraphics.ModifiedColorIntensity.OneIsIdentity",
    kGraphicsUnitTestFlags)

bool FCkTest_Graphics_ModifiedColorIntensity_OneIsIdentity::RunTest(const FString& Parameters)
{
    const auto Input = FColor{100, 150, 200, 255};
    const auto Out = UCk_Utils_Graphics_UE::Get_ModifiedColorIntensity(Input, 1.0f);
    TestEqual(TEXT("Intensity=1 returns the input color unchanged"), Out, Input);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Graphics_ModifiedColorIntensity_ZeroIsBlack,
    "CkTests.UnitTests.CkGraphics.ModifiedColorIntensity.ZeroIsBlack",
    kGraphicsUnitTestFlags)

bool FCkTest_Graphics_ModifiedColorIntensity_ZeroIsBlack::RunTest(const FString& Parameters)
{
    const auto Input = FColor{100, 150, 200, 255};
    const auto Out = UCk_Utils_Graphics_UE::Get_ModifiedColorIntensity(Input, 0.0f);
    // Intensity=0 must zero out the RGB channels (alpha policy is the
    // implementation's choice; we don't pin it here).
    TestEqual(TEXT("Intensity=0 zeroes R"), Out.R, static_cast<uint8>(0));
    TestEqual(TEXT("Intensity=0 zeroes G"), Out.G, static_cast<uint8>(0));
    TestEqual(TEXT("Intensity=0 zeroes B"), Out.B, static_cast<uint8>(0));
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Graphics_MeshMaterialOverride_CtorRoundtrip,
    "CkTests.UnitTests.CkGraphics.MeshMaterialOverride.CtorRoundtrip",
    kGraphicsUnitTestFlags)

bool FCkTest_Graphics_MeshMaterialOverride_CtorRoundtrip::RunTest(const FString& Parameters)
{
    const auto Override = FCk_MeshMaterialOverride{3, nullptr};
    TestEqual(TEXT("Constructor preserves _MaterialSlot"),       Override.Get_MaterialSlot(), 3);
    TestNull (TEXT("Constructor preserves _ReplacementMaterial (null in)"),
        Override.Get_ReplacementMaterial().Get());
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Graphics_CustomPrimitiveData_Type_Formatter,
    "CkTests.UnitTests.CkGraphics.CustomPrimitiveData_Type.Formatter",
    kGraphicsUnitTestFlags)

bool FCkTest_Graphics_CustomPrimitiveData_Type_Formatter::RunTest(const FString& Parameters)
{
    const ECk_CustomPrimitiveData_Type Values[] = {
        ECk_CustomPrimitiveData_Type::Float,
        ECk_CustomPrimitiveData_Type::Vector2,
        ECk_CustomPrimitiveData_Type::Vector3,
        ECk_CustomPrimitiveData_Type::Vector4,
        ECk_CustomPrimitiveData_Type::LinearColor,
    };
    TSet<FString> Seen;
    for (const auto V : Values)
    {
        const auto Str = ck::Format_UE(TEXT("{}"), V);
        TestFalse(*FString::Printf(TEXT("Type %d formats non-empty"), static_cast<int32>(V)), Str.IsEmpty());
        TestFalse(*FString::Printf(TEXT("Type %d unique"), static_cast<int32>(V)), Seen.Contains(Str));
        Seen.Add(Str);
    }
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Graphics_CustomPrimitiveData_Value_FloatCount,
    "CkTests.UnitTests.CkGraphics.CustomPrimitiveData_Value.FloatCount",
    kGraphicsUnitTestFlags)

bool FCkTest_Graphics_CustomPrimitiveData_Value_FloatCount::RunTest(const FString& Parameters)
{
    TestEqual(TEXT("Float type has FloatCount=1"),
        FCk_CustomPrimitiveData_Value{1.0f}.Get_FloatCount(), 1);
    TestEqual(TEXT("Vector2 type has FloatCount=2"),
        FCk_CustomPrimitiveData_Value{FVector2D{1.0f, 2.0f}}.Get_FloatCount(), 2);
    TestEqual(TEXT("Vector3 type has FloatCount=3"),
        FCk_CustomPrimitiveData_Value{FVector{1.0f, 2.0f, 3.0f}}.Get_FloatCount(), 3);
    TestEqual(TEXT("Vector4 type has FloatCount=4"),
        FCk_CustomPrimitiveData_Value{FVector4{1.0f, 2.0f, 3.0f, 4.0f}}.Get_FloatCount(), 4);
    TestEqual(TEXT("LinearColor type has FloatCount=4"),
        FCk_CustomPrimitiveData_Value{FLinearColor{0.1f, 0.2f, 0.3f, 0.4f}}.Get_FloatCount(), 4);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Graphics_CustomPrimitiveData_Value_ConvertToFloatArray,
    "CkTests.UnitTests.CkGraphics.CustomPrimitiveData_Value.ConvertToFloatArray",
    kGraphicsUnitTestFlags)

bool FCkTest_Graphics_CustomPrimitiveData_Value_ConvertToFloatArray::RunTest(const FString& Parameters)
{
    {
        const auto V = FCk_CustomPrimitiveData_Value{1.5f};
        const auto Arr = V.ConvertToFloatArray();
        TestEqual(TEXT("Float ConvertToFloatArray size"), Arr.Num(), 1);
        if (Arr.Num() == 1) { TestEqual(TEXT("Float[0]"), Arr[0], 1.5f); }
    }
    {
        const auto V = FCk_CustomPrimitiveData_Value{FVector{4.0f, 5.0f, 6.0f}};
        const auto Arr = V.ConvertToFloatArray();
        TestEqual(TEXT("Vector3 ConvertToFloatArray size"), Arr.Num(), 3);
        if (Arr.Num() == 3)
        {
            TestEqual(TEXT("Vector3[0]"), Arr[0], 4.0f);
            TestEqual(TEXT("Vector3[1]"), Arr[1], 5.0f);
            TestEqual(TEXT("Vector3[2]"), Arr[2], 6.0f);
        }
    }
    return true;
}
