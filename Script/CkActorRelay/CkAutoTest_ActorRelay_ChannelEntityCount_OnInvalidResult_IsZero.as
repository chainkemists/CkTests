// Language=angelscript

//============================================================================
// CK ACTOR RELAY - AUTOMATION TEST: ChannelEntityCount on invalid result == 0
//============================================================================
//
// Pins the documented sentinel: when `Get_IsChannelResultValid` is false,
// `Get_ChannelEntityCount` returns 0 (early-out, no ensure on the underlying
// invalid handle). Mirrors the audit's
// `ChannelResult.EntityCountSentinel` unit-test entry.
//============================================================================

class UCk_AutoTest_ActorRelay_ChannelEntityCount_OnInvalidResult_IsZero : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 2.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Result = FCk_ActorRelay_ChannelResult();

        Assert_True(utils_actor_relay::Get_IsChannelResultValid(Result) == false,
            "Precondition: default-constructed ChannelResult should be invalid");
        Assert_Equals_Int(utils_actor_relay::Get_ChannelEntityCount(Result), 0,
            "Get_ChannelEntityCount on an invalid ChannelResult should return 0 (sentinel)");

        FinishSuccess();
    }
}
