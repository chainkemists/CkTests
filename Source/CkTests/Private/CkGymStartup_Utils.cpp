#include "CkGymStartup_Utils.h"

// --------------------------------------------------------------------------------------------------------------------

auto
    UCk_Utils_GymStartup_UE::
    Get_StartupMode()
    -> ECkGym_StartupMode
{
    const auto* Settings = GetDefault<UCkGym_StartupSettings>();
    return Settings->StartupMode;
}

auto
    UCk_Utils_GymStartup_UE::
    Request_Set_StartupMode(
        ECkGym_StartupMode InMode)
    -> void
{
    auto* Settings = GetMutableDefault<UCkGym_StartupSettings>();
    if (Settings->StartupMode == InMode)
    { return; }

    Settings->StartupMode = InMode;
    Settings->SaveConfig();
}

auto
    UCk_Utils_GymStartup_UE::
    Get_DefaultGymName()
    -> FString
{
    const auto* Settings = GetDefault<UCkGym_StartupSettings>();
    return Settings->DefaultGymName;
}

auto
    UCk_Utils_GymStartup_UE::
    Request_Set_DefaultGymName(
        const FString& InName)
    -> void
{
    auto* Settings = GetMutableDefault<UCkGym_StartupSettings>();
    if (Settings->DefaultGymName == InName)
    { return; }

    Settings->DefaultGymName = InName;
    Settings->SaveConfig();
}

auto
    UCk_Utils_GymStartup_UE::
    Get_LastGymName()
    -> FString
{
    const auto* Settings = GetDefault<UCkGym_StartupSettings>();
    return Settings->LastGymName;
}

auto
    UCk_Utils_GymStartup_UE::
    Request_Set_LastGymName(
        const FString& InName)
    -> void
{
    auto* Settings = GetMutableDefault<UCkGym_StartupSettings>();
    if (Settings->LastGymName == InName)
    { return; }

    Settings->LastGymName = InName;
    Settings->SaveConfig();
}
