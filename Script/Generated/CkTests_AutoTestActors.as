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

class ACk_AutoTest_Acceleration_Add_CreatesFeature_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 4.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Acceleration_Add_CreatesFeature");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Actor_AddActorComponent_FiresOnComponentAdded_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 4.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Actor_AddActorComponent_FiresOnComponentAdded");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Actor_AddActorComponent_IsUniqueFalse_AllowsDuplicate_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Actor_AddActorComponent_IsUniqueFalse_AllowsDuplicate");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Actor_AddActorComponent_Tags_PropagateToComponent_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 4.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Actor_AddActorComponent_Tags_PropagateToComponent");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Actor_OnSpawnedDelegate_BindsToASFunction_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 2.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Actor_OnSpawnedDelegate_BindsToASFunction");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Actor_RemoveActorComponent_FiresOnComponentRemoved_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Actor_RemoveActorComponent_FiresOnComponentRemoved");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Actor_SpawnActor_FiresOnActorSpawned_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 4.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Actor_SpawnActor_FiresOnActorSpawned");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Actor_SpawnActor_SpawnTransform_AppliedToSpawnedActor_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 4.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Actor_SpawnActor_SpawnTransform_AppliedToSpawnedActor");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Actor_SpawnTransform_SetterWritesValue_Diagnostic_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 2.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Actor_SpawnTransform_SetterWritesValue_Diagnostic");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_ActorRelay_ChannelEntityCount_OnInvalidResult_IsZero_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 2.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_ActorRelay_ChannelEntityCount_OnInvalidResult_IsZero");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_ActorRelay_DefaultChannelResult_IsInvalid_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 2.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_ActorRelay_DefaultChannelResult_IsInvalid");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Aggro_AddHappyPath_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Aggro_AddHappyPath");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Aggro_ForEachExclusionPolicy_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Aggro_ForEachExclusionPolicy");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Aggro_GetBestAggroSingle_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Aggro_GetBestAggroSingle");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Aggro_GetTarget_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Aggro_GetTarget");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Aggro_OwnerAddHappyPath_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Aggro_OwnerAddHappyPath");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Aggro_RequestIncludeRestores_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Aggro_RequestIncludeRestores");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Aggro_TryGetAggroByTargetFound_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Aggro_TryGetAggroByTargetFound");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Aggro_TryGetAggroByTargetNotFound_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Aggro_TryGetAggroByTargetNotFound");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_AnimAsset_Add_CreatesValidHandle_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 4.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_AnimAsset_Add_CreatesValidHandle");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

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

class ACk_AutoTest_Attribute_ByteMultiplyComposes_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Attribute_ByteMultiplyComposes");
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

class ACk_AutoTest_Attribute_FloatOnClamped_NoFireWhenInBand_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 4.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Attribute_FloatOnClamped_NoFireWhenInBand");
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

class ACk_AutoTest_Attribute_FloatRefill_StopsAtMax_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Attribute_FloatRefill_StopsAtMax");
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

class ACk_AutoTest_Attribute_MayRequireReplicationToggle_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Attribute_MayRequireReplicationToggle");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Attribute_NotRevocable_AddCoalesces_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Attribute_NotRevocable_AddCoalesces");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Attribute_NotRevocable_OverrideReplaces_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Attribute_NotRevocable_OverrideReplaces");
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

class ACk_AutoTest_Attribute_Override_ChangesDeltaInPlace_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Attribute_Override_ChangesDeltaInPlace");
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

class ACk_AutoTest_Attribute_Request_ClearAllModifiers_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Attribute_Request_ClearAllModifiers");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Attribute_Revocable_PerCallHandleUniqueness_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Attribute_Revocable_PerCallHandleUniqueness");
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

class ACk_AutoTest_Attribute_SameFrameMutationsCoalesce_OneSignal_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Attribute_SameFrameMutationsCoalesce_OneSignal");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Attribute_VectorPerComponentClamp_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 2.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Attribute_VectorPerComponentClamp");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_CameraShake_Add_CreatesEntry_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 4.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_CameraShake_Add_CreatesEntry");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Chrono_GetTimeElapsed_Normalized_Linear_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Chrono_GetTimeElapsed_Normalized_Linear");
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

class ACk_AutoTest_Chrono_TickPastCompletion_ClampsAtDuration_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Chrono_TickPastCompletion_ClampsAtDuration");
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

class ACk_AutoTest_Cue_AfterOneFrame_DestroyedQuickly_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 4.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Cue_AfterOneFrame_DestroyedQuickly");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Cue_Persistent_StaysAlive_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 4.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Cue_Persistent_StaysAlive");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Cue_Timed_DestroyedAfterDuration_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 4.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Cue_Timed_DestroyedAfterDuration");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_DynamicFragment_Add_HasReturnsTrue_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 2.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_DynamicFragment_Add_HasReturnsTrue");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_DynamicFragment_AddGet_RoundTripsValue_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 2.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_DynamicFragment_AddGet_RoundTripsValue");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_DynamicFragment_RequestRemove_ClearsHas_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 2.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_DynamicFragment_RequestRemove_ClearsHas");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_DynamicFragment_TryRemove_OnAbsent_ReturnsFailed_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 2.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_DynamicFragment_TryRemove_OnAbsent_ReturnsFailed");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_EntityCollection_AddHappyPath_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_EntityCollection_AddHappyPath");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_EntityCollection_AddMultipleAddsAll_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_EntityCollection_AddMultipleAddsAll");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_EntityCollection_RequestAddEntitiesBatch_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_EntityCollection_RequestAddEntitiesBatch");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_EntityCollection_RequestAddSingleEntity_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_EntityCollection_RequestAddSingleEntity");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_EntityCollection_RequestRemoveSingleEntity_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_EntityCollection_RequestRemoveSingleEntity");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_EntityCollection_TryGetAbsentInvalid_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_EntityCollection_TryGetAbsentInvalid");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_EntityExtension_AddHappyPath_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_EntityExtension_AddHappyPath");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_EntityExtension_DistinctOwnersIsolated_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_EntityExtension_DistinctOwnersIsolated");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_EntityExtension_ForEachListsAll_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_EntityExtension_ForEachListsAll");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_EntityExtension_RemoveHappyPath_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_EntityExtension_RemoveHappyPath");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_EntityExtension_RemoveLeavesOthers_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_EntityExtension_RemoveLeavesOthers");
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

class ACk_AutoTest_EntityTag_AddEmptyName_Rejected_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_EntityTag_AddEmptyName_Rejected");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_EntityTag_AddFNameHappyPath_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_EntityTag_AddFNameHappyPath");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_EntityTag_AddGameplayTagHappyPath_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_EntityTag_AddGameplayTagHappyPath");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_EntityTag_AddIsCounted_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_EntityTag_AddIsCounted");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_EntityTag_BindRelevantTagsFilter_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_EntityTag_BindRelevantTagsFilter");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_EntityTag_ForEachEntityFindsByParent_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_EntityTag_ForEachEntityFindsByParent");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_EntityTag_FragmentCleanupOnEmpty_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_EntityTag_FragmentCleanupOnEmpty");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_EntityTag_GameplayTagParentFlatten_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_EntityTag_GameplayTagParentFlatten");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_EntityTag_GameplayTagParentUncountsCleanly_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_EntityTag_GameplayTagParentUncountsCleanly");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_EntityTag_GameplayTagSignalFiresOnPresenceFlip_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_EntityTag_GameplayTagSignalFiresOnPresenceFlip");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_EntityTag_GetAllTagsAsContainerIsExplicit_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_EntityTag_GetAllTagsAsContainerIsExplicit");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_EntityTag_HasAbsentTagFalse_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_EntityTag_HasAbsentTagFalse");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_EntityTag_RemoveGameplayTagRejectsPartial_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_EntityTag_RemoveGameplayTagRejectsPartial");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_EntityTag_RequestTryRemoveAbsentFailed_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_EntityTag_RequestTryRemoveAbsentFailed");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_EntityTag_RequestTryRemoveHappyPath_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_EntityTag_RequestTryRemoveHappyPath");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_EntityTag_SignalFiresOnPresenceFlip_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_EntityTag_SignalFiresOnPresenceFlip");
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

class ACk_AutoTest_GeometryCollectionOwner_Add_CreatesFeature_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 4.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_GeometryCollectionOwner_Add_CreatesFeature");
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

class ACk_AutoTest_Interaction_CancelAllInteractions_FinishesAsFailed_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 4.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Interaction_CancelAllInteractions_FinishesAsFailed");
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

class ACk_AutoTest_Interaction_Get_CurrentInteractions_DuringInFlight_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 4.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Interaction_Get_CurrentInteractions_DuringInFlight");
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

class ACk_AutoTest_Interaction_MultipleInteractors_SingleInteractionRejectsSecond_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 4.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Interaction_MultipleInteractors_SingleInteractionRejectsSecond");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Interaction_OnInteractionFinished_PayloadShape_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Interaction_OnInteractionFinished_PayloadShape");
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

class ACk_AutoTest_Interaction_ResetAfterCompletion_Reusable_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 4.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Interaction_ResetAfterCompletion_Reusable");
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

class ACk_AutoTest_Interaction_TimedInterruptedByCancel_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 4.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Interaction_TimedInterruptedByCancel");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Interaction_TryGet_Interaction_ReturnsActive_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 4.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Interaction_TryGet_Interaction_ReturnsActive");
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

class ACk_AutoTest_Inventory_AddItem_DuplicateInsertRejected_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 4.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Inventory_AddItem_DuplicateInsertRejected");
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

class ACk_AutoTest_Inventory_ResolveBestTransferTarget_NoCandidatePasses_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Inventory_ResolveBestTransferTarget_NoCandidatePasses");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Inventory_Sort_DataOnly_BasicOrder_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Inventory_Sort_DataOnly_BasicOrder");
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

class ACk_AutoTest_Inventory_Spatial_RelocateItem_BlockedByOther_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Inventory_Spatial_RelocateItem_BlockedByOther");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Inventory_Spatial_RelocateItem_RotationChange_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Inventory_Spatial_RelocateItem_RotationChange");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Inventory_Spatial_RelocateItem_Success_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Inventory_Spatial_RelocateItem_Success");
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

class ACk_AutoTest_Inventory_Transfer_Spatial_To_Spatial_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 4.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Inventory_Transfer_Spatial_To_Spatial");
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

class ACk_AutoTest_Inventory_TryGet_Inventory_ByName_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Inventory_TryGet_Inventory_ByName");
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

class ACk_AutoTest_Label_AddIsSetOnce_RejectsSecondAdd_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Label_AddIsSetOnce_RejectsSecondAdd");
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

class ACk_AutoTest_Label_MatchesAny_FromContainer_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Label_MatchesAny_FromContainer");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Marker_Add_Box_CreatesValidHandle_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 4.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Marker_Add_Box_CreatesValidHandle");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Marker_Add_Capsule_CreatesValidHandle_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 4.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Marker_Add_Capsule_CreatesValidHandle");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Marker_Add_Sphere_CreatesValidHandle_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 4.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Marker_Add_Sphere_CreatesValidHandle");
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

class ACk_AutoTest_ObjectiveOwner_Add_CreatesFeature_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_ObjectiveOwner_Add_CreatesFeature");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Pmg_DrawFilledBox_ReturnsValidHandle_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Pmg_DrawFilledBox_ReturnsValidHandle");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Pmg_DrawFilledSphere_ReturnsValidHandle_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Pmg_DrawFilledSphere_ReturnsValidHandle");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Probe_Add_Box_CreatesProbeEntity_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Probe_Add_Box_CreatesProbeEntity");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Probe_Add_Sphere_CreatesProbeEntity_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Probe_Add_Sphere_CreatesProbeEntity");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Probe_Get_ResponsePolicy_ReturnsConfigured_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Probe_Get_ResponsePolicy_ReturnsConfigured");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Probe_GetName_ReturnsConfiguredTag_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Probe_GetName_ReturnsConfiguredTag");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Probe_Request_EnableDisable_StateFlips_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 4.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Probe_Request_EnableDisable_StateFlips");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Projectile_Add_AttachesVelocityAndAcceleration_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 4.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Projectile_Add_AttachesVelocityAndAcceleration");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_RaySense_Add_CreatesEntity_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_RaySense_Add_CreatesEntity");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Record_AddHasFeature_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Record_AddHasFeature");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Record_ConnectDisconnectRoundTrip_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Record_ConnectDisconnectRoundTrip");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Record_DestroyEntryPrunesFromRecord_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Record_DestroyEntryPrunesFromRecord");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Record_GetValidEntryByTagFindsLabeled_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Record_GetValidEntryByTagFindsLabeled");
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

class ACk_AutoTest_Relationship_AttitudeDifferentTeamsIsHostile_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Relationship_AttitudeDifferentTeamsIsHostile");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Relationship_AttitudeNoTeamIsNeutral_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Relationship_AttitudeNoTeamIsNeutral");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Relationship_AttitudeOneHasNoTeamIsNeutral_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Relationship_AttitudeOneHasNoTeamIsNeutral");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Relationship_AttitudeOwnershipChainHostile_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Relationship_AttitudeOwnershipChainHostile");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Relationship_AttitudeSameTeamIsFriendly_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Relationship_AttitudeSameTeamIsFriendly");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Relationship_AttitudeSelfIsFriendly_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Relationship_AttitudeSelfIsFriendly");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Relationship_Team_AddDefaultUnassigned_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Relationship_Team_AddDefaultUnassigned");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Relationship_Team_AddHappyPath_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Relationship_Team_AddHappyPath");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Relationship_Team_AssignChanges_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Relationship_Team_AssignChanges");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Relationship_Team_AssignShiftsIsAssignedTo_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Relationship_Team_AssignShiftsIsAssignedTo");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Relationship_Team_GetIsAssignedTo_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Relationship_Team_GetIsAssignedTo");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Relationship_Team_GetIsSame_False_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Relationship_Team_GetIsSame_False");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Relationship_Team_GetIsSame_True_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Relationship_Team_GetIsSame_True");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Relationship_Team_HasFalseBeforeAdd_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Relationship_Team_HasFalseBeforeAdd");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Relationship_Team_TryGetInOwnershipChainFromOwner_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Relationship_Team_TryGetInOwnershipChainFromOwner");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Relationship_Team_TryGetInOwnershipChainNoTeam_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Relationship_Team_TryGetInOwnershipChainNoTeam");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Relationship_Team_UnassignSetsUnassigned_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Relationship_Team_UnassignSetsUnassigned");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_RenderStatus_Add_CreatesFeature_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_RenderStatus_Add_CreatesFeature");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Resolver_Source_AddHappyPath_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Resolver_Source_AddHappyPath");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Resolver_Source_CreateHappyPath_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Resolver_Source_CreateHappyPath");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Resolver_Source_CreateTransientHappyPath_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Resolver_Source_CreateTransientHappyPath");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Resolver_Source_ForEachDataBundleEmpty_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Resolver_Source_ForEachDataBundleEmpty");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Resolver_Source_HasFalseBeforeAdd_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Resolver_Source_HasFalseBeforeAdd");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Resolver_Target_AddHappyPath_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Resolver_Target_AddHappyPath");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Resolver_Target_CreateHappyPath_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Resolver_Target_CreateHappyPath");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Resolver_Target_CreateTransientHappyPath_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Resolver_Target_CreateTransientHappyPath");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Resolver_Target_ForEachDataBundleEmpty_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Resolver_Target_ForEachDataBundleEmpty");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Resolver_Target_HasFalseBeforeAdd_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Resolver_Target_HasFalseBeforeAdd");
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

class ACk_AutoTest_SceneNodeTween_Depth0_LeafMatchesExpected_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_SceneNodeTween_Depth0_LeafMatchesExpected");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_SceneNodeTween_Depth1_LeafMatchesExpected_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_SceneNodeTween_Depth1_LeafMatchesExpected");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_SceneNodeTween_Depth4_LeafMatchesExpected_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_SceneNodeTween_Depth4_LeafMatchesExpected");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_SceneNodeTween_NonUniformScalePropagatesToLeaf_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_SceneNodeTween_NonUniformScalePropagatesToLeaf");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_SceneNodeTween_RootDestroyDuringTween_ChildrenCleanedUp_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 4.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_SceneNodeTween_RootDestroyDuringTween_ChildrenCleanedUp");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_SceneNodeTween_RotationTween_OrientsLeafCorrectly_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_SceneNodeTween_RotationTween_OrientsLeafCorrectly");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_SceneNodeTween_TweenCompletes_LeafLandsAtTarget_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_SceneNodeTween_TweenCompletes_LeafLandsAtTarget");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_SceneNodeTween_TweenLoopYoyo_LeafTracksBoth_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 4.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_SceneNodeTween_TweenLoopYoyo_LeafTracksBoth");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Sfx_Add_CreatesValidHandle_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 2.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Sfx_Add_CreatesValidHandle");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Shape_Box_Add_RoundTripsHalfExtents_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Shape_Box_Add_RoundTripsHalfExtents");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Shape_Capsule_Add_RoundTripsDimensions_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Shape_Capsule_Add_RoundTripsDimensions");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Shape_Sphere_Add_RoundTripsRadius_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Shape_Sphere_Add_RoundTripsRadius");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_StateMachine_AddOverrideState_ReplacesBaseState_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_StateMachine_AddOverrideState_ReplacesBaseState");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_StateMachine_AlwaysTrueCondition_PassesImmediately_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_StateMachine_AlwaysTrueCondition_PassesImmediately");
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

class ACk_AutoTest_StateMachine_NoTransitionAvailable_StaysInState_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_StateMachine_NoTransitionAvailable_StaysInState");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_StateMachine_OnStateChanged_PayloadHasOldAndNew_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 6.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_StateMachine_OnStateChanged_PayloadHasOldAndNew");
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

class ACk_AutoTest_StateMachine_Stop_FiresOnStopped_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_StateMachine_Stop_FiresOnStopped");
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

class ACk_AutoTest_Substep_Add_CreatesFeature_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Substep_Add_CreatesFeature");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_TagSet_AddDuplicate_NoSignalFire_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 4.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_TagSet_AddDuplicate_NoSignalFire");
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

class ACk_AutoTest_TagSet_ClearAll_FiresSignalOnce_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 2.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_TagSet_ClearAll_FiresSignalOnce");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_TagSet_HasTag_HasAny_HasAll_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_TagSet_HasTag_HasAny_HasAll");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_TagSet_MultipleConcurrent_SignalsIndependent_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 2.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_TagSet_MultipleConcurrent_SignalsIndependent");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_TagSet_OnTagsChanged_DualPayload_SameTick_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 2.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_TagSet_OnTagsChanged_DualPayload_SameTick");
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

class ACk_AutoTest_TagSet_RemoveAbsent_NoSignalFire_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 4.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_TagSet_RemoveAbsent_NoSignalFire");
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

class ACk_AutoTest_Targeting_CreateFromLocation_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Targeting_CreateFromLocation");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Targeting_CreateFromLocationAndRotation_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Targeting_CreateFromLocationAndRotation");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Targeting_CreateHappyPath_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Targeting_CreateHappyPath");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Targeting_CreateTransientFromLocation_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Targeting_CreateTransientFromLocation");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Targeting_CreateTransientFromLocationAndRotation_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Targeting_CreateTransientFromLocationAndRotation");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Targeting_CreateTransientHappyPath_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Targeting_CreateTransientHappyPath");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Targeting_LifetimeAfterOneFrameDestroysEntity_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Targeting_LifetimeAfterOneFrameDestroysEntity");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Timer_AddOrReplace_ReplacesExisting_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 2.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Timer_AddOrReplace_ReplacesExisting");
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

class ACk_AutoTest_Timer_ForEach_Timer_VisitsAll_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 2.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Timer_ForEach_Timer_VisitsAll");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Timer_Get_CurrentTimerValue_DuringPause_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 4.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Timer_Get_CurrentTimerValue_DuringPause");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Timer_Jump_Backward_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 4.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Timer_Jump_Backward");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Timer_Jump_Forward_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 4.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Timer_Jump_Forward");
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

class ACk_AutoTest_Timer_OnDepleted_FiresOnConsume_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 4.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Timer_OnDepleted_FiresOnConsume");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Timer_OnUpdate_FiresEveryTickWhileActive_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 4.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Timer_OnUpdate_FiresEveryTickWhileActive");
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

class ACk_AutoTest_Timer_ReverseDirection_MidFlight_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Timer_ReverseDirection_MidFlight");
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

class ACk_AutoTest_Timer_TryGet_Timer_ByName_AmongMultiple_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Timer_TryGet_Timer_ByName_AmongMultiple");
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

class ACk_AutoTest_Transform_ForceRefreshRebroadcasts_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Transform_ForceRefreshRebroadcasts");
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

class ACk_AutoTest_Transform_SetLocationAndRotationAtomic_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Transform_SetLocationAndRotationAtomic");
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

class ACk_AutoTest_TransformInterpolation_LocationLerps_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_TransformInterpolation_LocationLerps");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Tween_CompletionBehavior_KeepEntity_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 4.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Tween_CompletionBehavior_KeepEntity");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Tween_EasingCurve_OutCubic_VsLinear_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 4.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Tween_EasingCurve_OutCubic_VsLinear");
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

class ACk_AutoTest_Tween_LoopCount_Finite_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 4.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Tween_LoopCount_Finite");
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

class ACk_AutoTest_UnrealComponent_AddHappyPath_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_UnrealComponent_AddHappyPath");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_UnrealComponent_GetAllComponentsListsAdded_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_UnrealComponent_GetAllComponentsListsAdded");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_UnrealComponent_GetAllHandlesListsAdded_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_UnrealComponent_GetAllHandlesListsAdded");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_UnrealComponent_GetOwningEntity_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_UnrealComponent_GetOwningEntity");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_UnrealComponent_RequestRemoveAfterFrame_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_UnrealComponent_RequestRemoveAfterFrame");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_UnrealComponent_TryGetHandleByTypeFound_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_UnrealComponent_TryGetHandleByTypeFound");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_UnrealComponent_TryGetHandleByTypeNotFound_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_UnrealComponent_TryGetHandleByTypeNotFound");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_UnrealComponent_TryGetOwningHandleFromComponent_Actor : ACk_AutoTestRunner
{
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_UnrealComponent_TryGetOwningHandleFromComponent");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Variables_Bool_SetGetRoundTrip_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Variables_Bool_SetGetRoundTrip");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Variables_Float_SetGetRoundTrip_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Variables_Float_SetGetRoundTrip");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Variables_GameplayTag_SetGetRoundTrip_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Variables_GameplayTag_SetGetRoundTrip");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Variables_Int32_SetGetRoundTrip_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Variables_Int32_SetGetRoundTrip");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Variables_SetOverwritesPrior_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Variables_SetOverwritesPrior");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Variables_String_SetGetRoundTrip_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Variables_String_SetGetRoundTrip");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

class ACk_AutoTest_Variables_Vector_SetGetRoundTrip_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 3.0f;
    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_Variables_Vector_SetGetRoundTrip");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }
}

