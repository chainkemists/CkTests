#include "Misc/AutomationTest.h"

#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/OwningActor/CkOwningActor_Utils.h"
#include "CkEcs/World/CkEcsWorld.h"
#include "CkUsf/Outline/CkUsf_Outline_Fragment.h"
#include "CkUsf/Outline/CkUsf_Outline_Processor.h"
#include "CkUsf/Outline/CkUsf_OutlinePreset.h"
#include "CkUsf/Outline/CkUsf_Outline_ProjectSettings.h"
#include "CkUsf/Outline/CkUsf_OutlineSubsystem.h"

#include "../CkUnitTest_Common.h"

#include "Components/StaticMeshComponent.h"
#include "Engine/World.h"
#include "GameFramework/Actor.h"

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Usf_OutlinePhysicalOwnership,
    "CkTests.UnitTests.CkUsf.OutlinePhysicalOwnership",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_Usf_OutlinePhysicalOwnership::RunTest(const FString& Parameters)
{
    auto* World = UWorld::CreateWorld(EWorldType::Game, false);
    if (TestNotNull(TEXT("a transient world exists"), World) == false)
    { return false; }

    auto* Subsystem = UCkUsf_OutlineSubsystem::Get_OutlineSubsystem(World);
    if (TestNotNull(TEXT("the world carries an outline subsystem"), Subsystem) == false)
    {
        World->DestroyWorld(false);
        return false;
    }

    auto* Actor = World->SpawnActor<AActor>(AActor::StaticClass(), FActorSpawnParameters{});
    auto* Primitive = NewObject<UStaticMeshComponent>(Actor);
    Actor->SetRootComponent(Primitive);
    Primitive->RegisterComponent();
    Primitive->SetRenderCustomDepth(true);
    Primitive->SetCustomDepthStencilValue(17);

    auto EcsWorld = ck::FEcsWorld{};
    auto& Registry = EcsWorld.Get_Registry();
    auto ActorOwner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Registry);
    auto ComponentOwner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(ActorOwner);
    auto ActorSource = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Registry);
    auto ComponentSource = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Registry);

    auto RuntimeConfig = FCk_Usf_OutlineRuntimeConfig{};
    if (TestTrue(TEXT("the project outline configuration is valid"),
        UCk_Utils_Usf_Outline_Settings_UE::TryGet_RuntimeConfig(RuntimeConfig)) == false)
    {
        World->DestroyWorld(false);
        return false;
    }

    const auto InteractionTag = UCk_Utils_Usf_Outline_Settings_UE::Get_GameplayInteractionOutlineTag();
    const auto SelectionTag = UCk_Utils_Usf_Outline_Settings_UE::Get_SelectionOutlineTag();
    const auto* InteractionDefinition = RuntimeConfig.TryGet(InteractionTag);
    const auto* SelectionDefinition = RuntimeConfig.TryGet(SelectionTag);
    if (TestNotNull(TEXT("interaction outline is configured"), InteractionDefinition) == false ||
        TestNotNull(TEXT("selection outline is configured"), SelectionDefinition) == false)
    {
        World->DestroyWorld(false);
        return false;
    }

    const auto ActorResolved = ck::FFragment_Usf_OutlineResolved{
        ActorSource, InteractionTag, InteractionDefinition->LayerTag, InteractionDefinition->Preset.Get(),
        InteractionDefinition->LayerIndex, 0};
    const auto InheritedComponentResolved = ck::FFragment_Usf_OutlineResolved{
        ActorSource, InteractionTag, InteractionDefinition->LayerTag, InteractionDefinition->Preset.Get(),
        InteractionDefinition->LayerIndex, 1};
    const auto ComponentOverrideResolved = ck::FFragment_Usf_OutlineResolved{
        ComponentSource, SelectionTag, SelectionDefinition->LayerTag, SelectionDefinition->Preset.Get(),
        SelectionDefinition->LayerIndex, 0};

    // One CK ensure can be surfaced through both the direct log and editor-message routes. Suppress every
    // matching diagnostic while the state assertions below prove the malformed write was rejected.
    AddExpectedErrorPlain(TEXT("resolved layer index [-1] is INVALID"),
        EAutomationExpectedErrorFlags::Contains, /*Occurrences=*/-1);
    const auto ForgedResolved = ck::FFragment_Usf_OutlineResolved{
        ComponentSource, SelectionTag, SelectionDefinition->LayerTag, SelectionDefinition->Preset.Get(),
        INDEX_NONE, 0};
    Subsystem->Set_ResolvedOutline(Primitive, ComponentOwner, ForgedResolved);
    TestEqual(TEXT("malformed resolved state does not publish a physical owner"),
        Subsystem->Get_OutlineOwnerCount(Primitive), 0);

    // A live-subtree claim can resolve both an actor entity and a managed-component dependent to the
    // same physical primitive. Both owners must coexist; call order must not turn removal into a last-writer
    // race or discard the lower owner that should be revealed afterward.
    Subsystem->Set_ResolvedOutline(Primitive, ActorOwner, ActorResolved);
    Subsystem->Set_ResolvedOutline(Primitive, ComponentOwner, InheritedComponentResolved);
    TestEqual(TEXT("the aliased primitive records both resolved entity owners"),
        Subsystem->Get_OutlineOwnerCount(Primitive), 2);
    TestTrue(TEXT("the nearer inherited owner wins without duplicate physical ownership"),
        Subsystem->Get_CurrentOutlinePreset(Primitive) == InteractionDefinition->Preset);

    Subsystem->Set_ResolvedOutline(Primitive, ComponentOwner, ComponentOverrideResolved);
    TestTrue(TEXT("a higher-layer component claim overrides the actor claim"),
        Subsystem->Get_CurrentOutlinePreset(Primitive) == SelectionDefinition->Preset);

    Subsystem->Clear_ResolvedOutline(Primitive, ComponentOwner);
    TestEqual(TEXT("clearing the override preserves the actor owner"),
        Subsystem->Get_OutlineOwnerCount(Primitive), 1);
    TestTrue(TEXT("clearing the override reveals the actor preset"),
        Subsystem->Get_CurrentOutlinePreset(Primitive) == InteractionDefinition->Preset);

    Subsystem->Clear_ResolvedOutline(Primitive, ActorOwner);
    TestEqual(TEXT("clearing the final owner empties physical ownership"),
        Subsystem->Get_OutlineOwnerCount(Primitive), 0);
    TestNull(TEXT("clearing the final owner removes the applied preset"),
        Subsystem->Get_CurrentOutlinePreset(Primitive));
    TestTrue(TEXT("the original custom-depth enablement is restored"), Primitive->bRenderCustomDepth);
    TestEqual(TEXT("the original custom-depth stencil is restored"), Primitive->CustomDepthStencilValue, 17);

    // Actor consumption reconciles its primitive set every frame so a component created after the claim
    // begins joins the same ownership contract without requiring the claim to be toggled.
    UCk_Utils_OwningActor_UE::Add(ActorOwner, Actor);
    ActorOwner.AddOrGet<ck::FFragment_Usf_OutlineResolved>() = ActorResolved;
    const auto SyncActor = [&ActorOwner]()
    {
        ck::FProcessor_Usf_OutlineActor_Sync::ForEachEntity(
            ck::FProcessor_Usf_OutlineActor_Sync::TimeType{}, ActorOwner,
            ActorOwner.Get<ck::FFragment_Usf_OutlineResolved>(),
            ActorOwner.Get<ck::FFragment_OwningActor_Current>());
    };
    SyncActor();

    auto* LatePrimitive = NewObject<UStaticMeshComponent>(Actor);
    Actor->AddInstanceComponent(LatePrimitive);
    LatePrimitive->RegisterComponent();
    SyncActor();
    TestEqual(TEXT("a late actor primitive gains the existing owner"),
        Subsystem->Get_OutlineOwnerCount(LatePrimitive), 1);
    TestTrue(TEXT("a late actor primitive receives the existing preset"),
        Subsystem->Get_CurrentOutlinePreset(LatePrimitive) == InteractionDefinition->Preset);

    ck::FProcessor_Usf_OutlineActor_Remove::ForEachEntity(
        ck::FProcessor_Usf_OutlineActor_Remove::TimeType{}, ActorOwner,
        ActorOwner.Get<ck::FFragment_Usf_OutlineApplied_Actor>());
    TestEqual(TEXT("actor removal clears the original primitive owner"),
        Subsystem->Get_OutlineOwnerCount(Primitive), 0);
    TestEqual(TEXT("actor removal clears the late primitive owner"),
        Subsystem->Get_OutlineOwnerCount(LatePrimitive), 0);

    World->DestroyWorld(false);
    return true;
}
