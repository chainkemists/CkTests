#pragma once

#include "CkTests/Net/CkAutoTest_NetSubject.h"

#include "CkAutoTest_NetSubject_Relationship.generated.h"

// --------------------------------------------------------------------------------------------------------------------

// Variant of ACk_AutoTest_NetSubject that bridges to the relationship-flavoured entity-script
// (UCk_AutoTest_NetSubject_RelationshipEntityScript_UE), which adds Player + Team child
// entities during Construct. Used by CkRelationship's Net_* tests to exercise the
// FCk_RepData_Player / FCk_RepData_Team replicated containers.
UCLASS()
class CKTESTS_API ACk_AutoTest_NetSubject_Relationship_UE : public ACk_AutoTest_NetSubject
{
    GENERATED_BODY()

public:
    ACk_AutoTest_NetSubject_Relationship_UE();
};

// --------------------------------------------------------------------------------------------------------------------
