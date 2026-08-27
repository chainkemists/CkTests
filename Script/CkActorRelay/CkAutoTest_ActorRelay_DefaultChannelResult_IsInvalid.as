// Language=angelscript

//============================================================================
// CK ACTOR RELAY - AUTOMATION TEST: Default ChannelResult is invalid
//============================================================================
//
// Pins the value-type contract that a default-constructed
// FCk_ActorRelay_ChannelResult reports `Get_IsChannelResultValid == false`.
// Mirrors the audit's `ChannelResult.DefaultCtorIsInvalid` unit-test entry.
//
// The full Request_AcquireChannel path requires a registered group
// subsystem (only present when spawned through CkAudio / CkCue / CkVfx),
// so the value-type contract is what's tractable from a standalone
// AutoTest.
//============================================================================

class UCk_AutoTest_ActorRelay_DefaultChannelResult_IsInvalid : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 2.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Result = FCk_ActorRelay_ChannelResult();

        Assert_True(utils_actor_relay::Get_IsChannelResultValid(Result) == false,
            "Default-constructed FCk_ActorRelay_ChannelResult should report IsChannelResultValid == false");

        FinishSuccess();
    }
}
