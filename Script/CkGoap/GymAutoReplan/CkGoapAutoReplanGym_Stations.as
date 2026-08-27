// Language=angelscript

//============================================================================
// CkGoapAutoReplan_Gym - three stations pinning each replan policy
//
// Each station shares the same minimal action graph (root + one or two
// operators) but configures _ReplanPolicy + _MinReplanIntervalSeconds
// differently to demonstrate when the planner triggers a replan.
//
// All three stations track:
//   - plan-completed count (incremented by OnPlanComplete)
//   - WS-change count (the station mutates Flip key on its own timer)
//
// The discrepancy between the two counts is what teaches the policy:
//   Explicit              -> plans = 1 initial; WS changes climb freely.
//   OnWorldStateDirty (no throttle)   -> plans climb 1:1 with WS changes.
//   OnWorldStateDirty (0.5s throttle) -> plans coalesce ~once per 0.5s.
//============================================================================

USTRUCT()
struct FCk_GoapGym_AutoReplan_Station_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    // Selector - which of the three policies this instance demonstrates.
    UPROPERTY()
    int32 Mode = 0;     // 0=Explicit, 1=OnWSDirty (throttled), 2=OnCostDirty
}

// Marker fragment stamped onto the station entity by the GameMode's
// `Goap.AutoReplan.Explicit.Replan` exec. The station tick polls for it,
// issues Request_Plan, then removes the fragment.
USTRUCT()
struct FCk_Fragment_GoapGym_ForceReplanPending
{
    UPROPERTY()
    int32 Sentinel = 1;
}

//============================================================================

class UCk_EntityScript_GoapGym_AutoReplan_Station : UCk_GenericEntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    UPROPERTY(ExposeOnSpawn)
    int32 Mode = 0;

    private FCk_Handle_Goap_Planner _Planner;
    private FCk_Handle_Goap_WorldState _WS;
    private int32 _PlanCount = 0;
    private int32 _WSChangeCount = 0;
    private bool _AltCostIncreased = false;
    private float _FlipAccumulator = 0.0;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow
    DoConstruct(FCk_Handle& InHandle)
    {
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);

        // Per-mode WS name tag so the GameMode's exec commands target the
        // right station's WS.
        auto WsName = Get_WsNameTagForMode();
        _WS = utils_goap_world_state::Create(InHandle, WsName,
            FCk_Fragment_Goap_WorldState_ParamsData());
        utils_goap_world_state::Set_Value(_WS,
            utils_gameplay_tag::ResolveGameplayTag(n"Gym.Goap.WS.AutoReplan.Goal"),
            false);
        utils_goap_world_state::Set_Value(_WS,
            utils_gameplay_tag::ResolveGameplayTag(n"Gym.Goap.WS.AutoReplan.Flip"),
            false);

        // U11.1: Planner goal on PlannerParams.
        auto Goal = TArray<FCk_GoapWS_Condition_Authored>();
        Goal.Add(FCk_GoapWS_Condition_Authored(
            utils_gameplay_tag::ResolveGameplayTag(n"Gym.Goap.WS.AutoReplan.Goal"),
            true));

        auto ActionSetParams = FCk_Fragment_Goap_PlannerParamsData(
            Get_PlannerTagForMode());
        ActionSetParams.Set_Goal(Goal);
        ActionSetParams.Set_WorldStateSource(_WS);
        ActionSetParams.Set_ReplanPolicy(Get_ReplanPolicyForMode());
        _Planner = utils_goap_planner::Add(InHandle, ActionSetParams);

        utils_goap_planner::AddAction(_Planner,
            FCk_Fragment_Goap_ActionParamsData(UCk_GoapGym_AutoReplan_FlipOp));

        // OnCostDirty station gets a second operator to demonstrate cost-swap.
        if (Mode == 2)
        {
            utils_goap_planner::AddAction(_Planner,
                FCk_Fragment_Goap_ActionParamsData(UCk_GoapGym_AutoReplan_AltOp));
        }

        if (Mode == 1)
        {
            // OnWSDirty station - 0.5s throttle interval to show coalescing.
            utils_goap_planner::Request_SetReplanInterval(_Planner, 0.5);
        }

        // Plan-counter bind. FireIfPayloadInFlightThisFrame default policy
        // catches the same-frame initial plan.
        utils_goap_planner::BindTo_OnPlanComplete(_Planner,
            FCk_Delegate_Goap_OnPlanComplete(this, n"OnPlanComplete"));

        // Auto-flipper timer - OnWSDirty + OnCostDirty stations flip
        // Flip key 10x per second to demonstrate (un)throttled replans.
        // Explicit station auto-flips too, to make the "no replan" visible.
        // Using OnUpdate (every tick) plus an internal accumulator to fire
        // every 0.1s would be more work - for the gym, fire every tick. The
        // visualisation still demonstrates the WS vs plan-count divergence.
        utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"OnAutoFlip"));

        utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"OnDisplayTick"));

        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    private FGameplayTag Get_WsNameTagForMode()
    {
        if (Mode == 0) { return utils_gameplay_tag::ResolveGameplayTag(n"Gym.Goap.WS.Explicit"); }
        if (Mode == 1) { return utils_gameplay_tag::ResolveGameplayTag(n"Gym.Goap.WS.OnWSDirty"); }
        return utils_gameplay_tag::ResolveGameplayTag(n"Gym.Goap.WS.OnCostDirty");
    }

    private FGameplayTag Get_PlannerTagForMode()
    {
        if (Mode == 0) { return utils_gameplay_tag::ResolveGameplayTag(n"Gym.Goap.ActionSet.Explicit"); }
        if (Mode == 1) { return utils_gameplay_tag::ResolveGameplayTag(n"Gym.Goap.ActionSet.OnWSDirty"); }
        return utils_gameplay_tag::ResolveGameplayTag(n"Gym.Goap.ActionSet.OnCostDirty");
    }

    private ECk_Goap_ReplanPolicy Get_ReplanPolicyForMode()
    {
        if (Mode == 0) { return ECk_Goap_ReplanPolicy::Explicit; }
        if (Mode == 1) { return ECk_Goap_ReplanPolicy::OnWorldStateDirty; }
        return ECk_Goap_ReplanPolicy::OnCostDirty;
    }

    private FString Get_PolicyLabel()
    {
        if (Mode == 0) { return "Explicit (manual replan only)"; }
        if (Mode == 1) { return "OnWorldStateDirty (throttled 0.5s)"; }
        return "OnCostDirty";
    }

    UFUNCTION()
    private void OnPlanComplete(FCk_Handle_Goap_Planner InPlanner, FCk_Goap_Payload_OnPlanComplete InPayload)
    {
        _PlanCount = _PlanCount + 1;
    }

    UFUNCTION()
    private void OnAutoFlip(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (ck::Is_NOT_Valid(_WS)) { return; }

        // Throttle to ~10 flips/sec - every tick would dilute the throttle
        // demonstration on Mode 1.
        _FlipAccumulator = _FlipAccumulator + float(InDeltaT.Get_Seconds());
        if (_FlipAccumulator < 0.1) { return; }
        _FlipAccumulator = 0.0;

        auto Tag = utils_gameplay_tag::ResolveGameplayTag(n"Gym.Goap.WS.AutoReplan.Flip");
        auto Cur = utils_goap_world_state::Get_Value(_WS, Tag);
        utils_goap_world_state::Set_Value(_WS, Tag, !Cur);
        _WSChangeCount = _WSChangeCount + 1;

        // OnCostDirty station: bump the AltOp's cost up and down every other
        // tick so the planner has a reason to flip operators based on cost.
        if (Mode == 2 && ck::IsValid(_Planner))
        {
            _AltCostIncreased = !_AltCostIncreased;
            auto NewCost = _AltCostIncreased ? 0.5f : 2.0f;
            utils_goap_planner::Request_SetChildActionCost(_Planner,
                UCk_GoapGym_AutoReplan_AltOp, NewCost);
        }
    }

    UFUNCTION()
    private void OnDisplayTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (ck::Is_NOT_Valid(_Planner)) { return; }

        // Drain a force-replan request stamped by the GameMode's exec.
        auto Self = ck::ToEntity(this);
        if (Self.Has_Fragment(FCk_Fragment_GoapGym_ForceReplanPending))
        {
            Self.Request_Remove(FCk_Fragment_GoapGym_ForceReplanPending);
            utils_goap_planner::Request_Plan(_Planner);
        }

        auto Status = utils_goap_planner::Get_PlanStatus(_Planner);
        auto Plan = utils_goap_planner::Get_PlanClasses(_Planner);

        auto ModeLabel = Get_PolicyLabel();
        auto Title = "";
        auto ButtonsBlock = "";
        if (Mode == 0)
        {
            Title = "STATION A / EXPLICIT";
            ButtonsBlock = "  Goap.AutoReplan.Explicit.Replan\n"
                + "       Manually issue Request_Plan.\n"
                + "       Plan count should jump exactly +1.";
        }
        else if (Mode == 1)
        {
            Title = "STATION B / OnWorldStateDirty (throttle 0.5s)";
            ButtonsBlock = "  (auto-flipping WS every 0.1s)\n"
                + "  Plan count should grow ~2/sec - coalesced from\n"
                + "  ~10 WS changes/sec by the 0.5s throttle window.";
        }
        else
        {
            Title = "STATION C / OnCostDirty";
            ButtonsBlock = "  (auto-bumping AltOp cost between 0.5 and 2.0)\n"
                + "  Plan flips between [FlipOp] and [AltOp] as the\n"
                + "  cheaper operator changes.";
        }

        auto Body = f"Policy   {ModeLabel}\n\n"
            + "Counters\n"
            + f"  Plan count       {_PlanCount}\n"
            + f"  WS changes       {_WSChangeCount}\n\n"
            + "Planner\n"
            + f"  Status           {CkGoapGym_Common::Format_PlanStatus(Status)}\n"
            + f"  Plan length      {Plan.Num()}\n\n"
            + "Console / behaviour\n"
            + ButtonsBlock;

        CkGym_Common::Update_StationDisplay(ck::ToEntity(this),
            Title, Body,
            "Replan policy showcase - see plan vs WS counts.");
    }
}
