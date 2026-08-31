// Language=angelscript
//
// CK OBJECT POOLING - AUTOMATION TEST: recycle resets SCRIPT-ONLY members
//
// The one test that pins the BEHAVIOUR of the script-object copy in
// Request_ResetToArchetype. Every other pooled subject declares its members
// UPROPERTY(), so the reflected FProperty sweep restores them and those tests
// stay green even if the script copy is removed entirely - they execute that
// call without asserting anything it does.
//
// ScriptOnlyValue has no UPROPERTY, so no FProperty exists for it and the
// reflected sweep cannot see it. Only asCScriptObject::PerformCopy resets it.
// A recycled instance that resumes its previous life's ScriptOnlyValue is the
// exact defect a precompiled-script-cache boot used to produce, when the copy
// was resolved by name and that registration had been deleted as unused.
//
// ReflectedValue rides along as the CONTROL that keeps a red legible: both
// stale means the whole reset regressed; only ScriptOnlyValue stale means the
// script copy specifically did.

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

        // stomp BOTH: the script-only member is the subject, the reflected one is the control
        Obj1.ScriptOnlyValue = 42;
        Obj1.ReflectedValue = 42;

        auto ReleaseResult = utils_object::TryReleaseToPool(Obj1);
        Assert_True(ReleaseResult == ECk_SucceededFailed::Succeeded,
            "release: TryReleaseToPool must succeed for a pool-managed object");
        if (IsFinished()) { return; }

        auto Obj2 = Cast<UCk_ObjectPoolingTest_ScriptOnlyMemberObject>(
            utils_object::Request_CreateNewObject_Pooled(
                this, UCk_ObjectPoolingTest_ScriptOnlyMemberObject, nullptr, PoolParams));

        // identity FIRST: without it a fresh instance would satisfy every assertion below and
        // the test would pass while proving nothing about recycling
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
