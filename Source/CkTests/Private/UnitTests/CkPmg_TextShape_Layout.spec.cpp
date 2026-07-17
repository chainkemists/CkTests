#include "Misc/AutomationTest.h"
#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/World/CkEcsWorld.h"
#include "CkPmg/CkPmg_Utils_TextShapes.h"
#include "CkPmg/CkPmg_Fragment_TextShapes.h"
#include "CkPmg/CkPmg_Fragment.h"
#include "CkPmg/CkPmg_Utils_DebugShapes.h"

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkPmg_TextShape_AddComposesFragments,
    "Ck.Pmg.TextShape.AddComposesFragments",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkPmg_TextShape_AddComposesFragments::RunTest(const FString& Parameters)
{
    auto EcsWorld = ck::FEcsWorld{};
    auto& Reg = EcsWorld.Get_Registry();
    auto Root = FCk_Handle{Reg.Get_TransientEntity(), Reg.Get_RegistryHandle()};
    auto Entity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Root, {});

    UCk_Utils_Pmg_TextShapes::Add_Text(
        Entity, FTransform::Identity, TEXT("Hi"),
        100.0f, FLinearColor::White, /*DrawLines=*/true, /*DrawFilled=*/true,
        2.0f, ECk_Pmg_TextAlign::Left, ECk_Plane_Axis::XZ, nullptr, /*Duration=*/-1.0f);

    TestTrue(TEXT("has Text params"),     Entity.Has<ck::FFragment_Pmg_Text_Params>());
    TestTrue(TEXT("has Common"),          Entity.Has<ck::FFragment_Pmg_DebugShape_Common>());
    TestTrue(TEXT("has Current"),         Entity.Has<ck::FFragment_Pmg_DebugShape_Current>());
    TestTrue(TEXT("has NeedsSetup gate"), Entity.Has<ck::FTag_Pmg_DebugShape_NeedsSetup>());
    if (Entity.Has<ck::FFragment_Pmg_Text_Params>())
    {
        TestEqual(TEXT("text stored"),
            Entity.Get<ck::FFragment_Pmg_Text_Params>().Get_Text(), FString(TEXT("Hi")));
    }
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkPmg_TextShape_SetTextReArmsSetup,
    "Ck.Pmg.TextShape.SetTextReArmsSetup",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkPmg_TextShape_SetTextReArmsSetup::RunTest(const FString& Parameters)
{
    auto EcsWorld = ck::FEcsWorld{};
    auto& Reg = EcsWorld.Get_Registry();
    auto Root = FCk_Handle{Reg.Get_TransientEntity(), Reg.Get_RegistryHandle()};
    auto Entity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Root, {});

    auto TextHandle = UCk_Utils_Pmg_TextShapes::Add_Text(
        Entity, FTransform::Identity, TEXT("one"), 100.0f, FLinearColor::White,
        true, true, 2.0f, ECk_Pmg_TextAlign::Left, ECk_Plane_Axis::XZ, nullptr, -1.0f);

    // Simulate the Setup processor having consumed the gate.
    Entity.Remove<ck::FTag_Pmg_DebugShape_NeedsSetup>();

    UCk_Utils_Pmg_DebugShape_UE::Request_SetText(TextHandle, TEXT("two"));

    TestEqual(TEXT("text updated"),
        Entity.Get<ck::FFragment_Pmg_Text_Params>().Get_Text(), FString(TEXT("two")));
    TestTrue(TEXT("setup gate re-armed"), Entity.Has<ck::FTag_Pmg_DebugShape_NeedsSetup>());
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkPmg_TextShape_MakeTextFromHexCodepoints,
    "Ck.Pmg.TextShape.MakeTextFromHexCodepoints",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkPmg_TextShape_MakeTextFromHexCodepoints::RunTest(const FString& Parameters)
{
    TestEqual(TEXT("ASCII hex codepoints -> text"),
        UCk_Utils_Pmg_TextShapes::MakeText_FromHexCodepoints(TEXT("48 49")), FString(TEXT("HI")));

    // Supplementary-plane codepoint (U+1F600) encodes as a UTF-16 surrogate pair (length 2).
    const FString Emoji = UCk_Utils_Pmg_TextShapes::MakeText_FromHexCodepoints(TEXT("1F600"));
    TestEqual(TEXT("emoji codepoint -> 2 UTF-16 units (surrogate pair)"), Emoji.Len(), 2);
    return true;
}
