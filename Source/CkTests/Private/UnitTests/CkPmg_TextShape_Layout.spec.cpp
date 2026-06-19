#include "Misc/AutomationTest.h"
#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/Ecs/CkEcsWorld.h"
#include "CkPmg/CkPmg_Utils_TextShapes.h"
#include "CkPmg/CkPmg_Fragment_TextShapes.h"
#include "CkPmg/CkPmg_Fragment.h"

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
