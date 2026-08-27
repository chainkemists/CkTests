// --------------------------------------------------------------------------------------------------------------------
// Crowd Diagnostic Gym - Gate 3+
//
// Auto-cycling 2-agent HeadOn + 5-agent Cluster stations spaced 3000cm apart so probes
// can't cross. Drives the digest-emission debugging loop instead of the screenshot loop:
// every cycle ends with per-agent metrics logged at LogCk_Crowd Display, grep-friendly
// under the [CrowdDiag] prefix.
//
// Cycle timeline:
//   t=0.0s  spawn agents + issue MoveTo (both stations simultaneously)
//   t=9.0s  emit cycle digest (per-agent x/y/speed/dir + RDP-simplified path)
//   t=10.0s destroy agents, increment cycle counter, repeat
//
// Console:
//   Ck_GymCrowd_Diag_Pause    pause auto-cycling without destroying current agents
//   Ck_GymCrowd_Diag_Resume   resume auto-cycling
//   Ck_GymCrowd_Diag_DumpNow  emit current cycle's digest immediately (for in-progress state)
// --------------------------------------------------------------------------------------------------------------------

class ACk_CrowdGym_Diag_GameMode : ACkTests_Gym_Base_GameMode
{
    default PlayerControllerClass = ACk_CrowdGym_Diag_PlayerController;
    default DefaultPawnClass = ACk_Gym_Base_Pawn;
}
