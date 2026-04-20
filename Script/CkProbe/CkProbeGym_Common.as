//============================================================================
// PROBE GYM — SHARED CONSOLE→STATION MESSAGES + GAMEPLAY TAGS
//
// Generic CkFoundation Probe feature gym. Mirrors the BB Trigger gym's shape
// (debug + physical stations driving the raw Probe API directly) and adds a
// nested scene-node stress station to catch transform-composition bugs where
// a Probe attached to a rotated/offset scene-node chain desyncs from its
// Jolt body.
//
// Tags declared here so no Config/DefaultGameplayTags.ini editing is needed:
//   CkTests.Probe.Gym.Marker   — detectable identity (balls, pawn, chained
//                                 probe at end of scene-node chain)
//   CkTests.Probe.Gym.Detector — detector identity (static sensor probes)
//============================================================================

namespace Ck
{
    asset Asset_ProbeGym_Tags of UCk_GameplayTags
    {
        GameplayTags.Add(n"CkTests.Probe.Gym.Marker");
        GameplayTags.Add(n"CkTests.Probe.Gym.Detector");
    }
}

//============================================================================
// Console-command → station messages. Each PlayerController Exec finds
// station entities by tag and broadcasts one of these structs.
//============================================================================

USTRUCT()
struct FCk_Message_ProbeGym_ForceEnter
{
};

USTRUCT()
struct FCk_Message_ProbeGym_ForceExit
{
};

USTRUCT()
struct FCk_Message_ProbeGym_Reset
{
};
