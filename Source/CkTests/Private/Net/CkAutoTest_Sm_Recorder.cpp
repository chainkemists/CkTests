#include "CkTests/Net/CkAutoTest_Sm_Recorder.h"

#include "Engine/World.h"

// --------------------------------------------------------------------------------------------------------------------

auto
    UCk_AutoTest_Sm_RecorderSubsystem::
    RecordEvent(
        TSubclassOf<UCk_SmState_EntityScript> InStateClass,
        ECk_AutoTest_Sm_EventKind InKind,
        ECk_Sm_NetContext InNetContext,
        FName InTaskTag)
    -> void
{
    auto Event = FCk_AutoTest_Sm_RecordedEvent{};
    Event.StateClass = InStateClass;
    Event.Kind = InKind;
    Event.NetContext = InNetContext;
    Event.TaskTag = InTaskTag;
    Event.OrderIndex = _NextOrderIndex++;
    Event.WallClock = FPlatformTime::Seconds();

    _Events.Add(MoveTemp(Event));
}

// --------------------------------------------------------------------------------------------------------------------

auto
    UCk_AutoTest_Sm_RecorderSubsystem::
    Reset()
    -> void
{
    _Events.Reset();
    _NextOrderIndex = 0;
}

// --------------------------------------------------------------------------------------------------------------------

auto
    UCk_AutoTest_Sm_RecorderSubsystem::
    Get_EventsForState(
        TSubclassOf<UCk_SmState_EntityScript> InStateClass) const
    -> TArray<FCk_AutoTest_Sm_RecordedEvent>
{
    auto Filtered = TArray<FCk_AutoTest_Sm_RecordedEvent>{};
    for (const auto& Event : _Events)
    {
        if (Event.StateClass.Get() == InStateClass)
        { Filtered.Add(Event); }
    }
    return Filtered;
}

// --------------------------------------------------------------------------------------------------------------------

auto
    UCk_AutoTest_Sm_RecorderSubsystem::
    ShouldCreateSubsystem(
        UObject* Outer) const
    -> bool
{
    // Recorder is only useful in PIE / standalone game worlds. Skip editor preview, asset-thumbnail
    // worlds, and CDO worlds — they never run gameplay and would just allocate dead state.
    auto* World = Cast<UWorld>(Outer);
    if (World == nullptr)
    { return false; }

    const auto WorldType = World->WorldType;
    const auto IsGameplayWorld = WorldType == EWorldType::PIE
        || WorldType == EWorldType::Game
        || WorldType == EWorldType::GamePreview;

    return IsGameplayWorld;
}

// --------------------------------------------------------------------------------------------------------------------
