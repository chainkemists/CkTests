#include "Misc/AutomationTest.h"

#if WITH_DEV_AUTOMATION_TESTS

#include "Serialization/MemoryWriter.h"
#include "Serialization/ObjectAndNameAsStringProxyArchive.h"
#include "StructUtils/InstancedStruct.h"

#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/Persistence/CkPersistenceHandlerRegistry.h"
#include "CkEcs/Snapshot/CkSnapshot_RestoreMarker.h"
#include "CkEcs/World/CkEcsWorld.h"
#include "CkPhysics/Velocity/CkVelocity_Fragment.h"
#include "CkStateMachine/Net/CkStateMachine_RepData.h"
#include "CkStateMachine/StateMachine/CkStateMachine_Fragment.h"

namespace
{
    auto SerializePayload(const FInstancedStruct& InPayload) -> TArray<uint8>
    {
        auto Bytes = TArray<uint8>{};
        auto Writer = FMemoryWriter{Bytes, true};
        auto Proxy = FObjectAndNameAsStringProxyArchive{Writer, true};
        Proxy.SetIsPersistent(true);
        auto Copy = FInstancedStruct{InPayload};
        Copy.Serialize(Proxy);
        return Bytes;
    }

    auto AddStateMachineForProduce(
        ck::FEcsWorld& InWorld,
        const ECk_Sm_ReplicationModel InReplicationModel,
        const bool bSaveTransient) -> FCk_Handle
    {
        auto Entity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(InWorld.Get_Registry());
        auto Params = FCk_Fragment_StateMachine_ParamsData{};
        Params.Set_ReplicationModel(InReplicationModel);
        Entity.Add<ck::FFragment_Sm_Params>(Params);
        Entity.Add<ck::FFragment_Sm_Current>();
        if (bSaveTransient)
        { Entity.Add<ck::FTag_Snapshot_SaveTransient>(); }
        return Entity;
    }

    auto AssertStateMachineProducePolicy(
        FAutomationTestBase& InTest,
        const UScriptStruct* InPayloadType,
        const ECk_Sm_ReplicationModel InReplicationModel,
        const TCHAR* InModelName) -> bool
    {
        const auto* Handler = FCk_PersistenceHandlerRegistry::Find(InPayloadType);
        if (NOT InTest.TestNotNull(FString::Printf(TEXT("%s save handler registered"), InModelName), Handler)
            || NOT InTest.TestTrue(FString::Printf(TEXT("%s handler exposes Produce"), InModelName),
                Handler != nullptr && static_cast<bool>(Handler->Produce)))
        { return false; }

        auto RootWorld = ck::FEcsWorld{};
        auto Root = AddStateMachineForProduce(RootWorld, InReplicationModel, /*bSaveTransient=*/false);
        const auto RootPayload = Handler->Produce(Root);
        InTest.TestTrue(FString::Printf(TEXT("ordinary root %s state machine produces a save payload"), InModelName),
            RootPayload.IsSet());

        auto DerivedWorld = ck::FEcsWorld{};
        auto Derived = AddStateMachineForProduce(DerivedWorld, InReplicationModel, /*bSaveTransient=*/true);
        const auto DerivedPayload = Handler->Produce(Derived);
        InTest.TestFalse(FString::Printf(TEXT("save-transient %s state machine produces no save payload"), InModelName),
            DerivedPayload.IsSet());
        return true;
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkSnapshot_V3_ProduceSensitivity,
    "Ck.Snapshot.V3.ProduceSensitivity.Velocity",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkSnapshot_V3_ProduceSensitivity::RunTest(const FString& Parameters)
{
    auto EcsWorld = ck::FEcsWorld{};
    auto& Registry = EcsWorld.Get_Registry();
    auto Entity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Registry);

    const auto Initial = FVector{10.0, 20.0, 30.0};
    const auto Mutated = FVector{-40.0, 50.0, 60.0};
    Entity.Add<ck::FFragment_Velocity_Current>(Initial);

    const auto* Handler = FCk_PersistenceHandlerRegistry::Find(FCk_RepData_Velocity::StaticStruct());
    if (NOT TestNotNull(TEXT("Velocity save handler registered"), Handler) ||
        NOT TestTrue(TEXT("Velocity handler exposes Produce"), Handler != nullptr && static_cast<bool>(Handler->Produce)))
    { return false; }

    const auto First = Handler->Produce(Entity);
    const auto Unchanged = Handler->Produce(Entity);
    if (NOT TestTrue(TEXT("Produce emitted both unchanged samples"), First.IsSet() && Unchanged.IsSet()))
    { return false; }

    const auto FirstBytes = SerializePayload(First.GetValue());
    const auto UnchangedBytes = SerializePayload(Unchanged.GetValue());
    TestTrue(TEXT("unchanged live state produces identical payload bytes"), FirstBytes == UnchangedBytes);

    Entity.Replace<ck::FFragment_Velocity_Current>(Mutated);
    const auto Changed = Handler->Produce(Entity);
    if (NOT TestTrue(TEXT("Produce emitted the mutated sample"), Changed.IsSet()))
    { return false; }

    const auto ChangedBytes = SerializePayload(Changed.GetValue());
    TestTrue(TEXT("mutating live state changes produced payload bytes"), FirstBytes != ChangedBytes);
    TestTrue(TEXT("mutated payload contains the new velocity"),
        Changed.GetValue().Get<FCk_RepData_Velocity>().Value.Equals(Mutated));
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkSnapshot_V3_SaveTransientStateMachine_WithHistory_Produce,
    "Ck.Snapshot.V3.SaveTransientStateMachine.WithHistory.Produce",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkSnapshot_V3_SaveTransientStateMachine_WithHistory_Produce::RunTest(const FString& Parameters)
{
    return AssertStateMachineProducePolicy(*this,
        FCk_RepData_StateMachine_WithHistory::StaticStruct(),
        ECk_Sm_ReplicationModel::WithHistory,
        TEXT("WithHistory"));
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkSnapshot_V3_SaveTransientStateMachine_NoHistory_Produce,
    "Ck.Snapshot.V3.SaveTransientStateMachine.NoHistory.Produce",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkSnapshot_V3_SaveTransientStateMachine_NoHistory_Produce::RunTest(const FString& Parameters)
{
    return AssertStateMachineProducePolicy(*this,
        FCk_RepData_StateMachine_NoHistory::StaticStruct(),
        ECk_Sm_ReplicationModel::WithoutHistory,
        TEXT("NoHistory"));
}

#endif // WITH_DEV_AUTOMATION_TESTS
