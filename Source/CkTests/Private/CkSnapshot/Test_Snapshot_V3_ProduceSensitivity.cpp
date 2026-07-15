#include "Misc/AutomationTest.h"

#if WITH_DEV_AUTOMATION_TESTS

#include "Serialization/MemoryWriter.h"
#include "Serialization/ObjectAndNameAsStringProxyArchive.h"
#include "StructUtils/InstancedStruct.h"

#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/Persistence/CkPersistenceHandlerRegistry.h"
#include "CkEcs/World/CkEcsWorld.h"
#include "CkPhysics/Velocity/CkVelocity_Fragment.h"

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

#endif // WITH_DEV_AUTOMATION_TESTS
