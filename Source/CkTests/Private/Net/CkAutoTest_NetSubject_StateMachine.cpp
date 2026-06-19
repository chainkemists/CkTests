#include "CkTests/Net/CkAutoTest_NetSubject_StateMachine.h"

#include "CkTests/Net/CkAutoTest_NetSubject_StateMachineEntityScript.h"

// --------------------------------------------------------------------------------------------------------------------

ACk_AutoTest_NetSubject_StateMachine_UE::
    ACk_AutoTest_NetSubject_StateMachine_UE()
{
    _EntityScriptClass = UCk_AutoTest_NetSubject_StateMachineEntityScript_UE::StaticClass();
}

// --------------------------------------------------------------------------------------------------------------------

ACk_AutoTest_NetSubject_StateMachineNoHistory_UE::
    ACk_AutoTest_NetSubject_StateMachineNoHistory_UE()
{
    _EntityScriptClass = UCk_AutoTest_NetSubject_StateMachineNoHistoryEntityScript_UE::StaticClass();
}

// --------------------------------------------------------------------------------------------------------------------

ACk_AutoTest_NetSubject_StateMachineDoesNotReplicate_UE::
    ACk_AutoTest_NetSubject_StateMachineDoesNotReplicate_UE()
{
    _EntityScriptClass = UCk_AutoTest_NetSubject_StateMachineDoesNotReplicateEntityScript_UE::StaticClass();
}

// --------------------------------------------------------------------------------------------------------------------
