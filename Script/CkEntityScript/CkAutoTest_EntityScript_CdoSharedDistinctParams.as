// Language=angelscript

//============================================================================
// CK ENTITY SCRIPT — AUTOMATION TEST: CDO-SHARED DISTINCT PARAMS PER ENTITY
//============================================================================
//
// Verifies that two same-frame spawns of ONE NotInstanced (CDO-shared) entity
// script class each keep their own spawn params and script-entity identity:
//   1. Spawn UCk_EntityScript_CdoSharedGym twice in the same frame with
//      different FCdoSharedGym_SpawnParams payloads.
//   2. The shared script's DoBeginPlay records DoGet_ScriptEntity() and the
//      typed DoGet_SpawnParams() payload into a FCdoSharedGym_Observed
//      fragment on each entity.
//   3. Assert per entity: observed payload matches what THAT entity was
//      spawned with, and the observed script entity is the entity itself.
//   4. Also assert the Utils read-back (utils_entity_script::Get_SpawnParams)
//      returns each entity's own params.
//
// Regression pin for the CDO clobbering defect: BeginPlay runs in a later
// processor than spawn handling, so before params moved onto the entity
// (FFragment_EntityScript_Current) and _AssociatedEntity was re-stamped per
// callback, the SECOND spawn's injection overwrote the first's members and
// back-pointer — both entities then observed the second spawn's values.
//============================================================================

class UCk_AutoTest_EntityScript_CdoSharedDistinctParams : UCk_AutoTest_Base
{
    private const int32 _FirstInt = 11;
    private const FName _FirstName = n"First";
    private const int32 _SecondInt = 22;
    private const FName _SecondName = n"Second";

    private FCk_Handle_EntityScript _FirstEntity;
    private FCk_Handle_EntityScript _SecondEntity;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Owner = InHandle;

        auto FirstParams = FCdoSharedGym_SpawnParams();
        FirstParams.PayloadInt = _FirstInt;
        FirstParams.PayloadName = _FirstName;

        auto SecondParams = FCdoSharedGym_SpawnParams();
        SecondParams.PayloadInt = _SecondInt;
        SecondParams.PayloadName = _SecondName;

        // Same frame, same NotInstanced class — the second request must not clobber
        // the first entity's params or script-entity back-pointer.
        auto FirstRequest = utils_entity_script::Request_SpawnEntity(
            Owner, UCk_EntityScript_CdoSharedGym, FirstParams);
        auto SecondRequest = utils_entity_script::Request_SpawnEntity(
            Owner, UCk_EntityScript_CdoSharedGym, SecondParams);

        utils_pending_entity_script::Promise_OnConstructed(
            FirstRequest, FCk_Delegate_EntityScript_Constructed(this, n"OnFirstConstructed"));
        utils_pending_entity_script::Promise_OnConstructed(
            SecondRequest, FCk_Delegate_EntityScript_Constructed(this, n"OnSecondConstructed"));
    }

    UFUNCTION()
    private void OnFirstConstructed(FCk_Handle_EntityScript InEntityScriptHandle)
    {
        _FirstEntity = InEntityScriptHandle;
        DoMaybeScheduleVerify();
    }

    UFUNCTION()
    private void OnSecondConstructed(FCk_Handle_EntityScript InEntityScriptHandle)
    {
        _SecondEntity = InEntityScriptHandle;
        DoMaybeScheduleVerify();
    }

    private void DoMaybeScheduleVerify()
    {
        if (ck::Is_NOT_Valid(_FirstEntity) || ck::Is_NOT_Valid(_SecondEntity))
        { return; }

        // BeginPlay (which writes the observation fragment) runs in a later processor
        // than OnConstructed — give it a frame.
        WaitOneFrame(n"DoVerify");
    }

    UFUNCTION()
    private void DoVerify(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        if (_FirstEntity.Has_Fragment(FCdoSharedGym_Observed) == false
            || _SecondEntity.Has_Fragment(FCdoSharedGym_Observed) == false)
        {
            FinishFailure("Observed fragment missing — BeginPlay did not run (or did not record) for one of the spawned entities");
            return;
        }

        const auto& FirstObserved = _FirstEntity.Get_Fragment(FCdoSharedGym_Observed);
        const auto& SecondObserved = _SecondEntity.Get_Fragment(FCdoSharedGym_Observed);

        // --- Per-entity spawn params observed from inside BeginPlay -----------------
        Assert_True(FirstObserved.HadValidSpawnParams,
            "First entity's BeginPlay should observe valid SpawnParams");
        Assert_True(SecondObserved.HadValidSpawnParams,
            "Second entity's BeginPlay should observe valid SpawnParams");

        Assert_Equals_Int(FirstObserved.ObservedInt, _FirstInt,
            "First entity should observe ITS OWN PayloadInt (not the second spawn's)");
        Assert_True(FirstObserved.ObservedName == _FirstName,
            f"First entity should observe ITS OWN PayloadName (expected '{_FirstName}', got '{FirstObserved.ObservedName}')");

        Assert_Equals_Int(SecondObserved.ObservedInt, _SecondInt,
            "Second entity should observe ITS OWN PayloadInt");
        Assert_True(SecondObserved.ObservedName == _SecondName,
            f"Second entity should observe ITS OWN PayloadName (expected '{_SecondName}', got '{SecondObserved.ObservedName}')");

        // --- Per-callback script-entity identity ------------------------------------
        Assert_True(FirstObserved.ObservedScriptEntity == _FirstEntity,
            "First entity's BeginPlay should see DoGet_ScriptEntity() == itself (CDO back-pointer re-stamped per callback)");
        Assert_True(SecondObserved.ObservedScriptEntity == _SecondEntity,
            "Second entity's BeginPlay should see DoGet_ScriptEntity() == itself");

        // --- Utils read-back of the stored params ------------------------------------
        auto FirstStored = utils_entity_script::Get_SpawnParams(_FirstEntity);
        Assert_True(FirstStored.IsValid(),
            "Get_SpawnParams should return valid params for the first entity");
        if (FirstStored.IsValid())
        {
            auto FirstStoredParams = FirstStored.Get(FCdoSharedGym_SpawnParams);
            Assert_Equals_Int(FirstStoredParams.PayloadInt, _FirstInt,
                "Stored SpawnParams on the first entity should hold its own payload");
        }

        auto SecondStored = utils_entity_script::Get_SpawnParams(_SecondEntity);
        Assert_True(SecondStored.IsValid(),
            "Get_SpawnParams should return valid params for the second entity");
        if (SecondStored.IsValid())
        {
            auto SecondStoredParams = SecondStored.Get(FCdoSharedGym_SpawnParams);
            Assert_Equals_Int(SecondStoredParams.PayloadInt, _SecondInt,
                "Stored SpawnParams on the second entity should hold its own payload");
        }

        FinishSuccess();
    }
}
