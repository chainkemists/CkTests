#include "Misc/AutomationTest.h"

#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/World/CkEcsWorld.h"
#include "CkUsf/Outline/CkUsf_Outline_Fragment.h"
#include "CkUsf/Outline/CkUsf_Outline_Processor.h"
#include "CkUsf/Outline/CkUsf_Outline_ProjectSettings.h"
#include "CkUsf/Outline/CkUsf_Outline_Utils.h"

#include "../CkUnitTest_Common.h"

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Usf_OutlineClaims,
    "CkTests.UnitTests.CkUsf.OutlineClaims",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_Usf_OutlineClaims::RunTest(const FString& Parameters)
{
    auto EcsWorld = ck::FEcsWorld{};
    auto& Registry = EcsWorld.Get_Registry();

    auto Target = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Registry);
    auto SourceA = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Registry);
    auto SourceB = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Registry);
    const auto InteractionTag =
        UCk_Utils_Usf_Outline_Settings_UE::Get_GameplayInteractionOutlineTag();
    const auto SelectionTag = UCk_Utils_Usf_Outline_Settings_UE::Get_SelectionOutlineTag();

    UCk_Utils_Usf_Outline_UE::Set_OutlineClaim(
        Target, SourceA, InteractionTag, ECk_Usf_OutlineScope::EntityOnly, {});
    UCk_Utils_Usf_Outline_UE::Set_OutlineClaim(
        Target, SourceA, InteractionTag, ECk_Usf_OutlineScope::EntityOnly, {});

    TestTrue(TEXT("a declared claim owns the stencil contract immediately"),
        UCk_Utils_Usf_Outline_UE::Has_Outline(Target));
    TestNull(TEXT("a claim has no preset until resolution publishes one"),
        UCk_Utils_Usf_Outline_UE::TryGet_OutlinePreset(Target));
    TestTrue(TEXT("an identical Set is idempotent"),
        Target.Get<ck::FFragment_Usf_OutlineClaims>()._Claims.Num() == 1);

    UCk_Utils_Usf_Outline_UE::Set_OutlineClaim(
        Target, SourceB, SelectionTag, ECk_Usf_OutlineScope::EntityOnly, {});
    TestTrue(TEXT("different sources own independent claims"),
        Target.Get<ck::FFragment_Usf_OutlineClaims>()._Claims.Num() == 2);

    ck::FProcessor_Usf_OutlineClaims_Resolve::ForEachEntity(
        FCk_Time{0.0f}, Target, Target.Get<ck::FFragment_Usf_OutlineClaims>());
    TestTrue(TEXT("the highest configured layer wins"),
        Target.Get<ck::FFragment_Usf_OutlineResolved>().Get_OutlineTag().MatchesTagExact(SelectionTag));
    TestNotNull(TEXT("the resolved claim exposes its configured preset"),
        UCk_Utils_Usf_Outline_UE::TryGet_OutlinePreset(Target));

    UCk_Utils_Usf_Outline_UE::Clear_OutlineClaim(Target, SourceB, SelectionTag, {});
    Target.Remove<ck::FFragment_Usf_OutlineResolved>();
    ck::FProcessor_Usf_OutlineClaims_Resolve::ForEachEntity(
        FCk_Time{0.0f}, Target, Target.Get<ck::FFragment_Usf_OutlineClaims>());
    TestTrue(TEXT("clearing the winner reveals the lower claim"),
        Target.Get<ck::FFragment_Usf_OutlineResolved>().Get_OutlineTag().MatchesTagExact(InteractionTag));

    AddExpectedError(TEXT("Cannot clear unowned outline claim"),
        EAutomationExpectedErrorFlags::Contains, 2);
    UCk_Utils_Usf_Outline_UE::Clear_OutlineClaim(Target, SourceB, SelectionTag, {});
    TestTrue(TEXT("an unowned clear leaves existing claims untouched"),
        Target.Get<ck::FFragment_Usf_OutlineClaims>()._Claims.Num() == 1);

    AddExpectedError(TEXT("is invalid or unconfigured"),
        EAutomationExpectedErrorFlags::Contains, 2);
    const auto RootOutlineTag = FGameplayTag::RequestGameplayTag(TEXT("Outline"));
    UCk_Utils_Usf_Outline_UE::Set_OutlineClaim(
        Target, SourceB, RootOutlineTag, ECk_Usf_OutlineScope::EntityOnly, {});
    TestTrue(TEXT("an unconfigured tag causes no mutation"),
        Target.Get<ck::FFragment_Usf_OutlineClaims>()._Claims.Num() == 1);

    AddExpectedError(TEXT("Outline claim source is INVALID"),
        EAutomationExpectedErrorFlags::Contains, 2);
    auto InvalidSource = FCk_Handle{};
    UCk_Utils_Usf_Outline_UE::Set_OutlineClaim(
        Target, InvalidSource, SelectionTag, ECk_Usf_OutlineScope::EntityOnly, {});
    TestTrue(TEXT("an invalid source causes no mutation"),
        Target.Get<ck::FFragment_Usf_OutlineClaims>()._Claims.Num() == 1);

    auto MalformedTarget = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Registry);
    MalformedTarget.AddOrGet<ck::FFragment_Usf_OutlineClaims>()._Claims.Add(
        ck::FUsf_OutlineClaim{InvalidSource, SelectionTag, ECk_Usf_OutlineScope::EntityOnly});
    AddExpectedError(TEXT("Reaping outline claim with invalid source"),
        EAutomationExpectedErrorFlags::Contains, 2);
    ck::FProcessor_Usf_OutlineClaims_Resolve::ForEachEntity(
        FCk_Time{0.0f}, MalformedTarget,
        MalformedTarget.Get<ck::FFragment_Usf_OutlineClaims>());
    TestFalse(TEXT("reaping the last malformed claim removes the empty container"),
        MalformedTarget.Has<ck::FFragment_Usf_OutlineClaims>());

    auto Root = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Registry);
    auto Child = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Root);
    UCk_Utils_Usf_Outline_UE::Set_OutlineClaim(
        Root, SourceA, SelectionTag, ECk_Usf_OutlineScope::EntityAndDependents, {});
    ck::FProcessor_Usf_OutlineClaims_Resolve::ForEachEntity(
        FCk_Time{0.0f}, Root, Root.Get<ck::FFragment_Usf_OutlineClaims>());
    TestTrue(TEXT("a live-subtree claim reaches an existing dependent"),
        Child.Has<ck::FFragment_Usf_OutlineResolved>());

    auto LateChild = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Root);
    Root.Remove<ck::FFragment_Usf_OutlineResolved>();
    Child.Remove<ck::FFragment_Usf_OutlineResolved>();
    ck::FProcessor_Usf_OutlineClaims_Resolve::ForEachEntity(
        FCk_Time{0.0f}, Root, Root.Get<ck::FFragment_Usf_OutlineClaims>());
    TestTrue(TEXT("a later-created dependent joins the live subtree"),
        LateChild.Has<ck::FFragment_Usf_OutlineResolved>());

    return true;
}
