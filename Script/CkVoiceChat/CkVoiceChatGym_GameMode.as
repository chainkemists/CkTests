// Language=angelscript

// Voice-chat gym: mic loopback + push-to-talk transmit edges (the roger-beep recipe's
// audition surface). GameMode is minimal per the gym spec - all logic lives in the PC.
class ACk_VoiceChatGym_GameMode : ACkTests_Gym_Base_GameMode
{
    default PlayerControllerClass = ACk_VoiceChatGym_PlayerController;
    default DefaultPawnClass = ACk_Gym_Base_Pawn;
}
