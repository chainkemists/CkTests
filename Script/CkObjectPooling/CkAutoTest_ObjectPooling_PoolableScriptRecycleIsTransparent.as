// Language=angelscript
//
// CK OBJECT POOLING - AUTOMATION TEST: a recycled EntityScript is indistinguishable from fresh
//
// The core transparency requirement, proven from INSIDE the script: the subject records the
// Scratch value it observes at Construct into an entity variable. Incarnation #1 stomps Scratch
// in BeginPlay; after destroy + respawn the recycled incarnation must observe the archetype
// default (the recycle reset ran) and BeginPlay must run again - while the pool stats prove it
// really was the same recycled instance, not a fresh create.

class UCk_AutoTest_ObjectPooling_PoolableScriptRecycleIsTransparent : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;

    private FCk_Handle _FirstEntity;
    private FCk_Handle _SecondEntity;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();

        auto Pending = utils_entity_script::Request_SpawnEntity(
            InHandle, UCk_ObjectPoolingTest_TransparencyScript, FInstancedStruct());
        utils_pending_entity_script::Promise_OnConstructed(
            Pending, FCk_Delegate_EntityScript_Constructed(this, n"OnFirstConstructed"));
    }

    UFUNCTION()
    private void OnFirstConstructed(FCk_Handle_EntityScript InEntity)
    {
        if (IsFinished()) { return; }

        _FirstEntity = FCk_Handle(InEntity);

        auto ObservedTag = utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.ObjectPooling.ObservedScratch");
        ECk_SucceededFailed Status = ECk_SucceededFailed::Failed;
        auto Observed = utils_variables_int32::Get_ByName(_FirstEntity, ObservedTag.GetTagName(), ECk_Recursion::NotRecursive, Status);
        Assert_True(Status == ECk_SucceededFailed::Succeeded, "incarnation #1: Construct must have recorded its observation");
        Assert_Equals_Int(Observed, 0, "incarnation #1: a fresh instance observes the archetype default");
        if (IsFinished()) { return; }

        // BeginPlay (which stomps Scratch to 99) runs after Construct. Wait on the
        // SawBeginPlay variable the next hop asserts on rather than on a frame budget:
        // Construct has only just returned, so it is decisively unset here.
        WaitUntil(n"Check_FirstBegunPlay", n"OnFirstBegunPlay");
    }

    // Reads the marker the subject's BeginPlay writes onto its own entity. Absent
    // variable == not begun, so this is false both before the spawn and between
    // Construct and BeginPlay.
    private bool DoSawBeginPlay(FCk_Handle InEntity)
    {
        if (!ck::IsValid(InEntity)) { return false; }

        auto BeginPlayTag = utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.ObjectPooling.SawBeginPlay");
        ECk_SucceededFailed Status = ECk_SucceededFailed::Failed;
        auto SawBeginPlay = utils_variables_int32::Get_ByName(InEntity, BeginPlayTag.GetTagName(), ECk_Recursion::NotRecursive, Status);
        return Status == ECk_SucceededFailed::Succeeded && SawBeginPlay == 1;
    }

    UFUNCTION()
    private void Check_FirstBegunPlay(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(DoSawBeginPlay(_FirstEntity));
    }

    UFUNCTION()
    private void OnFirstBegunPlay(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto BeginPlayTag = utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.ObjectPooling.SawBeginPlay");
        ECk_SucceededFailed Status = ECk_SucceededFailed::Failed;
        auto SawBeginPlay = utils_variables_int32::Get_ByName(_FirstEntity, BeginPlayTag.GetTagName(), ECk_Recursion::NotRecursive, Status);
        Assert_True(Status == ECk_SucceededFailed::Succeeded && SawBeginPlay == 1,
            "incarnation #1: BeginPlay must have run (and stomped Scratch to 99)");
        if (IsFinished()) { return; }

        utils_entity_lifetime::Request_DestroyEntity(_FirstEntity);

        // Respawning before the destroyed entity's script instance is back in the pool
        // would make spawn #2 a MISS and fail the NumHits assertion below for a timing
        // reason rather than a real one. Wait for the instance to actually be free.
        WaitUntil(n"Check_InstanceReturnedToPool", n"OnDestroySettled");
    }

    // NumFree is 0 while the instance is in use, so this cannot release early - it goes
    // true only once the destroy has run teardown all the way through the pool release.
    UFUNCTION()
    private void Check_InstanceReturnedToPool(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Stats = utils_object::Get_ObjectPoolStats(this, UCk_ObjectPoolingTest_TransparencyScript, nullptr);
        auto Res = OutResult;
        Res.Set(Stats.Get_NumFree() >= 1);
    }

    UFUNCTION()
    private void OnDestroySettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto Pending = utils_entity_script::Request_SpawnEntity(
            DoGet_ScriptEntity(), UCk_ObjectPoolingTest_TransparencyScript, FInstancedStruct());
        utils_pending_entity_script::Promise_OnConstructed(
            Pending, FCk_Delegate_EntityScript_Constructed(this, n"OnSecondConstructed"));
    }

    UFUNCTION()
    private void OnSecondConstructed(FCk_Handle_EntityScript InEntity)
    {
        if (IsFinished()) { return; }

        _SecondEntity = FCk_Handle(InEntity);

        // the recycled incarnation must have observed the RESET value at Construct - if the
        // recycle reset had not run, it would have observed incarnation #1's stomped 99
        auto ObservedTag = utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.ObjectPooling.ObservedScratch");
        ECk_SucceededFailed Status = ECk_SucceededFailed::Failed;
        auto Observed = utils_variables_int32::Get_ByName(_SecondEntity, ObservedTag.GetTagName(), ECk_Recursion::NotRecursive, Status);
        Assert_True(Status == ECk_SucceededFailed::Succeeded, "incarnation #2: Construct must have re-run and recorded");
        Assert_Equals_Int(Observed, 0,
            "incarnation #2: the RECYCLED instance must observe the archetype default (0) at Construct, not the previous incarnation's stomped 99 - recycled must be indistinguishable from fresh");
        if (IsFinished()) { return; }

        // and it really was a recycle, not a fresh create
        auto Stats = utils_object::Get_ObjectPoolStats(this, UCk_ObjectPoolingTest_TransparencyScript, nullptr);
        Assert_Equals_Int(Stats.Get_NumHits(), 1, "spawn #2 must be a pool HIT (same instance recycled)");
        Assert_Equals_Int(Stats.Get_NumLiveInstances(), 1, "exactly 1 live script instance across both spawns");
        if (IsFinished()) { return; }

        // The recycled incarnation's BeginPlay has not run yet - assert that rather than
        // assume it. The entity is new, but a recycled entity id that somehow kept its
        // variables would make the wait below pass on its first poll and prove nothing.
        Assert_True(!DoSawBeginPlay(_SecondEntity),
            "incarnation #2: SawBeginPlay must still be unset at Construct time");
        if (IsFinished()) { return; }

        WaitUntil(n"Check_SecondBegunPlay", n"OnSecondBegunPlay");
    }

    UFUNCTION()
    private void Check_SecondBegunPlay(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(DoSawBeginPlay(_SecondEntity));
    }

    UFUNCTION()
    private void OnSecondBegunPlay(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto BeginPlayTag = utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.ObjectPooling.SawBeginPlay");
        ECk_SucceededFailed Status = ECk_SucceededFailed::Failed;
        auto SawBeginPlay = utils_variables_int32::Get_ByName(_SecondEntity, BeginPlayTag.GetTagName(), ECk_Recursion::NotRecursive, Status);
        Assert_True(Status == ECk_SucceededFailed::Succeeded && SawBeginPlay == 1,
            "incarnation #2: BeginPlay must run again on the recycled instance");

        FinishSuccess();
    }
}
