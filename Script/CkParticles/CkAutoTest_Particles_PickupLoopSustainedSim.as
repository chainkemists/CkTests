// Language=angelscript

//============================================================================
// CK PARTICLES - AUTOMATION TEST: PICKUP LOOP SUSTAINED SIM
//============================================================================
//
// Behavior 26 (the NS_PickupLoop port) keeps a live, rendering component
// simulating for 60 real frames without wedging the editor. The probe exists
// because activating exactly this pair in the VfxExamples gym hung the
// maintainer's editor (2026-08-02) while its three Loop siblings did not, and
// its cadence row is innocuous (27.5/s x 4.0 s ~ 110 particles steady-state)
// - so the failure mode under investigation is a stalled frame loop, not a
// wrong picture. Sixty chained WaitOneFrame calls each consume one REAL
// frame; a sim whose frames take seconds-to-minutes cannot clear sixty of
// them inside the timeout, so a wedge reports as a timeout red instead of
// hanging the run.
//============================================================================

// The probe runs TWO 60-frame phases and traces a timestamped marker between them, so
// the LOG's own wall clock separates "this headless editor just ticks slowly" (both
// phases slow) from "behavior 26 is the cost" (only the spawned phase slow). The first
// measured run (2026-08-03) showed 0.51 s/frame with the system alive - this shape
// exists to attribute it.
class UCk_AutoTest_Particles_PickupLoopSustainedSim : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 240.0f;

    private UNiagaraComponent _Component;
    private int32 _FramesRemaining = 60;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();

        // Niagara refuses to create a component when the process cannot render
        // (FApp::CanEverRender() is false under -nullrhi), and a non-rendering
        // process can't reproduce a render-side stall anyway.
        if (!utils_render_target::Get_CanRenderOnThisProcess())
        {
            Print(f"[PickupLoopSustainedSim] this process cannot render (e.g. -nullrhi) - skipping");
            FinishSuccess();
            return;
        }

        Print(f"[PickupLoopSustainedSim] BASELINE phase start (60 frames, nothing spawned)");
        WaitOneFrame(n"OnBaselineFrameElapsed");
    }

    UFUNCTION()
    private void OnBaselineFrameElapsed(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        auto _CkPerfScope = ck::ScopedStat();

        _FramesRemaining--;
        if (_FramesRemaining > 0)
        {
            WaitOneFrame(n"OnBaselineFrameElapsed");
            return;
        }

        Print(f"[PickupLoopSustainedSim] BASELINE phase end - spawning behavior 26");

        _Component = utils_particles::Spawn_BehaviorAtLocation(
            26, FVector(0, 0, 300), FRotator::ZeroRotator, FVector(1.0, 1.0, 1.0), NAME_None);

        Assert_True(ck::IsValid(_Component), "behavior 26 must spawn a live component");

        if (ck::Is_NOT_Valid(_Component))
        {
            FinishSuccess();
            return;
        }

        _FramesRemaining = 60;
        WaitOneFrame(n"OnSpawnedFrameElapsed");
    }

    UFUNCTION()
    private void OnSpawnedFrameElapsed(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        auto _CkPerfScope = ck::ScopedStat();

        _FramesRemaining--;
        if (_FramesRemaining > 0)
        {
            WaitOneFrame(n"OnSpawnedFrameElapsed");
            return;
        }

        Print(f"[PickupLoopSustainedSim] SPAWNED phase end (60 frames with behavior 26 alive)");

        if (ck::IsValid(_Component))
        {
            _Component.DestroyComponent();
        }

        FinishSuccess();
    }
}
