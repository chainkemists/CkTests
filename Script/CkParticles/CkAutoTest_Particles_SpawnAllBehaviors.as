// Language=angelscript

//============================================================================
// CK PARTICLES — AUTOMATION TEST: SPAWN ALL BEHAVIORS
//============================================================================
//
// Every registered BehaviorId (the whole roster, incl. the marketplace
// recreations) spawns a live component from its template via the runtime utils.
// This exercises: template asset load, DI wiring, User.BehaviorId patch,
// and the per-texture material-instance swap path.
//============================================================================

class UCk_AutoTest_Particles_SpawnAllBehaviors : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;

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
            ck::Trace("[Particles] this process cannot render (e.g. -nullrhi) — Niagara drops every spawn; skipping");
            FinishSuccess();
            return;
        }

        for (int BehaviorId = 0; BehaviorId < UCk_Utils_Particles_UE::Get_NumBehaviors(); ++BehaviorId)
        {
            auto Component = UCk_Utils_Particles_UE::Spawn_BehaviorAtLocation(
                BehaviorId, FVector(0, 0, 300));

            Assert_True(ck::IsValid(Component),
                f"Spawn_BehaviorAtLocation must return a live component for BehaviorId {BehaviorId}");
        }

        FinishSuccess();
    }
}
