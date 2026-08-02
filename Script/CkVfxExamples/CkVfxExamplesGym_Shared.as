// Language=angelscript

//============================================================================
// CK VFX EXAMPLES GYM — pair registry + station tags
//============================================================================
//
// One entry per Vefects effect that CkParticles ports FAITHFULLY (not the
// "marketplace-inspired" behaviors, which stay in the Particles gym). Each
// entry drives TWO adjacent stations: the CkParticles recreation and the
// ORIGINAL Niagara system, so a human can judge fidelity side by side.
//
// The original is addressed by PATH STRING ONLY and resolved at runtime.
// Nothing here references a Vefects asset, so the gym creates no package
// dependency on that content and works unchanged when it is absent.
//
//============================================================================

USTRUCT()
struct FCk_VfxExamples_Pair
{
    UPROPERTY()
    FString DisplayName;

    UPROPERTY()
    FName CkStationTag;

    UPROPERTY()
    FName OriginalStationTag;

    UPROPERTY()
    int32 BehaviorId = 0;

    // Procedural-texture name handed to the CkParticles spawn. NAME_None lets a
    // behavior's bound CkUsf look reach User.SpriteMaterial unopposed; a behavior
    // whose look IS a procedural texture must name it or it renders the default glow.
    UPROPERTY()
    FName TextureName = NAME_None;

    // PACKAGE paths, tried in order. The asset registry keys on "<package>.<leaf>",
    // so the leaf is carried separately rather than parsed back out of the string —
    // repackaging Vefects as a content plugin is then a one-line data edit here.
    UPROPERTY()
    TArray<FString> OriginalCandidatePackagePaths;

    UPROPERTY()
    FString OriginalAssetName;

    UPROPERTY()
    FString Credit;

    UPROPERTY()
    FVector SpawnOffset;

    UPROPERTY()
    float Scale = 1.0;
}

namespace CkVfxExamples
{
    TArray<FCk_VfxExamples_Pair> Get_Pairs()
    {
        auto Pairs = TArray<FCk_VfxExamples_Pair>();

        {
            auto Pair = FCk_VfxExamples_Pair();
            Pair.DisplayName = "SLASH";
            Pair.CkStationTag = n"Gym.VfxExamples.Slash.Ck";
            Pair.OriginalStationTag = n"Gym.VfxExamples.Slash.Original";
            Pair.BehaviorId = 7;
            // 7's five looks ride the Slash cadence row's own renderers, which bind
            // them explicitly. An explicit texture here would only reach the SHARED
            // sprite renderers, which this behavior never tags — inert, but it would
            // read as meaningful.
            Pair.TextureName = NAME_None;
            Pair.OriginalCandidatePackagePaths.Add("/Game/Vefects/Anime_VFX/Shared/Skills/NS_BasicAttack");
            Pair.OriginalCandidatePackagePaths.Add("/Vefects/Anime_VFX/Shared/Skills/NS_BasicAttack");
            Pair.OriginalAssetName = "NS_BasicAttack";
            Pair.Credit = "Original: Vefects NS_BasicAttack";
            Pair.SpawnOffset = FVector(-200, 0, 120);
            Pair.Scale = 1.0;
            Pairs.Add(Pair);
        }

        {
            auto Pair = FCk_VfxExamples_Pair();
            Pair.DisplayName = "LIGHTNING RANGE";
            Pair.CkStationTag = n"Gym.VfxExamples.LightningRange.Ck";
            Pair.OriginalStationTag = n"Gym.VfxExamples.LightningRange.Original";
            Pair.BehaviorId = 17;
            // 17 binds its CkUsf look through User.SpriteMaterial; an explicit
            // texture would win over it.
            Pair.TextureName = NAME_None;
            Pair.OriginalCandidatePackagePaths.Add("/Game/Vefects/Anime_VFX/Shared/Skills/NS_Lightning_Range");
            Pair.OriginalCandidatePackagePaths.Add("/Vefects/Anime_VFX/Shared/Skills/NS_Lightning_Range");
            Pair.OriginalAssetName = "NS_Lightning_Range";
            Pair.Credit = "Original: Vefects NS_Lightning_Range";
            Pair.SpawnOffset = FVector(-200, 0, 10);
            Pair.Scale = 1.0;
            Pairs.Add(Pair);
        }

        {
            auto Pair = FCk_VfxExamples_Pair();
            Pair.DisplayName = "GUNSHOT PROJECTILE";
            Pair.CkStationTag = n"Gym.VfxExamples.GunshotProjectile.Ck";
            Pair.OriginalStationTag = n"Gym.VfxExamples.GunshotProjectile.Original";
            Pair.BehaviorId = 18;
            // Both of 18's looks ride the ProjectileTrio cadence row's own renderers, which bind
            // them explicitly. An explicit texture here would only reach the SHARED sprite
            // renderers, which this behavior never tags.
            Pair.TextureName = NAME_None;
            Pair.OriginalCandidatePackagePaths.Add("/Game/Vefects/Anime_VFX/Shared/Skills/NS_Gunshot_Projectile");
            Pair.OriginalCandidatePackagePaths.Add("/Vefects/Anime_VFX/Shared/Skills/NS_Gunshot_Projectile");
            Pair.OriginalAssetName = "NS_Gunshot_Projectile";
            Pair.Credit = "Original: Vefects NS_Gunshot_Projectile";
            // The streaks run along local -X and the longest reaches ~445 units back, so the
            // trail is laid out from the station centre rather than pushed further away.
            Pair.SpawnOffset = FVector(0, 0, 120);
            Pair.Scale = 1.0;
            Pairs.Add(Pair);
        }

        {
            auto Pair = FCk_VfxExamples_Pair();
            Pair.DisplayName = "ARROW PROJECTILE";
            Pair.CkStationTag = n"Gym.VfxExamples.ArrowProjectile.Ck";
            Pair.OriginalStationTag = n"Gym.VfxExamples.ArrowProjectile.Original";
            Pair.BehaviorId = 19;
            // 19's camera-facing head binds PartDisAdd01 through User.SpriteMaterial; naming a
            // texture here would WIN over that binding and render the glow head untextured.
            Pair.TextureName = NAME_None;
            Pair.OriginalCandidatePackagePaths.Add("/Game/Vefects/Anime_VFX/Shared/Skills/NS_Arrow_Projectile");
            Pair.OriginalCandidatePackagePaths.Add("/Vefects/Anime_VFX/Shared/Skills/NS_Arrow_Projectile");
            Pair.OriginalAssetName = "NS_Arrow_Projectile";
            Pair.Credit = "Original: Vefects NS_Arrow_Projectile";
            Pair.SpawnOffset = FVector(0, 0, 120);
            Pair.Scale = 1.0;
            Pairs.Add(Pair);
        }

        {
            auto Pair = FCk_VfxExamples_Pair();
            Pair.DisplayName = "FIRE";
            Pair.CkStationTag = n"Gym.VfxExamples.Fire.Ck";
            Pair.OriginalStationTag = n"Gym.VfxExamples.Fire.Original";
            Pair.BehaviorId = 20;
            // All three of 20's looks ride the FireBurst cadence row's own renderers, which bind them
            // explicitly. An explicit texture here would only reach the SHARED sprite renderers, which
            // this behavior never tags.
            Pair.TextureName = NAME_None;
            Pair.OriginalCandidatePackagePaths.Add("/Game/Vefects/Anime_VFX/Shared/Skills/NS_Fire");
            Pair.OriginalCandidatePackagePaths.Add("/Vefects/Anime_VFX/Shared/Skills/NS_Fire");
            Pair.OriginalAssetName = "NS_Fire";
            Pair.Credit = "Original: Vefects NS_Fire";
            // A ground fire: the glows are 500 units across and the sparkles rise off a hemisphere, so it
            // sits on the pedestal rather than above it.
            Pair.SpawnOffset = FVector(0, 0, 10);
            Pair.Scale = 1.0;
            Pairs.Add(Pair);
        }

        {
            auto Pair = FCk_VfxExamples_Pair();
            Pair.DisplayName = "FIREBALL HIT";
            Pair.CkStationTag = n"Gym.VfxExamples.FireBallHit.Ck";
            Pair.OriginalStationTag = n"Gym.VfxExamples.FireBallHit.Original";
            Pair.BehaviorId = 21;
            Pair.TextureName = NAME_None;
            Pair.OriginalCandidatePackagePaths.Add("/Game/Vefects/Anime_VFX/Shared/Skills/NS_FireBall_Hit");
            Pair.OriginalCandidatePackagePaths.Add("/Vefects/Anime_VFX/Shared/Skills/NS_FireBall_Hit");
            Pair.OriginalAssetName = "NS_FireBall_Hit";
            Pair.Credit = "Original: Vefects NS_FireBall_Hit";
            // An impact burst at a fixed point, so it wants head height rather than the floor.
            Pair.SpawnOffset = FVector(0, 0, 120);
            Pair.Scale = 1.0;
            Pairs.Add(Pair);
        }

        {
            auto Pair = FCk_VfxExamples_Pair();
            Pair.DisplayName = "GUNSHOT HIT";
            Pair.CkStationTag = n"Gym.VfxExamples.GunshotHit.Ck";
            Pair.OriginalStationTag = n"Gym.VfxExamples.GunshotHit.Original";
            Pair.BehaviorId = 22;
            Pair.TextureName = NAME_None;
            Pair.OriginalCandidatePackagePaths.Add("/Game/Vefects/Anime_VFX/Shared/Skills/NS_Gunshot_Hit");
            Pair.OriginalCandidatePackagePaths.Add("/Vefects/Anime_VFX/Shared/Skills/NS_Gunshot_Hit");
            Pair.OriginalAssetName = "NS_Gunshot_Hit";
            Pair.Credit = "Original: Vefects NS_Gunshot_Hit";
            Pair.SpawnOffset = FVector(0, 0, 120);
            Pair.Scale = 1.0;
            Pairs.Add(Pair);
        }

        {
            auto Pair = FCk_VfxExamples_Pair();
            Pair.DisplayName = "ARROW CAST";
            Pair.CkStationTag = n"Gym.VfxExamples.ArrowCast.Ck";
            Pair.OriginalStationTag = n"Gym.VfxExamples.ArrowCast.Original";
            Pair.BehaviorId = 23;
            Pair.TextureName = NAME_None;
            Pair.OriginalCandidatePackagePaths.Add("/Game/Vefects/Anime_VFX/Shared/Skills/NS_Arrow_Cast");
            Pair.OriginalCandidatePackagePaths.Add("/Vefects/Anime_VFX/Shared/Skills/NS_Arrow_Cast");
            Pair.OriginalAssetName = "NS_Arrow_Cast";
            Pair.Credit = "Original: Vefects NS_Arrow_Cast";
            // The bow flash sits at hand height, and its wind tube travels ~230 units down local -X over 1.5 s,
            // so the station is left clear ahead of it rather than pushed back.
            Pair.SpawnOffset = FVector(0, 0, 120);
            Pair.Scale = 1.0;
            Pairs.Add(Pair);
        }

        {
            auto Pair = FCk_VfxExamples_Pair();
            Pair.DisplayName = "ARROW HIT";
            Pair.CkStationTag = n"Gym.VfxExamples.ArrowHit.Ck";
            Pair.OriginalStationTag = n"Gym.VfxExamples.ArrowHit.Original";
            Pair.BehaviorId = 24;
            Pair.TextureName = NAME_None;
            Pair.OriginalCandidatePackagePaths.Add("/Game/Vefects/Anime_VFX/Shared/Skills/NS_Arrow_Hit");
            Pair.OriginalCandidatePackagePaths.Add("/Vefects/Anime_VFX/Shared/Skills/NS_Arrow_Hit");
            Pair.OriginalAssetName = "NS_Arrow_Hit";
            Pair.Credit = "Original: Vefects NS_Arrow_Hit";
            Pair.SpawnOffset = FVector(0, 0, 120);
            Pair.Scale = 1.0;
            Pairs.Add(Pair);
        }

        {
            auto Pair = FCk_VfxExamples_Pair();
            Pair.DisplayName = "BOMB SPAWN";
            Pair.CkStationTag = n"Gym.VfxExamples.BombSpawn.Ck";
            Pair.OriginalStationTag = n"Gym.VfxExamples.BombSpawn.Original";
            Pair.BehaviorId = 25;
            Pair.TextureName = NAME_None;
            Pair.OriginalCandidatePackagePaths.Add("/Game/Vefects/Anime_VFX/Shared/Skills/NS_Bomb_Spawn");
            Pair.OriginalCandidatePackagePaths.Add("/Vefects/Anime_VFX/Shared/Skills/NS_Bomb_Spawn");
            Pair.OriginalAssetName = "NS_Bomb_Spawn";
            Pair.Credit = "Original: Vefects NS_Bomb_Spawn";
            // A prop appearing in mid-air with its flares laid out around it, so it wants head height.
            Pair.SpawnOffset = FVector(0, 0, 120);
            Pair.Scale = 1.0;
            Pairs.Add(Pair);
        }

        // The four rate-only Loop ports. Unlike every pair above them these sources are INFINITE systems: the
        // original pedestal re-fires nothing because it never finishes, so the A/B here is a STEADY-STATE
        // comparison of two continuously spawning streams, not two arcs synced at t = 0. Judge density, palette
        // and motion character; do not expect the two sides to be in phase.
        {
            auto Pair = FCk_VfxExamples_Pair();
            Pair.DisplayName = "PICKUP LOOP";
            Pair.CkStationTag = n"Gym.VfxExamples.PickupLoop.Ck";
            Pair.OriginalStationTag = n"Gym.VfxExamples.PickupLoop.Original";
            Pair.BehaviorId = 26;
            // All six of 26's looks ride the PickupLoop cadence row's own renderers, which bind them explicitly.
            // An explicit texture here would only reach the SHARED sprite renderers, which this behavior never tags.
            Pair.TextureName = NAME_None;
            Pair.OriginalCandidatePackagePaths.Add("/Game/Vefects/Anime_VFX/Shared/Skills/NS_PickupLoop");
            Pair.OriginalCandidatePackagePaths.Add("/Vefects/Anime_VFX/Shared/Skills/NS_PickupLoop");
            Pair.OriginalAssetName = "NS_PickupLoop";
            Pair.Credit = "Original: Vefects NS_PickupLoop";
            // A pickup hovering in mid-air: its glows are centred on the spawn point rather than rising from it.
            Pair.SpawnOffset = FVector(0, 0, 120);
            Pair.Scale = 1.0;
            Pairs.Add(Pair);
        }

        {
            auto Pair = FCk_VfxExamples_Pair();
            Pair.DisplayName = "HEAL LOOP";
            Pair.CkStationTag = n"Gym.VfxExamples.HealLoop.Ck";
            Pair.OriginalStationTag = n"Gym.VfxExamples.HealLoop.Original";
            Pair.BehaviorId = 27;
            Pair.TextureName = NAME_None;
            Pair.OriginalCandidatePackagePaths.Add("/Game/Vefects/Anime_VFX/Shared/Skills/NS_HealLoop");
            Pair.OriginalCandidatePackagePaths.Add("/Vefects/Anime_VFX/Shared/Skills/NS_HealLoop");
            Pair.OriginalAssetName = "NS_HealLoop";
            Pair.Credit = "Original: Vefects NS_HealLoop";
            // A body aura: its sparkles are fired UP out of a cylinder at the feet, so it sits on the pedestal.
            Pair.SpawnOffset = FVector(0, 0, 10);
            Pair.Scale = 1.0;
            Pairs.Add(Pair);
        }

        {
            auto Pair = FCk_VfxExamples_Pair();
            Pair.DisplayName = "BUFF LOOP";
            Pair.CkStationTag = n"Gym.VfxExamples.BuffLoop.Ck";
            Pair.OriginalStationTag = n"Gym.VfxExamples.BuffLoop.Original";
            Pair.BehaviorId = 28;
            Pair.TextureName = NAME_None;
            Pair.OriginalCandidatePackagePaths.Add("/Game/Vefects/Anime_VFX/Shared/Skills/NS_BuffLoop");
            Pair.OriginalCandidatePackagePaths.Add("/Vefects/Anime_VFX/Shared/Skills/NS_BuffLoop");
            Pair.OriginalAssetName = "NS_BuffLoop";
            Pair.Credit = "Original: Vefects NS_BuffLoop";
            Pair.SpawnOffset = FVector(0, 0, 10);
            Pair.Scale = 1.0;
            Pairs.Add(Pair);
        }

        {
            auto Pair = FCk_VfxExamples_Pair();
            Pair.DisplayName = "DEBUFF LOOP";
            Pair.CkStationTag = n"Gym.VfxExamples.DebuffLoop.Ck";
            Pair.OriginalStationTag = n"Gym.VfxExamples.DebuffLoop.Original";
            Pair.BehaviorId = 29;
            Pair.TextureName = NAME_None;
            Pair.OriginalCandidatePackagePaths.Add("/Game/Vefects/Anime_VFX/Shared/Skills/NS_DebuffLoop");
            Pair.OriginalCandidatePackagePaths.Add("/Vefects/Anime_VFX/Shared/Skills/NS_DebuffLoop");
            Pair.OriginalAssetName = "NS_DebuffLoop";
            Pair.Credit = "Original: Vefects NS_DebuffLoop";
            // Its arrows spawn 150 units UP and fall, so the station wants the ground rather than head height.
            Pair.SpawnOffset = FVector(0, 0, 10);
            Pair.Scale = 1.0;
            Pairs.Add(Pair);
        }

        // The three "Cast" ports. These are Loop-Once systems again, so the harness's OnSystemFinished re-arm
        // brings both sides back in phase and the A/B is a SYNCED replay from t = 0, not a steady-state read.
        {
            auto Pair = FCk_VfxExamples_Pair();
            Pair.DisplayName = "PICKUP CAST";
            Pair.CkStationTag = n"Gym.VfxExamples.PickupCast.Ck";
            Pair.OriginalStationTag = n"Gym.VfxExamples.PickupCast.Original";
            Pair.BehaviorId = 30;
            // All eight of 30's looks ride the PickupCast cadence row's own renderers, which bind them
            // explicitly. An explicit texture here would only reach the SHARED sprite renderers, which this
            // behavior never tags.
            Pair.TextureName = NAME_None;
            Pair.OriginalCandidatePackagePaths.Add("/Game/Vefects/Anime_VFX/Shared/Skills/NS_PickupCast");
            Pair.OriginalCandidatePackagePaths.Add("/Vefects/Anime_VFX/Shared/Skills/NS_PickupCast");
            Pair.OriginalAssetName = "NS_PickupCast";
            Pair.Credit = "Original: Vefects NS_PickupCast";
            // A pickup appearing in mid-air: an 800-unit flash and two concentric rings centred on the spawn.
            Pair.SpawnOffset = FVector(0, 0, 120);
            Pair.Scale = 1.0;
            Pairs.Add(Pair);
        }

        {
            auto Pair = FCk_VfxExamples_Pair();
            Pair.DisplayName = "HEAL CAST";
            Pair.CkStationTag = n"Gym.VfxExamples.HealCast.Ck";
            Pair.OriginalStationTag = n"Gym.VfxExamples.HealCast.Original";
            Pair.BehaviorId = 31;
            Pair.TextureName = NAME_None;
            Pair.OriginalCandidatePackagePaths.Add("/Game/Vefects/Anime_VFX/Shared/Skills/NS_HealCast");
            Pair.OriginalCandidatePackagePaths.Add("/Vefects/Anime_VFX/Shared/Skills/NS_HealCast");
            Pair.OriginalAssetName = "NS_HealCast";
            Pair.Credit = "Original: Vefects NS_HealCast";
            // Its lens flares spawn 70 units BELOW the origin and rise, so the station wants head height rather
            // than the pedestal top.
            Pair.SpawnOffset = FVector(0, 0, 120);
            Pair.Scale = 1.0;
            Pairs.Add(Pair);
        }

        {
            auto Pair = FCk_VfxExamples_Pair();
            Pair.DisplayName = "DEBUFF CAST";
            Pair.CkStationTag = n"Gym.VfxExamples.DebuffCast.Ck";
            Pair.OriginalStationTag = n"Gym.VfxExamples.DebuffCast.Original";
            Pair.BehaviorId = 32;
            Pair.TextureName = NAME_None;
            Pair.OriginalCandidatePackagePaths.Add("/Game/Vefects/Anime_VFX/Shared/Skills/NS_DebuffCast");
            Pair.OriginalCandidatePackagePaths.Add("/Vefects/Anime_VFX/Shared/Skills/NS_DebuffCast");
            Pair.OriginalAssetName = "NS_DebuffCast";
            Pair.Credit = "Original: Vefects NS_DebuffCast";
            // Its dark sparkles implode from a 200-unit SHELL centred on the spawn point, so the station needs
            // clearance all round rather than sitting on the floor.
            Pair.SpawnOffset = FVector(0, 0, 120);
            Pair.Scale = 1.0;
            Pairs.Add(Pair);
        }

        // The three attack Casts. Loop-Once systems again, so the harness's OnSystemFinished re-arm keeps both
        // sides synced from t = 0. All three aim down local +X, so judge them from the side rather than head-on.
        {
            auto Pair = FCk_VfxExamples_Pair();
            Pair.DisplayName = "GUNSHOT CAST";
            Pair.CkStationTag = n"Gym.VfxExamples.GunshotCast.Ck";
            Pair.OriginalStationTag = n"Gym.VfxExamples.GunshotCast.Original";
            Pair.BehaviorId = 33;
            // All twelve of 33's looks ride the GunshotCast cadence row's own renderers, which bind them
            // explicitly. An explicit texture here would only reach the SHARED sprite renderers, which this
            // behavior never tags.
            Pair.TextureName = NAME_None;
            Pair.OriginalCandidatePackagePaths.Add("/Game/Vefects/Anime_VFX/Shared/Skills/NS_Gunshot_Cast");
            Pair.OriginalCandidatePackagePaths.Add("/Vefects/Anime_VFX/Shared/Skills/NS_Gunshot_Cast");
            Pair.OriginalAssetName = "NS_Gunshot_Cast";
            Pair.Credit = "Original: Vefects NS_Gunshot_Cast";
            // A muzzle flash at hand height, with an 800-unit shell around it and a lightning card 354 units
            // out along +X, so the station wants head height and clearance ahead of it.
            Pair.SpawnOffset = FVector(0, 0, 120);
            Pair.Scale = 1.0;
            Pairs.Add(Pair);
        }

        {
            auto Pair = FCk_VfxExamples_Pair();
            Pair.DisplayName = "FIREBALL CAST";
            Pair.CkStationTag = n"Gym.VfxExamples.FireBallCast.Ck";
            Pair.OriginalStationTag = n"Gym.VfxExamples.FireBallCast.Original";
            Pair.BehaviorId = 34;
            Pair.TextureName = NAME_None;
            Pair.OriginalCandidatePackagePaths.Add("/Game/Vefects/Anime_VFX/Shared/Skills/NS_FireBall_Cast");
            Pair.OriginalCandidatePackagePaths.Add("/Vefects/Anime_VFX/Shared/Skills/NS_FireBall_Cast");
            Pair.OriginalAssetName = "NS_FireBall_Cast";
            Pair.Credit = "Original: Vefects NS_FireBall_Cast";
            // Half a second of gathering glow up to 1300 units wide, then a discharge — it wants the most room
            // of any pair in the gym, and its wind tube travels 230 units down local -X afterwards.
            Pair.SpawnOffset = FVector(0, 0, 120);
            Pair.Scale = 1.0;
            Pairs.Add(Pair);
        }

        {
            auto Pair = FCk_VfxExamples_Pair();
            Pair.DisplayName = "LIGHTNING CAST";
            Pair.CkStationTag = n"Gym.VfxExamples.LightningCast.Ck";
            Pair.OriginalStationTag = n"Gym.VfxExamples.LightningCast.Original";
            Pair.BehaviorId = 35;
            Pair.TextureName = NAME_None;
            Pair.OriginalCandidatePackagePaths.Add("/Game/Vefects/Anime_VFX/Shared/Skills/NS_Lightning_Cast");
            Pair.OriginalCandidatePackagePaths.Add("/Vefects/Anime_VFX/Shared/Skills/NS_Lightning_Cast");
            Pair.OriginalAssetName = "NS_Lightning_Cast";
            Pair.Credit = "Original: Vefects NS_Lightning_Cast";
            // Its sparkles fly omnidirectionally off the cast point for up to 1.5 s, so the station needs
            // clearance all round rather than sitting on the floor.
            Pair.SpawnOffset = FVector(0, 0, 120);
            Pair.Scale = 1.0;
            Pairs.Add(Pair);
        }

        {
            auto Pair = FCk_VfxExamples_Pair();
            Pair.DisplayName = "FIREBALL PROJECTILE";
            Pair.CkStationTag = n"Gym.VfxExamples.FireBallProjectile.Ck";
            Pair.OriginalStationTag = n"Gym.VfxExamples.FireBallProjectile.Original";
            Pair.BehaviorId = 36;
            Pair.TextureName = NAME_None;
            Pair.OriginalCandidatePackagePaths.Add("/Game/Vefects/Anime_VFX/Shared/Skills/NS_FireBall_Projectile");
            Pair.OriginalCandidatePackagePaths.Add("/Vefects/Anime_VFX/Shared/Skills/NS_FireBall_Projectile");
            Pair.OriginalAssetName = "NS_FireBall_Projectile";
            Pair.Credit = "Original: Vefects NS_FireBall_Projectile";
            // A continuous 10-second fireball: its core sits ~20 units back along -X and its flames, smoke
            // and two ribbons stream a further 250 units behind that, so the station wants clear air behind
            // it rather than distance in front.
            Pair.SpawnOffset = FVector(120, 0, 120);
            Pair.Scale = 1.0;
            Pairs.Add(Pair);
        }

        {
            auto Pair = FCk_VfxExamples_Pair();
            Pair.DisplayName = "BOMB PROJECTILE";
            Pair.CkStationTag = n"Gym.VfxExamples.BombProjectile.Ck";
            Pair.OriginalStationTag = n"Gym.VfxExamples.BombProjectile.Original";
            Pair.BehaviorId = 37;
            Pair.TextureName = NAME_None;
            Pair.OriginalCandidatePackagePaths.Add("/Game/Vefects/Anime_VFX/Shared/Skills/NS_Bomb_Projectile");
            Pair.OriginalCandidatePackagePaths.Add("/Vefects/Anime_VFX/Shared/Skills/NS_Bomb_Projectile");
            Pair.OriginalAssetName = "NS_Bomb_Projectile";
            Pair.Credit = "Original: Vefects NS_Bomb_Projectile";
            // A bomb hanging inside three coincident 300-unit glow shells for 2.5 s, flashing at the end.
            // NEITHER side draws its trail here: the source spawns trail points per unit of TRAVEL and the
            // pedestal does not move (recipe NS_Bomb_Projectile.md §13).
            Pair.SpawnOffset = FVector(0, 0, 120);
            Pair.Scale = 1.0;
            Pairs.Add(Pair);
        }

        {
            auto Pair = FCk_VfxExamples_Pair();
            Pair.DisplayName = "BUFF CAST";
            Pair.CkStationTag = n"Gym.VfxExamples.BuffCast.Ck";
            Pair.OriginalStationTag = n"Gym.VfxExamples.BuffCast.Original";
            Pair.BehaviorId = 38;
            Pair.TextureName = NAME_None;
            Pair.OriginalCandidatePackagePaths.Add("/Game/Vefects/Anime_VFX/Shared/Skills/NS_BuffCast");
            Pair.OriginalCandidatePackagePaths.Add("/Vefects/Anime_VFX/Shared/Skills/NS_BuffCast");
            Pair.OriginalAssetName = "NS_BuffCast";
            Pair.Credit = "Original: Vefects NS_BuffCast";
            // A support cast that RISES: its two chevrons start a metre below the cast point and climb for
            // 1.5 s, and its seven sparkles throw trails omnidirectionally, so the station wants headroom
            // rather than floor.
            Pair.SpawnOffset = FVector(0, 0, 140);
            Pair.Scale = 1.0;
            Pairs.Add(Pair);
        }

        {
            auto Pair = FCk_VfxExamples_Pair();
            Pair.DisplayName = "LIGHTNING MUZZLE";
            Pair.CkStationTag = n"Gym.VfxExamples.LightningMuzzle.Ck";
            Pair.OriginalStationTag = n"Gym.VfxExamples.LightningMuzzle.Original";
            Pair.BehaviorId = 39;
            Pair.TextureName = NAME_None;
            Pair.OriginalCandidatePackagePaths.Add("/Game/Vefects/Anime_VFX/Shared/Skills/NS_Lightning_Muzzle");
            Pair.OriginalCandidatePackagePaths.Add("/Vefects/Anime_VFX/Shared/Skills/NS_Lightning_Muzzle");
            Pair.OriginalAssetName = "NS_Lightning_Muzzle";
            Pair.Credit = "Original: Vefects NS_Lightning_Muzzle";
            // A muzzle flash fired along +X: sparkles, spikes and both arcs travel down the barrel for up
            // to 3000 units/s over 0.3 s, so the station needs clear air in FRONT of it.
            Pair.SpawnOffset = FVector(0, 0, 120);
            Pair.Scale = 1.0;
            Pairs.Add(Pair);
        }

        {
            auto Pair = FCk_VfxExamples_Pair();
            Pair.DisplayName = "EXPLOSION GROUND";
            Pair.CkStationTag = n"Gym.VfxExamples.ExplosionGround.Ck";
            Pair.OriginalStationTag = n"Gym.VfxExamples.ExplosionGround.Original";
            Pair.BehaviorId = 40;
            Pair.TextureName = NAME_None;
            Pair.OriginalCandidatePackagePaths.Add("/Game/Vefects/Anime_VFX/Shared/Skills/NS_ExplosionGround");
            Pair.OriginalCandidatePackagePaths.Add("/Vefects/Anime_VFX/Shared/Skills/NS_ExplosionGround");
            Pair.OriginalAssetName = "NS_ExplosionGround";
            Pair.Credit = "Original: Vefects NS_ExplosionGround";
            // A ground blast: every spawn is HEMISPHERICAL and its longest layer is a 1.5 s scorch
            // decal lying flat under the burst, so this station is judged from the FLOOR up. The
            // source's dynamic point light is dropped ([P4-D2]); judge the sprite layers, not the
            // floor illumination.
            Pair.SpawnOffset = FVector(0, 0, 20);
            Pair.Scale = 1.0;
            Pairs.Add(Pair);
        }

        {
            auto Pair = FCk_VfxExamples_Pair();
            Pair.DisplayName = "EXPLOSION GROUND (ICE)";
            Pair.CkStationTag = n"Gym.VfxExamples.ExplosionGroundIce.Ck";
            Pair.OriginalStationTag = n"Gym.VfxExamples.ExplosionGroundIce.Original";
            Pair.BehaviorId = 41;
            Pair.TextureName = NAME_None;
            Pair.OriginalCandidatePackagePaths.Add("/Game/Vefects/Anime_VFX/Shared/Skills/NS_ExplosionIceGround");
            Pair.OriginalCandidatePackagePaths.Add("/Vefects/Anime_VFX/Shared/Skills/NS_ExplosionIceGround");
            Pair.OriginalAssetName = "NS_ExplosionIceGround";
            Pair.Credit = "Original: Vefects NS_ExplosionIceGround";
            // The same blast recoloured. Its only structural differences from behavior 40 are colour
            // tables, so the two Ck pedestals should read as ONE effect in two palettes — if they do
            // not, the palette twins are not sharing their layer math.
            Pair.SpawnOffset = FVector(0, 0, 20);
            Pair.Scale = 1.0;
            Pairs.Add(Pair);
        }

        {
            auto Pair = FCk_VfxExamples_Pair();
            Pair.DisplayName = "EXPLOSION OMNI";
            Pair.CkStationTag = n"Gym.VfxExamples.ExplosionOmni.Ck";
            Pair.OriginalStationTag = n"Gym.VfxExamples.ExplosionOmni.Original";
            Pair.BehaviorId = 42;
            Pair.TextureName = NAME_None;
            Pair.OriginalCandidatePackagePaths.Add("/Game/Vefects/Anime_VFX/Shared/Skills/NS_ExplosionOmni");
            Pair.OriginalCandidatePackagePaths.Add("/Vefects/Anime_VFX/Shared/Skills/NS_ExplosionOmni");
            Pair.OriginalAssetName = "NS_ExplosionOmni";
            Pair.Credit = "Original: Vefects NS_ExplosionOmni";
            // The airburst twin of the ground blast: every hemispherical spawn opens to a full sphere
            // and the scorch decal is gone, so this station wants clear air all round it rather than
            // floor. Its smoke lives 1.3 s, the longest layer here.
            Pair.SpawnOffset = FVector(0, 0, 140);
            Pair.Scale = 1.0;
            Pairs.Add(Pair);
        }

        {
            auto Pair = FCk_VfxExamples_Pair();
            Pair.DisplayName = "EXPLOSION OMNI (ICE)";
            Pair.CkStationTag = n"Gym.VfxExamples.ExplosionOmniIce.Ck";
            Pair.OriginalStationTag = n"Gym.VfxExamples.ExplosionOmniIce.Original";
            Pair.BehaviorId = 43;
            Pair.TextureName = NAME_None;
            Pair.OriginalCandidatePackagePaths.Add("/Game/Vefects/Anime_VFX/Shared/Skills/NS_ExplosionIceOmni");
            Pair.OriginalCandidatePackagePaths.Add("/Vefects/Anime_VFX/Shared/Skills/NS_ExplosionIceOmni");
            Pair.OriginalAssetName = "NS_ExplosionIceOmni";
            Pair.Credit = "Original: Vefects NS_ExplosionIceOmni";
            // The airburst recoloured. Two layers also live 50 % longer here (the bubble and the
            // spikes, 0.1 s -> 0.15 s), which is the one non-colour difference worth looking for.
            Pair.SpawnOffset = FVector(0, 0, 140);
            Pair.Scale = 1.0;
            Pairs.Add(Pair);
        }

        {
            auto Pair = FCk_VfxExamples_Pair();
            Pair.DisplayName = "BOMB EXPLOSION";
            Pair.CkStationTag = n"Gym.VfxExamples.BombExplosion.Ck";
            Pair.OriginalStationTag = n"Gym.VfxExamples.BombExplosion.Original";
            Pair.BehaviorId = 44;
            Pair.TextureName = NAME_None;
            Pair.OriginalCandidatePackagePaths.Add("/Game/Vefects/Anime_VFX/Shared/Skills/NS_Bomb_Explosion");
            Pair.OriginalCandidatePackagePaths.Add("/Vefects/Anime_VFX/Shared/Skills/NS_Bomb_Explosion");
            Pair.OriginalAssetName = "NS_Bomb_Explosion";
            Pair.Credit = "Original: Vefects NS_Bomb_Explosion";
            // The batch's giant: 162 particles over 23 emitters, all of it over inside half a second.
            // Its five shells are CAMERA-FACING meshes, so the read changes as you orbit the station —
            // walk around it rather than judging from one angle.
            Pair.SpawnOffset = FVector(0, 0, 60);
            Pair.Scale = 1.0;
            Pairs.Add(Pair);
        }

        {
            auto Pair = FCk_VfxExamples_Pair();
            Pair.DisplayName = "LIGHTNING HIT";
            Pair.CkStationTag = n"Gym.VfxExamples.LightningHit.Ck";
            Pair.OriginalStationTag = n"Gym.VfxExamples.LightningHit.Original";
            Pair.BehaviorId = 45;
            Pair.TextureName = NAME_None;
            Pair.OriginalCandidatePackagePaths.Add("/Game/Vefects/Anime_VFX/Shared/Skills/NS_Lightning_Hit");
            Pair.OriginalCandidatePackagePaths.Add("/Vefects/Anime_VFX/Shared/Skills/NS_Lightning_Hit");
            Pair.OriginalAssetName = "NS_Lightning_Hit";
            Pair.Credit = "Original: Vefects NS_Lightning_Hit";
            // The everything-effect: 22 emitters through every renderer class the pipeline has. It is a
            // GROUND impact, so judge it from the two flat decals up — and note that seven of its layers
            // are WORLD-space in the source and LOCAL here, which is invisible at a stationary pedestal.
            Pair.SpawnOffset = FVector(0, 0, 20);
            Pair.Scale = 1.0;
            Pairs.Add(Pair);
        }

        return Pairs;
    }

    // Returns the first candidate that resolves, or null. Silent at Warning/Error
    // level on every miss: an absent Vefects install is the expected state, and the
    // AutoTest harness escalates a Warning during a test into a test failure.
    UNiagaraSystem TryLoad_OriginalSystem(FCk_VfxExamples_Pair InPair)
    {
        for (auto Candidate : InPair.OriginalCandidatePackagePaths)
        {
            auto ObjectPath = Candidate + "." + InPair.OriginalAssetName;
            auto System = utils_i_o::LoadAssetByName_NiagaraSystem(ObjectPath, ECk_AssetSearchScope::All);

            if (ck::IsValid(System))
            { return System; }
        }

        return nullptr;
    }

    // Re-arms a component from t=0. Activate(bReset = true) is the single call that both
    // resets the simulation and reactivates: a plain Activate() NO-OPS on a component that
    // already ran to completion, which is exactly the state a finishing system ends in.
    void Request_RestartComponent(UNiagaraComponent InComponent)
    {
        if (ck::Is_NOT_Valid(InComponent))
        { return; }

        InComponent.Activate(true);
    }
}

namespace Ck
{
    asset VfxExamplesGym_Tags of UCk_GameplayTags
    {
        GameplayTags.Add(n"Gym.VfxExamples.Slash.Ck");
        GameplayTags.Add(n"Gym.VfxExamples.Slash.Original");
        GameplayTags.Add(n"Gym.VfxExamples.LightningRange.Ck");
        GameplayTags.Add(n"Gym.VfxExamples.LightningRange.Original");
        GameplayTags.Add(n"Gym.VfxExamples.GunshotProjectile.Ck");
        GameplayTags.Add(n"Gym.VfxExamples.GunshotProjectile.Original");
        GameplayTags.Add(n"Gym.VfxExamples.ArrowProjectile.Ck");
        GameplayTags.Add(n"Gym.VfxExamples.ArrowProjectile.Original");
        GameplayTags.Add(n"Gym.VfxExamples.Fire.Ck");
        GameplayTags.Add(n"Gym.VfxExamples.Fire.Original");
        GameplayTags.Add(n"Gym.VfxExamples.FireBallHit.Ck");
        GameplayTags.Add(n"Gym.VfxExamples.FireBallHit.Original");
        GameplayTags.Add(n"Gym.VfxExamples.GunshotHit.Ck");
        GameplayTags.Add(n"Gym.VfxExamples.GunshotHit.Original");
        GameplayTags.Add(n"Gym.VfxExamples.ArrowCast.Ck");
        GameplayTags.Add(n"Gym.VfxExamples.ArrowCast.Original");
        GameplayTags.Add(n"Gym.VfxExamples.ArrowHit.Ck");
        GameplayTags.Add(n"Gym.VfxExamples.ArrowHit.Original");
        GameplayTags.Add(n"Gym.VfxExamples.BombSpawn.Ck");
        GameplayTags.Add(n"Gym.VfxExamples.BombSpawn.Original");
        GameplayTags.Add(n"Gym.VfxExamples.PickupLoop.Ck");
        GameplayTags.Add(n"Gym.VfxExamples.PickupLoop.Original");
        GameplayTags.Add(n"Gym.VfxExamples.HealLoop.Ck");
        GameplayTags.Add(n"Gym.VfxExamples.HealLoop.Original");
        GameplayTags.Add(n"Gym.VfxExamples.BuffLoop.Ck");
        GameplayTags.Add(n"Gym.VfxExamples.BuffLoop.Original");
        GameplayTags.Add(n"Gym.VfxExamples.DebuffLoop.Ck");
        GameplayTags.Add(n"Gym.VfxExamples.DebuffLoop.Original");
        GameplayTags.Add(n"Gym.VfxExamples.PickupCast.Ck");
        GameplayTags.Add(n"Gym.VfxExamples.PickupCast.Original");
        GameplayTags.Add(n"Gym.VfxExamples.HealCast.Ck");
        GameplayTags.Add(n"Gym.VfxExamples.HealCast.Original");
        GameplayTags.Add(n"Gym.VfxExamples.DebuffCast.Ck");
        GameplayTags.Add(n"Gym.VfxExamples.DebuffCast.Original");
        GameplayTags.Add(n"Gym.VfxExamples.GunshotCast.Ck");
        GameplayTags.Add(n"Gym.VfxExamples.GunshotCast.Original");
        GameplayTags.Add(n"Gym.VfxExamples.FireBallCast.Ck");
        GameplayTags.Add(n"Gym.VfxExamples.FireBallCast.Original");
        GameplayTags.Add(n"Gym.VfxExamples.LightningCast.Ck");
        GameplayTags.Add(n"Gym.VfxExamples.LightningCast.Original");
        GameplayTags.Add(n"Gym.VfxExamples.FireBallProjectile.Ck");
        GameplayTags.Add(n"Gym.VfxExamples.FireBallProjectile.Original");
        GameplayTags.Add(n"Gym.VfxExamples.BombProjectile.Ck");
        GameplayTags.Add(n"Gym.VfxExamples.BombProjectile.Original");
        GameplayTags.Add(n"Gym.VfxExamples.BuffCast.Ck");
        GameplayTags.Add(n"Gym.VfxExamples.BuffCast.Original");
        GameplayTags.Add(n"Gym.VfxExamples.LightningMuzzle.Ck");
        GameplayTags.Add(n"Gym.VfxExamples.LightningMuzzle.Original");
        GameplayTags.Add(n"Gym.VfxExamples.ExplosionGround.Ck");
        GameplayTags.Add(n"Gym.VfxExamples.ExplosionGround.Original");
        GameplayTags.Add(n"Gym.VfxExamples.ExplosionGroundIce.Ck");
        GameplayTags.Add(n"Gym.VfxExamples.ExplosionGroundIce.Original");
        GameplayTags.Add(n"Gym.VfxExamples.ExplosionOmni.Ck");
        GameplayTags.Add(n"Gym.VfxExamples.ExplosionOmni.Original");
        GameplayTags.Add(n"Gym.VfxExamples.ExplosionOmniIce.Ck");
        GameplayTags.Add(n"Gym.VfxExamples.ExplosionOmniIce.Original");
        GameplayTags.Add(n"Gym.VfxExamples.BombExplosion.Ck");
        GameplayTags.Add(n"Gym.VfxExamples.BombExplosion.Original");
        GameplayTags.Add(n"Gym.VfxExamples.LightningHit.Ck");
        GameplayTags.Add(n"Gym.VfxExamples.LightningHit.Original");
    }
}
