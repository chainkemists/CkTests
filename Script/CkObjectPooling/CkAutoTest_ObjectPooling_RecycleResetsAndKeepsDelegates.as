// Language=angelscript
//
// CK OBJECT POOLING — AUTOMATION TEST: recycle round trip on a plain pooled object
//
// Fully synchronous via the direct pooled API. acquire -> bind participant +
// stomp Value -> release -> acquire again. Proves in one shot: the pool re-issues
// the SAME instance (pointer identity), the reset-to-archetype restored Value to
// the CDO default, the participant delegates SURVIVED the recycle (reset skips the
// participant property) and fired OnReleased then OnAcquired, and the stats read a
// hit.

class UCk_AutoTest_ObjectPooling_RecycleResetsAndKeepsDelegates : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 5.0f;

    private int32 _NumAcquiredObserved = 0;
    private int32 _NumReleasedObserved = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();

        auto PoolParams = FCk_ObjectPooling_PoolParams(); // defaults: Recycle / Unbounded / Grow

        auto Obj1 = Cast<UCk_ObjectPoolingTest_PlainObject>(
            utils_object::Request_CreateNewObject_Pooled(
                this, UCk_ObjectPoolingTest_PlainObject, nullptr, PoolParams));

        Assert_True(ck::IsValid(Obj1), "acquire #1: pooled create must return an instance");
        if (IsFinished()) { return; }

        // bind the participant hooks onto the TEST (stable across the object's recycle); these binds
        // live in the participant property, which the recycle reset deliberately skips
        Obj1.Participant.BindTo_OnAcquiredFromPool(
            FCk_Delegate_ObjectPoolingParticipant_OnAcquired(this, n"OnAcquired"));
        Obj1.Participant.BindTo_OnReleasedToPool(
            FCk_Delegate_ObjectPoolingParticipant_OnReleased(this, n"OnReleased"));

        // stomp a reflected property — the recycle reset must bring it back to the archetype's 0
        Obj1.Value = 42;

        auto ReleaseResult = utils_object::TryReleaseToPool(Obj1);
        Assert_True(ReleaseResult == ECk_SucceededFailed::Succeeded,
            "release: TryReleaseToPool must succeed for a pool-managed object");
        Assert_Equals_Int(_NumReleasedObserved, 1, "release: OnReleasedToPool must have fired once");
        if (IsFinished()) { return; }

        auto Obj2 = Cast<UCk_ObjectPoolingTest_PlainObject>(
            utils_object::Request_CreateNewObject_Pooled(
                this, UCk_ObjectPoolingTest_PlainObject, nullptr, PoolParams));

        Assert_True(Obj2 == Obj1, "acquire #2: the pool must re-issue the SAME instance (pointer identity)");
        Assert_Equals_Int(Obj2.Value, 0,
            "acquire #2: recycle reset must restore Value to the archetype default (0), was stomped to 42");
        Assert_Equals_Int(_NumAcquiredObserved, 1,
            "acquire #2: the delegate bound before the recycle must fire OnAcquiredFromPool once (binds survive the reset)");

        auto Stats = utils_object::Get_ObjectPoolStats(this, UCk_ObjectPoolingTest_PlainObject, nullptr);
        Assert_Equals_Int(Stats.Get_NumHits(), 1, "acquire #2: must be a pool HIT, not a fresh create");
        Assert_Equals_Int(Stats.Get_NumLiveInstances(), 1, "exactly 1 live instance across both acquires");

        FinishSuccess();
    }

    UFUNCTION()
    private void OnAcquired() { _NumAcquiredObserved++; }

    UFUNCTION()
    private void OnReleased() { _NumReleasedObserved++; }
}
