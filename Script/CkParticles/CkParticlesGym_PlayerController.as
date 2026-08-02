// --------------------------------------------------------------------------------------------------------------------
// CkParticles gym PlayerController ("Particles"): one station per CkParticles behavior,
// each spawning the seed template with that behavior + a fitting procedural texture. Ids 9+ are the
// marketplace recreations (VFX corpus translation sheets); station notes credit their exemplar systems.
// Everything here is text-authored HLSL + C++ — no Niagara graph was edited for any of these effects.
//
// The faithful Vefects ports (Slash 7, LightningRange 17, GunshotProjectile 18, ArrowProjectile 19) have no
// station here — the VfxExamples gym owns them, showing each beside its original for an objective A/B.
// Roster-driven AUTOTEST coverage is unaffected: CkAutoTest_Particles_SpawnAllBehaviors still iterates
// Get_NumBehaviors(), so the ports remain covered.
// --------------------------------------------------------------------------------------------------------------------

class ACk_ParticlesGym_PlayerController : ACk_Gym_Base_PlayerController
{
    private TArray<UNiagaraComponent> _Spawned;

    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

        Stations.Add(Make_Station(n"Gym.Particles.Gravity", "GRAVITY (0)",
            "Velocity-integrating fall.", "Default behavior — also the unknown-id fallback."));
        Stations.Add(Make_Station(n"Gym.Particles.Swirl", "SWIRL (1)",
            "Age-driven vortex helix.", "Blue -> magenta tint over life."));
        Stations.Add(Make_Station(n"Gym.Particles.Explosion", "EXPLOSION (2)",
            "Radial burst, ease-out + sag.", "Per-Seed direction and range."));
        Stations.Add(Make_Station(n"Gym.Particles.Fire", "FIRE (3)",
            "Rising column, tapers inward.", "White-hot -> dark red."));
        Stations.Add(Make_Station(n"Gym.Particles.Fireworks", "FIREWORKS (4)",
            "Decelerating burst sphere.", "Per-particle rainbow + twinkle."));
        Stations.Add(Make_Station(n"Gym.Particles.Galaxy", "GALAXY (5)",
            "3-arm rotating spiral disk.", "Blue core -> warm rim."));
        Stations.Add(Make_Station(n"Gym.Particles.Beam", "BEAM (6)",
            "Converging stream along +X.", "Aim via spawn rotation."));
        Stations.Add(Make_Station(n"Gym.Particles.Nova", "NOVA (8)",
            "Expanding flat shockwave ring.", "White-hot -> orange."));
        Stations.Add(Make_Station(n"Gym.Particles.MuzzleFlash", "MUZZLE FLASH (9)",
            "Core flash + flecks + sparks, +X.", "From sA NS_AR_Muzzleflash_1/2."));
        Stations.Add(Make_Station(n"Gym.Particles.ImpactBurst", "IMPACT BURST (10)",
            "Flash pop + sparks + smoke puff.", "From sA NS_AR_Impact_1 / Projectile_Hit_1."));
        Stations.Add(Make_Station(n"Gym.Particles.Tracer", "TRACER (11)",
            "Trail quads + backward spark spray.", "From sA NS_BulletTrail_1/3."));
        Stations.Add(Make_Station(n"Gym.Particles.SmokePlume", "SMOKE PLUME (12)",
            "Buoyant puffs, grey ramp, ember pop.", "From M5VFX 0_6_smoke + NS_Smoke_White."));
        Stations.Add(Make_Station(n"Gym.Particles.SparksBurst", "SPARKS BURST (13)",
            "Hemisphere streaks, heavy gravity.", "From StarterContent P_Sparks."));
        Stations.Add(Make_Station(n"Gym.Particles.GroundRing", "GROUND RING (14)",
            "Expanding ring + spark fountain.", "From sA NS_Ground_Crack / NS_AOE_Attack_1."));
        Stations.Add(Make_Station(n"Gym.Particles.LightningStrike", "LIGHTNING STRIKE (15)",
            "Strobing jagged bolt + crackle + dust.", "From sA NS_LightningStrike_1."));
        Stations.Add(Make_Station(n"Gym.Particles.AuraSwirl", "AURA SWIRL (16)",
            "Orbiting torus flame ring.", "From sA NS_FlameAura_1 (+ NS_Aura_1 spin)."));

        return Stations;
    }

    private FCkGym_Station_SpawnParams_Payload Make_Station(FName InTag, FString InTitle, FString InLine1, FString InLine2)
    {
        auto Station = FCkGym_Station_SpawnParams_Payload();
        Station.Tags.Add(InTag);
        Station.Title = FText::FromString(InTitle);
        auto Description = TArray<FText>();
        Description.Add(FText::FromString(InLine1));
        Description.Add(FText::FromString(InLine2));
        Station.Description = Description;
        Station.AutoSize = true;
        return Station;
    }

    void Request_StartGym() override
    {
        Request_SpawnAllBehaviors();
        ck::Trace("🟠 Particles Gym - all behaviors spawned");
    }

    void Request_SpawnAllBehaviors()
    {
        // Clear any prior spawns (supports restart).
        for (auto Existing : _Spawned)
        {
            if (ck::IsValid(Existing)) { Existing.DestroyComponent(); }
        }
        _Spawned.Empty();

        Request_SpawnBehavior(n"Gym.Particles.Gravity",         0,  n"Glow",     FVector(-200, 0, 150), 1.0);
        Request_SpawnBehavior(n"Gym.Particles.Swirl",           1,  n"Glow",     FVector(-200, 0, 120), 1.0);
        Request_SpawnBehavior(n"Gym.Particles.Explosion",       2,  n"Flare",    FVector(-200, 0, 150), 1.0);
        Request_SpawnBehavior(n"Gym.Particles.Fire",            3,  n"Glow",     FVector(-200, 0, 60),  1.0);
        Request_SpawnBehavior(n"Gym.Particles.Fireworks",       4,  n"Flare",    FVector(-200, 0, 150), 1.0);
        Request_SpawnBehavior(n"Gym.Particles.Galaxy",          5,  n"Glow",     FVector(-200, 0, 150), 1.0);
        Request_SpawnBehavior(n"Gym.Particles.Beam",            6,  n"Streak",   FVector(-200, 0, 120), 1.0);
        Request_SpawnBehavior(n"Gym.Particles.Nova",            8,  n"Ring",     FVector(-200, 0, 30),  1.0);
        Request_SpawnBehavior(n"Gym.Particles.MuzzleFlash",     9,  n"Flare",    FVector(-200, 0, 120), 1.0);
        Request_SpawnBehavior(n"Gym.Particles.ImpactBurst",     10, n"Glow",     FVector(-200, 0, 15),  1.0);
        Request_SpawnBehavior(n"Gym.Particles.Tracer",          11, n"Streak",   FVector(-200, 0, 120), 1.0);
        Request_SpawnBehavior(n"Gym.Particles.SmokePlume",      12, n"Smoke",    FVector(-200, 0, 20),  1.0);
        Request_SpawnBehavior(n"Gym.Particles.SparksBurst",     13, n"Streak",   FVector(-200, 0, 100), 1.0);
        Request_SpawnBehavior(n"Gym.Particles.GroundRing",      14, n"Ring",     FVector(-200, 0, 10),  0.6);
        Request_SpawnBehavior(n"Gym.Particles.LightningStrike", 15, n"Electric", FVector(-200, 0, 5),   1.0);
        Request_SpawnBehavior(n"Gym.Particles.AuraSwirl",       16, n"Glow",     FVector(-200, 0, 20),  1.0);
    }

    private void Request_SpawnBehavior(FName InStationTag, int InBehaviorId, FName InTexture, FVector InOffset, float64 InScale)
    {
        auto StationTransform = Get_StationTransform(InStationTag.ToString());
        auto Location = StationTransform.Location + InOffset;

        auto Component = UCk_Utils_Particles_UE::Spawn_BehaviorAtLocation(
            InBehaviorId, Location, FRotator::ZeroRotator, FVector(InScale, InScale, InScale), InTexture);

        if (ck::IsValid(Component))
        {
            _Spawned.Add(Component);
        }
        else
        {
            ck::Error(f"❌ Particles gym: failed to spawn BehaviorId {InBehaviorId} at station {InStationTag}");
        }
    }

    UFUNCTION(Exec, DisplayName="Particles Gym - Restart All Behaviors")
    void Ck_GymParticles_RestartAll()
    {
        Request_SpawnAllBehaviors();
    }
}
