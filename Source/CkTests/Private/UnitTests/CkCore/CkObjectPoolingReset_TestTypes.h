#pragma once

#include "CkCore/Macros/CkMacros.h"
#include "CkCore/ObjectPooling/CkObjectPoolingParticipant.h"

#include "CkObjectPoolingReset_TestTypes.generated.h"

// --------------------------------------------------------------------------------------------------------------------
// Support types for the Ck.ObjectPooling.ResetToArchetype unit tests. Test-only — never used at
// runtime. The Instanced subobject property is the load-bearing part: the recycle reset must leave
// the recycled object owning its OWN subobject copy, never aliasing the archetype's.

UCLASS()
class UCk_PoolingResetTest_SubConfig_UE : public UObject
{
    GENERATED_BODY()

public:
    UPROPERTY()
    int32 _Number = 0;
};

// --------------------------------------------------------------------------------------------------------------------

UCLASS()
class UCk_PoolingResetTest_Host_UE : public UObject
{
    GENERATED_BODY()

public:
    UPROPERTY()
    int32 _Value = 0;

    UPROPERTY(Instanced)
    TObjectPtr<UCk_PoolingResetTest_SubConfig_UE> _SubConfig;

    UPROPERTY()
    FCk_Handle_ObjectPoolingParticipant _Participant;

public:
    UFUNCTION()
    void OnAcquired_First() { ++_TimesFirstHandlerFired; }

    UFUNCTION()
    void OnAcquired_Second() { ++_TimesSecondHandlerFired; }

public:
    // non-reflected on purpose — must never be touched by the reset sweep
    int32 _TimesFirstHandlerFired = 0;
    int32 _TimesSecondHandlerFired = 0;
};
