// Auto-generated AutoTest actor wrappers — DO NOT EDIT.
// Regenerated on editor startup and after every AngelScript recompile.
//
// =====================================================================
// WHY DO THESE WRAPPERS LOOK SO WEIRD?
// =====================================================================
//
// You'd normally write a wrapper like this — short, type-safe:
//
//   class A<TestName>_Actor : ACk_AutoTestRunner
//   {
//       default _TestEntityScriptClass = U<TestName>;   // compile-time ref
//   }
//
// We don't, because that compile-time reference creates a deadlock when
// the entity-script .as file is deleted while the editor is running:
//
//   1. AS file watcher misses the delete for one cycle.
//   2. Generator emits a wrapper still referencing U<TestName>.
//   3. AS recompiles the generated file → fails because U<TestName> is
//      gone → PostCompile stops firing → generator can't fix the file
//      it just emitted. Editor stays broken until manual recovery.
//
// The runtime-resolved form below sidesteps the deadlock: the entity-
// script class is referenced as a string literal inside an override of
// Get_TestEntityScriptClass, looked up at runtime via FSoftClassPath.
// AS doesn't resolve the string at compile time, so the wrapper compiles
// regardless of whether U<TestName> exists. If it's gone, the lookup
// returns null and the test reports a clear runtime failure; one sync
// pass later the wrapper is removed entirely. Self-healing.
//
// =====================================================================
// HAND-AUTHORED OPT-OUT
// =====================================================================
//
// For tests that need a custom _TimeoutSeconds or any other wrapper
// customization, hand-author your own A<TestName>_Actor class anywhere
// OUTSIDE Script/Generated/ using the simpler compile-time form:
//
//   class A<TestName>_Actor : ACk_AutoTestRunner
//   {
//       default _TestEntityScriptClass = U<TestName>;
//       default _TimeoutSeconds = 2.0f;
//   }
//
// The generator detects hand-authored wrappers by class name + source
// path and skips emission for that test, leaving yours authoritative.
// (Hand-authored wrappers don't carry the deletion-race risk because
// deleting the .as file removes BOTH classes atomically — no stale
// generated file to get out of sync.)

class ACk_AutoTest_AStar_BasicSearch_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_AStar_BasicSearch");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_AStar_CostThreshold_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_AStar_CostThreshold");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_AStar_NoPath_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_AStar_NoPath");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Attribute_ByteBasic_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Attribute_ByteBasic");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Attribute_ByteModifierAdd_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Attribute_ByteModifierAdd");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Attribute_FloatBasic_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Attribute_FloatBasic");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Attribute_FloatClamping_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Attribute_FloatClamping");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Attribute_FloatIncrement_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Attribute_FloatIncrement");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Attribute_FloatMinMaxComponents_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Attribute_FloatMinMaxComponents");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Attribute_FloatModifierAdd_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Attribute_FloatModifierAdd");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Attribute_FloatModifierRemove_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Attribute_FloatModifierRemove");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Attribute_FloatModifierStacking_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Attribute_FloatModifierStacking");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Attribute_FloatOverflow_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Attribute_FloatOverflow");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Attribute_FloatRefill_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Attribute_FloatRefill");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Attribute_IntegerBasic_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Attribute_IntegerBasic");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Attribute_IntegerClamping_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Attribute_IntegerClamping");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Attribute_IntegerModifierAdd_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Attribute_IntegerModifierAdd");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Attribute_IntegerModifierRemove_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Attribute_IntegerModifierRemove");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Attribute_IntegerModifierStacking_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Attribute_IntegerModifierStacking");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Attribute_IntegerMultiplyComposes_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Attribute_IntegerMultiplyComposes");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Attribute_IntegerOverflow_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Attribute_IntegerOverflow");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Attribute_OnClampedPayloadDirection_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Attribute_OnClampedPayloadDirection");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Attribute_PreClampAsymmetry_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Attribute_PreClampAsymmetry");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Attribute_RevokeModifierDuringValueChanged_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Attribute_RevokeModifierDuringValueChanged");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Chrono_TickAndComplete_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Chrono_TickAndComplete");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_CrossCutting_DestroyOwner_DuringHandleRequests_NoCrash_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_CrossCutting_DestroyOwner_DuringHandleRequests_NoCrash");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_CrossCutting_DestroyOwner_DuringSignalBroadcast_DelegatesSkipped_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_CrossCutting_DestroyOwner_DuringSignalBroadcast_DelegatesSkipped");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_CrossCutting_EndPlay_ReleasesRecordEntries_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_CrossCutting_EndPlay_ReleasesRecordEntries");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_CrossCutting_SameFrame_AttributeOverrideCoalesces_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_CrossCutting_SameFrame_AttributeOverrideCoalesces");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_CrossCutting_SameFrame_TagSetAddAndRemoveCancel_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_CrossCutting_SameFrame_TagSetAddAndRemoveCancel");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_CrossCutting_SameFrame_TransformSetLocationCoalesces_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_CrossCutting_SameFrame_TransformSetLocationCoalesces");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_EntityLifecycle_BatchDestroy_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_EntityLifecycle_BatchDestroy");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_EntityLifecycle_CircularContextOwnership_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 2.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_EntityLifecycle_CircularContextOwnership");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_EntityLifecycle_ContextOwnerGrandparent_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_EntityLifecycle_ContextOwnerGrandparent");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_EntityLifecycle_ContextOwnerOverride_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_EntityLifecycle_ContextOwnerOverride");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_EntityLifecycle_DeferredSetupCompleteCallbacks_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_EntityLifecycle_DeferredSetupCompleteCallbacks");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_EntityLifecycle_DeferredSetupState_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_EntityLifecycle_DeferredSetupState");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_EntityLifecycle_DependentsCountMutations_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_EntityLifecycle_DependentsCountMutations");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_EntityLifecycle_HandleAndEntity_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_EntityLifecycle_HandleAndEntity");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_EntityLifecycle_IsTransientEntityVsContext_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_EntityLifecycle_IsTransientEntityVsContext");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_EntityLifecycle_OnBeginDestroy_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_EntityLifecycle_OnBeginDestroy");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_EntityLifecycle_OwnershipTree_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_EntityLifecycle_OwnershipTree");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_EntityLifecycle_ScriptCastQueries_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_EntityLifecycle_ScriptCastQueries");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_EntityLifecycle_TagAddRemove_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_EntityLifecycle_TagAddRemove");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_EntityScript_BasicSpawn_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_EntityScript_BasicSpawn");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_EntityScript_SpawnedEntityHasTag_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_EntityScript_SpawnedEntityHasTag");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_EntityScript_SpawnedEntityIsDependent_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_EntityScript_SpawnedEntityIsDependent");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_EntityScript_SpawnParamsRoundTrip_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_EntityScript_SpawnParamsRoundTrip");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Eqs_BasicQuery_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Eqs_BasicQuery");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Eqs_Cancel_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Eqs_Cancel");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Eqs_Immediate_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Eqs_Immediate");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Eqs_NavProjection_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Eqs_NavProjection");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Eqs_OnCircle_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Eqs_OnCircle");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Eqs_RandomRunMode_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Eqs_RandomRunMode");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Eqs_VolumeCheck_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Eqs_VolumeCheck");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Goap_BasicPlan_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Goap_BasicPlan");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Goap_DependencyChain_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Goap_DependencyChain");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Grid_AddAndDimensions_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Grid_AddAndDimensions");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Grid_CellCoordinatesAreUnique_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Grid_CellCoordinatesAreUnique");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Grid_CellsAreEnabledByDefault_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Grid_CellsAreEnabledByDefault");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Grid_DisabledCellRejectsPlacement_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Grid_DisabledCellRejectsPlacement");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Grid_DisjointIntersection_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Grid_DisjointIntersection");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Grid_IntersectionCardinality_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Grid_IntersectionCardinality");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Grid_OverlappingIntersection_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Grid_OverlappingIntersection");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Grid_RotationLocalCoordMapping_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Grid_RotationLocalCoordMapping");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Interaction_CanInteractWithComplexValidation_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Interaction_CanInteractWithComplexValidation");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Interaction_ConcurrentInteractionsSameTarget_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Interaction_ConcurrentInteractionsSameTarget");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Interaction_Instant_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Interaction_Instant");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Interaction_ManualFail_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Interaction_ManualFail");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Interaction_ManualSuccess_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Interaction_ManualSuccess");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Interaction_OnNewInteractionPayload_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Interaction_OnNewInteractionPayload");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Interaction_Timed_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Interaction_Timed");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Interaction_ValidationAllows_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Interaction_ValidationAllows");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Interaction_ValidationChannelMismatch_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Interaction_ValidationChannelMismatch");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Interaction_ValidationCustomFails_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Interaction_ValidationCustomFails");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Interaction_ValidationTargetDisabled_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Interaction_ValidationTargetDisabled");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Inventory_CustomCanAcceptItem_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Inventory_CustomCanAcceptItem");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Inventory_DataOnly_AddItem_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Inventory_DataOnly_AddItem");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Inventory_DataOnly_BoundedReject_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Inventory_DataOnly_BoundedReject");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Inventory_DataOnly_OverrideBounds_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Inventory_DataOnly_OverrideBounds");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Inventory_DataOnly_RemoveItem_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Inventory_DataOnly_RemoveItem");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Inventory_DataOnly_Unbounded_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Inventory_DataOnly_Unbounded");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Inventory_Spatial_AddByDefinition_NoSpace_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 4.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Inventory_Spatial_AddByDefinition_NoSpace");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Inventory_SpatialPlacementRejection_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 4.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Inventory_SpatialPlacementRejection");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Inventory_StackableTrait_SplitStack_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Inventory_StackableTrait_SplitStack");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Inventory_StackableTrait_StackItems_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Inventory_StackableTrait_StackItems");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Inventory_TagsTrait_AddTag_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Inventory_TagsTrait_AddTag");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Inventory_TagsTrait_RemoveTag_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Inventory_TagsTrait_RemoveTag");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Inventory_TransferItem_BaseHandleFacade_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 4.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Inventory_TransferItem_BaseHandleFacade");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Inventory_TransferItemPayload_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 4.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Inventory_TransferItemPayload");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Label_AddAndQuery_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Label_AddAndQuery");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Label_HierarchicalMatching_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Label_HierarchicalMatching");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Messaging_BasicBroadcast_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Messaging_BasicBroadcast");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Messaging_BindingPolicyInFlight_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Messaging_BindingPolicyInFlight");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Messaging_MultiListener_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Messaging_MultiListener");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Messaging_MultipleTypes_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Messaging_MultipleTypes");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Messaging_PostFireUnbind_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Messaging_PostFireUnbind");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Messaging_Unbind_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Messaging_Unbind");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Registry_AllocatorStress_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Registry_AllocatorStress");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Registry_HandleCopyDestroy_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Registry_HandleCopyDestroy");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Registry_HandleInFragmentLifecycle_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Registry_HandleInFragmentLifecycle");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_SceneNode_ActorAttachedToActor_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_SceneNode_ActorAttachedToActor");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_SceneNode_BareChildOfBareParent_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_SceneNode_BareChildOfBareParent");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_SceneNode_DeepHierarchy_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_SceneNode_DeepHierarchy");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_SceneNode_MeshSocketAnchor_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_SceneNode_MeshSocketAnchor");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_SceneNode_MultipleChildren_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_SceneNode_MultipleChildren");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_SceneNode_NonUniformScalePropagation_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_SceneNode_NonUniformScalePropagation");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_SceneNode_OffsetUpdates_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_SceneNode_OffsetUpdates");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_SceneNode_ParentDestroyCascade_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_SceneNode_ParentDestroyCascade");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_StateMachine_BasicTransition_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_StateMachine_BasicTransition");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_StateMachine_DivergenceFirstBranch_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 7.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_StateMachine_DivergenceFirstBranch");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_StateMachine_DivergenceFirstBranchTimed_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_StateMachine_DivergenceFirstBranchTimed");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_StateMachine_EventDrivenMultiCondition_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 2.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_StateMachine_EventDrivenMultiCondition");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_StateMachine_HierarchicalFirstTransition_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_StateMachine_HierarchicalFirstTransition");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_StateMachine_NegatedEventDrivenCondition_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 2.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_StateMachine_NegatedEventDrivenCondition");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_StateMachine_RacingEventDrivenTransitions_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 2.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_StateMachine_RacingEventDrivenTransitions");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_StateMachine_TransitionExitBeforeEnter_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_StateMachine_TransitionExitBeforeEnter");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_StateMachine_TransitionOrdering_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_StateMachine_TransitionOrdering");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_TagSet_AddInitialAndQuery_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_TagSet_AddInitialAndQuery");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_TagSet_OnTagsChangedSignal_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_TagSet_OnTagsChangedSignal");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_TagSet_RequestAddRemove_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_TagSet_RequestAddRemove");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Timer_BasicCompletion_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Timer_BasicCompletion");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Timer_ChangeCountDirection_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Timer_ChangeCountDirection");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Timer_CountdownCompletion_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Timer_CountdownCompletion");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Timer_MultipleConcurrent_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Timer_MultipleConcurrent");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Timer_PauseHaltsElapsed_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Timer_PauseHaltsElapsed");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Timer_RequestComplete_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Timer_RequestComplete");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Timer_RequestConsume_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Timer_RequestConsume");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Timer_ResetMidFlight_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Timer_ResetMidFlight");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Timer_ResetOnDone_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Timer_ResetOnDone");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Timer_ResumeAfterPause_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Timer_ResumeAfterPause");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Timer_StopOnDone_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Timer_StopOnDone");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Transform_AddInitial_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Transform_AddInitial");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Transform_AddLocationOffset_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Transform_AddLocationOffset");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Transform_OnUpdateFires_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Transform_OnUpdateFires");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Transform_SetLocation_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Transform_SetLocation");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Transform_SetRotation_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Transform_SetRotation");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Transform_SetScale_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Transform_SetScale");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Tween_FloatCompletion_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Tween_FloatCompletion");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Tween_FloatUpdateCallback_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Tween_FloatUpdateCallback");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Tween_LinearColorCompletion_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Tween_LinearColorCompletion");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Tween_LoopRestart_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Tween_LoopRestart");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Tween_RotatorCompletion_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Tween_RotatorCompletion");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Tween_SelfDestructOnComplete_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Tween_SelfDestructOnComplete");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Tween_VectorCompletion_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Tween_VectorCompletion");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Tween_YoyoLoop_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Tween_YoyoLoop");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

