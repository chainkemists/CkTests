// --------------------------------------------------------------------------------------------------------------------
// Showcase for a PostProcess look: an unbound UPostProcessComponent applies a CkUsf PostProcess-domain
// look (EdgeOutline) to the entire view. Proves the post-process + scene-texture capability end-to-end.
// --------------------------------------------------------------------------------------------------------------------

class ACk_UsfGym_PostProcessShowcase : AActor
{
    UPROPERTY(DefaultComponent, RootComponent)
    USceneComponent SceneRoot;

    UPROPERTY(DefaultComponent)
    UPostProcessComponent PostProcess;

    // Unbound = affects the whole view regardless of volume bounds.
    default PostProcess.bUnbound = true;

    UPROPERTY()
    UCkUsf_LookDefinition Look = CkUsf::EdgeOutline;

    UFUNCTION(BlueprintOverride)
    void BeginPlay()
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto MID = UCk_Utils_Usf_UE::Apply_PostProcess_ToComponent(PostProcess, Look);
        if (MID != nullptr)
        {
            ck::Trace("[OK] CkUsf gym: post-process edge-outline applied to view");
        }
        else
        {
            ck::Warning("[FAIL] CkUsf gym: PostProcess MID failed - run 'Generate Look Materials' first");
        }
    }
}
