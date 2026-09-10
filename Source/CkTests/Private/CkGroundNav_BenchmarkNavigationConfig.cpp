#include "CkTests/GroundNav/CkGroundNav_BenchmarkNavigationConfig.h"

#include "NavMesh/RecastNavMesh.h"
#include "UObject/UnrealType.h"

namespace ck_groundnav_benchmark_navigation_config
{
    constexpr float GAgentRadius = 42.0f;
    constexpr float GAgentHeight = 192.0f;
    const FName GDefaultAgentName(TEXT("Default"));

    auto GetSupportedAgentsProperty(UClass& InNavigationSystemClass) -> FArrayProperty*
    {
        auto* Property = FindFProperty<FArrayProperty>(&InNavigationSystemClass, TEXT("SupportedAgents"));
        auto* Inner = Property != nullptr ? CastField<FStructProperty>(Property->Inner) : nullptr;
        return Inner != nullptr && Inner->Struct == FNavDataConfig::StaticStruct() ? Property : nullptr;
    }

    auto MakeFixtureAgent() -> FNavDataConfig
    {
        auto Agent = FNavDataConfig{GAgentRadius, GAgentHeight};
        Agent.Name = GDefaultAgentName;
        Agent.SetNavDataClass(ARecastNavMesh::StaticClass());
        Agent.SetPreferredNavData(ARecastNavMesh::StaticClass());
        return Agent;
    }

    auto InstallFixtureAgent(UNavigationSystemV1& InNavigationSystem) -> bool
    {
        if (InNavigationSystem.HasAnyFlags(RF_ClassDefaultObject))
        { return false; }
        auto* Property = GetSupportedAgentsProperty(*InNavigationSystem.GetClass());
        if (Property == nullptr)
        { return false; }

        auto Agents = FScriptArrayHelper{Property, Property->ContainerPtrToValuePtr<void>(&InNavigationSystem)};
        Agents.EmptyValues();
        const auto AgentIndex = Agents.AddValue();
        if (AgentIndex != 0)
        { return false; }
        *reinterpret_cast<FNavDataConfig*>(Agents.GetRawPtr(AgentIndex)) = MakeFixtureAgent();
        const auto& Agent = *reinterpret_cast<const FNavDataConfig*>(Agents.GetRawPtr(AgentIndex));
        return Agents.Num() == 1 && Agent.Name == GDefaultAgentName &&
            FMath::IsNearlyEqual(Agent.AgentRadius, GAgentRadius) &&
            FMath::IsNearlyEqual(Agent.AgentHeight, GAgentHeight) &&
            Agent.GetNavDataClass<ANavigationData>().Get() == ARecastNavMesh::StaticClass();
    }
}

UCk_GroundNav_BenchmarkNavigationConfig::UCk_GroundNav_BenchmarkNavigationConfig()
{
    DefaultAgentName = ck_groundnav_benchmark_navigation_config::GDefaultAgentName;
    SupportedAgentsMask.Empty();
    SupportedAgentsMask.Set(0);
    SupportedAgentsMask.MarkInitialized();
}

auto UCk_GroundNav_BenchmarkNavigationConfig::IsSupportedAgentsPropertyCompatible(UClass& InNavigationSystemClass) -> bool
{
    return InNavigationSystemClass.IsChildOf(UNavigationSystemV1::StaticClass()) &&
        ck_groundnav_benchmark_navigation_config::GetSupportedAgentsProperty(InNavigationSystemClass) != nullptr;
}

auto UCk_GroundNav_BenchmarkNavigationConfig::CreateAndConfigureNavigationSystem(UWorld& InWorld) const -> UNavigationSystemBase*
{
    auto* ExpectedClass = NavigationSystemClass.TryLoadClass<UNavigationSystemBase>();
    if (ExpectedClass == nullptr || !IsSupportedAgentsPropertyCompatible(*ExpectedClass))
    {
        UE_LOG(LogNavigation, Error, TEXT("GroundNav benchmark navigation config rejected an incompatible navigation-system class"));
        return nullptr;
    }

    auto* NavigationSystemBase = Super::CreateAndConfigureNavigationSystem(InWorld);
    auto* NavigationSystem = Cast<UNavigationSystemV1>(NavigationSystemBase);
    if (NavigationSystem == nullptr || !ck_groundnav_benchmark_navigation_config::InstallFixtureAgent(*NavigationSystem))
    {
        UE_LOG(LogNavigation, Error, TEXT("GroundNav benchmark navigation config could not install its fixture-local supported agent"));
        return nullptr;
    }
    return NavigationSystem;
}
