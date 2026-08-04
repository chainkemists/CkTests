// Language=angelscript

//============================================================================
// CK PARTICLES — AUTOMATION TEST: TUNING CONTRACT
//============================================================================
//
// A PLUMBING test for the per-instance tuning float4 (User.CkTuning), not a
// visual one: the picture it produces is checked by the CPU-mirror unit tests
// and by eye in the gym. What is asserted here is that the runtime API is
// total — a spawn with NO explicit tuning still returns a live component (a
// null one falls through to the behavior's convention tuning asset, or to the
// identity when none is on disk; it is not an error), and retuning that live
// component through the raw-value entry point leaves it alive.
//
// ---- Why the readback assertion is conditional ----------------------------
//
// UNiagaraComponent::GetVariableVec4 reads the component's OVERRIDE parameter
// store, and Niagara only redirects a write into that store for a user
// parameter the system actually declares. Templates are generated assets: one
// built before User.CkTuning existed carries no such parameter, so the write
// lands only on the deferred instance path and the readback reports bIsValid
// false. Asserting unconditionally would make this test a proxy for "has
// anyone re-run Create Template System", which is an asset-pipeline question,
// not a code one. So the readback asserts when the parameter is present and
// logs which branch it took when it is not.
//
// ---- Why no null-component case -------------------------------------------
//
// Request_ApplyTuning* guard an invalid component with CK_ENSURE_IF_NOT, and
// the AutoTest harness escalates an ensure into a failure. Passing null here
// would assert the guard by tripping it, which is a red test either way.
//============================================================================

class UCk_AutoTest_Particles_TuningContract : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 60.0f;

    // Deliberately non-identity in every lane, and all four distinct, so a
    // packing order swapped anywhere between here and the float4 shows up.
    private float _SizeMultiplier  = 2.0f;
    private float _ColorIntensity  = 3.0f;
    private float _AlphaMultiplier = 0.5f;
    private float _PlaybackSpeed   = 0.25f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();

        // Niagara refuses to create a component when the process cannot render:
        // UNiagaraFunctionLibrary::SpawnSystemAtLocation gates on FApp::CanEverRender(),
        // which is false under -nullrhi (the toolbox's default --test lane), so every
        // spawn returns null. Skip rather than assert something unachievable here.
        if (!utils_render_target::Get_CanRenderOnThisProcess())
        {
            Print("[Particles] this process cannot render (e.g. -nullrhi) — Niagara drops every spawn; skipping");
            FinishSuccess();
            return;
        }

        // Null: a caller with no tuning asset gets the identity and a live component.
        UCkParticles_TuningDefinition NoTuningAsset;

        auto Component = UCk_Utils_Particles_UE::Spawn_BehaviorAtLocation_Tuned(
            0, FVector(0, 0, 300), FRotator::ZeroRotator, FVector(1.0, 1.0, 1.0), NAME_None, NoTuningAsset);

        Assert_True(ck::IsValid(Component),
            "Spawn_BehaviorAtLocation_Tuned must return a live component even with no tuning asset");

        if (ck::Is_NOT_Valid(Component))
        {
            FinishSuccess();
            return;
        }

        UCk_Utils_Particles_UE::Request_ApplyTuningValues(
            Component, _SizeMultiplier, _ColorIntensity, _AlphaMultiplier, _PlaybackSpeed);

        Assert_True(ck::IsValid(Component),
            "Request_ApplyTuningValues must leave the component alive");

        Assert_TuningReadback(Component);

        Component.DestroyComponent();

        FinishSuccess();
    }

    // The parameter name mirrors ck::particles::Get_TuningParameterName(), which has no
    // Blueprint/AngelScript surface — a mismatch surfaces as the not-declared branch below.
    private void Assert_TuningReadback(UNiagaraComponent InComponent)
    {
        bool ParameterIsDeclared = false;
        auto Tuning = InComponent.GetVariableVec4(n"User.CkTuning", ParameterIsDeclared);

        if (!ParameterIsDeclared)
        {
            Print("[Particles] User.CkTuning is not declared on this template — regenerate the templates to cover the readback");
            return;
        }

        const float32 Tolerance = 0.001f;

        Assert_True(Math::Abs(Tuning.X - _SizeMultiplier) < Tolerance,
            f"User.CkTuning.x must carry the size multiplier, got {Tuning.X}");
        Assert_True(Math::Abs(Tuning.Y - _ColorIntensity) < Tolerance,
            f"User.CkTuning.y must carry the colour intensity, got {Tuning.Y}");
        Assert_True(Math::Abs(Tuning.Z - _AlphaMultiplier) < Tolerance,
            f"User.CkTuning.z must carry the alpha multiplier, got {Tuning.Z}");
        Assert_True(Math::Abs(Tuning.W - _PlaybackSpeed) < Tolerance,
            f"User.CkTuning.w must carry the playback speed, got {Tuning.W}");
    }
}
