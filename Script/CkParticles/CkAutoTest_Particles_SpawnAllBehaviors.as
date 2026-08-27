// Language=angelscript

//============================================================================
// CK PARTICLES - AUTOMATION TEST: SPAWN ALL BEHAVIORS
//============================================================================
//
// Every registered BehaviorId (the whole roster, incl. the marketplace
// recreations) spawns a live component from its template via the runtime utils.
// This exercises: template asset load, DI wiring, User.BehaviorId patch,
// and the per-texture material-instance swap path.
//
// ---- Each component is destroyed in the frame that spawned it -------------
//
// Spawn_BehaviorAtLocation spawns with bAutoDestroy=false and every template
// loops, so a component left alone keeps simulating for the rest of the PIE
// session. The roster size is Get_NumBehaviors() - never restate it. The moment the walk spans more than one
// frame, every later frame ticks the whole accumulated set - and a headless
// real-RHI frame carrying a few dozen of these costs minutes, not milliseconds.
// That cost, not the spawn path this test claims to cover, becomes what the
// test measures, and it drags the run long enough for unrelated background
// Warnings (the engine's periodic connectivity probe) to land inside the test
// window, where the harness escalates them into a failure.
//
// What is asserted is what the spawn call RETURNED, recorded at the moment of
// the spawn - so destroying immediately costs the assertion nothing. The
// sibling VfxExamples pair-station test destroys on the same grounds.
//
// ---- Why the spawns are staggered across frames ---------------------------
//
// Spawning the roster in one frame pays first-render PSO creation and any cold
// static-mesh build for every template at once, with the game thread producing
// no log output while it grinds - and a harness idle-watchdog cannot tell a
// frozen editor from a busy one. A few ids per frame returns to the engine
// between batches so the process keeps ticking and logging while it works.
//============================================================================

class UCk_AutoTest_Particles_SpawnAllBehaviors : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 120.0f;

    // Ids spawned per frame. Small enough that no single frame stalls long enough to
    // look hung; large enough that the whole roster still lands in a handful of frames.
    private int32 _SpawnsPerFrame = 5;

    // How far through the roster the staggered walk has got.
    private int32 _NextBehaviorId = 0;

    // Whether Spawn_BehaviorAtLocation handed back a live component, recorded AT THE
    // MOMENT OF THE SPAWN - before this test destroys it again. The assertions run at
    // the end over the whole roster, against these records rather than against the
    // components, which no longer exist by then.
    private TArray<bool> _SpawnedLive;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();

        // Niagara refuses to create a component when the process cannot render:
        // UNiagaraFunctionLibrary::SpawnSystemAtLocation gates on FApp::CanEverRender(),
        // which is false under -nullrhi (the toolbox's default --test lane), so every
        // spawn returns null. Skip rather than assert something unachievable here.
        // Run this lane with --no-nullrhi to actually exercise the spawns.
        if (!utils_render_target::Get_CanRenderOnThisProcess())
        {
            ck::Trace("[Particles] this process cannot render (e.g. -nullrhi) - Niagara drops every spawn; skipping");
            FinishSuccess();
            return;
        }

        Spawn_NextBatch();
    }

    // Spawns up to _SpawnsPerFrame ids, then either yields a frame or runs the final
    // assertion set. The roster bound is read fresh on every pass, so nothing here
    // restates a behavior count.
    private void Spawn_NextBatch()
    {
        auto NumBehaviors = UCk_Utils_Particles_UE::Get_NumBehaviors();

        auto BatchEnd = _NextBehaviorId + _SpawnsPerFrame;
        if (BatchEnd > NumBehaviors)
        { BatchEnd = NumBehaviors; }

        while (_NextBehaviorId < BatchEnd)
        {
            auto Component = UCk_Utils_Particles_UE::Spawn_BehaviorAtLocation(
                _NextBehaviorId, FVector(0, 0, 300));

            _SpawnedLive.Add(ck::IsValid(Component));

            if (ck::IsValid(Component))
            { Component.DestroyComponent(); }

            _NextBehaviorId++;
        }

        if (_NextBehaviorId < NumBehaviors)
        {
            WaitOneFrame(n"INTERNAL__Particles_OnBatchSettled");
            return;
        }

        Assert_WholeRosterSpawned();
    }

    UFUNCTION()
    private void INTERNAL__Particles_OnBatchSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        Spawn_NextBatch();
    }

    // The final assertion set: one live component per id, across the whole roster,
    // driven by Get_NumBehaviors so no id is ever restated here.
    private void Assert_WholeRosterSpawned()
    {
        auto NumBehaviors = UCk_Utils_Particles_UE::Get_NumBehaviors();

        Assert_Equals_Int(_SpawnedLive.Num(), NumBehaviors,
            "The staggered walk must visit every BehaviorId exactly once");

        for (int BehaviorId = 0; BehaviorId < NumBehaviors; ++BehaviorId)
        {
            if (BehaviorId >= _SpawnedLive.Num())
            { break; }

            Assert_True(_SpawnedLive[BehaviorId],
                f"Spawn_BehaviorAtLocation must return a live component for BehaviorId {BehaviorId}");
        }

        FinishSuccess();
    }
}
