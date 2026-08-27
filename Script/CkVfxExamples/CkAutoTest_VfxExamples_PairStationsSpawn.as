// Language=angelscript

//============================================================================
// CK VFX EXAMPLES - AUTOMATION TEST: PAIR STATIONS SPAWN
//============================================================================
//
// The A/B pair registry is well-formed and BOTH sides of every pair reach a
// live component: the CkParticles side through the normal spawn path, the
// original side either through a resolved candidate path or through the
// placeholder branch. Neither branch may emit a Warning or Error - the harness
// escalates one into a test failure, which is exactly the guarantee the
// "Vefects content is optional" contract needs.
//============================================================================

class UCk_AutoTest_VfxExamples_PairStationsSpawn : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 15.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();

        auto Pairs = CkVfxExamples::Get_Pairs();
        Assert_True(Pairs.Num() > 0, "the VfxExamples pair registry must not be empty");

        for (auto Pair : Pairs)
        {
            Assert_True(Pair.BehaviorId >= 0 && Pair.BehaviorId < utils_particles::Get_NumBehaviors(),
                f"pair '{Pair.DisplayName}' must name a BehaviorId inside the CkParticles roster");
            Assert_True(Pair.OriginalCandidatePackagePaths.Num() > 0,
                f"pair '{Pair.DisplayName}' must carry at least one original-asset candidate path");
            Assert_True(Pair.OriginalAssetName != "",
                f"pair '{Pair.DisplayName}' must carry the original asset's leaf name");
            Assert_True(Pair.Credit != "",
                f"pair '{Pair.DisplayName}' must credit the effect it recreates");
        }

        // Niagara refuses to create a component when the process cannot render:
        // UNiagaraFunctionLibrary::SpawnSystemAtLocation gates on FApp::CanEverRender(),
        // which is false under -nullrhi (the toolbox's default --test lane), so every
        // spawn returns null. Run this lane with --no-nullrhi to exercise the spawns.
        if (!utils_render_target::Get_CanRenderOnThisProcess())
        {
            ck::Trace("[VfxExamples] this process cannot render (e.g. -nullrhi) - Niagara drops every spawn; skipping the spawn half");
            FinishSuccess();
            return;
        }

        for (auto Pair : Pairs)
        {
            Run_PairSpawnChecks(Pair);
        }

        if (_PlaceholderCount > 0)
        {
            ck::Trace(f"[VfxExamples] {_PlaceholderCount} pair(s) took the placeholder branch - the original content is not installed");
        }

        FinishSuccess();
    }

    private int32 _PlaceholderCount = 0;

    // One pair's spawn contract, with the spawns destroyed before returning: with the
    // originals installed, letting all pairs' systems accumulate to the end of the test
    // recreates the many-live-systems regime that collapses frame times (the reason the
    // gym itself now runs one pair at a time).
    private void Run_PairSpawnChecks(FCk_VfxExamples_Pair InPair)
    {
        auto Spawned = TArray<UNiagaraComponent>();

        auto CkComponent = utils_particles::Spawn_BehaviorAtLocation(
            InPair.BehaviorId, FVector(0, 0, 300), FRotator::ZeroRotator,
            FVector(1.0, 1.0, 1.0), InPair.TextureName);

        Assert_True(ck::IsValid(CkComponent),
            f"the CkParticles side of pair '{InPair.DisplayName}' must spawn a live component");

        if (ck::IsValid(CkComponent)) { Spawned.Add(CkComponent); }

        auto Original = CkVfxExamples::TryLoad_OriginalSystem(InPair);

        if (ck::Is_NOT_Valid(Original))
        {
            _PlaceholderCount++;
        }
        else
        {
            auto AutoDestroy = false;
            auto AutoActivate = true;
            auto PreCullCheck = true;

            auto OriginalComponent = Niagara::SpawnSystemAtLocation(
                Original, FVector(0, 0, 300), FRotator::ZeroRotator, FVector(1.0, 1.0, 1.0),
                AutoDestroy, AutoActivate, ENCPoolMethod::None, PreCullCheck);

            Assert_True(ck::IsValid(OriginalComponent),
                f"the resolved original system for pair '{InPair.DisplayName}' must spawn a live component");

            if (ck::IsValid(OriginalComponent))
            {
                Spawned.Add(OriginalComponent);

                // The loop mechanism, asserted without waiting for a system to actually finish.
                // A SECOND spawn with bAutoActivate=false is the only deterministic way to reach
                // IsActive()==false from AS: Niagara's Deactivate() is a SOFT stop that keeps the
                // component active while live particles drain, and DeactivateImmediate() is a plain
                // virtual (no UFUNCTION anywhere in the chain), so it is not bindable. Asserting the
                // re-arm on the already-active component above would pass vacuously.
                auto Idle = Niagara::SpawnSystemAtLocation(
                    Original, FVector(0, 0, 300), FRotator::ZeroRotator, FVector(1.0, 1.0, 1.0),
                    AutoDestroy, false, ENCPoolMethod::None, PreCullCheck);

                if (ck::IsValid(Idle))
                {
                    Spawned.Add(Idle);

                    Assert_True(Idle.IsActive() == false,
                        f"a bAutoActivate=false spawn for pair '{InPair.DisplayName}' must start inactive");

                    CkVfxExamples::Request_RestartComponent(Idle);

                    Assert_True(Idle.IsActive(),
                        f"Request_RestartComponent must re-activate the idle original for pair '{InPair.DisplayName}'");
                }
            }
        }

        for (auto Component : Spawned)
        {
            if (ck::IsValid(Component)) { Component.DestroyComponent(); }
        }
    }
}
