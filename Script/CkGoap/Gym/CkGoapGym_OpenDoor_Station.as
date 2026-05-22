// Language=angelscript

//============================================================================
// CkGoapGym — Open Door station entity
//
// Visual + interactive wrapper around the OpenDoor Planner. The station
// entity carries its own Goap root, Planner, and WS. A Tick timer refreshes
// the alcove panel with the current Door.IsOpen value, plan status, and the
// resolved plan.
//
// Player commands (exec'd on ACk_GoapGym_PlayerController, routed by station
// tag):
//   Goap.OpenDoor.Toggle  — flips Door.IsOpen and lets OnWorldStateDirty
//                           replan from the new state.
//============================================================================

USTRUCT()
struct FCk_GoapGym_OpenDoor_Station_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;
}

class UCk_EntityScript_GoapGym_OpenDoor_Station : UCk_GenericEntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    private FCk_Handle_Goap_Planner _Planner;
    private FCk_Handle_Goap_Action _RootAction;
    private FCk_Handle_Goap_WorldState _WS;
    private TArray<TSubclassOf<UCk_GoapAction_EntityScript>> _KnownClasses;
    private TArray<FString> _KnownLabels;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow
    DoConstruct(FCk_Handle& InHandle)
    {
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);

        // World-state for this station — Door.IsOpen starts closed.
        _WS = utils_goap_world_state::Create(InHandle,
            utils_gameplay_tag::ResolveGameplayTag(n"Gym.Goap.WS.Door"),
            FCk_Fragment_Goap_WorldState_ParamsData());
        utils_goap_world_state::Set_Value(_WS,
            utils_gameplay_tag::ResolveGameplayTag(n"Gym.Goap.WS.Door.IsOpen"),
            false);

        // U11.1: Planner goal Door.IsOpen=true. OnWorldStateDirty so toggling
        // the WS automatically retriggers planning.
        auto Goal = TArray<FCk_GoapWS_Condition_Authored>();
        Goal.Add(FCk_GoapWS_Condition_Authored(
            utils_gameplay_tag::ResolveGameplayTag(n"Gym.Goap.WS.Door.IsOpen"),
            true));

        auto ActionSetParams = FCk_Fragment_Goap_PlannerParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"Gym.Goap.ActionSet.Door"));
        ActionSetParams.Set_Goal(Goal);
        ActionSetParams.Set_WorldStateSource(_WS);
        _Planner = utils_goap_planner::Add(InHandle, ActionSetParams);

        auto RootParams = FCk_Fragment_Goap_ActionParamsData(UCk_GoapGym_OpenDoor_Root);
        RootParams.Set_ReplanPolicy(ECk_Goap_ReplanPolicy::OnWorldStateDirty);

        _RootAction = utils_goap_planner::AddAction(_Planner, RootParams);

        // Single operator — atomic OpenDoor.
        auto OpParams = FCk_Fragment_Goap_ActionParamsData(UCk_GoapGym_OpenDoor_Operator);
        utils_goap_planner::AddAction(_Planner, OpParams);

        // Label map for plan rendering.
        _KnownClasses.Add(UCk_GoapGym_OpenDoor_Operator);
        _KnownLabels.Add("OpenDoor");

        utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"OnDisplayTick"));

        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    UFUNCTION()
    private void OnDisplayTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (ck::Is_NOT_Valid(_RootAction)) { return; }

        auto IsOpen = utils_goap_world_state::Get_Value(_WS,
            utils_gameplay_tag::ResolveGameplayTag(n"Gym.Goap.WS.Door.IsOpen"));
        auto Status = utils_goap_planner::Get_PlanStatus(_Planner);
        auto Plan = utils_goap_planner::Get_PlanClasses(_Planner);

        auto WSLine = f"  Door.IsOpen      {CkGoapGym_Common::Render_Bool(IsOpen)}";
        auto StatusLine = f"  Status           {CkGoapGym_Common::Format_PlanStatus(Status)}";
        auto PlanLine = f"  Plan             {CkGoapGym_Common::Format_Plan(Plan, _KnownClasses, _KnownLabels)}";
        auto ChainLine = f"  Chain.Num()      {utils_goap_planner::Get_ActiveChain(_Planner).Num()}";

        auto Body = "World State\n" + WSLine
            + "\n\nPlanner\n" + StatusLine
            + "\n" + PlanLine
            + "\n" + ChainLine
            + "\n\nButtons\n  Goap.Door.Toggle  Flip Door.IsOpen";

        CkGym_Common::Update_StationDisplay(ck::ToEntity(this),
            "STATION 1 / OPEN DOOR", Body,
            "Single atomic operator. Root goal Door.IsOpen=true.\nOpenDoor is the only operator.");
    }
}
