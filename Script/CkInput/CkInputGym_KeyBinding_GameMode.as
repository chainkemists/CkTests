// Language=angelscript

//============================================================================
// CK INPUT KEY-BINDING GYM - GameMode
//
// Five stations over the shipped UCk_Utils_KeyBinding_UE / UCk_Utils_KeyIcon_UE
// surface: reset + persistence, binding inspection, remap + conflict, key-icon
// glyphs, and the mapping-changed signal.
//
// The gym runs itself. The Remap + Conflict station owns a state machine that
// walks the whole remapping surface on a loop and checks every step against what
// it expected, and the other four panels colour their own live reads green or
// red off the same profile. A viewer only types a command to drive something by
// hand - every one of them holds the demo first.
//============================================================================

class ACk_InputGym_KeyBinding_GameMode : ACkTests_Gym_Base_GameMode
{
    default PlayerControllerClass = ACk_InputGym_KeyBinding_PlayerController;
    default DefaultPawnClass = ACk_Gym_Base_Pawn;
};
