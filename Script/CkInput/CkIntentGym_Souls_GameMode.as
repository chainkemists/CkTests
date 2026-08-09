// Language=angelscript

//============================================================================
// CK INTENT SOULS GYM — GameMode
//
// Three stations over the ONE ambiguity that reaches forward — the hold. The
// fighting gym next door shows that a press is answered immediately unless
// waiting is the only way to be right; this one shows the case where waiting IS
// the only way to be right, and what that costs: the tap/hold pair resolving at
// its threshold, a two-second charge counting down in front of you, and a menu
// opening mid-charge and eating it.
//
// Nothing here runs itself. Every station arms its own move set, tells the
// viewer what to do, and grades what came back — so the panels read as working
// or broken to somebody who has never heard of this module.
//============================================================================

class ACk_IntentGym_Souls_GameMode : ACkTests_Gym_Base_GameMode
{
    default PlayerControllerClass = ACk_IntentGym_Souls_PlayerController;
    default DefaultPawnClass = ACk_Gym_Base_Pawn;
};
