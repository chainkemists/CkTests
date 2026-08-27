// Language=angelscript

//============================================================================
// CK EQS - SHARED GAMEPLAY TAGS
//============================================================================
//
// Tags for gym station discovery. Pattern from CkAStar_Shared.as.
//============================================================================

namespace Ck
{
    asset EqsGym_Tags of UCk_GameplayTags
    {
        GameplayTags.Add(n"Gym.Eqs.SimpleGrid");
        GameplayTags.Add(n"Gym.Eqs.Donut");
        GameplayTags.Add(n"Gym.Eqs.Cone");
        GameplayTags.Add(n"Gym.Eqs.Immediate");
        GameplayTags.Add(n"Gym.Eqs.RandomBest");

        // v1.1 stations.
        GameplayTags.Add(n"Gym.Eqs.NavProjection");
        GameplayTags.Add(n"Gym.Eqs.OnCircle");
        GameplayTags.Add(n"Gym.Eqs.VolumeCheck");
        GameplayTags.Add(n"Gym.Eqs.Random");
        GameplayTags.Add(n"Gym.Eqs.Trace");
        GameplayTags.Add(n"Gym.Eqs.Overlap");
        GameplayTags.Add(n"Gym.Eqs.EntitiesWithTag");

        // EntitiesWithTag scenario: required tag on the spawned target entities.
        GameplayTags.Add(n"Gym.Eqs.Target");

        // Overlap scenario: probe-name tag the markers carry; the test filter matches it.
        GameplayTags.Add(n"Gym.Eqs.OverlapMarker");

        // Trace scenario: probe-name tag the invisible LOS blocker (co-located with the
        // visible wall) carries; the Trace test's _TraceFilter matches it so the wall
        // actually blocks LOS at the probe-trace level.
        GameplayTags.Add(n"Gym.Eqs.TraceBlocker");
    }
}
