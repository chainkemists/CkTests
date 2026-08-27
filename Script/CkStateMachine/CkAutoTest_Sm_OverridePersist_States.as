// Language=angelscript

//============================================================================
// CK STATE MACHINE - SAVE/LOAD OVERRIDE-PERSISTENCE STATE CLASSES
//============================================================================
//
// Two state classes used by the C++ gate Ck.Snapshot.SmStateOverride_Reload
// (Test_Snapshot_SmStateOverride_Reload_Gate.spec.cpp), which pins that a
// runtime Request_AddOverrideState survives a snapshot save -> OpenLevel reload.
//
// These live in AngelScript because an override-state class must override
// DoGet_StatesToOverride, a BlueprintImplementableEvent - authorable only in
// AngelScript/Blueprint, NOT plain C++. The C++ gate resolves both classes by
// package path (/Script/Angelscript.Ck_SmOvrPersist_*), the same idiom the
// SubStateMachine net subjects use for their AS-authored states.
//
// Topology: Target is an ordinary sink state the SM can be transitioned into.
// Replacement declares Target's state tag in Get_StatesToOverride, so once the
// override is installed, any Request_Transition into Target resolves to
// Replacement instead (UCk_Utils_SmState_UE::Get_ResolvedStateClass).
//============================================================================

UCLASS()
class UCk_SmOvrPersist_Target : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle) { /* sink - no transitions */ }
}

UCLASS()
class UCk_SmOvrPersist_Replacement : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle) { /* sink - no transitions */ }

    UFUNCTION(BlueprintOverride)
    TArray<FGameplayTag> DoGet_StatesToOverride() const
    {
        auto Tags = TArray<FGameplayTag>();
        Tags.Add(UCk_SmState_EntityScript::Get_StateTagForClass(UCk_SmOvrPersist_Target));
        return Tags;
    }
}
