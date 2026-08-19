// Language=angelscript
//============================================================================
// CK CROWD — AUTOMATION TEST: AN ORPHANED PENDING SLOT IS RECONCILED
//============================================================================
//
// The pending watchdog is keyed on the SLOT, not on FTag_CrowdAgent_PathPending,
// and this test is why. A tag-keyed reconciler cannot see the state the original
// defect produced — slot Pending, tags gone — because losing the tag is exactly
// what ending an episode does. Keying on the slot is what lets it converge from
// arbitrary state instead of only from states the API can still reach.
//
// That is also what makes this row impossible to drive normally: now that every
// terminal releases its episode, an orphan cannot be produced through the public
// API at all. So the fixture runs a REAL episode and a REAL Stop first, then
// re-parks the slot behind the agent's back to synthesise the exact corpse the
// bug used to leave — and requires the reconciler to clean it up.
//============================================================================

class UCk_AutoTest_Crowd_Watchdog_OrphanedPendingSlotIsReleased : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 20.0f;

    private FCk_Handle_CrowdAgent _Agent;
    private const FVector Spawn = FVector(0.0, 0.0, 0.0);
    private const FVector Goal = FVector(300.0, 0.0, 0.0);

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step(           "run and stop a real movement episode",        n"Step_MoveThenStop");
        Add_Step_WaitFrames("let the release settle",                      20);
        Add_Step(           "the released episode left nothing behind",    n"Step_AssertReleased");
        Add_Step(           "synthesise the orphan the defect used to leave", n"Step_OrphanTheSlot");
        Add_Step_WaitFrames("give the reconciler a tick to notice",        10);
        Add_Step(           "the reconciler released the orphan",          n"Step_AssertReconciled");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_MoveThenStop(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto LocalHandle = InHandle;
        LocalHandle.Set_DebugName(n"WatchdogOrphan_Agent");
        utils_nav::Request_NavigationRebuild_ForTesting(LocalHandle);

        auto AgentTransform = utils_transform::Add(LocalHandle,
            FTransform(FRotator::ZeroRotator, Spawn, FVector::OneVector),
            ECk_Replication::DoesNotReplicate);
        auto AgentParams = FCk_Fragment_CrowdAgent_ParamsData(42.0f, 192.0f);
        AgentParams.Set_MaxSpeed(60.0f);
        _Agent = utils_crowd_agent::Add(AgentTransform, AgentParams);

        utils_velocity::Add(LocalHandle,
            FCk_Fragment_Velocity_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector),
            ECk_Replication::DoesNotReplicate);
        utils_acceleration::Add(LocalHandle,
            FCk_Fragment_Acceleration_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector),
            ECk_Replication::DoesNotReplicate);
        utils_euler_integrator::Request_Start(LocalHandle);

        utils_crowd_agent::Request_MoveTo(_Agent, FCk_Request_CrowdAgent_MoveTo(Goal));
        utils_crowd_agent::Request_Stop(_Agent);
    }

    UFUNCTION()
    private void Step_AssertReleased(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(utils_nav::Get_PathStatus(_Agent) == ECk_Nav_PathStatus::None,
            "the real Stop must release the episode before the orphan is synthesised, or this test proves nothing");
    }

    UFUNCTION()
    private void Step_OrphanTheSlot(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        // Park the slot WITHOUT the crowd tags that a real dispatch would set. Only the framework
        // can reach this state now; that is the point of the seam.
        auto AgentGeneric = FCk_Handle(_Agent);
        utils_nav::Request_MarkPathPending_ForTesting(AgentGeneric, 999);

        Assert_True(utils_nav::Get_PathStatus(_Agent) == ECk_Nav_PathStatus::Pending,
            "fixture must actually leave the slot Pending, or the reconciler has nothing to find");
    }

    UFUNCTION()
    private void Step_AssertReconciled(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto Status = utils_nav::Get_PathStatus(_Agent);
        Assert_True(Status != ECk_Nav_PathStatus::Pending,
            f"the reconciler must release a Pending slot that no live episode owns — it still reads {Status}, which is the wedge the watchdog exists to prevent");
    }
}

class ACk_AutoTest_Crowd_Watchdog_OrphanedPendingSlotIsReleased_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 20.0f;
    default _TestEntityScriptClass = UCk_AutoTest_Crowd_Watchdog_OrphanedPendingSlotIsReleased;

    // The reconciler is SUPPOSED to ensure on an orphaned slot — firing loudly is the behaviour
    // under test, so declare it rather than let the harness auto-fail on the test's own
    // deliberate output. Plain substring match, not regex.
    UFUNCTION(BlueprintOverride)
    TArray<FString> Get_ExpectedLogErrors() const
    {
        TArray<FString> Out;
        Out.Add("holds a Pending nav-path slot with no live movement episode");
        return Out;
    }
}
