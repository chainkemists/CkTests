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
    }
}
