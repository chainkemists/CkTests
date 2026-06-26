#include "CkTests/Net/CkAutoTest_NetSubject_StateMachineEntityScript.h"

#include "CkTests/Net/CkAutoTest_NetSubject_StateMachine.h"
#include "CkTests/Net/CkAutoTest_NetSubject_StateMachineOwningClientPawn.h"
#include "CkTests/Net/CkAutoTest_Sm_RecordingState.h"

#include "CkStateMachine/StateMachine/CkStateMachine_Utils.h"
#include "CkStateMachine/StateMachine/CkStateMachine_Fragment_Data.h"
#include "CkStateMachine/State/EntityScripts/CkSmState_EntityScript.h"

#include "CkAttribute/ByteAttribute/CkByteAttribute_Utils.h"
#include "CkAttribute/ByteAttribute/CkByteAttribute_Fragment_Data.h"
#include "CkAttribute/FloatAttribute/CkFloatAttribute_Utils.h"
#include "CkAttribute/FloatAttribute/CkFloatAttribute_Fragment_Data.h"

#include "CkEcs/OwningActor/CkOwningActor_Utils.h"

#include "GameplayTagContainer.h"
#include "UObject/SoftObjectPath.h"

// --------------------------------------------------------------------------------------------------------------------

auto
    UCk_AutoTest_NetSubject_StateMachineEntityScript_UE::
    Construct(
        FCk_Handle& InHandle,
        const FInstancedStruct& InSpawnParams)
    -> ECk_EntityScript_ConstructionFlow
{
    // Super::Construct sets up the WithActor bridge (OwningActor + Transform + Label) and must
    // run before we add the SM — the SM's replication driver needs an OwningActor in the chain
    // to bind its rep payload to a replicated outer Actor.
    const auto Flow = Super::Construct(InHandle, InSpawnParams);

    auto Params = FCk_Fragment_StateMachine_ParamsData{Get_InitialStateClass()};
    Params.Set_Replication(Get_Replication());
    Params.Set_AuthorityModel(Get_AuthorityModel());
    Params.Set_ReplicationModel(Get_ReplicationModel());
    Params.Set_AutoStart(Get_AutoStart());

    auto SM = UCk_Utils_StateMachine_UE::Add(InHandle, Params);

    auto* OwningActor = UCk_Utils_OwningActor_UE::Get_EntityOwningActor(InHandle);
    DoStashStateMachine(OwningActor, SM);

    return Flow;
}

// --------------------------------------------------------------------------------------------------------------------

auto
    UCk_AutoTest_NetSubject_StateMachineEntityScript_UE::
    Get_IsSnapshotRespawnable() const
    -> bool
{
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

auto
    UCk_AutoTest_NetSubject_StateMachineEntityScript_UE::
    DoStashStateMachine(
        AActor* InOwningActor,
        const FCk_Handle_StateMachine& InSM)
    -> void
{
    if (auto* SmActor = Cast<ACk_AutoTest_NetSubject_StateMachine_UE>(InOwningActor))
    {
        SmActor->_TestStateMachine = InSM;
    }
}

// --------------------------------------------------------------------------------------------------------------------

auto
    UCk_AutoTest_NetSubject_StateMachineOwningClientEntityScript_UE::
    DoStashStateMachine(
        AActor* InOwningActor,
        const FCk_Handle_StateMachine& InSM)
    -> void
{
    if (auto* PawnSubject = Cast<ACk_AutoTest_NetSubject_StateMachineOwningClient_Pawn>(InOwningActor))
    {
        PawnSubject->_TestStateMachine = InSM;
    }
}

// --------------------------------------------------------------------------------------------------------------------

auto
    UCk_AutoTest_NetSubject_StateMachineEntityScript_UE::
    Get_InitialStateClass() const
    -> TSubclassOf<UCk_SmState_EntityScript>
{
    return UCk_AutoTest_Sm_RecordingState_A::StaticClass();
}

// --------------------------------------------------------------------------------------------------------------------

auto
    UCk_AutoTest_NetSubject_StateMachineOwningClientSubSmEntityScript_UE::
    Get_InitialStateClass() const
    -> TSubclassOf<UCk_SmState_EntityScript>
{
    // AS state classes aren't visible to C++ at compile time. Resolve the AngelScript-authored
    // parent state by package path (leading 'U' is stripped from the AS class name in the UClass
    // FName, per the /Script/Angelscript.<Name> convention). Returns null if the AS topology failed
    // to compile — Construct's StateMachine Add then ensures on the invalid initial-state class,
    // surfacing the real cause instead of a silent no-SM.
    static const auto AsParentHoldPath = FSoftClassPath{TEXT("/Script/Angelscript.Ck_SmNetSubTest_Parent_Hold")};
    return AsParentHoldPath.TryLoadClass<UCk_SmState_EntityScript>();
}

// --------------------------------------------------------------------------------------------------------------------

auto
    UCk_AutoTest_NetSubject_StateMachineDoesNotReplicateEntityScript_UE::
    Get_InitialStateClass() const
    -> TSubclassOf<UCk_SmState_EntityScript>
{
    // Reuse the AS tick-gated Wait state authored for the SubSm test (Delay task → TaskResults
    // transition → Sub_Reached) as a TOP-LEVEL SM root. Resolved by package path like the SubSm
    // variant; null if the AS topology failed to compile (Add then ensures on the invalid class).
    static const auto AsSubWaitPath = FSoftClassPath{TEXT("/Script/Angelscript.Ck_SmNetSubTest_Sub_Wait")};
    return AsSubWaitPath.TryLoadClass<UCk_SmState_EntityScript>();
}

// --------------------------------------------------------------------------------------------------------------------

auto
    UCk_AutoTest_NetSubject_StateMachineOwningClientSubSmGatedEntityScript_UE::
    Construct(
        FCk_Handle& InHandle,
        const FInstancedStruct& InSpawnParams)
    -> ECk_EntityScript_ConstructionFlow
{
    // Super builds the WithActor bridge + the OwningClientAuth SM (initial state = our AS parent via
    // Get_InitialStateClass) + stashes the SM handle. AutoStart is Disabled for OwningClientAuth, so the
    // SM does not run until the spec issues Request_Start post-possession — adding the attributes here
    // (after the SM Add) is in time for the sub-SM's first evaluation.
    const auto Flow = Super::Construct(InHandle, InSpawnParams);

    // Float "speed" effect — Replicates so the authority-applied Multiply modifier's FinalValue
    // propagates to the owning client for the assertion. Base 100 (x1.5 modifier -> 150 when applied).
    {
        const auto SpeedTag = FGameplayTag::RequestGameplayTag(FName{TEXT("FloatAttribute.Gyms.A")});
        auto SpeedParams = FCk_Fragment_FloatAttribute_ParamsData{SpeedTag, 100.0f};
        UCk_Utils_FloatAttribute_UE::Add(InHandle, SpeedParams, ECk_Replication::Replicates);
    }

    // Byte "input" intent — DoesNotReplicate so each machine owns its copy. The spec sets it ONLY on
    // the owning client; the server's copy stays 0. This is the crux: the server's sub-SM never sees
    // the client-local input, so it never enters Sub_Active and never runs the authority-gated task.
    {
        const auto InputTag = FGameplayTag::RequestGameplayTag(FName{TEXT("ByteAttribute.Gyms.Intent.R")});
        auto InputParams = FCk_Fragment_ByteAttribute_ParamsData{InputTag, static_cast<uint8>(0)};
        UCk_Utils_ByteAttribute_UE::Add(InHandle, InputParams, ECk_Replication::DoesNotReplicate);
    }

    return Flow;
}

// --------------------------------------------------------------------------------------------------------------------

auto
    UCk_AutoTest_NetSubject_StateMachineOwningClientSubSmGatedEntityScript_UE::
    Get_InitialStateClass() const
    -> TSubclassOf<UCk_SmState_EntityScript>
{
    // AS-authored parent state (hosts the SubStateMachine task whose sub-SM is byte-attr-gated with an
    // authority-gated Multiply task). Resolved by path; null if the AS topology failed to compile.
    static const auto AsParentPath = FSoftClassPath{TEXT("/Script/Angelscript.Ck_SmNetSubGatedTest_Parent_Hold")};
    return AsParentPath.TryLoadClass<UCk_SmState_EntityScript>();
}

// --------------------------------------------------------------------------------------------------------------------
