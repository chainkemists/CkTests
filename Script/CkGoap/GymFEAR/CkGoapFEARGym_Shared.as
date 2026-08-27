// Language=angelscript

//============================================================================
// CkGoapFEAR_Gym - Shared tags
//
// Canonical "this is what GOAP is for" demo, adapted from Jeff Orkin's
// F.E.A.R. AI paper. One station, one Planner promoted to a sub-Planner at
// AttackEnemy. Player toggles WS keys via console commands and watches the
// plan re-resolve - including the iconic flank-ambush short-circuit.
//
// Two tag families are introduced here so they exist as registry-known tags
// when the planner / world-state ask for them at runtime:
//
//   FEAR.WS.*         - world-state keys + ActionSet + WS entity names.
//   FEAR.Station.*    - station identity tag (one entity per gym).
//
// The FEAR gym intentionally lives in its own namespace separate from the
// existing Gym.Goap.* tree so the two gyms can never collide.
//============================================================================

namespace Ck
{
    asset GoapFEARGym_Tags of UCk_GameplayTags
    {
        // Station identity tag (one per station-instance entity).
        GameplayTags.Add(n"Gym.GoapFEAR.Station.Combatant");

        // Planner name tags - top-level + promoted sub-Planner.
        GameplayTags.Add(n"Gym.GoapFEAR.ActionSet.Combatant");
        GameplayTags.Add(n"Gym.GoapFEAR.ActionSet.Combatant.AttackEnemy");

        // World-state entity name tag (one per station).
        GameplayTags.Add(n"Gym.GoapFEAR.WS.Combatant");

        // World-state keys.
        GameplayTags.Add(n"Gym.GoapFEAR.WS.Combatant.EnemyVisible");
        GameplayTags.Add(n"Gym.GoapFEAR.WS.Combatant.EnemyNeutralized");
        GameplayTags.Add(n"Gym.GoapFEAR.WS.Combatant.HasAmmo");
        GameplayTags.Add(n"Gym.GoapFEAR.WS.Combatant.HasAmmoReserve");
        GameplayTags.Add(n"Gym.GoapFEAR.WS.Combatant.AtCover");
        GameplayTags.Add(n"Gym.GoapFEAR.WS.Combatant.BehindEnemy");
        GameplayTags.Add(n"Gym.GoapFEAR.WS.Combatant.HeardSound");
        GameplayTags.Add(n"Gym.GoapFEAR.WS.Combatant.Patrolling");
    }
}
