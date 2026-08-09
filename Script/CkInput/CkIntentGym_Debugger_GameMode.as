// Language=angelscript

//============================================================================
// CK INTENT DEBUGGER GYM — GameMode
//
// Four stations that exist to be looked at BESIDE something else. The two gyms
// next door teach the module; this one feeds the tool that reads it. Each
// station generates the traffic one of the Ck Intent Debugger's views is for —
// deferral episodes for the timeline, a masker for the layer stack, a stick
// sweep for the key/state rosette, three windowed misses for the near-miss ring
// — and each panel names the view to open and states exactly what should appear
// in it.
//
// THE PANEL IS THE CONTROL, THE VIEW IS THE READING. Every number a station
// prints is read back off the same recorded state the debugger reads: the
// phases, the frame record, the layer's drained captures, the scan ring. So a
// panel and a view that disagree is a real finding about one of them, which is
// the only reason to build a gym for a debugger rather than screenshots.
//
// Nothing here runs itself, for the same reason the other two gyms do not: the
// state machines advance on what the PLAYER does.
//============================================================================

class ACk_IntentGym_Debugger_GameMode : ACkTests_Gym_Base_GameMode
{
    default PlayerControllerClass = ACk_IntentGym_Debugger_PlayerController;
    default DefaultPawnClass = ACk_Gym_Base_Pawn;
};
