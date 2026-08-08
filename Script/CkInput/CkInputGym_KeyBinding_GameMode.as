// Language=angelscript

//============================================================================
// CK INPUT KEY-BINDING GYM — GameMode
//
// Five stations over the shipped UCk_Utils_KeyBinding_UE / UCk_Utils_KeyIcon_UE
// surface: binding inspection, remap + conflict, reset + persistence, key-icon
// glyphs, and the mapping-changed signal. Everything is driven from
// ACk_InputGym_KeyBinding_PlayerController exec commands.
//============================================================================

class ACk_InputGym_KeyBinding_GameMode : ACkTests_Gym_Base_GameMode
{
    default PlayerControllerClass = ACk_InputGym_KeyBinding_PlayerController;
    default DefaultPawnClass = ACk_Gym_Base_Pawn;
};
