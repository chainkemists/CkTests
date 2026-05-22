// Language=angelscript

//============================================================================
// CkGoapGym_Shared
//
// Shared scaffolding for the three CkGoap gyms:
//   - CkGoap_Gym             — five-station ascending-complexity showcase
//   - CkGoapAutoReplan_Gym   — three-station replan-policy showcase
//   - CkGoapEmpire_Gym       — five-action empire-research plan
//
// Each gym station is its own ECS entity carrying:
//   - utils_transform   (so the GymStation alcove can render where we place it)
//   - utils_goap        (a Goap root)
//   - one or more utils_goap_planner::Add entries
//   - a Tick timer that re-pushes the status panel text every frame
//
// World-state mutations and "buttons" are exposed as UFUNCTION(Exec) console
// commands on each gym's player controller. Each command resolves the station
// by its gym station tag, then mutates the WS handle it holds — the GOAP
// runtime reacts via the OnWorldStateDirty replan policy on the relevant root.
//============================================================================

namespace Ck
{
    asset GoapGym_Tags of UCk_GameplayTags
    {
        // Station identity tags (one per station-instance entity).
        GameplayTags.Add(n"Gym.Goap.Station.OpenDoor");
        GameplayTags.Add(n"Gym.Goap.Station.MakeTea");
        GameplayTags.Add(n"Gym.Goap.Station.CrossRiver");
        GameplayTags.Add(n"Gym.Goap.Station.Patrol");
        GameplayTags.Add(n"Gym.Goap.Station.Survival");
        GameplayTags.Add(n"Gym.Goap.Station.CombatBrain");

        GameplayTags.Add(n"Gym.Goap.AutoReplan.Explicit");
        GameplayTags.Add(n"Gym.Goap.AutoReplan.OnWSDirty");
        GameplayTags.Add(n"Gym.Goap.AutoReplan.OnCostDirty");

        GameplayTags.Add(n"Gym.Goap.Empire.Research");

        // Planner name tags (one per Planner — used for Find_ByName).
        GameplayTags.Add(n"Gym.Goap.ActionSet.Door");
        GameplayTags.Add(n"Gym.Goap.ActionSet.Tea");
        GameplayTags.Add(n"Gym.Goap.ActionSet.CrossRiver");
        GameplayTags.Add(n"Gym.Goap.ActionSet.Patrol");
        GameplayTags.Add(n"Gym.Goap.ActionSet.Survival.Hunger");
        GameplayTags.Add(n"Gym.Goap.ActionSet.Survival.Defense");
        GameplayTags.Add(n"Gym.Goap.ActionSet.CombatBrain");
        GameplayTags.Add(n"Gym.Goap.ActionSet.CombatBrain.Engage");
        GameplayTags.Add(n"Gym.Goap.ActionSet.CombatBrain.LightAttacks");
        GameplayTags.Add(n"Gym.Goap.ActionSet.CombatBrain.HeavyAttacks");
        GameplayTags.Add(n"Gym.Goap.ActionSet.Explicit");
        GameplayTags.Add(n"Gym.Goap.ActionSet.OnWSDirty");
        GameplayTags.Add(n"Gym.Goap.ActionSet.OnCostDirty");
        GameplayTags.Add(n"Gym.Goap.ActionSet.Empire");

        // World-state entity name tags (one per WS entity per station).
        GameplayTags.Add(n"Gym.Goap.WS.Door");
        GameplayTags.Add(n"Gym.Goap.WS.Tea");
        GameplayTags.Add(n"Gym.Goap.WS.CrossRiver");
        GameplayTags.Add(n"Gym.Goap.WS.Patrol");
        GameplayTags.Add(n"Gym.Goap.WS.Survival");
        GameplayTags.Add(n"Gym.Goap.WS.CombatBrain");
        GameplayTags.Add(n"Gym.Goap.WS.Explicit");
        GameplayTags.Add(n"Gym.Goap.WS.OnWSDirty");
        GameplayTags.Add(n"Gym.Goap.WS.OnCostDirty");
        GameplayTags.Add(n"Gym.Goap.WS.Empire");

        // World-state keys — Open Door station.
        GameplayTags.Add(n"Gym.Goap.WS.Door.IsOpen");

        // World-state keys — Make Tea station.
        GameplayTags.Add(n"Gym.Goap.WS.Tea.HasKettle");
        GameplayTags.Add(n"Gym.Goap.WS.Tea.HasWater");
        GameplayTags.Add(n"Gym.Goap.WS.Tea.HasTeaLeaves");
        GameplayTags.Add(n"Gym.Goap.WS.Tea.HasCup");
        GameplayTags.Add(n"Gym.Goap.WS.Tea.WaterBoiled");
        GameplayTags.Add(n"Gym.Goap.WS.Tea.TeaSteeped");
        GameplayTags.Add(n"Gym.Goap.WS.Tea.TeaPoured");
        GameplayTags.Add(n"Gym.Goap.WS.Tea.TeaServed");

        // World-state keys — Cross River station.
        GameplayTags.Add(n"Gym.Goap.WS.CrossRiver.BridgeIsOpen");
        GameplayTags.Add(n"Gym.Goap.WS.CrossRiver.HasCoin");
        GameplayTags.Add(n"Gym.Goap.WS.CrossRiver.Crossed");

        // World-state keys — Patrol station (U11.6 multi-tier shape).
        // Top goal: AreaPatrolled=true (replaces old Complete).
        // Mid-tier composites each satisfy one sub-key before MarkDone fires.
        GameplayTags.Add(n"Gym.Goap.WS.Patrol.AtWaypoint");
        GameplayTags.Add(n"Gym.Goap.WS.Patrol.AreaScanned");
        GameplayTags.Add(n"Gym.Goap.WS.Patrol.AreaPatrolled");

        // World-state keys — Survival station.
        GameplayTags.Add(n"Gym.Goap.WS.Survival.Hungry");
        GameplayTags.Add(n"Gym.Goap.WS.Survival.HasFood");
        GameplayTags.Add(n"Gym.Goap.WS.Survival.ThreatActive");
        GameplayTags.Add(n"Gym.Goap.WS.Survival.HasWeapon");
        GameplayTags.Add(n"Gym.Goap.WS.Survival.SafeFromThreat");

        // World-state keys — Combat Brain station (4-tier canonical demo).
        // Mirrors the DeepNesting AutoTest's shape:
        //   Alive (Planner)  goal EnemyDead=true
        //     Engage (Action+Planner) goal EnemyAttacked=true
        //       LightAttacks (Action+Planner) goal EnemyHit=true
        //         Light1/Light2/Light3 (atomic leaves) effect EnemyHit
        //       HeavyAttacks (Action+Planner) goal EnemyHit=true
        //         Heavy1/Heavy2 (atomic leaves) effect EnemyHit
        //     Win (atomic leaf) pre EnemyAttacked, effect EnemyDead
        // Two additional WS keys gate the mid-tier branches and let the user
        // observe replans when toggled: WeaponEquipped (light branch) and
        // StaminaHigh (heavy branch).
        GameplayTags.Add(n"Gym.Goap.WS.CombatBrain.EnemyVisible");
        GameplayTags.Add(n"Gym.Goap.WS.CombatBrain.WeaponEquipped");
        GameplayTags.Add(n"Gym.Goap.WS.CombatBrain.StaminaHigh");
        GameplayTags.Add(n"Gym.Goap.WS.CombatBrain.EnemyHit");
        GameplayTags.Add(n"Gym.Goap.WS.CombatBrain.EnemyAttacked");
        GameplayTags.Add(n"Gym.Goap.WS.CombatBrain.EnemyDead");

        // World-state keys — AutoReplan stations (Explicit / OnWSDirty / OnCostDirty).
        GameplayTags.Add(n"Gym.Goap.WS.AutoReplan.Goal");
        GameplayTags.Add(n"Gym.Goap.WS.AutoReplan.Flip");

        // World-state keys — Empire station.
        GameplayTags.Add(n"Gym.Goap.WS.Empire.HasFood");
        GameplayTags.Add(n"Gym.Goap.WS.Empire.HasGold");
        GameplayTags.Add(n"Gym.Goap.WS.Empire.HasWood");
        GameplayTags.Add(n"Gym.Goap.WS.Empire.BarracksBuilt");
        GameplayTags.Add(n"Gym.Goap.WS.Empire.FeudalResearched");
    }
}

//============================================================================
// CkGoapGym_Common — shared helpers used by every station entity script
//============================================================================
namespace CkGoapGym_Common
{
    // Translate ECk_GoapPlanStatus -> short label.
    FString Format_PlanStatus(ECk_GoapPlanStatus InStatus)
    {
        if (InStatus == ECk_GoapPlanStatus::Idle)                 { return "IDLE"; }
        if (InStatus == ECk_GoapPlanStatus::Planning)             { return "PLANNING..."; }
        if (InStatus == ECk_GoapPlanStatus::PlanFound)            { return "PLAN FOUND"; }
        if (InStatus == ECk_GoapPlanStatus::PlanFailed)           { return "PLAN FAILED"; }
        if (InStatus == ECk_GoapPlanStatus::CostThresholdReached) { return "COST THRESHOLD"; }
        return "?";
    }

    // Render a boolean WS value in a panel-friendly way.
    FString Render_Bool(bool InValue)
    {
        return InValue ? "[X]" : "[ ]";
    }

    // Renders an action plan as a label chain using a caller-provided label
    // resolver. We can't trivially reflect class -> human name from
    // TSubclassOf<UCk_GoapAction_EntityScript> in AS, so each station passes a
    // parallel TArray<FString> of labels in declaration order plus the
    // matching TArray<TSubclassOf<>> for equality lookup.
    FString
    Format_Plan(
        TArray<TSubclassOf<UCk_GoapAction_EntityScript>> InPlan,
        TArray<TSubclassOf<UCk_GoapAction_EntityScript>> InKnownClasses,
        TArray<FString> InKnownLabels)
    {
        if (InPlan.Num() == 0) { return "(empty — goal already satisfied)"; }

        auto Out = "";
        for (int32 i = 0; i < InPlan.Num(); i++)
        {
            auto Label = Lookup_Label(InPlan[i], InKnownClasses, InKnownLabels);
            if (i == 0) { Out = Label; }
            else        { Out = f"{Out} -> {Label}"; }
        }
        return Out;
    }

    FString
    Lookup_Label(
        TSubclassOf<UCk_GoapAction_EntityScript> InQuery,
        TArray<TSubclassOf<UCk_GoapAction_EntityScript>> InKnownClasses,
        TArray<FString> InKnownLabels)
    {
        for (int32 i = 0; i < InKnownClasses.Num() && i < InKnownLabels.Num(); i++)
        {
            if (InKnownClasses[i] == InQuery) { return InKnownLabels[i]; }
        }
        return "<unknown>";
    }
}
