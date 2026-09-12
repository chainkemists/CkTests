// Language=angelscript

// Two isolated domains for the authored runtime-tuner PIE test. They reuse the verified
// VisualLod gym render assets, but do not alter the gym's shared configuration.
namespace Ck
{
    asset VisualLodArbiterTunersPie_Tags of UCk_GameplayTags
    {
        GameplayTags.Add(n"AutoTest.VisualLod.ArbiterTuners.A");
        GameplayTags.Add(n"AutoTest.VisualLod.ArbiterTuners.B");
    }
}

FCk_VisualLod_CrowdConfig Make_ArbiterTunersPieCrowdConfig()
{
    FCk_VisualLod_CrowdConfig CrowdCfg;
    CrowdCfg._AnimCollection = iskm_assets::AnimCollection_Demo();
    CrowdCfg.Set_PoolSize(2);
    CrowdCfg.Set_TileSize(1000.0f);
    CrowdCfg.Set_IdleSequenceIndex(0);
    CrowdCfg.Set_MoveSequenceIndex(2);

    TArray<FCk_VisualLod_RenderBand> RenderBands;
    FCk_VisualLod_RenderBand FullBand;
    FullBand.Set_DistanceThreshold(0.0f);
    FullBand.Set_RendererProfile(visual_lod_gym_assets::FullRenderProfile());
    RenderBands.Add(FullBand);
    CrowdCfg.Set_RenderBands(RenderBands);
    return CrowdCfg;
}

asset Asset_VisualLodArbiterTunersPie_ConfigA of UCk_VisualLodArbiter_Data
{
    _DomainTag = utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.VisualLod.ArbiterTuners.A");
    _PromoteDistance = 400.0f;
    _DemoteDistance = 800.0f;
    _NearBudget = 3;
    _LockBudget = 1;
    _LockPromoteMaxDistance = 1200.0f;
    _ViewConeMarginDeg = 10.0f;
    _AlwaysInViewDistance = 200.0f;
    _PreemptDistanceMargin = 80.0f;
    _MaxPreemptsPerTick = 1;
    _FadeDuration = FCk_Time(0.2);
    _FadeAnchorLeadFrames = 1.0f;
    _FadeAnchorBakeLagIntervals = 0.5f;
    _CrowdConfigs.Add(Make_ArbiterTunersPieCrowdConfig());
}

asset Asset_VisualLodArbiterTunersPie_ConfigB of UCk_VisualLodArbiter_Data
{
    _DomainTag = utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.VisualLod.ArbiterTuners.B");
    _PromoteDistance = 500.0f;
    _DemoteDistance = 900.0f;
    _NearBudget = 4;
    _LockBudget = 2;
    _LockPromoteMaxDistance = 1600.0f;
    _ViewConeMarginDeg = 12.0f;
    _AlwaysInViewDistance = 250.0f;
    _PreemptDistanceMargin = 90.0f;
    _MaxPreemptsPerTick = 2;
    _FadeDuration = FCk_Time(0.3);
    _FadeAnchorLeadFrames = 1.5f;
    _FadeAnchorBakeLagIntervals = 0.75f;
    _CrowdConfigs.Add(Make_ArbiterTunersPieCrowdConfig());
}

