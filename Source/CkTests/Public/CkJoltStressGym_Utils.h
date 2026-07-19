#pragma once

#include "CoreMinimal.h"

#include <Kismet/BlueprintFunctionLibrary.h>

#include "CkJoltStressGym_Utils.generated.h"

// --------------------------------------------------------------------------------------------------------------------
//
// CVar bridge for the Jolt stress-test gym (CkJoltGym_Stress.as). The CVars are
// FAutoConsoleVariableRef file-scope statics (house C++ CVar pattern — see
// ck.Jolt.DebugDraw.Enabled in CkJolt_Subsystem.cpp), so they exist from module load and can be
// set in the console before the gym ever runs; the gym reads them through these AS/BP-callable
// getters.
//
// AS callsite spelling: `UCk_Utils_JoltStressGym_UE::Get_InitialBalls()`.
//
// --------------------------------------------------------------------------------------------------------------------

UCLASS()
class CKTESTS_API UCk_Utils_JoltStressGym_UE : public UBlueprintFunctionLibrary
{
    GENERATED_BODY()

public:
    UFUNCTION(BlueprintPure, Category = "Ck|Utils|JoltStressGym",
              DisplayName = "[Ck][JoltStressGym] Get InitialBalls")
    static int32
    Get_InitialBalls();

    UFUNCTION(BlueprintPure, Category = "Ck|Utils|JoltStressGym",
              DisplayName = "[Ck][JoltStressGym] Get BallsPerWave")
    static int32
    Get_BallsPerWave();

    UFUNCTION(BlueprintPure, Category = "Ck|Utils|JoltStressGym",
              DisplayName = "[Ck][JoltStressGym] Get WaveIntervalSeconds")
    static float
    Get_WaveIntervalSeconds();

    UFUNCTION(BlueprintPure, Category = "Ck|Utils|JoltStressGym",
              DisplayName = "[Ck][JoltStressGym] Get MaxBalls")
    static int32
    Get_MaxBalls();
};
