#pragma once

#include "CoreMinimal.h"

#include "CkStateMachine/State/EntityScripts/CkSmState_EntityScript.h"

#include "CkAutoTest_Sm_RecordingState.generated.h"

// --------------------------------------------------------------------------------------------------------------------
//
// Base class for SM state classes used in multi-client replication AutoTests. Overrides
// EnterState/ExitState to push a RecordedEvent into the per-world UCk_AutoTest_Sm_RecorderSubsystem
// before delegating to Super, so test drivers can inspect the per-world fire pattern.
//
// Concrete test states (A, B, C, etc.) subclass this and override DoDefineState to wire up
// transitions / tasks. No additional override of Enter/Exit is needed — recording is automatic.
//
// --------------------------------------------------------------------------------------------------------------------

UCLASS(Abstract)
class CKTESTS_API UCk_AutoTest_Sm_RecordingState_Base : public UCk_SmState_EntityScript
{
    GENERATED_BODY()

public:
    auto
    EnterState(
        FCk_Handle_SmState InHandle,
        ECk_Sm_NetContext InNetContext) -> void override;

    auto
    ExitState(
        FCk_Handle_SmState InHandle,
        ECk_Sm_NetContext InNetContext) -> void override;
};

// --------------------------------------------------------------------------------------------------------------------
//
// Three canonical test state classes — A, B, C — used by the 12.1 (Server-auth A→B→C replay) and
// other tests in the suite. Each is a no-op state with no tasks or transitions; tests wire up
// transitions externally by passing TSubclassOf<UCk_SmState_EntityScript> to the SM builder.
//
// Additional named test state classes can be added below as the test suite grows. Kept in one file
// because they share zero behavior — pure markers for the SM machinery to distinguish.
//
// --------------------------------------------------------------------------------------------------------------------

UCLASS()
class CKTESTS_API UCk_AutoTest_Sm_RecordingState_A : public UCk_AutoTest_Sm_RecordingState_Base
{
    GENERATED_BODY()
};

UCLASS()
class CKTESTS_API UCk_AutoTest_Sm_RecordingState_B : public UCk_AutoTest_Sm_RecordingState_Base
{
    GENERATED_BODY()
};

UCLASS()
class CKTESTS_API UCk_AutoTest_Sm_RecordingState_C : public UCk_AutoTest_Sm_RecordingState_Base
{
    GENERATED_BODY()
};

UCLASS()
class CKTESTS_API UCk_AutoTest_Sm_RecordingState_D : public UCk_AutoTest_Sm_RecordingState_Base
{
    GENERATED_BODY()
};

// --------------------------------------------------------------------------------------------------------------------
