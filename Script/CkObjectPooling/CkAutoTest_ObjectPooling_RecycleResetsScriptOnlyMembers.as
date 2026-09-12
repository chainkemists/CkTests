// Language=angelscript
//
// CK OBJECT POOLING - AUTOMATION TEST: recycle resets SCRIPT-ONLY members
//
// The one test that pins the BEHAVIOUR of the script-object copy in
// Request_ResetToArchetype. Every other pooled subject declares its members
// UPROPERTY(), so the reflected FProperty sweep restores them and those tests
// stay green with the script copy removed entirely. ScriptOnlyValue is invisible
// to that sweep; ReflectedValue is the control that keeps a red legible.

class UCk_AutoTest_ObjectPooling_RecycleResetsScriptOnlyMembers : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 5.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();

        auto PoolParams = FCk_ObjectPooling_PoolParams(); // defaults: Recycle / Unbounded / Grow

        auto Obj1 = Cast<UCk_ObjectPoolingTest_ScriptOnlyMemberObject>(
            utils_object::Request_CreateNewObject_Pooled(
                this, UCk_ObjectPoolingTest_ScriptOnlyMemberObject, nullptr, PoolParams));

        Assert_True(ck::IsValid(Obj1), "acquire #1: pooled create must return an instance");
        if (IsFinished()) { return; }

        Assert_Equals_Int(Obj1.ScriptOnlyValue, 0,
            "acquire #1: a fresh instance must start at the archetype default");
        if (IsFinished()) { return; }

        Obj1.ScriptOnlyValue = 42;
        Obj1.ReflectedValue = 42;

        auto ReleaseResult = utils_object::TryReleaseToPool(Obj1);
        Assert_True(ReleaseResult == ECk_SucceededFailed::Succeeded,
            "release: TryReleaseToPool must succeed for a pool-managed object");
        if (IsFinished()) { return; }

        auto Obj2 = Cast<UCk_ObjectPoolingTest_ScriptOnlyMemberObject>(
            utils_object::Request_CreateNewObject_Pooled(
                this, UCk_ObjectPoolingTest_ScriptOnlyMemberObject, nullptr, PoolParams));

        Assert_True(Obj2 == Obj1,
            "acquire #2: the pool must re-issue the SAME instance (pointer identity) - otherwise the reset assertions below are vacuous");
        if (IsFinished()) { return; }

        Assert_Equals_Int(Obj2.ScriptOnlyValue, 0,
            "acquire #2: the recycle reset must restore the NON-UPROPERTY member to the archetype default (0), was stomped to 42 - the reflected sweep cannot see this member, so only the direct asCScriptObject::PerformCopy call can have restored it");

        Assert_Equals_Int(Obj2.ReflectedValue, 0,
            "acquire #2: control - the reflected member must also be back to 0; if THIS is stale too the whole reset regressed, not just the script copy");

        auto Stats = utils_object::Get_ObjectPoolStats(
            this, UCk_ObjectPoolingTest_ScriptOnlyMemberObject, nullptr);
        Assert_Equals_Int(Stats.Get_NumHits(), 1, "acquire #2: must be a pool HIT, not a fresh create");
        Assert_Equals_Int(Stats.Get_NumLiveInstances(), 1, "exactly 1 live instance across both acquires");

        FinishSuccess();
    }
}
