// Language=angelscript

//============================================================================
// CK PARTICLES GYM — station tags
//============================================================================
//
// One station per CkParticles behavior, EXCEPT the faithful Vefects ports
// (7, 17, 18, 19) — those live in the VfxExamples gym, paired against their
// originals.
// Ids 9+ are the marketplace recreations (VFX corpus translation sheets,
// 2026-07-12); their station descriptions credit the exemplar systems they
// were derived from.
//
//============================================================================

namespace Ck
{
    asset ParticlesGym_Tags of UCk_GameplayTags
    {
        GameplayTags.Add(n"Gym.Particles.Gravity");
        GameplayTags.Add(n"Gym.Particles.Swirl");
        GameplayTags.Add(n"Gym.Particles.Explosion");
        GameplayTags.Add(n"Gym.Particles.Fire");
        GameplayTags.Add(n"Gym.Particles.Fireworks");
        GameplayTags.Add(n"Gym.Particles.Galaxy");
        GameplayTags.Add(n"Gym.Particles.Beam");
        GameplayTags.Add(n"Gym.Particles.Nova");
        GameplayTags.Add(n"Gym.Particles.MuzzleFlash");
        GameplayTags.Add(n"Gym.Particles.ImpactBurst");
        GameplayTags.Add(n"Gym.Particles.Tracer");
        GameplayTags.Add(n"Gym.Particles.SmokePlume");
        GameplayTags.Add(n"Gym.Particles.SparksBurst");
        GameplayTags.Add(n"Gym.Particles.GroundRing");
        GameplayTags.Add(n"Gym.Particles.LightningStrike");
        GameplayTags.Add(n"Gym.Particles.AuraSwirl");
    }
}
