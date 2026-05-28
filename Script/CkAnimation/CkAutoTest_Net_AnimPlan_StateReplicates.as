// Language=angelscript

//============================================================================
// CK ANIMATION — NET AUTOMATION TEST: ANIMPLAN STATE REPLICATES
//============================================================================
//
// AnimPlan state is pure tag data (goal/cluster/state gameplay tags) — no
// skeletal mesh required for the state-replication contract. The default
// NetSubject's entity-script adds a Replicates AnimPlan (goal + cluster +
// state A) on both worlds. The server Request_UpdateAnimState's it to state B;
// the client polls Get_AnimState for B via the FCk_RepData_AnimPlans handler
// (OnChange -> Request_UpdateAnimState on the client). The AnimPlan is fetched
// by goal tag (TryGet_AnimPlan), so no actor stash is needed.
//
// Surface: Ck.Animation.Net.AS_AnimPlan_StateReplicates
//============================================================================

class UCk_AutoTest_Net_AnimPlan_StateReplicates : UCk_AutoTest_NetBase
{
    private FName _GoalName    = n"AnimPlan.Goal.AutoTest_Net";
    private FName _ClusterName = n"AnimPlan.Cluster.AutoTest_Net";
    private FName _StateBName  = n"AnimPlan.State.AutoTest_Net_B";

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Subject = Get_SubjectEntity();
        if (ck::Is_NOT_Valid(Subject))
        { FinishFailure("subject entity not found"); return; }

        auto GoalTag = utils_gameplay_tag::ResolveGameplayTag(_GoalName);
        auto AnimPlan = utils_anim_plan::TryGet_AnimPlan(Subject, GoalTag);
        if (ck::Is_NOT_Valid(AnimPlan))
        { FinishFailure("AnimPlan not found on subject — entity-script Construct didn't add it?"); return; }

        if (utils_net::Get_HasAuthority(Subject))
        {
            auto ClusterTag = utils_gameplay_tag::ResolveGameplayTag(_ClusterName);
            auto StateBTag  = utils_gameplay_tag::ResolveGameplayTag(_StateBName);
            auto Request = FCk_Request_AnimPlan_UpdateAnimState(ClusterTag, StateBTag);
            utils_anim_plan::Request_UpdateAnimState(AnimPlan, Request);
            FinishSuccess();
            return;
        }

        WaitOneFrame(n"OnPollState");
    }

    private int _PollCount = 0;
    private const int kPollBudget = 400;

    UFUNCTION()
    private void OnPollState(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        _PollCount++;

        auto Subject = Get_SubjectEntity();
        if (ck::Is_NOT_Valid(Subject))
        { WaitOneFrame(n"OnPollState"); return; }

        auto GoalTag = utils_gameplay_tag::ResolveGameplayTag(_GoalName);
        auto AnimPlan = utils_anim_plan::TryGet_AnimPlan(Subject, GoalTag);
        if (ck::Is_NOT_Valid(AnimPlan))
        { WaitOneFrame(n"OnPollState"); return; }

        auto StateBTag = utils_gameplay_tag::ResolveGameplayTag(_StateBName);
        if (utils_anim_plan::Get_AnimState(AnimPlan).Get_AnimState() == StateBTag)
        {
            FinishSuccess();
            return;
        }
        if (_PollCount > kPollBudget)
        { FinishFailure("client AnimPlan never gained the replicated state B"); return; }

        WaitOneFrame(n"OnPollState");
    }
}
