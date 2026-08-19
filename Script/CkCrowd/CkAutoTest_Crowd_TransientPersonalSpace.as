// Language=angelscript
//============================================================================
// CK CROWD — AUTOMATION TEST: TRANSIENT PERSONAL SPACE
//============================================================================

class UCk_AutoTest_Crowd_TransientPersonalSpace : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 4.0f;

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

        if (_Phase == 0 && _ElapsedSeconds >= 0.15)
        {
            utils_crowd_agent::Request_SetTransientPersonalSpaceScale(_Agent, 0.5, 0.40);
            _Phase = 1;
            return;
        }

        if (_Phase == 1 && _ElapsedSeconds >= 0.25)
        {
            Assert_True(Math::IsNearlyEqual(utils_crowd_agent::Get_TransientPersonalSpaceScale(_Agent), 0.5, 0.001),
                "valid transient personal-space request did not apply its scale");
            Assert_True(utils_crowd_agent::Get_TransientPersonalSpaceRemainingSeconds(_Agent) > 0.05,
                "valid transient personal-space request did not retain a positive duration");
            utils_crowd_agent::Request_SetTransientPersonalSpaceScale(_Agent, 0.75, 0.50);
            _Phase = 2;
            return;
        }

        if (_Phase == 2 && _ElapsedSeconds >= 0.35)
        {
            Assert_True(Math::IsNearlyEqual(utils_crowd_agent::Get_TransientPersonalSpaceScale(_Agent), 0.75, 0.001),
                "refresh request did not replace the active personal-space scale");
            Assert_True(utils_crowd_agent::Get_TransientPersonalSpaceRemainingSeconds(_Agent) > 0.35,
                "refresh request did not replace the active personal-space expiry");
            utils_crowd_agent::Request_SetTransientPersonalSpaceScale(_Agent, 0.20, 10.0);
            _Phase = 3;
            return;
        }

        if (_Phase == 3 && _ElapsedSeconds >= 0.45)
        {
            Assert_True(Math::IsNearlyEqual(utils_crowd_agent::Get_TransientPersonalSpaceScale(_Agent), 0.75, 0.001),
                "invalid personal-space request mutated the active scale");
            Assert_True(utils_crowd_agent::Get_TransientPersonalSpaceRemainingSeconds(_Agent) < 1.0,
                "invalid personal-space request mutated the active expiry");
            _Phase = 4;
            return;
        }

        if (_Phase == 4 && _ElapsedSeconds >= 0.70)
        {
            Assert_True(Math::IsNearlyEqual(utils_crowd_agent::Get_TransientPersonalSpaceScale(_Agent), 0.75, 0.001),
                "refresh did not survive beyond the original request expiry");
            _Phase = 5;
            return;
        }

        if (_Phase == 5 && _ElapsedSeconds >= 1.00)
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
