// Language=angelscript
//============================================================================
// CK CROWD - AUTOMATION TEST: TRANSIENT PERSONAL SPACE
//============================================================================

class UCk_AutoTest_Crowd_TransientPersonalSpace : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;

    private FCk_Handle_CrowdAgent _Agent;
    private float _ElapsedSeconds = 0.0;
    private int32 _Phase = 0;

    private const float TickSeconds = 0.05;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;
        utils_transform::Add(LocalHandle,
            FTransform(FRotator::ZeroRotator, FVector::ZeroVector, FVector::OneVector),
            ECk_Replication::DoesNotReplicate);

        auto Params = FCk_Fragment_CrowdAgent_ParamsData(42.0f, 192.0f);
        auto AgentEntity = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        auto AgentTransform = utils_transform::Add(AgentEntity,
            FTransform(FRotator::ZeroRotator, FVector(0.0, 0.0, 100.0), FVector::OneVector),
            ECk_Replication::DoesNotReplicate);
        _Agent = utils_crowd_agent::Add(AgentTransform, Params);

        auto TimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(TickSeconds));
        TimerParams.Set_StartingState(ECk_Timer_State::Running)
                   .Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        auto Timer = utils_timer::Add(LocalHandle, TimerParams);
        Timer.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        _ElapsedSeconds += TickSeconds;

        // TIMELINE NOTE: every window below is sized in TICKS, not in tenths. The previous timeline
        // sampled the "refresh outlives the original expiry" case at 0.70 against an expiry at 0.75 --
        // a margin of exactly ONE tick, so a single tick of slop between this counter and game time
        // read a still-live scale as expired. Phase 2 passing proved the feature extends the expiry
        // correctly; only the sampling point was wrong. Margins are now >= 6 ticks on both sides.
        //   request  @0.30 dur 1.00 -> original expiry 1.30
        //   refresh  @0.60 dur 1.50 -> refreshed expiry 2.10
        //   survival @1.60 sits 6 ticks past 1.30 and 10 ticks before 2.10
        if (_Phase == 0 && _ElapsedSeconds >= 0.30)
        {
            utils_crowd_agent::Request_SetTransientPersonalSpaceScale(_Agent, 0.5, 1.00);
            _Phase = 1;
            return;
        }

        if (_Phase == 1 && _ElapsedSeconds >= 0.60)
        {
            Assert_True(Math::IsNearlyEqual(utils_crowd_agent::Get_TransientPersonalSpaceScale(_Agent), 0.5, 0.001),
                "valid transient personal-space request did not apply its scale");
            Assert_True(utils_crowd_agent::Get_TransientPersonalSpaceRemainingSeconds(_Agent) > 0.30,
                "valid transient personal-space request did not retain a positive duration");
            utils_crowd_agent::Request_SetTransientPersonalSpaceScale(_Agent, 0.75, 1.50);
            _Phase = 2;
            return;
        }

        if (_Phase == 2 && _ElapsedSeconds >= 0.90)
        {
            Assert_True(Math::IsNearlyEqual(utils_crowd_agent::Get_TransientPersonalSpaceScale(_Agent), 0.75, 0.001),
                "refresh request did not replace the active personal-space scale");
            Assert_True(utils_crowd_agent::Get_TransientPersonalSpaceRemainingSeconds(_Agent) > 1.00,
                "refresh request did not replace the active personal-space expiry");
            utils_crowd_agent::Request_SetTransientPersonalSpaceScale(_Agent, 0.20, 10.0);
            _Phase = 3;
            return;
        }

        if (_Phase == 3 && _ElapsedSeconds >= 1.20)
        {
            Assert_True(Math::IsNearlyEqual(utils_crowd_agent::Get_TransientPersonalSpaceScale(_Agent), 0.75, 0.001),
                "invalid personal-space request mutated the active scale");
            Assert_True(utils_crowd_agent::Get_TransientPersonalSpaceRemainingSeconds(_Agent) < 2.0,
                "invalid personal-space request mutated the active expiry");
            _Phase = 4;
            return;
        }

        if (_Phase == 4 && _ElapsedSeconds >= 1.60)
        {
            Assert_True(Math::IsNearlyEqual(utils_crowd_agent::Get_TransientPersonalSpaceScale(_Agent), 0.75, 0.001),
                f"refresh did not survive beyond the original request expiry (original would have died at 1.30, refreshed expiry 2.10, sampled at {_ElapsedSeconds}, remaining={utils_crowd_agent::Get_TransientPersonalSpaceRemainingSeconds(_Agent)})");
            _Phase = 5;
            return;
        }

        if (_Phase == 5 && _ElapsedSeconds >= 2.50)
        {
            Assert_True(Math::IsNearlyEqual(utils_crowd_agent::Get_TransientPersonalSpaceScale(_Agent), 1.0, 0.001),
                "expired personal-space request did not restore the default scale");
            Assert_True(utils_crowd_agent::Get_TransientPersonalSpaceRemainingSeconds(_Agent) <= 0.001,
                "expired personal-space request retained a positive duration");
            FinishSuccess();
        }
    }
}

class ACk_AutoTest_Crowd_TransientPersonalSpace_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Crowd_TransientPersonalSpace;
    default _TimeoutSeconds = 4.0f;

    UFUNCTION(BlueprintOverride)
    TArray<FString> Get_ExpectedLogErrors() const
    {
        TArray<FString> Out;
        // The invalid-request phase deliberately proves fail-closed/no-mutation.
        Out.Add("Request_SetTransientPersonalSpaceScale dropped");
        return Out;
    }
}
