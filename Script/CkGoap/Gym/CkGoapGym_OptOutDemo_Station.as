// Language=angelscript

//============================================================================
// CkGoapGym — Opt-Out Demo station
//
// EXPLICITLY demonstrates the _AllowPlanFailed=true opt-out path described in
// CkGoap/CLAUDE.md § "Design tenets / Every Planner must always produce a
// valid plan". This is the COUNTERPART to the other CkGoap gyms: every other
// game-content Planner must comply with the always-valid-plan tenet (and the
// gyms here include explicit fallback Actions to do so). This station is the
// one place where opting out is the demo.
//
// Construction:
//   - Planner goal:  OptOutDemo.Unreachable = true
//   - One Action (CannotReach) whose effect = OptOutDemo.Unreachable=true,
//     gated by a precondition (OptOutDemo.Touch=true) that the gym never
//     flips. Even though the Action's effect technically matches the goal,
//     the precondition is registered as false and never satisfied — so the
//     planner provably never finds a viable Action chain.
//   - PlannerParams.Set_AllowPlanFailed(true). Without this flag, the
//     framework's runtime CK_ENSURE_IF_NOT on PlanFailed would fire.
//
// What the debugger should show:
//   - PlanStatus = PlanFailed every replan
//   - An OPT-OUT indicator (whatever the debugger renders for
//     _AllowPlanFailed=true) signalling this is intentional, not a bug
//   - No CK_ENSURE_IF_NOT warnings in the log
//
// Compare with MakeTea: MakeTea also opts out but ONLY when the player drops
// an ingredient. This station opts out unconditionally — the goal is
// structurally unreachable. Treat the two stations together as the complete
// teaching pair for the opt-out path.
//============================================================================

USTRUCT()
struct FCk_GoapGym_OptOutDemo_Station_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;
}

// The intentionally-blocked Action. Precondition Touch=true is never flipped
// by the gym, so the precondition is always false and the planner backchain
// never finds this Action selectable. The Action exists only to register
// both WS keys in the Planner's key registry — without at least one Action
// referencing each key, writes to them would be silent no-ops.
class UCk_GoapGym_OptOutDemo_CannotReach : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        AddPrecondition(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.OptOutDemo.Touch"), true);
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.OptOutDemo.Unreachable"), true);
        SetCost(1.0);
    }
}

class UCk_EntityScript_GoapGym_OptOutDemo_Station : UCk_GenericEntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    private FCk_Handle_Goap_Planner _Planner;
    private FCk_Handle_Goap_WorldState _WS;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow
    DoConstruct(FCk_Handle& InHandle)
    {
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);

        _WS = utils_goap_world_state::Create(InHandle,
            utils_gameplay_tag::ResolveGameplayTag(n"Gym.Goap.WS.OptOutDemo"),
            FCk_Fragment_Goap_WorldState_ParamsData());
        utils_goap_world_state::Set_Value(_WS,
            utils_gameplay_tag::ResolveGameplayTag(n"Gym.Goap.WS.OptOutDemo.Unreachable"),
            false);
        utils_goap_world_state::Set_Value(_WS,
            utils_gameplay_tag::ResolveGameplayTag(n"Gym.Goap.WS.OptOutDemo.Touch"),
            false);

        auto Goal = TArray<FCk_GoapWS_Condition_Authored>();
        Goal.Add(FCk_GoapWS_Condition_Authored(
            utils_gameplay_tag::ResolveGameplayTag(n"Gym.Goap.WS.OptOutDemo.Unreachable"),
            true));

        auto PlannerParams = FCk_Fragment_Goap_PlannerParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"Gym.Goap.ActionSet.OptOutDemo"));
        PlannerParams.Set_Goal(Goal);
        PlannerParams.Set_WorldStateSource(_WS);
        PlannerParams.Set_ReplanPolicy(ECk_Goap_ReplanPolicy::OnWorldStateDirty);

        // -----------------------------------------------------------------
        // This station intentionally demonstrates the _AllowPlanFailed=true
        // opt-out path. PlanFailed will fire continuously (the goal is
        // structurally unreachable from the catalog). The debugger should
        // clearly show this is opted-in rather than a misconfiguration.
        // See CkGoap/CLAUDE.md § "Design tenets / Every Planner must always
        // produce a valid plan" for the tenet itself and the opt-out rules.
        // -----------------------------------------------------------------
        PlannerParams.Set_AllowPlanFailed(true);

        _Planner = utils_goap_planner::Add(InHandle, PlannerParams);

        utils_goap_planner::AddAction(_Planner,
            FCk_Fragment_Goap_ActionParamsData(UCk_GoapGym_OptOutDemo_CannotReach));

        utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"OnDisplayTick"));

        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    UFUNCTION()
    private void OnDisplayTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (ck::Is_NOT_Valid(_Planner)) { return; }

        auto Status = utils_goap_planner::Get_PlanStatus(_Planner);
        auto Plan = utils_goap_planner::Get_PlanClasses(_Planner);

        auto Body = "This station explicitly opts out of the always-valid-plan\n"
            + "tenet via _AllowPlanFailed=true. The Planner's goal is\n"
            + "unreachable (no Action's effect can satisfy it from any WS\n"
            + "state — the sole Action has a precondition the gym never\n"
            + "flips), so PlanFailed fires every replan. Watch the\n"
            + "debugger: the OPT-OUT indicator should make it clear this\n"
            + "is INTENTIONAL, not a bug.\n\n"
            + "Compare with MakeTea (Station 2): MakeTea opts out only when\n"
            + "the player drops an ingredient. This station is permanently\n"
            + "PlanFailed by design.\n\n"
            + "Planner\n"
            + f"  Status        {CkGoapGym_Common::Format_PlanStatus(Status)}\n"
            + f"  Plan length   {Plan.Num()}   (expected: 0)\n\n"
            + "See CkGoap/CLAUDE.md § \"Design tenets / Every Planner must\n"
            + "always produce a valid plan\" for the tenet itself and the\n"
            + "rules around opt-out.";

        CkGym_Common::Update_StationDisplay(ck::ToEntity(this),
            "STATION 7 / OPT-OUT DEMO", Body,
            "Intentional _AllowPlanFailed=true.\nDemonstrates the tenet's opt-out path.");
    }
}
