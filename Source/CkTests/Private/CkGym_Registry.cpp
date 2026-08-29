#include "CkGym_Registry.h"

#include "CkGymStartup_Utils.h"
#include "CkTests/CkTests_Log.h"

#include "CkCore/Ensure/CkEnsure.h"

#include <Kismet/KismetSystemLibrary.h>

// --------------------------------------------------------------------------------------------------------------------

auto
    UCkGym_Registry_Subsystem::
    Register(
        const FCkGym_Entry& InEntry)
    -> void
{
    for (const auto& Existing : _Entries)
    {
        if (Existing.DisplayName == InEntry.DisplayName)
        { return; }
    }

    _Entries.Add(InEntry);
}

auto
    UCkGym_Registry_Subsystem::
    Get_Entries() const
    -> const TArray<FCkGym_Entry>&
{
    return _Entries;
}

auto
    UCkGym_Registry_Subsystem::
    Get_CurrentGymIndex() const
    -> int32
{
    return _CurrentGymIndex;
}

auto
    UCkGym_Registry_Subsystem::
    Get_GymLevelName() const
    -> FString
{
    return _GymLevelName;
}

auto
    UCkGym_Registry_Subsystem::
    Get_SuppressHUDDuringStartup() const
    -> bool
{
    return _SuppressHUDDuringStartup;
}

auto
    UCkGym_Registry_Subsystem::
    Set_SuppressHUDDuringStartup(
        bool InSuppress)
    -> void
{
    _SuppressHUDDuringStartup = InSuppress;
}

auto
    UCkGym_Registry_Subsystem::
    Find_GymIndexByName(
        const FString& InName) const
    -> int32
{
    if (InName.IsEmpty())
    { return INDEX_NONE; }

    for (auto Index = 0; Index < _Entries.Num(); ++Index)
    {
        if (_Entries[Index].DisplayName == InName)
        { return Index; }
    }

    return INDEX_NONE;
}

auto
    UCkGym_Registry_Subsystem::
    Request_TravelToGym(
        int32 InIndex)
    -> void
{
    if (_Entries.Num() == 0)
    { return; }

    const auto WrappedIndex = Get_WrappedIndex(InIndex, _Entries.Num());
    const auto& Entry = _Entries[WrappedIndex];

    const auto GameModeClassIsValid = IsValid(Entry.GameModeClass.Get());
    CK_ENSURE_IF_NOT(GameModeClassIsValid,
        TEXT("Gym entry [{}] has no valid GameModeClass - cannot travel"), Entry.DisplayName)
    { return; }

    _CurrentGymIndex = WrappedIndex;

    const auto ClassPath = Entry.GameModeClass.Get()->GetPathName();
    const auto LevelName = Entry.LevelName.IsEmpty() ? _GymLevelName : Entry.LevelName;

    // Persist the chosen gym so the "Last" startup mode can resume it, and feed the recents list.
    UCk_Utils_GymStartup_UE::Request_Set_LastGymName(Entry.DisplayName);
    UCk_Utils_GymStartup_UE::Request_PushRecentGym(Entry.DisplayName);

    const auto TravelURL = FString::Printf(TEXT("%s?game=%s"), *LevelName, *ClassPath);
    ck::tests::Log(TEXT("[GymRegistry] ServerTravel {}"), TravelURL);

    UKismetSystemLibrary::ExecuteConsoleCommand(GetGameInstance(),
        FString::Printf(TEXT("ServerTravel %s"), *TravelURL));
}

// --------------------------------------------------------------------------------------------------------------------

auto
    UCkGym_Registry_Subsystem::
    Get_WrappedIndex(
        int32 InIndex,
        int32 InNum)
    -> int32
{
    auto Wrapped = InIndex % InNum;
    if (Wrapped < 0)
    { Wrapped += InNum; }

    return Wrapped;
}

auto
    UCkGym_Registry_Subsystem::
    Get_RecentsAfterVisit(
        const TArray<FString>& InRecents,
        const FString& InVisited,
        int32 InCap)
    -> TArray<FString>
{
    auto Result = TArray<FString>{};
    Result.Add(InVisited);

    for (const auto& Existing : InRecents)
    {
        if (Existing == InVisited)
        { continue; }

        if (Result.Num() >= InCap)
        { break; }

        Result.Add(Existing);
    }

    return Result;
}
