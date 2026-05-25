#pragma once

#include "CoreMinimal.h"

#include "Subsystems/WorldSubsystem.h"

#include "CkStateMachine/Net/CkStateMachine_NetContext.h"
#include "CkStateMachine/State/EntityScripts/CkSmState_EntityScript.h"

#include "CkAutoTest_Sm_Recorder.generated.h"

// --------------------------------------------------------------------------------------------------------------------
//
// Per-world recorder for SM lifecycle events, used by multi-client replication AutoTests to observe
// what fires on each PIE world (server + N clients) for cross-machine ordering assertions.
//
// The shape of a test:
//   1. Each PIE world has its own UCk_AutoTest_Sm_RecorderSubsystem instance (UWorldSubsystem
//      lifecycle is per-world).
//   2. Recording SM state classes (UCk_SmState_RecordingBase + subclasses) push an event into
//      this subsystem on every EnterState/ExitState fire, tagging it with the NetContext the SM
//      framework computed.
//   3. The multi-client test driver, running in the editor process, walks
//      GEngine->GetWorldContexts() and reads each world's recorder to assert per-machine ordering.
//
// Events are stored append-only in arrival order; tests assert on prefix/suffix patterns.
//
// --------------------------------------------------------------------------------------------------------------------

UENUM()
enum class ECk_AutoTest_Sm_EventKind : uint8
{
    EnterState,
    ExitState,
    EnterTask,
    ExitTask
};

USTRUCT()
struct CKTESTS_API FCk_AutoTest_Sm_RecordedEvent
{
    GENERATED_BODY()

public:
    UPROPERTY()
    TSoftClassPtr<UCk_SmState_EntityScript> StateClass;

    UPROPERTY()
    ECk_AutoTest_Sm_EventKind Kind = ECk_AutoTest_Sm_EventKind::EnterState;

    UPROPERTY()
    ECk_Sm_NetContext NetContext = ECk_Sm_NetContext::Standalone;

    UPROPERTY()
    FName TaskTag = NAME_None;

    UPROPERTY()
    int32 OrderIndex = 0;

    UPROPERTY()
    double WallClock = 0.0;
};

// --------------------------------------------------------------------------------------------------------------------

UCLASS()
class CKTESTS_API UCk_AutoTest_Sm_RecorderSubsystem : public UWorldSubsystem
{
    GENERATED_BODY()

public:
    auto
    RecordEvent(
        TSubclassOf<UCk_SmState_EntityScript> InStateClass,
        ECk_AutoTest_Sm_EventKind InKind,
        ECk_Sm_NetContext InNetContext,
        FName InTaskTag = NAME_None) -> void;

    auto
    Reset() -> void;

    auto
    Get_Events() const -> const TArray<FCk_AutoTest_Sm_RecordedEvent>& { return _Events; }

    auto
    Get_EventsForState(
        TSubclassOf<UCk_SmState_EntityScript> InStateClass) const -> TArray<FCk_AutoTest_Sm_RecordedEvent>;

    auto
    Get_EventCount() const -> int32 { return _Events.Num(); }

protected:
    auto
    ShouldCreateSubsystem(
        UObject* Outer) const -> bool override;

private:
    TArray<FCk_AutoTest_Sm_RecordedEvent> _Events;
    int32 _NextOrderIndex = 0;
};

// --------------------------------------------------------------------------------------------------------------------
