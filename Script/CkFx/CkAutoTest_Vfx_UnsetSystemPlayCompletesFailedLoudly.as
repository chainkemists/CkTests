// Language=angelscript
//
// CK FX - AUTOMATION TEST: a play on an unset-system vfx completes Failed and diagnoses loudly
//
// Pins the Vfx quartet's deferral + null contract end-to-end: an unset particle system is a legal
// inert composition (no ensure at Add/Setup - mirrors Sfx's unset-cue semantics); the PLAY path is
// where it gets loud - the deferred drain fires the resolve ensure and the request-completion
// delegate reports Failed exactly once. (The pre-quartet synchronous spawn failed silently.)

class UCk_AutoTest_Vfx_UnsetSystemPlayCompletesFailedLoudly : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;

    private int32 _CompletionCount = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto OwnerHandle = InHandle;

        auto Params = FCk_Fragment_Vfx_ParamsData();
        Params.Set_Name(utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Vfx.UnsetSystem_Play"));

        auto VfxHandle = utils_vfx::Add(OwnerHandle, Params);
        Assert_True(ck::IsValid(VfxHandle), "utils_vfx::Add should return a valid FCk_Handle_Vfx");
        if (IsFinished()) { return; }

        // Requested BEFORE setup completes - must queue behind NeedsSetup (which composes inert for
        // an unset system), then the drain resolves null, ensures, and completes Failed.
        auto PlayRequest = FCk_Request_Vfx_PlayAtLocation();
        PlayRequest._Outer = this;

        utils_vfx::Request_PlayAtLocation(VfxHandle, PlayRequest,
            FCk_Delegate_Request_OnCompleted(this, n"OnPlayCompleted"));
    }

    UFUNCTION()
    private void OnPlayCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        if (IsFinished()) { return; }

        _CompletionCount++;
        Assert_Equals_Int(_CompletionCount, 1, "the completion delegate must fire exactly once");
        Assert_True(InResult == ECk_Request_OperationResult::Failed,
            f"an unset-system play must complete Failed (got {InResult})");

        FinishSuccess();
    }
}

//============================================================================
// HAND-AUTHORED WRAPPER ACTOR - registers the deliberate-ensure log pattern.
//============================================================================

class ACk_AutoTest_Vfx_UnsetSystemPlayCompletesFailedLoudly_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Vfx_UnsetSystemPlayCompletesFailedLoudly;

    UFUNCTION(BlueprintOverride)
    TArray<FString> Get_ExpectedLogErrors() const
    {
        TArray<FString> Out;
        Out.Add("cannot play - its ParticleSystem is not resolved");
        return Out;
    }
}
