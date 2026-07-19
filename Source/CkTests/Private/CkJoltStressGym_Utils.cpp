#include "CkJoltStressGym_Utils.h"

#include <HAL/IConsoleManager.h>

// --------------------------------------------------------------------------------------------------------------------

namespace ck_jolt_stress_gym_utils
{
    namespace cvar
    {
        static int32 InitialBalls = 50;
        static FAutoConsoleVariableRef CVar_InitialBalls(TEXT("ck.JoltStressGym.InitialBalls"),
            InitialBalls,
            TEXT("Balls the Jolt stress gym drops at gym start. Change applies on gym (re)start "
                 "(Ck_Gym_Restart)."));

        static int32 BallsPerWave = 10;
        static FAutoConsoleVariableRef CVar_BallsPerWave(TEXT("ck.JoltStressGym.BallsPerWave"),
            BallsPerWave,
            TEXT("Balls the Jolt stress gym adds per wave. Read live each wave."));

        static float WaveIntervalSeconds = 10.0f;
        static FAutoConsoleVariableRef CVar_WaveIntervalSeconds(TEXT("ck.JoltStressGym.WaveIntervalSeconds"),
            WaveIntervalSeconds,
            TEXT("Seconds between the Jolt stress gym's ball waves. Change applies on gym (re)start "
                 "(Ck_Gym_Restart)."));

        static int32 MaxBalls = 2000;
        static FAutoConsoleVariableRef CVar_MaxBalls(TEXT("ck.JoltStressGym.MaxBalls"),
            MaxBalls,
            TEXT("Hard cap on live balls in the Jolt stress gym — waves and exec bursts stop adding "
                 "at this count. Read live. The Jolt project settings' MaxBodies must exceed it."));
    }
}

// --------------------------------------------------------------------------------------------------------------------

auto
    UCk_Utils_JoltStressGym_UE::
    Get_InitialBalls()
    -> int32
{
    return ck_jolt_stress_gym_utils::cvar::InitialBalls;
}

auto
    UCk_Utils_JoltStressGym_UE::
    Get_BallsPerWave()
    -> int32
{
    return ck_jolt_stress_gym_utils::cvar::BallsPerWave;
}

auto
    UCk_Utils_JoltStressGym_UE::
    Get_WaveIntervalSeconds()
    -> float
{
    return ck_jolt_stress_gym_utils::cvar::WaveIntervalSeconds;
}

auto
    UCk_Utils_JoltStressGym_UE::
    Get_MaxBalls()
    -> int32
{
    return ck_jolt_stress_gym_utils::cvar::MaxBalls;
}
