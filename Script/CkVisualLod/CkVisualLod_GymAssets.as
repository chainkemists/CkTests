// Language=angelscript

//============================================================================
// CK VISUAL LOD GYM - wrapper assets
//============================================================================
//
// AS-authored arbiter config for the VisualLod gym, wired to the shared Iskm
// demo content (iskm_assets:: accessors - bare Asset_* symbols are not visible
// across .as files). Gym-scale distances: the promote/demote band sits a short
// walk from the station so the flip is easy to trigger on foot.
//
// Direct UCk_Utils_* / literal-init rules match CkIskmRenderer_Assets.as
// the deferred-asset-init system re-runs this chain once the engine is safe.
//============================================================================

asset Asset_VisualLodGym_ArbiterConfig of UCk_VisualLodArbiter_Data
{
    _DomainTag = utils_gameplay_tag::ResolveGameplayTag(n"Gym.VisualLod.Domain");

    // A short walk: promote inside 9m, demote past 13m - the hysteresis band is wide enough
    // to see a mid-fade reversal by stepping back and forth across it.
    _PromoteDistance = 900.0f;
    _DemoteDistance  = 1300.0f;

    // Budget 5 against a 40-member crowd: walking the line makes ranked preemption visible
    // the worst incumbent dissolves back as a better-placed member takes its slot.
    _NearBudget = 5;
    _LockBudget = 2;
    _LockPromoteMaxDistance = 4000.0f;

    _ViewConeMarginDeg    = 10.0f;
    _AlwaysInViewDistance = 300.0f;
    _PreemptDistanceMargin = 200.0f;
    _MaxPreemptsPerTick    = 2;

    // The two ends of the one fade alpha. Slot 13 is the crowd instance float the CkUsf
    // VisualLodCrowdFade look reads; index 0 is the proxy custom-primitive-data float
    // VisualLodNearFade reads. Both are the defaults - stated here because the station's material
    // wiring hard-codes the matching look assets, and a silent drift on either end shows up as a pop.
    _FadeDuration = FCk_Time(0.3);
    _FadeCustomDataSlot = 13;
    _FadeNearCustomPrimitiveDataSlot = 0;

    FCk_VisualLod_CrowdConfig CrowdCfg;
    CrowdCfg._AnimCollection = iskm_assets::AnimCollection_Demo();
    CrowdCfg.Set_PoolSize(64);
    CrowdCfg.Set_TileSize(1500.0f);
    CrowdCfg.Set_IdleSequenceIndex(0);
    CrowdCfg.Set_MoveSequenceIndex(2);
    _CrowdConfigs.Add(CrowdCfg);
}

namespace visual_lod_gym_assets
{
    UCk_VisualLodArbiter_Data ArbiterConfig() { return Asset_VisualLodGym_ArbiterConfig; }
}
