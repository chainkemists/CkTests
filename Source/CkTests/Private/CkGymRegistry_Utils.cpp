#include "CkGymRegistry_Utils.h"

#include "CkGymStartup_Utils.h"
#include "CkTests/CkTests_Log.h"

#include "CkCore/Macros/CkMacros.h"

#include <Engine/GameInstance.h>
#include <Engine/World.h>

// --------------------------------------------------------------------------------------------------------------------

auto
    UCk_Utils_GymRegistry_UE::
    Request_RegisterGym(
        const UObject* InWorldContextObject,
        const FString& InDisplayName,
        TSubclassOf<AGameModeBase> InGameModeClass,
        const FString& InLevelName,
        const FString& InCategory)
    -> void
{
    auto* Subsystem = DoGet_Subsystem(InWorldContextObject);
    if (NOT IsValid(Subsystem))
    {
        ck::tests::Warning(TEXT("[GymRegistry] Request_RegisterGym called but subsystem not available (DisplayName={})"),
            InDisplayName);
        return;
    }

    auto Entry = FCkGym_Entry{};
    Entry.DisplayName = InDisplayName;
    Entry.GameModeClass = InGameModeClass;
    Entry.LevelName = InLevelName;
    Entry.Category = InCategory;

    Subsystem->Register(Entry);
}

auto
    UCk_Utils_GymRegistry_UE::
    Get_GymRegistry(
        const UObject* InWorldContextObject)
    -> TArray<FCkGym_Entry>
{
    const auto* Subsystem = DoGet_Subsystem(InWorldContextObject);
    if (NOT IsValid(Subsystem))
    { return {}; }

    return Subsystem->Get_Entries();
}

auto
    UCk_Utils_GymRegistry_UE::
    Get_CurrentGymIndex(
        const UObject* InWorldContextObject)
    -> int32
{
    const auto* Subsystem = DoGet_Subsystem(InWorldContextObject);
    if (NOT IsValid(Subsystem))
    { return INDEX_NONE; }

    return Subsystem->Get_CurrentGymIndex();
}

auto
    UCk_Utils_GymRegistry_UE::
    Get_SuppressHUDDuringStartup(
        const UObject* InWorldContextObject)
    -> bool
{
    const auto* Subsystem = DoGet_Subsystem(InWorldContextObject);
    if (NOT IsValid(Subsystem))
    { return false; }

    return Subsystem->Get_SuppressHUDDuringStartup();
}

auto
    UCk_Utils_GymRegistry_UE::
    Request_Set_SuppressHUDDuringStartup(
        const UObject* InWorldContextObject,
        bool InSuppress)
    -> void
{
    auto* Subsystem = DoGet_Subsystem(InWorldContextObject);
    if (NOT IsValid(Subsystem))
    { return; }

    Subsystem->Set_SuppressHUDDuringStartup(InSuppress);
}

auto
    UCk_Utils_GymRegistry_UE::
    Find_GymIndexByName(
        const UObject* InWorldContextObject,
        const FString& InName)
    -> int32
{
    const auto* Subsystem = DoGet_Subsystem(InWorldContextObject);
    if (NOT IsValid(Subsystem))
    { return INDEX_NONE; }

    return Subsystem->Find_GymIndexByName(InName);
}

auto
    UCk_Utils_GymRegistry_UE::
    Resolve_StartupGymIndex(
        const UObject* InWorldContextObject)
    -> int32
{
    const auto* Subsystem = DoGet_Subsystem(InWorldContextObject);
    if (NOT IsValid(Subsystem))
    { return INDEX_NONE; }

    switch (UCk_Utils_GymStartup_UE::Get_StartupMode())
    {
        case ECkGym_StartupMode::Default:
            return Subsystem->Find_GymIndexByName(UCk_Utils_GymStartup_UE::Get_DefaultGymName());
        case ECkGym_StartupMode::Last:
            return Subsystem->Find_GymIndexByName(UCk_Utils_GymStartup_UE::Get_LastGymName());
        case ECkGym_StartupMode::Cycler:
        default:
            return INDEX_NONE;
    }
}

auto
    UCk_Utils_GymRegistry_UE::
    Request_TravelToGym(
        const UObject* InWorldContextObject,
        int32 InIndex)
    -> void
{
    auto* Subsystem = DoGet_Subsystem(InWorldContextObject);
    if (NOT IsValid(Subsystem))
    { return; }

    Subsystem->Request_TravelToGym(InIndex);
}

auto
    UCk_Utils_GymRegistry_UE::
    Request_TravelToGymByName(
        const UObject* InWorldContextObject,
        const FString& InName)
    -> void
{
    auto* Subsystem = DoGet_Subsystem(InWorldContextObject);
    if (NOT IsValid(Subsystem))
    { return; }

    const auto Index = Subsystem->Find_GymIndexByName(InName);
    if (Index == INDEX_NONE)
    {
        ck::tests::Warning(TEXT("[GymRegistry] Request_TravelToGymByName: no gym registered with DisplayName '{}'"),
            InName);
        return;
    }

    Subsystem->Request_TravelToGym(Index);
}

auto
    UCk_Utils_GymRegistry_UE::
    Request_NextGym(
        const UObject* InWorldContextObject)
    -> void
{
    auto* Subsystem = DoGet_Subsystem(InWorldContextObject);
    if (NOT IsValid(Subsystem))
    { return; }

    Subsystem->Request_TravelToGym(Subsystem->Get_CurrentGymIndex() + 1);
}

auto
    UCk_Utils_GymRegistry_UE::
    Request_PrevGym(
        const UObject* InWorldContextObject)
    -> void
{
    auto* Subsystem = DoGet_Subsystem(InWorldContextObject);
    if (NOT IsValid(Subsystem))
    { return; }

    Subsystem->Request_TravelToGym(Subsystem->Get_CurrentGymIndex() - 1);
}

// --------------------------------------------------------------------------------------------------------------------

auto
    UCk_Utils_GymRegistry_UE::
    DoGet_Subsystem(
        const UObject* InWorldContextObject)
    -> UCkGym_Registry_Subsystem*
{
    if (NOT IsValid(InWorldContextObject))
    { return nullptr; }

    const auto* World = InWorldContextObject->GetWorld();
    if (NOT IsValid(World))
    { return nullptr; }

    auto* GameInstance = World->GetGameInstance();
    if (NOT IsValid(GameInstance))
    { return nullptr; }

    return GameInstance->GetSubsystem<UCkGym_Registry_Subsystem>();
}
