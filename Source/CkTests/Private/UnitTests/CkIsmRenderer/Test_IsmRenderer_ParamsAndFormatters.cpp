// Unit tests for CkIsmRenderer pure-data surface: IsmProxy ParamsData
// defaults + the two enum formatters (RenderPolicy + InstanceUpdatePolicy).

#include "Misc/AutomationTest.h"

#include "CkCore/Format/CkFormat.h"
#include "CkIsmRenderer/Proxy/CkIsmProxy_Fragment_Data.h"
#include "CkIsmRenderer/Renderer/CkIsmRenderer_Fragment_Data.h"

// --------------------------------------------------------------------------------------------------------------------

namespace
{
    constexpr auto kIsmRendererUnitTestFlags =
        EAutomationTestFlags::EditorContext |
        EAutomationTestFlags::ClientContext |
        EAutomationTestFlags::ProductFilter;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_IsmRenderer_ProxyParamsData_Defaults,
    "CkTests.UnitTests.CkIsmRenderer.ProxyParamsData.Defaults",
    kIsmRendererUnitTestFlags)

bool FCkTest_IsmRenderer_ProxyParamsData_Defaults::RunTest(const FString& Parameters)
{
    const auto Params = FCk_IsmProxy_Spec{};
    TestEqual(TEXT("Default _StartingState is Enable"),     Params.Get_StartingState(),     ECk_EnableDisable::Enable);
    TestEqual(TEXT("Default _LocalLocationOffset is Zero"), Params.Get_LocalLocationOffset(), FVector::ZeroVector);
    TestEqual(TEXT("Default _LocalRotationOffset is Zero"), Params.Get_LocalRotationOffset(), FRotator::ZeroRotator);
    TestEqual(TEXT("Default _ScaleMultiplier is One"),      Params.Get_ScaleMultiplier(),     FVector::OneVector);
    TestEqual(TEXT("Default _CustomInstanceDataDefaults is empty"),
        Params.Get_CustomInstanceDataDefaults().Num(), 0);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_IsmRenderer_ProxyParamsData_OffsetSettersRoundtrip,
    "CkTests.UnitTests.CkIsmRenderer.ProxyParamsData.OffsetSettersRoundtrip",
    kIsmRendererUnitTestFlags)

bool FCkTest_IsmRenderer_ProxyParamsData_OffsetSettersRoundtrip::RunTest(const FString& Parameters)
{
    auto Params = FCk_IsmProxy_Spec{};
    const auto Loc = FVector{10.0f, 20.0f, 30.0f};
    const auto Rot = FRotator{0.0f, 45.0f, 0.0f};
    const auto Scale = FVector{2.0f, 0.5f, 1.0f};
    Params.Set_LocalLocationOffset(Loc);
    Params.Set_LocalRotationOffset(Rot);
    Params.Set_ScaleMultiplier(Scale);

    TestEqual(TEXT("LocalLocationOffset round-trips"), Params.Get_LocalLocationOffset(), Loc);
    TestEqual(TEXT("LocalRotationOffset round-trips"), Params.Get_LocalRotationOffset(), Rot);
    TestEqual(TEXT("ScaleMultiplier round-trips"),     Params.Get_ScaleMultiplier(),     Scale);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_IsmRenderer_RenderPolicy_Formatter,
    "CkTests.UnitTests.CkIsmRenderer.RenderPolicy.Formatter",
    kIsmRendererUnitTestFlags)

bool FCkTest_IsmRenderer_RenderPolicy_Formatter::RunTest(const FString& Parameters)
{
    const auto Ism  = ck::Format_UE(TEXT("{}"), ECk_Ism_RenderPolicy::ISM);
    const auto Hism = ck::Format_UE(TEXT("{}"), ECk_Ism_RenderPolicy::HISM);
    TestFalse(TEXT("ISM non-empty"),  Ism.IsEmpty());
    TestFalse(TEXT("HISM non-empty"), Hism.IsEmpty());
    TestNotEqual(TEXT("ISM vs HISM distinct"), Ism, Hism);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_IsmRenderer_InstanceUpdatePolicy_Formatter,
    "CkTests.UnitTests.CkIsmRenderer.InstanceUpdatePolicy.Formatter",
    kIsmRendererUnitTestFlags)

bool FCkTest_IsmRenderer_InstanceUpdatePolicy_Formatter::RunTest(const FString& Parameters)
{
    const auto Recreate = ck::Format_UE(TEXT("{}"), ECk_Ism_InstanceUpdatePolicy::Recreate);
    const auto Update   = ck::Format_UE(TEXT("{}"), ECk_Ism_InstanceUpdatePolicy::Update);
    TestFalse(TEXT("Recreate non-empty"), Recreate.IsEmpty());
    TestFalse(TEXT("Update non-empty"),   Update.IsEmpty());
    TestNotEqual(TEXT("Recreate vs Update distinct"), Recreate, Update);
    return true;
}
