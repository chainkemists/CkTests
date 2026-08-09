// Language=angelscript

//============================================================================
// CK INTENT FIGHTING GYM — GameMode
//
// Three stations over the CkIntent surface, all of them read by the player's own
// hands rather than by injected events: the deferral-frame counter that puts a
// number on the module's latency claim, the deferred-versus-instant contrast
// that makes the forward-ambiguity law visible on two buttons at once, and the
// near-miss ring that answers "I did the motion and nothing came out".
//
// Nothing here runs itself. Every station arms its own move set, tells the
// viewer what to do, and grades what came back — so the panels read as working
// or broken to somebody who has never heard of this module.
//============================================================================

class ACk_IntentGym_Fighting_GameMode : ACkTests_Gym_Base_GameMode
{
    default PlayerControllerClass = ACk_IntentGym_Fighting_PlayerController;
    default DefaultPawnClass = ACk_Gym_Base_Pawn;
};
