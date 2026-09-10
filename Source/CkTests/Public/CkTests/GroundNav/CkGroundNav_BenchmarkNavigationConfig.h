#pragma once

#include "NavigationSystem.h"

#include "CkGroundNav_BenchmarkNavigationConfig.generated.h"

/**
 * Map-owned navigation setup for GroundNavMatchedBenchmark. It changes only the
 * newly created world's supported agent before that world registers its Recast data.
 */
UCLASS()
class CKTESTS_API UCk_GroundNav_BenchmarkNavigationConfig : public UNavigationSystemModuleConfig
{
    GENERATED_BODY()

public:
    UCk_GroundNav_BenchmarkNavigationConfig();

    auto CreateAndConfigureNavigationSystem(UWorld& InWorld) const -> UNavigationSystemBase* override;

    static auto IsSupportedAgentsPropertyCompatible(UClass& InNavigationSystemClass) -> bool;
};
