// Language=angelscript

//============================================================================
// CK ACTOR — AUTOMATION TEST: OnActorSpawned DELEGATE BINDS TO AS UFUNCTION
//============================================================================
//
// Diagnostic seed for CkActor. Verifies that the TwoParams delegate
// FCk_Delegate_ActorModifier_OnActorSpawned can be constructed from
// AS and bound to a UFUNCTION matching its signature:
//
//   DECLARE_DYNAMIC_DELEGATE_TwoParams(
//       FCk_Delegate_ActorModifier_OnActorSpawned,
//       AActor*, InActorSpawned,
//       const FInstancedStruct&, InOptionalPayload);
//
// The AS-side signature for AActor* is `AActor` (no pointer/ref
// decoration), and `const FInstancedStruct&` collapses to a by-value
// `FInstancedStruct` param (cf. the FCk_Lambda_InHandle binding pattern
// used in CkAttributeGym_Byte_Multiple.as).
//
// This is the simplest blocker-isolator: if construction compiles,
// the OnActorSpawned binding pathway works and we can proceed to
// Request_SpawnActor; if it fails, we know the issue is in the
// delegate exposure / AS code-generator for raw-UObject-pointer
// delegate params (which then implicates ThreeParams variants too).
//============================================================================

class UCk_AutoTest_Actor_OnSpawnedDelegate_BindsToASFunction : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 2.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto MyDelegate = FCk_Delegate_ActorModifier_OnActorSpawned(this, n"OnSpawned");
        Assert_True(MyDelegate.IsBound(),
            "FCk_Delegate_ActorModifier_OnActorSpawned should report IsBound() after AS construction");
        FinishSuccess();
    }

    UFUNCTION()
    private void OnSpawned(AActor InActorSpawned, const FInstancedStruct &in InOptionalPayload)
    {
    }
}
