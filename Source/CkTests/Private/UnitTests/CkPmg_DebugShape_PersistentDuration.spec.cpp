#include "Misc/AutomationTest.h"

#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/Scheduler/CkSchedulerDebugData.h"
#include "CkEcs/World/CkEcsWorld.h"
#include "CkPmg/CkPmg_Fragment.h"
#include "CkPmg/CkPmg_Processor_DebugShapes.h"
#include "CkPmg/CkPmg_Utils_DebugLines.h"
#include "CkPmg/CkPmg_Utils_DebugShapes.h"
#include "CkPmg/CkPmg_Utils_TextShapes.h"

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkPmg_DebugShape_FillColor_UsesFixedLowOpacity,
    "Ck.Pmg.DebugShape.FillColor.UsesFixedLowOpacity",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkPmg_DebugShape_FillColor_UsesFixedLowOpacity::RunTest(const FString& Parameters)
{
    const auto OutlineColor = FLinearColor{0.2f, 0.4f, 0.8f, 1.0f};
    const auto FillColor = ck::pmg_debug_shape::Get_FillColor(OutlineColor);

    TestTrue(TEXT("fill preserves the outline RGB"),
        FMath::IsNearlyEqual(FillColor.R, OutlineColor.R) &&
        FMath::IsNearlyEqual(FillColor.G, OutlineColor.G) &&
        FMath::IsNearlyEqual(FillColor.B, OutlineColor.B));
    TestTrue(TEXT("fill uses the shared nearly-transparent opacity"),
        FMath::IsNearlyEqual(FillColor.A, ck::pmg_debug_shape::FillOpacity));
    TestTrue(TEXT("fill opacity remains low enough for scene visibility"), FillColor.A <= 0.1f);
    TestTrue(TEXT("semantic outline color remains opaque"), FMath::IsNearlyEqual(OutlineColor.A, 1.0f));
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkPmg_DebugShape_PersistentDuration_SkipsDurationProcessor,
    "Ck.Pmg.DebugShape.PersistentDuration.SkipsDurationProcessor",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkPmg_DebugShape_PersistentDuration_SkipsDurationProcessor::RunTest(const FString& Parameters)
{
    auto EcsWorld = ck::FEcsWorld{};
    auto& Registry = EcsWorld.Get_Registry();
    auto Root = FCk_Handle{Registry.Get_TransientEntity(), Registry.Get_RegistryHandle()};
    auto Entity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Root, {});

    UCk_Utils_Pmg_TextShapes::Add_Text(
        Entity, FTransform::Identity, TEXT("Persistent"),
        100.0f, FLinearColor::White, true, true,
        2.0f, ECk_Pmg_TextAlign::Left, ECk_Plane_Axis::XZ, nullptr, -1.0f);

    Entity.Remove<ck::FTag_Pmg_DebugShape_NeedsSetup>();

    TestTrue(TEXT("persistent duration is classified at creation"),
        Entity.Has<ck::FTag_Pmg_DebugShape_PersistentDuration>());

#if !UE_BUILD_SHIPPING
    ck::GDebug_LastProcessedEntityCount = -1;
#endif

    auto Processor = ck::FProcessor_Pmg_DebugShape_CheckDuration{Registry};
    Processor.Tick(FCk_Time::ZeroSecond());

#if !UE_BUILD_SHIPPING
    TestEqual(TEXT("persistent shape is excluded from duration processor"),
        ck::GDebug_LastProcessedEntityCount, 0);
#endif

    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkPmg_DebugShape_PersistentDuration_RequestUpdatesMembership,
    "Ck.Pmg.DebugShape.PersistentDuration.RequestUpdatesMembership",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkPmg_DebugShape_PersistentDuration_RequestUpdatesMembership::RunTest(const FString& Parameters)
{
    auto EcsWorld = ck::FEcsWorld{};
    auto& Registry = EcsWorld.Get_Registry();
    auto Root = FCk_Handle{Registry.Get_TransientEntity(), Registry.Get_RegistryHandle()};
    auto Entity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Root, {});

    auto Shape = UCk_Utils_Pmg_TextShapes::Add_Text(
        Entity, FTransform::Identity, TEXT("Persistent"),
        100.0f, FLinearColor::White, true, true,
        2.0f, ECk_Pmg_TextAlign::Left, ECk_Plane_Axis::XZ, nullptr, -1.0f);

    Entity.Remove<ck::FTag_Pmg_DebugShape_NeedsSetup>();
    UCk_Utils_Pmg_DebugShape_UE::Request_SetDuration(
        Shape, FCk_Request_Pmg_DebugShape_SetDuration{FCk_Time{1.0f}}, {});

    auto Processor = ck::FProcessor_Pmg_DebugShape_HandleRequests{Registry};
    Processor.Tick(FCk_Time::ZeroSecond());

    TestFalse(TEXT("finite duration re-enrolls shape in duration processing"),
        Entity.Has<ck::FTag_Pmg_DebugShape_PersistentDuration>());

    UCk_Utils_Pmg_DebugShape_UE::Request_SetDuration(
        Shape, FCk_Request_Pmg_DebugShape_SetDuration{FCk_Time{-1.0f}}, {});
    Processor.Tick(FCk_Time::ZeroSecond());

    TestTrue(TEXT("persistent duration removes shape from duration processing"),
        Entity.Has<ck::FTag_Pmg_DebugShape_PersistentDuration>());
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkPmg_DebugLineSet_ComposesRetainedShapeAndRebakesThickness,
    "Ck.Pmg.DebugLineSet.BreadcrumbSupport.ComposesAndRebakesThickness",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkPmg_DebugLineSet_ComposesRetainedShapeAndRebakesThickness::RunTest(const FString& Parameters)
{
    AddExpectedError(
        TEXT("Cannot create a retained PMG line set under invalid owner"),
        EAutomationExpectedErrorFlags::Contains,
        2);
    auto InvalidOwner = FCk_Handle{};
    const auto RejectedLineSet = ck::pmg::Create_DebugLineSet(
        InvalidOwner,
        FTransform::Identity,
        FLinearColor::White,
        2.0f);
    TestFalse(TEXT("an invalid owner is rejected before line-set composition"),
        ck::IsValid(RejectedLineSet));

    auto EcsWorld = ck::FEcsWorld{};
    auto& Registry = EcsWorld.Get_Registry();
    auto Root = FCk_Handle{Registry.Get_TransientEntity(), Registry.Get_RegistryHandle()};
    auto Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Root, {});

    auto LineSet = ck::pmg::Create_DebugLineSet(
        Owner,
        FTransform::Identity,
        FLinearColor::White,
        2.0f);

    TestTrue(TEXT("line set is a valid typed PMG shape"), ck::IsValid(LineSet));
    TestTrue(TEXT("line set owns a PMG current fragment"),
        LineSet.Has<ck::FFragment_Pmg_DebugShape_Current>());
    TestTrue(TEXT("line set is routed to its dedicated setup processor"),
        LineSet.Has<ck::FTag_Pmg_DebugShape_LineSet>() &&
        LineSet.Has<ck::FTag_Pmg_DebugShape_NeedsSetup>());
    TestTrue(TEXT("line set persists with its owning entity"),
        LineSet.Has<ck::FTag_Pmg_DebugShape_PersistentDuration>());

    ck::pmg::Append_DebugLine_World(
        LineSet,
        FVector::ZeroVector,
        FVector{100.0f, 0.0f, 0.0f},
        FLinearColor::White,
        2.0f);
    TestTrue(TEXT("append creates one cached line and arms one-shot baking"),
        LineSet.Has<ck::FFragment_Pmg_DebugShape_Lines>() &&
        LineSet.Get<ck::FFragment_Pmg_DebugShape_Lines>().Get_Lines().Num() == 1 &&
        LineSet.Has<ck::FTag_Pmg_DebugShape_LinesNeedBaking>());

    LineSet.Remove<ck::FTag_Pmg_DebugShape_NeedsSetup>();
    UCk_Utils_Pmg_DebugShape_UE::Request_SetLineThickness(
        LineSet,
        FCk_Request_Pmg_DebugShape_SetLineThickness{5.0f},
        {});
    auto Processor = ck::FProcessor_Pmg_DebugShape_HandleRequests{Registry};
    Processor.Tick(FCk_Time::ZeroSecond());

    TestTrue(TEXT("thickness mutation updates cached geometry before rebaking"),
        FMath::IsNearlyEqual(
            LineSet.Get<ck::FFragment_Pmg_DebugShape_Lines>().Get_Lines()[0]._Thickness,
            5.0f));
    TestTrue(TEXT("thickness mutation re-arms one-shot line baking"),
        LineSet.Has<ck::FTag_Pmg_DebugShape_LinesNeedBaking>());
    return true;
}
