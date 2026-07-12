// Language=angelscript

//============================================================================
// CK PARTICLES — AUTOMATION TEST: SPAWN ALL BEHAVIORS
//============================================================================
//
// Every registered BehaviorId (0-16, incl. the 8 marketplace recreations)
// spawns a live component from the seed template via the runtime utils.
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

        for (int BehaviorId = 0; BehaviorId <= 16; ++BehaviorId)
        {
            auto Component = UCk_Utils_Particles_UE::Spawn_BehaviorAtLocation(
                BehaviorId, FVector(0, 0, 300));

            Assert_True(ck::IsValid(Component),
                f"Spawn_BehaviorAtLocation must return a live component for BehaviorId {BehaviorId}");
        }

        FinishSuccess();
    }
}
