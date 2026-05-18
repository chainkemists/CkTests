// Auto-generated EntityScript spawn-params — DO NOT EDIT.
// This file is regenerated on editor startup and after every AngelScript recompile.
//
// For each UCk_EntityScript_UE subclass, two declarations are emitted:
//   - FCk_MyEntityScript_SpawnParams  (file-scope USTRUCT, unique name — avoids the
//     `Params` name-collision across namespaces that trips the Unreal naming check)
//   - namespace UCk_MyEntityScript { FCk_MyEntityScript_SpawnParams Params() { ... } }
//     so callers can still write `UCk_MyEntityScript::Params()`.
//
// Properties are flattened across the hierarchy (AS has no struct inheritance). Non-
// trivial struct defaults outside the CkReflection_Utils allowlist are emitted without
// an initializer — set them on the instance before calling Request_SpawnEntity.

USTRUCT()
struct FCk_AdvancedAchievementCue_SpawnParams
{
    UPROPERTY()
    FTransform Transform = FTransform::Identity;

    FCk_AdvancedAchievementCue_SpawnParams(FTransform InTransform)
    {
        Transform = InTransform;
    }
}

namespace UCk_AdvancedAchievementCue
{
    FCk_AdvancedAchievementCue_SpawnParams Params()
    {
        return FCk_AdvancedAchievementCue_SpawnParams();
    }

    FCk_AdvancedAchievementCue_SpawnParams Params(FTransform InTransform)
    {
        return FCk_AdvancedAchievementCue_SpawnParams(InTransform);
    }
}

USTRUCT()
struct FCk_AdvancedConcurrencyTestCue_SpawnParams
{
    UPROPERTY()
    FTransform Transform = FTransform::Identity;

    FCk_AdvancedConcurrencyTestCue_SpawnParams(FTransform InTransform)
    {
        Transform = InTransform;
    }
}

namespace UCk_AdvancedConcurrencyTestCue
{
    FCk_AdvancedConcurrencyTestCue_SpawnParams Params()
    {
        return FCk_AdvancedConcurrencyTestCue_SpawnParams();
    }

    FCk_AdvancedConcurrencyTestCue_SpawnParams Params(FTransform InTransform)
    {
        return FCk_AdvancedConcurrencyTestCue_SpawnParams(InTransform);
    }
}

USTRUCT()
struct FCk_AdvancedInterfacePickupCue_SpawnParams
{
    UPROPERTY()
    FTransform Transform = FTransform::Identity;

    FCk_AdvancedInterfacePickupCue_SpawnParams(FTransform InTransform)
    {
        Transform = InTransform;
    }
}

namespace UCk_AdvancedInterfacePickupCue
{
    FCk_AdvancedInterfacePickupCue_SpawnParams Params()
    {
        return FCk_AdvancedInterfacePickupCue_SpawnParams();
    }

    FCk_AdvancedInterfacePickupCue_SpawnParams Params(FTransform InTransform)
    {
        return FCk_AdvancedInterfacePickupCue_SpawnParams(InTransform);
    }
}

USTRUCT()
struct FCk_AdvancedMusicDirectorCue_SpawnParams
{
    UPROPERTY()
    FTransform Transform = FTransform::Identity;

    FCk_AdvancedMusicDirectorCue_SpawnParams(FTransform InTransform)
    {
        Transform = InTransform;
    }
}

namespace UCk_AdvancedMusicDirectorCue
{
    FCk_AdvancedMusicDirectorCue_SpawnParams Params()
    {
        return FCk_AdvancedMusicDirectorCue_SpawnParams();
    }

    FCk_AdvancedMusicDirectorCue_SpawnParams Params(FTransform InTransform)
    {
        return FCk_AdvancedMusicDirectorCue_SpawnParams(InTransform);
    }
}

USTRUCT()
struct FCk_AutoTest_Aggro_AddHappyPath_SpawnParams
{
}

namespace UCk_AutoTest_Aggro_AddHappyPath
{
    FCk_AutoTest_Aggro_AddHappyPath_SpawnParams Params()
    {
        return FCk_AutoTest_Aggro_AddHappyPath_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Aggro_ForEachExclusionPolicy_SpawnParams
{
}

namespace UCk_AutoTest_Aggro_ForEachExclusionPolicy
{
    FCk_AutoTest_Aggro_ForEachExclusionPolicy_SpawnParams Params()
    {
        return FCk_AutoTest_Aggro_ForEachExclusionPolicy_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Aggro_GetBestAggroSingle_SpawnParams
{
}

namespace UCk_AutoTest_Aggro_GetBestAggroSingle
{
    FCk_AutoTest_Aggro_GetBestAggroSingle_SpawnParams Params()
    {
        return FCk_AutoTest_Aggro_GetBestAggroSingle_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Aggro_GetTarget_SpawnParams
{
}

namespace UCk_AutoTest_Aggro_GetTarget
{
    FCk_AutoTest_Aggro_GetTarget_SpawnParams Params()
    {
        return FCk_AutoTest_Aggro_GetTarget_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Aggro_OwnerAddHappyPath_SpawnParams
{
}

namespace UCk_AutoTest_Aggro_OwnerAddHappyPath
{
    FCk_AutoTest_Aggro_OwnerAddHappyPath_SpawnParams Params()
    {
        return FCk_AutoTest_Aggro_OwnerAddHappyPath_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Aggro_RequestIncludeRestores_SpawnParams
{
}

namespace UCk_AutoTest_Aggro_RequestIncludeRestores
{
    FCk_AutoTest_Aggro_RequestIncludeRestores_SpawnParams Params()
    {
        return FCk_AutoTest_Aggro_RequestIncludeRestores_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Aggro_TryGetAggroByTargetFound_SpawnParams
{
}

namespace UCk_AutoTest_Aggro_TryGetAggroByTargetFound
{
    FCk_AutoTest_Aggro_TryGetAggroByTargetFound_SpawnParams Params()
    {
        return FCk_AutoTest_Aggro_TryGetAggroByTargetFound_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Aggro_TryGetAggroByTargetNotFound_SpawnParams
{
}

namespace UCk_AutoTest_Aggro_TryGetAggroByTargetNotFound
{
    FCk_AutoTest_Aggro_TryGetAggroByTargetNotFound_SpawnParams Params()
    {
        return FCk_AutoTest_Aggro_TryGetAggroByTargetNotFound_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_AStar_BasicSearch_SpawnParams
{
}

namespace UCk_AutoTest_AStar_BasicSearch
{
    FCk_AutoTest_AStar_BasicSearch_SpawnParams Params()
    {
        return FCk_AutoTest_AStar_BasicSearch_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_AStar_CostThreshold_SpawnParams
{
}

namespace UCk_AutoTest_AStar_CostThreshold
{
    FCk_AutoTest_AStar_CostThreshold_SpawnParams Params()
    {
        return FCk_AutoTest_AStar_CostThreshold_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_AStar_NoPath_SpawnParams
{
}

namespace UCk_AutoTest_AStar_NoPath
{
    FCk_AutoTest_AStar_NoPath_SpawnParams Params()
    {
        return FCk_AutoTest_AStar_NoPath_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Attribute_ByteBasic_SpawnParams
{
}

namespace UCk_AutoTest_Attribute_ByteBasic
{
    FCk_AutoTest_Attribute_ByteBasic_SpawnParams Params()
    {
        return FCk_AutoTest_Attribute_ByteBasic_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Attribute_ByteModifierAdd_SpawnParams
{
}

namespace UCk_AutoTest_Attribute_ByteModifierAdd
{
    FCk_AutoTest_Attribute_ByteModifierAdd_SpawnParams Params()
    {
        return FCk_AutoTest_Attribute_ByteModifierAdd_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Attribute_ByteMultiplyComposes_SpawnParams
{
}

namespace UCk_AutoTest_Attribute_ByteMultiplyComposes
{
    FCk_AutoTest_Attribute_ByteMultiplyComposes_SpawnParams Params()
    {
        return FCk_AutoTest_Attribute_ByteMultiplyComposes_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Attribute_FloatBasic_SpawnParams
{
}

namespace UCk_AutoTest_Attribute_FloatBasic
{
    FCk_AutoTest_Attribute_FloatBasic_SpawnParams Params()
    {
        return FCk_AutoTest_Attribute_FloatBasic_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Attribute_FloatClamping_SpawnParams
{
}

namespace UCk_AutoTest_Attribute_FloatClamping
{
    FCk_AutoTest_Attribute_FloatClamping_SpawnParams Params()
    {
        return FCk_AutoTest_Attribute_FloatClamping_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Attribute_FloatIncrement_SpawnParams
{
}

namespace UCk_AutoTest_Attribute_FloatIncrement
{
    FCk_AutoTest_Attribute_FloatIncrement_SpawnParams Params()
    {
        return FCk_AutoTest_Attribute_FloatIncrement_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Attribute_FloatMinMaxComponents_SpawnParams
{
}

namespace UCk_AutoTest_Attribute_FloatMinMaxComponents
{
    FCk_AutoTest_Attribute_FloatMinMaxComponents_SpawnParams Params()
    {
        return FCk_AutoTest_Attribute_FloatMinMaxComponents_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Attribute_FloatModifierAdd_SpawnParams
{
}

namespace UCk_AutoTest_Attribute_FloatModifierAdd
{
    FCk_AutoTest_Attribute_FloatModifierAdd_SpawnParams Params()
    {
        return FCk_AutoTest_Attribute_FloatModifierAdd_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Attribute_FloatModifierRemove_SpawnParams
{
}

namespace UCk_AutoTest_Attribute_FloatModifierRemove
{
    FCk_AutoTest_Attribute_FloatModifierRemove_SpawnParams Params()
    {
        return FCk_AutoTest_Attribute_FloatModifierRemove_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Attribute_FloatModifierStacking_SpawnParams
{
}

namespace UCk_AutoTest_Attribute_FloatModifierStacking
{
    FCk_AutoTest_Attribute_FloatModifierStacking_SpawnParams Params()
    {
        return FCk_AutoTest_Attribute_FloatModifierStacking_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Attribute_FloatOverflow_SpawnParams
{
}

namespace UCk_AutoTest_Attribute_FloatOverflow
{
    FCk_AutoTest_Attribute_FloatOverflow_SpawnParams Params()
    {
        return FCk_AutoTest_Attribute_FloatOverflow_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Attribute_FloatRefill_SpawnParams
{
}

namespace UCk_AutoTest_Attribute_FloatRefill
{
    FCk_AutoTest_Attribute_FloatRefill_SpawnParams Params()
    {
        return FCk_AutoTest_Attribute_FloatRefill_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Attribute_IntegerBasic_SpawnParams
{
}

namespace UCk_AutoTest_Attribute_IntegerBasic
{
    FCk_AutoTest_Attribute_IntegerBasic_SpawnParams Params()
    {
        return FCk_AutoTest_Attribute_IntegerBasic_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Attribute_IntegerClamping_SpawnParams
{
}

namespace UCk_AutoTest_Attribute_IntegerClamping
{
    FCk_AutoTest_Attribute_IntegerClamping_SpawnParams Params()
    {
        return FCk_AutoTest_Attribute_IntegerClamping_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Attribute_IntegerModifierAdd_SpawnParams
{
}

namespace UCk_AutoTest_Attribute_IntegerModifierAdd
{
    FCk_AutoTest_Attribute_IntegerModifierAdd_SpawnParams Params()
    {
        return FCk_AutoTest_Attribute_IntegerModifierAdd_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Attribute_IntegerModifierRemove_SpawnParams
{
}

namespace UCk_AutoTest_Attribute_IntegerModifierRemove
{
    FCk_AutoTest_Attribute_IntegerModifierRemove_SpawnParams Params()
    {
        return FCk_AutoTest_Attribute_IntegerModifierRemove_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Attribute_IntegerModifierStacking_SpawnParams
{
}

namespace UCk_AutoTest_Attribute_IntegerModifierStacking
{
    FCk_AutoTest_Attribute_IntegerModifierStacking_SpawnParams Params()
    {
        return FCk_AutoTest_Attribute_IntegerModifierStacking_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Attribute_IntegerMultiplyComposes_SpawnParams
{
}

namespace UCk_AutoTest_Attribute_IntegerMultiplyComposes
{
    FCk_AutoTest_Attribute_IntegerMultiplyComposes_SpawnParams Params()
    {
        return FCk_AutoTest_Attribute_IntegerMultiplyComposes_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Attribute_IntegerOverflow_SpawnParams
{
}

namespace UCk_AutoTest_Attribute_IntegerOverflow
{
    FCk_AutoTest_Attribute_IntegerOverflow_SpawnParams Params()
    {
        return FCk_AutoTest_Attribute_IntegerOverflow_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Attribute_NotRevocable_AddCoalesces_SpawnParams
{
}

namespace UCk_AutoTest_Attribute_NotRevocable_AddCoalesces
{
    FCk_AutoTest_Attribute_NotRevocable_AddCoalesces_SpawnParams Params()
    {
        return FCk_AutoTest_Attribute_NotRevocable_AddCoalesces_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Attribute_NotRevocable_OverrideReplaces_SpawnParams
{
}

namespace UCk_AutoTest_Attribute_NotRevocable_OverrideReplaces
{
    FCk_AutoTest_Attribute_NotRevocable_OverrideReplaces_SpawnParams Params()
    {
        return FCk_AutoTest_Attribute_NotRevocable_OverrideReplaces_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Attribute_OnClampedPayloadDirection_SpawnParams
{
}

namespace UCk_AutoTest_Attribute_OnClampedPayloadDirection
{
    FCk_AutoTest_Attribute_OnClampedPayloadDirection_SpawnParams Params()
    {
        return FCk_AutoTest_Attribute_OnClampedPayloadDirection_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Attribute_Override_ChangesDeltaInPlace_SpawnParams
{
}

namespace UCk_AutoTest_Attribute_Override_ChangesDeltaInPlace
{
    FCk_AutoTest_Attribute_Override_ChangesDeltaInPlace_SpawnParams Params()
    {
        return FCk_AutoTest_Attribute_Override_ChangesDeltaInPlace_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Attribute_PreClampAsymmetry_SpawnParams
{
}

namespace UCk_AutoTest_Attribute_PreClampAsymmetry
{
    FCk_AutoTest_Attribute_PreClampAsymmetry_SpawnParams Params()
    {
        return FCk_AutoTest_Attribute_PreClampAsymmetry_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Attribute_Request_ClearAllModifiers_SpawnParams
{
}

namespace UCk_AutoTest_Attribute_Request_ClearAllModifiers
{
    FCk_AutoTest_Attribute_Request_ClearAllModifiers_SpawnParams Params()
    {
        return FCk_AutoTest_Attribute_Request_ClearAllModifiers_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Attribute_Revocable_PerCallHandleUniqueness_SpawnParams
{
}

namespace UCk_AutoTest_Attribute_Revocable_PerCallHandleUniqueness
{
    FCk_AutoTest_Attribute_Revocable_PerCallHandleUniqueness_SpawnParams Params()
    {
        return FCk_AutoTest_Attribute_Revocable_PerCallHandleUniqueness_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Attribute_RevokeModifierDuringValueChanged_SpawnParams
{
}

namespace UCk_AutoTest_Attribute_RevokeModifierDuringValueChanged
{
    FCk_AutoTest_Attribute_RevokeModifierDuringValueChanged_SpawnParams Params()
    {
        return FCk_AutoTest_Attribute_RevokeModifierDuringValueChanged_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Attribute_SameFrameMutationsCoalesce_OneSignal_SpawnParams
{
}

namespace UCk_AutoTest_Attribute_SameFrameMutationsCoalesce_OneSignal
{
    FCk_AutoTest_Attribute_SameFrameMutationsCoalesce_OneSignal_SpawnParams Params()
    {
        return FCk_AutoTest_Attribute_SameFrameMutationsCoalesce_OneSignal_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Base_SpawnParams
{
}

namespace UCk_AutoTest_Base
{
    FCk_AutoTest_Base_SpawnParams Params()
    {
        return FCk_AutoTest_Base_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Chrono_GetTimeElapsed_Normalized_Linear_SpawnParams
{
}

namespace UCk_AutoTest_Chrono_GetTimeElapsed_Normalized_Linear
{
    FCk_AutoTest_Chrono_GetTimeElapsed_Normalized_Linear_SpawnParams Params()
    {
        return FCk_AutoTest_Chrono_GetTimeElapsed_Normalized_Linear_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Chrono_TickAndComplete_SpawnParams
{
}

namespace UCk_AutoTest_Chrono_TickAndComplete
{
    FCk_AutoTest_Chrono_TickAndComplete_SpawnParams Params()
    {
        return FCk_AutoTest_Chrono_TickAndComplete_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Chrono_TickPastCompletion_ClampsAtDuration_SpawnParams
{
}

namespace UCk_AutoTest_Chrono_TickPastCompletion_ClampsAtDuration
{
    FCk_AutoTest_Chrono_TickPastCompletion_ClampsAtDuration_SpawnParams Params()
    {
        return FCk_AutoTest_Chrono_TickPastCompletion_ClampsAtDuration_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_CrossCutting_DestroyOwner_DuringHandleRequests_NoCrash_SpawnParams
{
}

namespace UCk_AutoTest_CrossCutting_DestroyOwner_DuringHandleRequests_NoCrash
{
    FCk_AutoTest_CrossCutting_DestroyOwner_DuringHandleRequests_NoCrash_SpawnParams Params()
    {
        return FCk_AutoTest_CrossCutting_DestroyOwner_DuringHandleRequests_NoCrash_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_CrossCutting_DestroyOwner_DuringSignalBroadcast_DelegatesSkipped_SpawnParams
{
}

namespace UCk_AutoTest_CrossCutting_DestroyOwner_DuringSignalBroadcast_DelegatesSkipped
{
    FCk_AutoTest_CrossCutting_DestroyOwner_DuringSignalBroadcast_DelegatesSkipped_SpawnParams Params()
    {
        return FCk_AutoTest_CrossCutting_DestroyOwner_DuringSignalBroadcast_DelegatesSkipped_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_CrossCutting_EndPlay_ReleasesRecordEntries_SpawnParams
{
}

namespace UCk_AutoTest_CrossCutting_EndPlay_ReleasesRecordEntries
{
    FCk_AutoTest_CrossCutting_EndPlay_ReleasesRecordEntries_SpawnParams Params()
    {
        return FCk_AutoTest_CrossCutting_EndPlay_ReleasesRecordEntries_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_CrossCutting_SameFrame_AttributeOverrideCoalesces_SpawnParams
{
}

namespace UCk_AutoTest_CrossCutting_SameFrame_AttributeOverrideCoalesces
{
    FCk_AutoTest_CrossCutting_SameFrame_AttributeOverrideCoalesces_SpawnParams Params()
    {
        return FCk_AutoTest_CrossCutting_SameFrame_AttributeOverrideCoalesces_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_CrossCutting_SameFrame_TagSetAddAndRemoveCancel_SpawnParams
{
}

namespace UCk_AutoTest_CrossCutting_SameFrame_TagSetAddAndRemoveCancel
{
    FCk_AutoTest_CrossCutting_SameFrame_TagSetAddAndRemoveCancel_SpawnParams Params()
    {
        return FCk_AutoTest_CrossCutting_SameFrame_TagSetAddAndRemoveCancel_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_CrossCutting_SameFrame_TransformSetLocationCoalesces_SpawnParams
{
}

namespace UCk_AutoTest_CrossCutting_SameFrame_TransformSetLocationCoalesces
{
    FCk_AutoTest_CrossCutting_SameFrame_TransformSetLocationCoalesces_SpawnParams Params()
    {
        return FCk_AutoTest_CrossCutting_SameFrame_TransformSetLocationCoalesces_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Crowd_Pathfinding_Failure_SpawnParams
{
}

namespace UCk_AutoTest_Crowd_Pathfinding_Failure
{
    FCk_AutoTest_Crowd_Pathfinding_Failure_SpawnParams Params()
    {
        return FCk_AutoTest_Crowd_Pathfinding_Failure_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Crowd_Pathfinding_Success_SpawnParams
{
}

namespace UCk_AutoTest_Crowd_Pathfinding_Success
{
    FCk_AutoTest_Crowd_Pathfinding_Success_SpawnParams Params()
    {
        return FCk_AutoTest_Crowd_Pathfinding_Success_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Crowd_Separation_Convergence_SpawnParams
{
}

namespace UCk_AutoTest_Crowd_Separation_Convergence
{
    FCk_AutoTest_Crowd_Separation_Convergence_SpawnParams Params()
    {
        return FCk_AutoTest_Crowd_Separation_Convergence_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Crowd_Separation_HeadOnPass_SpawnParams
{
}

namespace UCk_AutoTest_Crowd_Separation_HeadOnPass
{
    FCk_AutoTest_Crowd_Separation_HeadOnPass_SpawnParams Params()
    {
        return FCk_AutoTest_Crowd_Separation_HeadOnPass_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Crowd_Separation_Vibration_SpawnParams
{
}

namespace UCk_AutoTest_Crowd_Separation_Vibration
{
    FCk_AutoTest_Crowd_Separation_Vibration_SpawnParams Params()
    {
        return FCk_AutoTest_Crowd_Separation_Vibration_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Cue_AfterOneFrame_DestroyedQuickly_SpawnParams
{
}

namespace UCk_AutoTest_Cue_AfterOneFrame_DestroyedQuickly
{
    FCk_AutoTest_Cue_AfterOneFrame_DestroyedQuickly_SpawnParams Params()
    {
        return FCk_AutoTest_Cue_AfterOneFrame_DestroyedQuickly_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Cue_Persistent_StaysAlive_SpawnParams
{
}

namespace UCk_AutoTest_Cue_Persistent_StaysAlive
{
    FCk_AutoTest_Cue_Persistent_StaysAlive_SpawnParams Params()
    {
        return FCk_AutoTest_Cue_Persistent_StaysAlive_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Cue_Timed_DestroyedAfterDuration_SpawnParams
{
}

namespace UCk_AutoTest_Cue_Timed_DestroyedAfterDuration
{
    FCk_AutoTest_Cue_Timed_DestroyedAfterDuration_SpawnParams Params()
    {
        return FCk_AutoTest_Cue_Timed_DestroyedAfterDuration_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_EntityCollection_AddHappyPath_SpawnParams
{
}

namespace UCk_AutoTest_EntityCollection_AddHappyPath
{
    FCk_AutoTest_EntityCollection_AddHappyPath_SpawnParams Params()
    {
        return FCk_AutoTest_EntityCollection_AddHappyPath_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_EntityCollection_AddMultipleAddsAll_SpawnParams
{
}

namespace UCk_AutoTest_EntityCollection_AddMultipleAddsAll
{
    FCk_AutoTest_EntityCollection_AddMultipleAddsAll_SpawnParams Params()
    {
        return FCk_AutoTest_EntityCollection_AddMultipleAddsAll_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_EntityCollection_RequestAddEntitiesBatch_SpawnParams
{
}

namespace UCk_AutoTest_EntityCollection_RequestAddEntitiesBatch
{
    FCk_AutoTest_EntityCollection_RequestAddEntitiesBatch_SpawnParams Params()
    {
        return FCk_AutoTest_EntityCollection_RequestAddEntitiesBatch_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_EntityCollection_RequestAddSingleEntity_SpawnParams
{
}

namespace UCk_AutoTest_EntityCollection_RequestAddSingleEntity
{
    FCk_AutoTest_EntityCollection_RequestAddSingleEntity_SpawnParams Params()
    {
        return FCk_AutoTest_EntityCollection_RequestAddSingleEntity_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_EntityCollection_RequestRemoveSingleEntity_SpawnParams
{
}

namespace UCk_AutoTest_EntityCollection_RequestRemoveSingleEntity
{
    FCk_AutoTest_EntityCollection_RequestRemoveSingleEntity_SpawnParams Params()
    {
        return FCk_AutoTest_EntityCollection_RequestRemoveSingleEntity_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_EntityCollection_TryGetAbsentInvalid_SpawnParams
{
}

namespace UCk_AutoTest_EntityCollection_TryGetAbsentInvalid
{
    FCk_AutoTest_EntityCollection_TryGetAbsentInvalid_SpawnParams Params()
    {
        return FCk_AutoTest_EntityCollection_TryGetAbsentInvalid_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_EntityExtension_AddHappyPath_SpawnParams
{
}

namespace UCk_AutoTest_EntityExtension_AddHappyPath
{
    FCk_AutoTest_EntityExtension_AddHappyPath_SpawnParams Params()
    {
        return FCk_AutoTest_EntityExtension_AddHappyPath_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_EntityExtension_DistinctOwnersIsolated_SpawnParams
{
}

namespace UCk_AutoTest_EntityExtension_DistinctOwnersIsolated
{
    FCk_AutoTest_EntityExtension_DistinctOwnersIsolated_SpawnParams Params()
    {
        return FCk_AutoTest_EntityExtension_DistinctOwnersIsolated_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_EntityExtension_ForEachListsAll_SpawnParams
{
}

namespace UCk_AutoTest_EntityExtension_ForEachListsAll
{
    FCk_AutoTest_EntityExtension_ForEachListsAll_SpawnParams Params()
    {
        return FCk_AutoTest_EntityExtension_ForEachListsAll_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_EntityExtension_RemoveHappyPath_SpawnParams
{
}

namespace UCk_AutoTest_EntityExtension_RemoveHappyPath
{
    FCk_AutoTest_EntityExtension_RemoveHappyPath_SpawnParams Params()
    {
        return FCk_AutoTest_EntityExtension_RemoveHappyPath_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_EntityExtension_RemoveLeavesOthers_SpawnParams
{
}

namespace UCk_AutoTest_EntityExtension_RemoveLeavesOthers
{
    FCk_AutoTest_EntityExtension_RemoveLeavesOthers_SpawnParams Params()
    {
        return FCk_AutoTest_EntityExtension_RemoveLeavesOthers_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_EntityLifecycle_BatchDestroy_SpawnParams
{
}

namespace UCk_AutoTest_EntityLifecycle_BatchDestroy
{
    FCk_AutoTest_EntityLifecycle_BatchDestroy_SpawnParams Params()
    {
        return FCk_AutoTest_EntityLifecycle_BatchDestroy_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_EntityLifecycle_CircularContextOwnership_SpawnParams
{
}

namespace UCk_AutoTest_EntityLifecycle_CircularContextOwnership
{
    FCk_AutoTest_EntityLifecycle_CircularContextOwnership_SpawnParams Params()
    {
        return FCk_AutoTest_EntityLifecycle_CircularContextOwnership_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_EntityLifecycle_ContextOwnerGrandparent_SpawnParams
{
}

namespace UCk_AutoTest_EntityLifecycle_ContextOwnerGrandparent
{
    FCk_AutoTest_EntityLifecycle_ContextOwnerGrandparent_SpawnParams Params()
    {
        return FCk_AutoTest_EntityLifecycle_ContextOwnerGrandparent_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_EntityLifecycle_ContextOwnerOverride_SpawnParams
{
}

namespace UCk_AutoTest_EntityLifecycle_ContextOwnerOverride
{
    FCk_AutoTest_EntityLifecycle_ContextOwnerOverride_SpawnParams Params()
    {
        return FCk_AutoTest_EntityLifecycle_ContextOwnerOverride_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_EntityLifecycle_DeferredSetupCompleteCallbacks_SpawnParams
{
}

namespace UCk_AutoTest_EntityLifecycle_DeferredSetupCompleteCallbacks
{
    FCk_AutoTest_EntityLifecycle_DeferredSetupCompleteCallbacks_SpawnParams Params()
    {
        return FCk_AutoTest_EntityLifecycle_DeferredSetupCompleteCallbacks_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_EntityLifecycle_DeferredSetupState_SpawnParams
{
}

namespace UCk_AutoTest_EntityLifecycle_DeferredSetupState
{
    FCk_AutoTest_EntityLifecycle_DeferredSetupState_SpawnParams Params()
    {
        return FCk_AutoTest_EntityLifecycle_DeferredSetupState_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_EntityLifecycle_DependentsCountMutations_SpawnParams
{
}

namespace UCk_AutoTest_EntityLifecycle_DependentsCountMutations
{
    FCk_AutoTest_EntityLifecycle_DependentsCountMutations_SpawnParams Params()
    {
        return FCk_AutoTest_EntityLifecycle_DependentsCountMutations_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_EntityLifecycle_HandleAndEntity_SpawnParams
{
}

namespace UCk_AutoTest_EntityLifecycle_HandleAndEntity
{
    FCk_AutoTest_EntityLifecycle_HandleAndEntity_SpawnParams Params()
    {
        return FCk_AutoTest_EntityLifecycle_HandleAndEntity_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_EntityLifecycle_IsTransientEntityVsContext_SpawnParams
{
}

namespace UCk_AutoTest_EntityLifecycle_IsTransientEntityVsContext
{
    FCk_AutoTest_EntityLifecycle_IsTransientEntityVsContext_SpawnParams Params()
    {
        return FCk_AutoTest_EntityLifecycle_IsTransientEntityVsContext_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_EntityLifecycle_OnBeginDestroy_SpawnParams
{
}

namespace UCk_AutoTest_EntityLifecycle_OnBeginDestroy
{
    FCk_AutoTest_EntityLifecycle_OnBeginDestroy_SpawnParams Params()
    {
        return FCk_AutoTest_EntityLifecycle_OnBeginDestroy_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_EntityLifecycle_OwnershipTree_SpawnParams
{
}

namespace UCk_AutoTest_EntityLifecycle_OwnershipTree
{
    FCk_AutoTest_EntityLifecycle_OwnershipTree_SpawnParams Params()
    {
        return FCk_AutoTest_EntityLifecycle_OwnershipTree_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_EntityLifecycle_ScriptCastQueries_SpawnParams
{
}

namespace UCk_AutoTest_EntityLifecycle_ScriptCastQueries
{
    FCk_AutoTest_EntityLifecycle_ScriptCastQueries_SpawnParams Params()
    {
        return FCk_AutoTest_EntityLifecycle_ScriptCastQueries_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_EntityLifecycle_TagAddRemove_SpawnParams
{
}

namespace UCk_AutoTest_EntityLifecycle_TagAddRemove
{
    FCk_AutoTest_EntityLifecycle_TagAddRemove_SpawnParams Params()
    {
        return FCk_AutoTest_EntityLifecycle_TagAddRemove_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_EntityScript_BasicSpawn_SpawnParams
{
}

namespace UCk_AutoTest_EntityScript_BasicSpawn
{
    FCk_AutoTest_EntityScript_BasicSpawn_SpawnParams Params()
    {
        return FCk_AutoTest_EntityScript_BasicSpawn_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_EntityScript_SpawnedEntityHasTag_SpawnParams
{
}

namespace UCk_AutoTest_EntityScript_SpawnedEntityHasTag
{
    FCk_AutoTest_EntityScript_SpawnedEntityHasTag_SpawnParams Params()
    {
        return FCk_AutoTest_EntityScript_SpawnedEntityHasTag_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_EntityScript_SpawnedEntityIsDependent_SpawnParams
{
}

namespace UCk_AutoTest_EntityScript_SpawnedEntityIsDependent
{
    FCk_AutoTest_EntityScript_SpawnedEntityIsDependent_SpawnParams Params()
    {
        return FCk_AutoTest_EntityScript_SpawnedEntityIsDependent_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_EntityScript_SpawnParamsRoundTrip_SpawnParams
{
}

namespace UCk_AutoTest_EntityScript_SpawnParamsRoundTrip
{
    FCk_AutoTest_EntityScript_SpawnParamsRoundTrip_SpawnParams Params()
    {
        return FCk_AutoTest_EntityScript_SpawnParamsRoundTrip_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_EntityTag_AddEmptyName_Rejected_SpawnParams
{
}

namespace UCk_AutoTest_EntityTag_AddEmptyName_Rejected
{
    FCk_AutoTest_EntityTag_AddEmptyName_Rejected_SpawnParams Params()
    {
        return FCk_AutoTest_EntityTag_AddEmptyName_Rejected_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_EntityTag_AddFNameHappyPath_SpawnParams
{
}

namespace UCk_AutoTest_EntityTag_AddFNameHappyPath
{
    FCk_AutoTest_EntityTag_AddFNameHappyPath_SpawnParams Params()
    {
        return FCk_AutoTest_EntityTag_AddFNameHappyPath_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_EntityTag_AddGameplayTagHappyPath_SpawnParams
{
}

namespace UCk_AutoTest_EntityTag_AddGameplayTagHappyPath
{
    FCk_AutoTest_EntityTag_AddGameplayTagHappyPath_SpawnParams Params()
    {
        return FCk_AutoTest_EntityTag_AddGameplayTagHappyPath_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_EntityTag_HasAbsentTagFalse_SpawnParams
{
}

namespace UCk_AutoTest_EntityTag_HasAbsentTagFalse
{
    FCk_AutoTest_EntityTag_HasAbsentTagFalse_SpawnParams Params()
    {
        return FCk_AutoTest_EntityTag_HasAbsentTagFalse_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_EntityTag_RequestTryRemoveAbsentFailed_SpawnParams
{
}

namespace UCk_AutoTest_EntityTag_RequestTryRemoveAbsentFailed
{
    FCk_AutoTest_EntityTag_RequestTryRemoveAbsentFailed_SpawnParams Params()
    {
        return FCk_AutoTest_EntityTag_RequestTryRemoveAbsentFailed_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_EntityTag_RequestTryRemoveHappyPath_SpawnParams
{
}

namespace UCk_AutoTest_EntityTag_RequestTryRemoveHappyPath
{
    FCk_AutoTest_EntityTag_RequestTryRemoveHappyPath_SpawnParams Params()
    {
        return FCk_AutoTest_EntityTag_RequestTryRemoveHappyPath_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_EntityTag_TryGetTagNoTagReturnsNone_SpawnParams
{
}

namespace UCk_AutoTest_EntityTag_TryGetTagNoTagReturnsNone
{
    FCk_AutoTest_EntityTag_TryGetTagNoTagReturnsNone_SpawnParams Params()
    {
        return FCk_AutoTest_EntityTag_TryGetTagNoTagReturnsNone_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Eqs_BasicQuery_SpawnParams
{
}

namespace UCk_AutoTest_Eqs_BasicQuery
{
    FCk_AutoTest_Eqs_BasicQuery_SpawnParams Params()
    {
        return FCk_AutoTest_Eqs_BasicQuery_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Eqs_Cancel_SpawnParams
{
}

namespace UCk_AutoTest_Eqs_Cancel
{
    FCk_AutoTest_Eqs_Cancel_SpawnParams Params()
    {
        return FCk_AutoTest_Eqs_Cancel_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Eqs_Immediate_SpawnParams
{
}

namespace UCk_AutoTest_Eqs_Immediate
{
    FCk_AutoTest_Eqs_Immediate_SpawnParams Params()
    {
        return FCk_AutoTest_Eqs_Immediate_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Eqs_NavProjection_SpawnParams
{
}

namespace UCk_AutoTest_Eqs_NavProjection
{
    FCk_AutoTest_Eqs_NavProjection_SpawnParams Params()
    {
        return FCk_AutoTest_Eqs_NavProjection_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Eqs_OnCircle_SpawnParams
{
}

namespace UCk_AutoTest_Eqs_OnCircle
{
    FCk_AutoTest_Eqs_OnCircle_SpawnParams Params()
    {
        return FCk_AutoTest_Eqs_OnCircle_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Eqs_RandomRunMode_SpawnParams
{
}

namespace UCk_AutoTest_Eqs_RandomRunMode
{
    FCk_AutoTest_Eqs_RandomRunMode_SpawnParams Params()
    {
        return FCk_AutoTest_Eqs_RandomRunMode_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Eqs_VolumeCheck_SpawnParams
{
}

namespace UCk_AutoTest_Eqs_VolumeCheck
{
    FCk_AutoTest_Eqs_VolumeCheck_SpawnParams Params()
    {
        return FCk_AutoTest_Eqs_VolumeCheck_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Goap_BasicPlan_SpawnParams
{
}

namespace UCk_AutoTest_Goap_BasicPlan
{
    FCk_AutoTest_Goap_BasicPlan_SpawnParams Params()
    {
        return FCk_AutoTest_Goap_BasicPlan_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Goap_DependencyChain_SpawnParams
{
}

namespace UCk_AutoTest_Goap_DependencyChain
{
    FCk_AutoTest_Goap_DependencyChain_SpawnParams Params()
    {
        return FCk_AutoTest_Goap_DependencyChain_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Grid_AddAndDimensions_SpawnParams
{
}

namespace UCk_AutoTest_Grid_AddAndDimensions
{
    FCk_AutoTest_Grid_AddAndDimensions_SpawnParams Params()
    {
        return FCk_AutoTest_Grid_AddAndDimensions_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Grid_CellCoordinatesAreUnique_SpawnParams
{
}

namespace UCk_AutoTest_Grid_CellCoordinatesAreUnique
{
    FCk_AutoTest_Grid_CellCoordinatesAreUnique_SpawnParams Params()
    {
        return FCk_AutoTest_Grid_CellCoordinatesAreUnique_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Grid_CellsAreEnabledByDefault_SpawnParams
{
}

namespace UCk_AutoTest_Grid_CellsAreEnabledByDefault
{
    FCk_AutoTest_Grid_CellsAreEnabledByDefault_SpawnParams Params()
    {
        return FCk_AutoTest_Grid_CellsAreEnabledByDefault_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Grid_DisabledCellRejectsPlacement_SpawnParams
{
}

namespace UCk_AutoTest_Grid_DisabledCellRejectsPlacement
{
    FCk_AutoTest_Grid_DisabledCellRejectsPlacement_SpawnParams Params()
    {
        return FCk_AutoTest_Grid_DisabledCellRejectsPlacement_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Grid_DisjointIntersection_SpawnParams
{
}

namespace UCk_AutoTest_Grid_DisjointIntersection
{
    FCk_AutoTest_Grid_DisjointIntersection_SpawnParams Params()
    {
        return FCk_AutoTest_Grid_DisjointIntersection_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Grid_IntersectionCardinality_SpawnParams
{
}

namespace UCk_AutoTest_Grid_IntersectionCardinality
{
    FCk_AutoTest_Grid_IntersectionCardinality_SpawnParams Params()
    {
        return FCk_AutoTest_Grid_IntersectionCardinality_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Grid_OverlappingIntersection_SpawnParams
{
}

namespace UCk_AutoTest_Grid_OverlappingIntersection
{
    FCk_AutoTest_Grid_OverlappingIntersection_SpawnParams Params()
    {
        return FCk_AutoTest_Grid_OverlappingIntersection_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Grid_RotationLocalCoordMapping_SpawnParams
{
}

namespace UCk_AutoTest_Grid_RotationLocalCoordMapping
{
    FCk_AutoTest_Grid_RotationLocalCoordMapping_SpawnParams Params()
    {
        return FCk_AutoTest_Grid_RotationLocalCoordMapping_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Interaction_CancelAllInteractions_FinishesAsFailed_SpawnParams
{
}

namespace UCk_AutoTest_Interaction_CancelAllInteractions_FinishesAsFailed
{
    FCk_AutoTest_Interaction_CancelAllInteractions_FinishesAsFailed_SpawnParams Params()
    {
        return FCk_AutoTest_Interaction_CancelAllInteractions_FinishesAsFailed_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Interaction_CanInteractWithComplexValidation_SpawnParams
{
}

namespace UCk_AutoTest_Interaction_CanInteractWithComplexValidation
{
    FCk_AutoTest_Interaction_CanInteractWithComplexValidation_SpawnParams Params()
    {
        return FCk_AutoTest_Interaction_CanInteractWithComplexValidation_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Interaction_ConcurrentInteractionsSameTarget_SpawnParams
{
}

namespace UCk_AutoTest_Interaction_ConcurrentInteractionsSameTarget
{
    FCk_AutoTest_Interaction_ConcurrentInteractionsSameTarget_SpawnParams Params()
    {
        return FCk_AutoTest_Interaction_ConcurrentInteractionsSameTarget_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Interaction_Get_CurrentInteractions_DuringInFlight_SpawnParams
{
}

namespace UCk_AutoTest_Interaction_Get_CurrentInteractions_DuringInFlight
{
    FCk_AutoTest_Interaction_Get_CurrentInteractions_DuringInFlight_SpawnParams Params()
    {
        return FCk_AutoTest_Interaction_Get_CurrentInteractions_DuringInFlight_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Interaction_Instant_SpawnParams
{
}

namespace UCk_AutoTest_Interaction_Instant
{
    FCk_AutoTest_Interaction_Instant_SpawnParams Params()
    {
        return FCk_AutoTest_Interaction_Instant_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Interaction_ManualFail_SpawnParams
{
}

namespace UCk_AutoTest_Interaction_ManualFail
{
    FCk_AutoTest_Interaction_ManualFail_SpawnParams Params()
    {
        return FCk_AutoTest_Interaction_ManualFail_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Interaction_ManualSuccess_SpawnParams
{
}

namespace UCk_AutoTest_Interaction_ManualSuccess
{
    FCk_AutoTest_Interaction_ManualSuccess_SpawnParams Params()
    {
        return FCk_AutoTest_Interaction_ManualSuccess_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Interaction_MultipleInteractors_SingleInteractionRejectsSecond_SpawnParams
{
}

namespace UCk_AutoTest_Interaction_MultipleInteractors_SingleInteractionRejectsSecond
{
    FCk_AutoTest_Interaction_MultipleInteractors_SingleInteractionRejectsSecond_SpawnParams Params()
    {
        return FCk_AutoTest_Interaction_MultipleInteractors_SingleInteractionRejectsSecond_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Interaction_OnInteractionFinished_PayloadShape_SpawnParams
{
}

namespace UCk_AutoTest_Interaction_OnInteractionFinished_PayloadShape
{
    FCk_AutoTest_Interaction_OnInteractionFinished_PayloadShape_SpawnParams Params()
    {
        return FCk_AutoTest_Interaction_OnInteractionFinished_PayloadShape_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Interaction_OnNewInteractionPayload_SpawnParams
{
}

namespace UCk_AutoTest_Interaction_OnNewInteractionPayload
{
    FCk_AutoTest_Interaction_OnNewInteractionPayload_SpawnParams Params()
    {
        return FCk_AutoTest_Interaction_OnNewInteractionPayload_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Interaction_ResetAfterCompletion_Reusable_SpawnParams
{
}

namespace UCk_AutoTest_Interaction_ResetAfterCompletion_Reusable
{
    FCk_AutoTest_Interaction_ResetAfterCompletion_Reusable_SpawnParams Params()
    {
        return FCk_AutoTest_Interaction_ResetAfterCompletion_Reusable_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Interaction_Timed_SpawnParams
{
}

namespace UCk_AutoTest_Interaction_Timed
{
    FCk_AutoTest_Interaction_Timed_SpawnParams Params()
    {
        return FCk_AutoTest_Interaction_Timed_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Interaction_TimedInterruptedByCancel_SpawnParams
{
}

namespace UCk_AutoTest_Interaction_TimedInterruptedByCancel
{
    FCk_AutoTest_Interaction_TimedInterruptedByCancel_SpawnParams Params()
    {
        return FCk_AutoTest_Interaction_TimedInterruptedByCancel_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Interaction_TryGet_Interaction_ReturnsActive_SpawnParams
{
}

namespace UCk_AutoTest_Interaction_TryGet_Interaction_ReturnsActive
{
    FCk_AutoTest_Interaction_TryGet_Interaction_ReturnsActive_SpawnParams Params()
    {
        return FCk_AutoTest_Interaction_TryGet_Interaction_ReturnsActive_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Interaction_ValidationAllows_SpawnParams
{
}

namespace UCk_AutoTest_Interaction_ValidationAllows
{
    FCk_AutoTest_Interaction_ValidationAllows_SpawnParams Params()
    {
        return FCk_AutoTest_Interaction_ValidationAllows_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Interaction_ValidationChannelMismatch_SpawnParams
{
}

namespace UCk_AutoTest_Interaction_ValidationChannelMismatch
{
    FCk_AutoTest_Interaction_ValidationChannelMismatch_SpawnParams Params()
    {
        return FCk_AutoTest_Interaction_ValidationChannelMismatch_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Interaction_ValidationCustomFails_SpawnParams
{
}

namespace UCk_AutoTest_Interaction_ValidationCustomFails
{
    FCk_AutoTest_Interaction_ValidationCustomFails_SpawnParams Params()
    {
        return FCk_AutoTest_Interaction_ValidationCustomFails_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Interaction_ValidationTargetDisabled_SpawnParams
{
}

namespace UCk_AutoTest_Interaction_ValidationTargetDisabled
{
    FCk_AutoTest_Interaction_ValidationTargetDisabled_SpawnParams Params()
    {
        return FCk_AutoTest_Interaction_ValidationTargetDisabled_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Inventory_AddItem_DuplicateInsertRejected_SpawnParams
{
}

namespace UCk_AutoTest_Inventory_AddItem_DuplicateInsertRejected
{
    FCk_AutoTest_Inventory_AddItem_DuplicateInsertRejected_SpawnParams Params()
    {
        return FCk_AutoTest_Inventory_AddItem_DuplicateInsertRejected_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Inventory_AddItemByDefinition_MissingAsset_SpawnParams
{
}

namespace UCk_AutoTest_Inventory_AddItemByDefinition_MissingAsset
{
    FCk_AutoTest_Inventory_AddItemByDefinition_MissingAsset_SpawnParams Params()
    {
        return FCk_AutoTest_Inventory_AddItemByDefinition_MissingAsset_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Inventory_CustomCanAcceptItem_SpawnParams
{
}

namespace UCk_AutoTest_Inventory_CustomCanAcceptItem
{
    FCk_AutoTest_Inventory_CustomCanAcceptItem_SpawnParams Params()
    {
        return FCk_AutoTest_Inventory_CustomCanAcceptItem_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Inventory_DataOnly_AddItem_SpawnParams
{
}

namespace UCk_AutoTest_Inventory_DataOnly_AddItem
{
    FCk_AutoTest_Inventory_DataOnly_AddItem_SpawnParams Params()
    {
        return FCk_AutoTest_Inventory_DataOnly_AddItem_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Inventory_DataOnly_BoundedReject_SpawnParams
{
}

namespace UCk_AutoTest_Inventory_DataOnly_BoundedReject
{
    FCk_AutoTest_Inventory_DataOnly_BoundedReject_SpawnParams Params()
    {
        return FCk_AutoTest_Inventory_DataOnly_BoundedReject_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Inventory_DataOnly_OverrideBounds_SpawnParams
{
}

namespace UCk_AutoTest_Inventory_DataOnly_OverrideBounds
{
    FCk_AutoTest_Inventory_DataOnly_OverrideBounds_SpawnParams Params()
    {
        return FCk_AutoTest_Inventory_DataOnly_OverrideBounds_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Inventory_DataOnly_RemoveItem_SpawnParams
{
}

namespace UCk_AutoTest_Inventory_DataOnly_RemoveItem
{
    FCk_AutoTest_Inventory_DataOnly_RemoveItem_SpawnParams Params()
    {
        return FCk_AutoTest_Inventory_DataOnly_RemoveItem_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Inventory_DataOnly_Unbounded_SpawnParams
{
}

namespace UCk_AutoTest_Inventory_DataOnly_Unbounded
{
    FCk_AutoTest_Inventory_DataOnly_Unbounded_SpawnParams Params()
    {
        return FCk_AutoTest_Inventory_DataOnly_Unbounded_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Inventory_ResolveBestTransferTarget_NoCandidatePasses_SpawnParams
{
}

namespace UCk_AutoTest_Inventory_ResolveBestTransferTarget_NoCandidatePasses
{
    FCk_AutoTest_Inventory_ResolveBestTransferTarget_NoCandidatePasses_SpawnParams Params()
    {
        return FCk_AutoTest_Inventory_ResolveBestTransferTarget_NoCandidatePasses_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Inventory_Sort_DataOnly_BasicOrder_SpawnParams
{
}

namespace UCk_AutoTest_Inventory_Sort_DataOnly_BasicOrder
{
    FCk_AutoTest_Inventory_Sort_DataOnly_BasicOrder_SpawnParams Params()
    {
        return FCk_AutoTest_Inventory_Sort_DataOnly_BasicOrder_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Inventory_Spatial_AddByDefinition_NoSpace_SpawnParams
{
}

namespace UCk_AutoTest_Inventory_Spatial_AddByDefinition_NoSpace
{
    FCk_AutoTest_Inventory_Spatial_AddByDefinition_NoSpace_SpawnParams Params()
    {
        return FCk_AutoTest_Inventory_Spatial_AddByDefinition_NoSpace_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Inventory_Spatial_RelocateItem_BlockedByOther_SpawnParams
{
}

namespace UCk_AutoTest_Inventory_Spatial_RelocateItem_BlockedByOther
{
    FCk_AutoTest_Inventory_Spatial_RelocateItem_BlockedByOther_SpawnParams Params()
    {
        return FCk_AutoTest_Inventory_Spatial_RelocateItem_BlockedByOther_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Inventory_Spatial_RelocateItem_RotationChange_SpawnParams
{
}

namespace UCk_AutoTest_Inventory_Spatial_RelocateItem_RotationChange
{
    FCk_AutoTest_Inventory_Spatial_RelocateItem_RotationChange_SpawnParams Params()
    {
        return FCk_AutoTest_Inventory_Spatial_RelocateItem_RotationChange_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Inventory_Spatial_RelocateItem_Success_SpawnParams
{
}

namespace UCk_AutoTest_Inventory_Spatial_RelocateItem_Success
{
    FCk_AutoTest_Inventory_Spatial_RelocateItem_Success_SpawnParams Params()
    {
        return FCk_AutoTest_Inventory_Spatial_RelocateItem_Success_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Inventory_SpatialPlacementRejection_SpawnParams
{
}

namespace UCk_AutoTest_Inventory_SpatialPlacementRejection
{
    FCk_AutoTest_Inventory_SpatialPlacementRejection_SpawnParams Params()
    {
        return FCk_AutoTest_Inventory_SpatialPlacementRejection_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Inventory_StackableTrait_SplitStack_SpawnParams
{
}

namespace UCk_AutoTest_Inventory_StackableTrait_SplitStack
{
    FCk_AutoTest_Inventory_StackableTrait_SplitStack_SpawnParams Params()
    {
        return FCk_AutoTest_Inventory_StackableTrait_SplitStack_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Inventory_StackableTrait_SplitStack_BoundaryCount_SpawnParams
{
}

namespace UCk_AutoTest_Inventory_StackableTrait_SplitStack_BoundaryCount
{
    FCk_AutoTest_Inventory_StackableTrait_SplitStack_BoundaryCount_SpawnParams Params()
    {
        return FCk_AutoTest_Inventory_StackableTrait_SplitStack_BoundaryCount_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Inventory_StackableTrait_StackItems_SpawnParams
{
}

namespace UCk_AutoTest_Inventory_StackableTrait_StackItems
{
    FCk_AutoTest_Inventory_StackableTrait_StackItems_SpawnParams Params()
    {
        return FCk_AutoTest_Inventory_StackableTrait_StackItems_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Inventory_TagsTrait_AddTag_SpawnParams
{
}

namespace UCk_AutoTest_Inventory_TagsTrait_AddTag
{
    FCk_AutoTest_Inventory_TagsTrait_AddTag_SpawnParams Params()
    {
        return FCk_AutoTest_Inventory_TagsTrait_AddTag_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Inventory_TagsTrait_RemoveTag_SpawnParams
{
}

namespace UCk_AutoTest_Inventory_TagsTrait_RemoveTag
{
    FCk_AutoTest_Inventory_TagsTrait_RemoveTag_SpawnParams Params()
    {
        return FCk_AutoTest_Inventory_TagsTrait_RemoveTag_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Inventory_Transfer_RejectedByCustomCanAccept_SpawnParams
{
}

namespace UCk_AutoTest_Inventory_Transfer_RejectedByCustomCanAccept
{
    FCk_AutoTest_Inventory_Transfer_RejectedByCustomCanAccept_SpawnParams Params()
    {
        return FCk_AutoTest_Inventory_Transfer_RejectedByCustomCanAccept_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Inventory_Transfer_Spatial_To_Spatial_SpawnParams
{
}

namespace UCk_AutoTest_Inventory_Transfer_Spatial_To_Spatial
{
    FCk_AutoTest_Inventory_Transfer_Spatial_To_Spatial_SpawnParams Params()
    {
        return FCk_AutoTest_Inventory_Transfer_Spatial_To_Spatial_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Inventory_TransferItem_BaseHandleFacade_SpawnParams
{
}

namespace UCk_AutoTest_Inventory_TransferItem_BaseHandleFacade
{
    FCk_AutoTest_Inventory_TransferItem_BaseHandleFacade_SpawnParams Params()
    {
        return FCk_AutoTest_Inventory_TransferItem_BaseHandleFacade_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Inventory_TransferItemPayload_SpawnParams
{
}

namespace UCk_AutoTest_Inventory_TransferItemPayload
{
    FCk_AutoTest_Inventory_TransferItemPayload_SpawnParams Params()
    {
        return FCk_AutoTest_Inventory_TransferItemPayload_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Inventory_TryGet_Inventory_ByName_SpawnParams
{
}

namespace UCk_AutoTest_Inventory_TryGet_Inventory_ByName
{
    FCk_AutoTest_Inventory_TryGet_Inventory_ByName_SpawnParams Params()
    {
        return FCk_AutoTest_Inventory_TryGet_Inventory_ByName_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_IskmRenderer_AnimationFinishes_SpawnParams
{
}

namespace UCk_AutoTest_IskmRenderer_AnimationFinishes
{
    FCk_AutoTest_IskmRenderer_AnimationFinishes_SpawnParams Params()
    {
        return FCk_AutoTest_IskmRenderer_AnimationFinishes_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_IskmRenderer_AnimationPlayback_SpawnParams
{
}

namespace UCk_AutoTest_IskmRenderer_AnimationPlayback
{
    FCk_AutoTest_IskmRenderer_AnimationPlayback_SpawnParams Params()
    {
        return FCk_AutoTest_IskmRenderer_AnimationPlayback_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_IskmRenderer_AnimBP_SpawnParams
{
}

namespace UCk_AutoTest_IskmRenderer_AnimBP
{
    FCk_AutoTest_IskmRenderer_AnimBP_SpawnParams Params()
    {
        return FCk_AutoTest_IskmRenderer_AnimBP_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_IskmRenderer_AsyncLoad_SpawnParams
{
}

namespace UCk_AutoTest_IskmRenderer_AsyncLoad
{
    FCk_AutoTest_IskmRenderer_AsyncLoad_SpawnParams Params()
    {
        return FCk_AutoTest_IskmRenderer_AsyncLoad_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_IskmRenderer_CustomData_SpawnParams
{
}

namespace UCk_AutoTest_IskmRenderer_CustomData
{
    FCk_AutoTest_IskmRenderer_CustomData_SpawnParams Params()
    {
        return FCk_AutoTest_IskmRenderer_CustomData_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_IskmRenderer_CustomDataSuccess_SpawnParams
{
}

namespace UCk_AutoTest_IskmRenderer_CustomDataSuccess
{
    FCk_AutoTest_IskmRenderer_CustomDataSuccess_SpawnParams Params()
    {
        return FCk_AutoTest_IskmRenderer_CustomDataSuccess_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_IskmRenderer_Montage_SpawnParams
{
}

namespace UCk_AutoTest_IskmRenderer_Montage
{
    FCk_AutoTest_IskmRenderer_Montage_SpawnParams Params()
    {
        return FCk_AutoTest_IskmRenderer_Montage_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_IskmRenderer_MontageNotify_SpawnParams
{
}

namespace UCk_AutoTest_IskmRenderer_MontageNotify
{
    FCk_AutoTest_IskmRenderer_MontageNotify_SpawnParams Params()
    {
        return FCk_AutoTest_IskmRenderer_MontageNotify_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_IskmRenderer_OutfitAttach_SpawnParams
{
}

namespace UCk_AutoTest_IskmRenderer_OutfitAttach
{
    FCk_AutoTest_IskmRenderer_OutfitAttach_SpawnParams Params()
    {
        return FCk_AutoTest_IskmRenderer_OutfitAttach_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_IskmRenderer_OutfitSubmesh_SpawnParams
{
}

namespace UCk_AutoTest_IskmRenderer_OutfitSubmesh
{
    FCk_AutoTest_IskmRenderer_OutfitSubmesh_SpawnParams Params()
    {
        return FCk_AutoTest_IskmRenderer_OutfitSubmesh_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_IskmRenderer_PdaSmoke_SpawnParams
{
}

namespace UCk_AutoTest_IskmRenderer_PdaSmoke
{
    FCk_AutoTest_IskmRenderer_PdaSmoke_SpawnParams Params()
    {
        return FCk_AutoTest_IskmRenderer_PdaSmoke_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_IskmRenderer_PlayAnimationReissue_SpawnParams
{
}

namespace UCk_AutoTest_IskmRenderer_PlayAnimationReissue
{
    FCk_AutoTest_IskmRenderer_PlayAnimationReissue_SpawnParams Params()
    {
        return FCk_AutoTest_IskmRenderer_PlayAnimationReissue_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_IskmRenderer_ProxyAdd_SpawnParams
{
}

namespace UCk_AutoTest_IskmRenderer_ProxyAdd
{
    FCk_AutoTest_IskmRenderer_ProxyAdd_SpawnParams Params()
    {
        return FCk_AutoTest_IskmRenderer_ProxyAdd_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_IskmRenderer_Ragdoll_SpawnParams
{
}

namespace UCk_AutoTest_IskmRenderer_Ragdoll
{
    FCk_AutoTest_IskmRenderer_Ragdoll_SpawnParams Params()
    {
        return FCk_AutoTest_IskmRenderer_Ragdoll_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_IskmRenderer_RagdollPoseSource_SpawnParams
{
}

namespace UCk_AutoTest_IskmRenderer_RagdollPoseSource
{
    FCk_AutoTest_IskmRenderer_RagdollPoseSource_SpawnParams Params()
    {
        return FCk_AutoTest_IskmRenderer_RagdollPoseSource_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_IskmRenderer_RendererAdd_SpawnParams
{
}

namespace UCk_AutoTest_IskmRenderer_RendererAdd
{
    FCk_AutoTest_IskmRenderer_RendererAdd_SpawnParams Params()
    {
        return FCk_AutoTest_IskmRenderer_RendererAdd_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_IskmRenderer_Sockets_SpawnParams
{
}

namespace UCk_AutoTest_IskmRenderer_Sockets
{
    FCk_AutoTest_IskmRenderer_Sockets_SpawnParams Params()
    {
        return FCk_AutoTest_IskmRenderer_Sockets_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_IskmRenderer_SubsystemSmoke_SpawnParams
{
}

namespace UCk_AutoTest_IskmRenderer_SubsystemSmoke
{
    FCk_AutoTest_IskmRenderer_SubsystemSmoke_SpawnParams Params()
    {
        return FCk_AutoTest_IskmRenderer_SubsystemSmoke_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_IskmRenderer_TransitionReplaced_SpawnParams
{
}

namespace UCk_AutoTest_IskmRenderer_TransitionReplaced
{
    FCk_AutoTest_IskmRenderer_TransitionReplaced_SpawnParams Params()
    {
        return FCk_AutoTest_IskmRenderer_TransitionReplaced_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Label_AddAndQuery_SpawnParams
{
}

namespace UCk_AutoTest_Label_AddAndQuery
{
    FCk_AutoTest_Label_AddAndQuery_SpawnParams Params()
    {
        return FCk_AutoTest_Label_AddAndQuery_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Label_AddIsSetOnce_RejectsSecondAdd_SpawnParams
{
}

namespace UCk_AutoTest_Label_AddIsSetOnce_RejectsSecondAdd
{
    FCk_AutoTest_Label_AddIsSetOnce_RejectsSecondAdd_SpawnParams Params()
    {
        return FCk_AutoTest_Label_AddIsSetOnce_RejectsSecondAdd_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Label_HierarchicalMatching_SpawnParams
{
}

namespace UCk_AutoTest_Label_HierarchicalMatching
{
    FCk_AutoTest_Label_HierarchicalMatching_SpawnParams Params()
    {
        return FCk_AutoTest_Label_HierarchicalMatching_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Label_MatchesAny_FromContainer_SpawnParams
{
}

namespace UCk_AutoTest_Label_MatchesAny_FromContainer
{
    FCk_AutoTest_Label_MatchesAny_FromContainer_SpawnParams Params()
    {
        return FCk_AutoTest_Label_MatchesAny_FromContainer_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Messaging_BasicBroadcast_SpawnParams
{
}

namespace UCk_AutoTest_Messaging_BasicBroadcast
{
    FCk_AutoTest_Messaging_BasicBroadcast_SpawnParams Params()
    {
        return FCk_AutoTest_Messaging_BasicBroadcast_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Messaging_BindingPolicyInFlight_SpawnParams
{
}

namespace UCk_AutoTest_Messaging_BindingPolicyInFlight
{
    FCk_AutoTest_Messaging_BindingPolicyInFlight_SpawnParams Params()
    {
        return FCk_AutoTest_Messaging_BindingPolicyInFlight_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Messaging_MultiListener_SpawnParams
{
}

namespace UCk_AutoTest_Messaging_MultiListener
{
    FCk_AutoTest_Messaging_MultiListener_SpawnParams Params()
    {
        return FCk_AutoTest_Messaging_MultiListener_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Messaging_MultipleTypes_SpawnParams
{
}

namespace UCk_AutoTest_Messaging_MultipleTypes
{
    FCk_AutoTest_Messaging_MultipleTypes_SpawnParams Params()
    {
        return FCk_AutoTest_Messaging_MultipleTypes_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Messaging_PostFireUnbind_SpawnParams
{
}

namespace UCk_AutoTest_Messaging_PostFireUnbind
{
    FCk_AutoTest_Messaging_PostFireUnbind_SpawnParams Params()
    {
        return FCk_AutoTest_Messaging_PostFireUnbind_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Messaging_Unbind_SpawnParams
{
}

namespace UCk_AutoTest_Messaging_Unbind
{
    FCk_AutoTest_Messaging_Unbind_SpawnParams Params()
    {
        return FCk_AutoTest_Messaging_Unbind_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Nav_PathQueuedDuringBake_SpawnParams
{
}

namespace UCk_AutoTest_Nav_PathQueuedDuringBake
{
    FCk_AutoTest_Nav_PathQueuedDuringBake_SpawnParams Params()
    {
        return FCk_AutoTest_Nav_PathQueuedDuringBake_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_ObjectiveOwner_Add_CreatesFeature_SpawnParams
{
}

namespace UCk_AutoTest_ObjectiveOwner_Add_CreatesFeature
{
    FCk_AutoTest_ObjectiveOwner_Add_CreatesFeature_SpawnParams Params()
    {
        return FCk_AutoTest_ObjectiveOwner_Add_CreatesFeature_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Pmg_DrawFilledBox_ReturnsValidHandle_SpawnParams
{
}

namespace UCk_AutoTest_Pmg_DrawFilledBox_ReturnsValidHandle
{
    FCk_AutoTest_Pmg_DrawFilledBox_ReturnsValidHandle_SpawnParams Params()
    {
        return FCk_AutoTest_Pmg_DrawFilledBox_ReturnsValidHandle_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Pmg_DrawFilledSphere_ReturnsValidHandle_SpawnParams
{
}

namespace UCk_AutoTest_Pmg_DrawFilledSphere_ReturnsValidHandle
{
    FCk_AutoTest_Pmg_DrawFilledSphere_ReturnsValidHandle_SpawnParams Params()
    {
        return FCk_AutoTest_Pmg_DrawFilledSphere_ReturnsValidHandle_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Probe_Add_Box_CreatesProbeEntity_SpawnParams
{
}

namespace UCk_AutoTest_Probe_Add_Box_CreatesProbeEntity
{
    FCk_AutoTest_Probe_Add_Box_CreatesProbeEntity_SpawnParams Params()
    {
        return FCk_AutoTest_Probe_Add_Box_CreatesProbeEntity_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Probe_Add_Sphere_CreatesProbeEntity_SpawnParams
{
}

namespace UCk_AutoTest_Probe_Add_Sphere_CreatesProbeEntity
{
    FCk_AutoTest_Probe_Add_Sphere_CreatesProbeEntity_SpawnParams Params()
    {
        return FCk_AutoTest_Probe_Add_Sphere_CreatesProbeEntity_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Probe_Get_ResponsePolicy_ReturnsConfigured_SpawnParams
{
}

namespace UCk_AutoTest_Probe_Get_ResponsePolicy_ReturnsConfigured
{
    FCk_AutoTest_Probe_Get_ResponsePolicy_ReturnsConfigured_SpawnParams Params()
    {
        return FCk_AutoTest_Probe_Get_ResponsePolicy_ReturnsConfigured_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Probe_GetName_ReturnsConfiguredTag_SpawnParams
{
}

namespace UCk_AutoTest_Probe_GetName_ReturnsConfiguredTag
{
    FCk_AutoTest_Probe_GetName_ReturnsConfiguredTag_SpawnParams Params()
    {
        return FCk_AutoTest_Probe_GetName_ReturnsConfiguredTag_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Probe_Request_EnableDisable_StateFlips_SpawnParams
{
}

namespace UCk_AutoTest_Probe_Request_EnableDisable_StateFlips
{
    FCk_AutoTest_Probe_Request_EnableDisable_StateFlips_SpawnParams Params()
    {
        return FCk_AutoTest_Probe_Request_EnableDisable_StateFlips_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_RaySense_Add_CreatesEntity_SpawnParams
{
}

namespace UCk_AutoTest_RaySense_Add_CreatesEntity
{
    FCk_AutoTest_RaySense_Add_CreatesEntity_SpawnParams Params()
    {
        return FCk_AutoTest_RaySense_Add_CreatesEntity_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Record_AddHasFeature_SpawnParams
{
}

namespace UCk_AutoTest_Record_AddHasFeature
{
    FCk_AutoTest_Record_AddHasFeature_SpawnParams Params()
    {
        return FCk_AutoTest_Record_AddHasFeature_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Record_ConnectDisconnectRoundTrip_SpawnParams
{
}

namespace UCk_AutoTest_Record_ConnectDisconnectRoundTrip
{
    FCk_AutoTest_Record_ConnectDisconnectRoundTrip_SpawnParams Params()
    {
        return FCk_AutoTest_Record_ConnectDisconnectRoundTrip_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Record_DestroyEntryPrunesFromRecord_SpawnParams
{
}

namespace UCk_AutoTest_Record_DestroyEntryPrunesFromRecord
{
    FCk_AutoTest_Record_DestroyEntryPrunesFromRecord_SpawnParams Params()
    {
        return FCk_AutoTest_Record_DestroyEntryPrunesFromRecord_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Record_GetValidEntryByTagFindsLabeled_SpawnParams
{
}

namespace UCk_AutoTest_Record_GetValidEntryByTagFindsLabeled
{
    FCk_AutoTest_Record_GetValidEntryByTagFindsLabeled_SpawnParams Params()
    {
        return FCk_AutoTest_Record_GetValidEntryByTagFindsLabeled_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Registry_AllocatorStress_SpawnParams
{
}

namespace UCk_AutoTest_Registry_AllocatorStress
{
    FCk_AutoTest_Registry_AllocatorStress_SpawnParams Params()
    {
        return FCk_AutoTest_Registry_AllocatorStress_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Registry_HandleCopyDestroy_SpawnParams
{
}

namespace UCk_AutoTest_Registry_HandleCopyDestroy
{
    FCk_AutoTest_Registry_HandleCopyDestroy_SpawnParams Params()
    {
        return FCk_AutoTest_Registry_HandleCopyDestroy_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Registry_HandleInFragmentLifecycle_SpawnParams
{
}

namespace UCk_AutoTest_Registry_HandleInFragmentLifecycle
{
    FCk_AutoTest_Registry_HandleInFragmentLifecycle_SpawnParams Params()
    {
        return FCk_AutoTest_Registry_HandleInFragmentLifecycle_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Relationship_AttitudeDifferentTeamsIsHostile_SpawnParams
{
}

namespace UCk_AutoTest_Relationship_AttitudeDifferentTeamsIsHostile
{
    FCk_AutoTest_Relationship_AttitudeDifferentTeamsIsHostile_SpawnParams Params()
    {
        return FCk_AutoTest_Relationship_AttitudeDifferentTeamsIsHostile_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Relationship_AttitudeNoTeamIsNeutral_SpawnParams
{
}

namespace UCk_AutoTest_Relationship_AttitudeNoTeamIsNeutral
{
    FCk_AutoTest_Relationship_AttitudeNoTeamIsNeutral_SpawnParams Params()
    {
        return FCk_AutoTest_Relationship_AttitudeNoTeamIsNeutral_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Relationship_AttitudeOneHasNoTeamIsNeutral_SpawnParams
{
}

namespace UCk_AutoTest_Relationship_AttitudeOneHasNoTeamIsNeutral
{
    FCk_AutoTest_Relationship_AttitudeOneHasNoTeamIsNeutral_SpawnParams Params()
    {
        return FCk_AutoTest_Relationship_AttitudeOneHasNoTeamIsNeutral_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Relationship_AttitudeOwnershipChainHostile_SpawnParams
{
}

namespace UCk_AutoTest_Relationship_AttitudeOwnershipChainHostile
{
    FCk_AutoTest_Relationship_AttitudeOwnershipChainHostile_SpawnParams Params()
    {
        return FCk_AutoTest_Relationship_AttitudeOwnershipChainHostile_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Relationship_AttitudeSameTeamIsFriendly_SpawnParams
{
}

namespace UCk_AutoTest_Relationship_AttitudeSameTeamIsFriendly
{
    FCk_AutoTest_Relationship_AttitudeSameTeamIsFriendly_SpawnParams Params()
    {
        return FCk_AutoTest_Relationship_AttitudeSameTeamIsFriendly_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Relationship_AttitudeSelfIsFriendly_SpawnParams
{
}

namespace UCk_AutoTest_Relationship_AttitudeSelfIsFriendly
{
    FCk_AutoTest_Relationship_AttitudeSelfIsFriendly_SpawnParams Params()
    {
        return FCk_AutoTest_Relationship_AttitudeSelfIsFriendly_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Relationship_Team_AddDefaultUnassigned_SpawnParams
{
}

namespace UCk_AutoTest_Relationship_Team_AddDefaultUnassigned
{
    FCk_AutoTest_Relationship_Team_AddDefaultUnassigned_SpawnParams Params()
    {
        return FCk_AutoTest_Relationship_Team_AddDefaultUnassigned_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Relationship_Team_AddHappyPath_SpawnParams
{
}

namespace UCk_AutoTest_Relationship_Team_AddHappyPath
{
    FCk_AutoTest_Relationship_Team_AddHappyPath_SpawnParams Params()
    {
        return FCk_AutoTest_Relationship_Team_AddHappyPath_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Relationship_Team_AssignChanges_SpawnParams
{
}

namespace UCk_AutoTest_Relationship_Team_AssignChanges
{
    FCk_AutoTest_Relationship_Team_AssignChanges_SpawnParams Params()
    {
        return FCk_AutoTest_Relationship_Team_AssignChanges_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Relationship_Team_AssignShiftsIsAssignedTo_SpawnParams
{
}

namespace UCk_AutoTest_Relationship_Team_AssignShiftsIsAssignedTo
{
    FCk_AutoTest_Relationship_Team_AssignShiftsIsAssignedTo_SpawnParams Params()
    {
        return FCk_AutoTest_Relationship_Team_AssignShiftsIsAssignedTo_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Relationship_Team_GetIsAssignedTo_SpawnParams
{
}

namespace UCk_AutoTest_Relationship_Team_GetIsAssignedTo
{
    FCk_AutoTest_Relationship_Team_GetIsAssignedTo_SpawnParams Params()
    {
        return FCk_AutoTest_Relationship_Team_GetIsAssignedTo_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Relationship_Team_GetIsSame_False_SpawnParams
{
}

namespace UCk_AutoTest_Relationship_Team_GetIsSame_False
{
    FCk_AutoTest_Relationship_Team_GetIsSame_False_SpawnParams Params()
    {
        return FCk_AutoTest_Relationship_Team_GetIsSame_False_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Relationship_Team_GetIsSame_True_SpawnParams
{
}

namespace UCk_AutoTest_Relationship_Team_GetIsSame_True
{
    FCk_AutoTest_Relationship_Team_GetIsSame_True_SpawnParams Params()
    {
        return FCk_AutoTest_Relationship_Team_GetIsSame_True_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Relationship_Team_HasFalseBeforeAdd_SpawnParams
{
}

namespace UCk_AutoTest_Relationship_Team_HasFalseBeforeAdd
{
    FCk_AutoTest_Relationship_Team_HasFalseBeforeAdd_SpawnParams Params()
    {
        return FCk_AutoTest_Relationship_Team_HasFalseBeforeAdd_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Relationship_Team_TryGetInOwnershipChainFromOwner_SpawnParams
{
}

namespace UCk_AutoTest_Relationship_Team_TryGetInOwnershipChainFromOwner
{
    FCk_AutoTest_Relationship_Team_TryGetInOwnershipChainFromOwner_SpawnParams Params()
    {
        return FCk_AutoTest_Relationship_Team_TryGetInOwnershipChainFromOwner_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Relationship_Team_TryGetInOwnershipChainNoTeam_SpawnParams
{
}

namespace UCk_AutoTest_Relationship_Team_TryGetInOwnershipChainNoTeam
{
    FCk_AutoTest_Relationship_Team_TryGetInOwnershipChainNoTeam_SpawnParams Params()
    {
        return FCk_AutoTest_Relationship_Team_TryGetInOwnershipChainNoTeam_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Relationship_Team_UnassignSetsUnassigned_SpawnParams
{
}

namespace UCk_AutoTest_Relationship_Team_UnassignSetsUnassigned
{
    FCk_AutoTest_Relationship_Team_UnassignSetsUnassigned_SpawnParams Params()
    {
        return FCk_AutoTest_Relationship_Team_UnassignSetsUnassigned_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Resolver_Source_AddHappyPath_SpawnParams
{
}

namespace UCk_AutoTest_Resolver_Source_AddHappyPath
{
    FCk_AutoTest_Resolver_Source_AddHappyPath_SpawnParams Params()
    {
        return FCk_AutoTest_Resolver_Source_AddHappyPath_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Resolver_Source_CreateHappyPath_SpawnParams
{
}

namespace UCk_AutoTest_Resolver_Source_CreateHappyPath
{
    FCk_AutoTest_Resolver_Source_CreateHappyPath_SpawnParams Params()
    {
        return FCk_AutoTest_Resolver_Source_CreateHappyPath_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Resolver_Source_CreateTransientHappyPath_SpawnParams
{
}

namespace UCk_AutoTest_Resolver_Source_CreateTransientHappyPath
{
    FCk_AutoTest_Resolver_Source_CreateTransientHappyPath_SpawnParams Params()
    {
        return FCk_AutoTest_Resolver_Source_CreateTransientHappyPath_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Resolver_Source_ForEachDataBundleEmpty_SpawnParams
{
}

namespace UCk_AutoTest_Resolver_Source_ForEachDataBundleEmpty
{
    FCk_AutoTest_Resolver_Source_ForEachDataBundleEmpty_SpawnParams Params()
    {
        return FCk_AutoTest_Resolver_Source_ForEachDataBundleEmpty_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Resolver_Source_HasFalseBeforeAdd_SpawnParams
{
}

namespace UCk_AutoTest_Resolver_Source_HasFalseBeforeAdd
{
    FCk_AutoTest_Resolver_Source_HasFalseBeforeAdd_SpawnParams Params()
    {
        return FCk_AutoTest_Resolver_Source_HasFalseBeforeAdd_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Resolver_Target_AddHappyPath_SpawnParams
{
}

namespace UCk_AutoTest_Resolver_Target_AddHappyPath
{
    FCk_AutoTest_Resolver_Target_AddHappyPath_SpawnParams Params()
    {
        return FCk_AutoTest_Resolver_Target_AddHappyPath_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Resolver_Target_CreateHappyPath_SpawnParams
{
}

namespace UCk_AutoTest_Resolver_Target_CreateHappyPath
{
    FCk_AutoTest_Resolver_Target_CreateHappyPath_SpawnParams Params()
    {
        return FCk_AutoTest_Resolver_Target_CreateHappyPath_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Resolver_Target_CreateTransientHappyPath_SpawnParams
{
}

namespace UCk_AutoTest_Resolver_Target_CreateTransientHappyPath
{
    FCk_AutoTest_Resolver_Target_CreateTransientHappyPath_SpawnParams Params()
    {
        return FCk_AutoTest_Resolver_Target_CreateTransientHappyPath_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Resolver_Target_ForEachDataBundleEmpty_SpawnParams
{
}

namespace UCk_AutoTest_Resolver_Target_ForEachDataBundleEmpty
{
    FCk_AutoTest_Resolver_Target_ForEachDataBundleEmpty_SpawnParams Params()
    {
        return FCk_AutoTest_Resolver_Target_ForEachDataBundleEmpty_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Resolver_Target_HasFalseBeforeAdd_SpawnParams
{
}

namespace UCk_AutoTest_Resolver_Target_HasFalseBeforeAdd
{
    FCk_AutoTest_Resolver_Target_HasFalseBeforeAdd_SpawnParams Params()
    {
        return FCk_AutoTest_Resolver_Target_HasFalseBeforeAdd_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_SceneNode_ActorAttachedToActor_SpawnParams
{
}

namespace UCk_AutoTest_SceneNode_ActorAttachedToActor
{
    FCk_AutoTest_SceneNode_ActorAttachedToActor_SpawnParams Params()
    {
        return FCk_AutoTest_SceneNode_ActorAttachedToActor_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_SceneNode_AttachedActor_EntityScript_SpawnParams
{
    UPROPERTY()
    const TObjectPtr<AActor> _OwningActor = nullptr;

    FCk_AutoTest_SceneNode_AttachedActor_EntityScript_SpawnParams(const TObjectPtr<AActor> In_OwningActor)
    {
        _OwningActor = In_OwningActor;
    }
}

namespace UCk_AutoTest_SceneNode_AttachedActor_EntityScript
{
    FCk_AutoTest_SceneNode_AttachedActor_EntityScript_SpawnParams Params()
    {
        return FCk_AutoTest_SceneNode_AttachedActor_EntityScript_SpawnParams();
    }

    FCk_AutoTest_SceneNode_AttachedActor_EntityScript_SpawnParams Params(const TObjectPtr<AActor> In_OwningActor)
    {
        return FCk_AutoTest_SceneNode_AttachedActor_EntityScript_SpawnParams(In_OwningActor);
    }
}

USTRUCT()
struct FCk_AutoTest_SceneNode_BareChildOfBareParent_SpawnParams
{
}

namespace UCk_AutoTest_SceneNode_BareChildOfBareParent
{
    FCk_AutoTest_SceneNode_BareChildOfBareParent_SpawnParams Params()
    {
        return FCk_AutoTest_SceneNode_BareChildOfBareParent_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_SceneNode_DeepHierarchy_SpawnParams
{
}

namespace UCk_AutoTest_SceneNode_DeepHierarchy
{
    FCk_AutoTest_SceneNode_DeepHierarchy_SpawnParams Params()
    {
        return FCk_AutoTest_SceneNode_DeepHierarchy_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_SceneNode_MeshSocketAnchor_SpawnParams
{
}

namespace UCk_AutoTest_SceneNode_MeshSocketAnchor
{
    FCk_AutoTest_SceneNode_MeshSocketAnchor_SpawnParams Params()
    {
        return FCk_AutoTest_SceneNode_MeshSocketAnchor_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_SceneNode_MultipleChildren_SpawnParams
{
}

namespace UCk_AutoTest_SceneNode_MultipleChildren
{
    FCk_AutoTest_SceneNode_MultipleChildren_SpawnParams Params()
    {
        return FCk_AutoTest_SceneNode_MultipleChildren_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_SceneNode_NonUniformScalePropagation_SpawnParams
{
}

namespace UCk_AutoTest_SceneNode_NonUniformScalePropagation
{
    FCk_AutoTest_SceneNode_NonUniformScalePropagation_SpawnParams Params()
    {
        return FCk_AutoTest_SceneNode_NonUniformScalePropagation_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_SceneNode_OffsetUpdates_SpawnParams
{
}

namespace UCk_AutoTest_SceneNode_OffsetUpdates
{
    FCk_AutoTest_SceneNode_OffsetUpdates_SpawnParams Params()
    {
        return FCk_AutoTest_SceneNode_OffsetUpdates_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_SceneNode_ParentDestroyCascade_SpawnParams
{
}

namespace UCk_AutoTest_SceneNode_ParentDestroyCascade
{
    FCk_AutoTest_SceneNode_ParentDestroyCascade_SpawnParams Params()
    {
        return FCk_AutoTest_SceneNode_ParentDestroyCascade_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_SceneNodeTween_Depth0_LeafMatchesExpected_SpawnParams
{
}

namespace UCk_AutoTest_SceneNodeTween_Depth0_LeafMatchesExpected
{
    FCk_AutoTest_SceneNodeTween_Depth0_LeafMatchesExpected_SpawnParams Params()
    {
        return FCk_AutoTest_SceneNodeTween_Depth0_LeafMatchesExpected_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_SceneNodeTween_Depth1_LeafMatchesExpected_SpawnParams
{
}

namespace UCk_AutoTest_SceneNodeTween_Depth1_LeafMatchesExpected
{
    FCk_AutoTest_SceneNodeTween_Depth1_LeafMatchesExpected_SpawnParams Params()
    {
        return FCk_AutoTest_SceneNodeTween_Depth1_LeafMatchesExpected_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_SceneNodeTween_Depth4_LeafMatchesExpected_SpawnParams
{
}

namespace UCk_AutoTest_SceneNodeTween_Depth4_LeafMatchesExpected
{
    FCk_AutoTest_SceneNodeTween_Depth4_LeafMatchesExpected_SpawnParams Params()
    {
        return FCk_AutoTest_SceneNodeTween_Depth4_LeafMatchesExpected_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_SceneNodeTween_NonUniformScalePropagatesToLeaf_SpawnParams
{
}

namespace UCk_AutoTest_SceneNodeTween_NonUniformScalePropagatesToLeaf
{
    FCk_AutoTest_SceneNodeTween_NonUniformScalePropagatesToLeaf_SpawnParams Params()
    {
        return FCk_AutoTest_SceneNodeTween_NonUniformScalePropagatesToLeaf_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_SceneNodeTween_RootDestroyDuringTween_ChildrenCleanedUp_SpawnParams
{
}

namespace UCk_AutoTest_SceneNodeTween_RootDestroyDuringTween_ChildrenCleanedUp
{
    FCk_AutoTest_SceneNodeTween_RootDestroyDuringTween_ChildrenCleanedUp_SpawnParams Params()
    {
        return FCk_AutoTest_SceneNodeTween_RootDestroyDuringTween_ChildrenCleanedUp_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_SceneNodeTween_RotationTween_OrientsLeafCorrectly_SpawnParams
{
}

namespace UCk_AutoTest_SceneNodeTween_RotationTween_OrientsLeafCorrectly
{
    FCk_AutoTest_SceneNodeTween_RotationTween_OrientsLeafCorrectly_SpawnParams Params()
    {
        return FCk_AutoTest_SceneNodeTween_RotationTween_OrientsLeafCorrectly_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_SceneNodeTween_TweenCompletes_LeafLandsAtTarget_SpawnParams
{
}

namespace UCk_AutoTest_SceneNodeTween_TweenCompletes_LeafLandsAtTarget
{
    FCk_AutoTest_SceneNodeTween_TweenCompletes_LeafLandsAtTarget_SpawnParams Params()
    {
        return FCk_AutoTest_SceneNodeTween_TweenCompletes_LeafLandsAtTarget_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_SceneNodeTween_TweenLoopYoyo_LeafTracksBoth_SpawnParams
{
}

namespace UCk_AutoTest_SceneNodeTween_TweenLoopYoyo_LeafTracksBoth
{
    FCk_AutoTest_SceneNodeTween_TweenLoopYoyo_LeafTracksBoth_SpawnParams Params()
    {
        return FCk_AutoTest_SceneNodeTween_TweenLoopYoyo_LeafTracksBoth_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Shape_Box_Add_RoundTripsHalfExtents_SpawnParams
{
}

namespace UCk_AutoTest_Shape_Box_Add_RoundTripsHalfExtents
{
    FCk_AutoTest_Shape_Box_Add_RoundTripsHalfExtents_SpawnParams Params()
    {
        return FCk_AutoTest_Shape_Box_Add_RoundTripsHalfExtents_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Shape_Capsule_Add_RoundTripsDimensions_SpawnParams
{
}

namespace UCk_AutoTest_Shape_Capsule_Add_RoundTripsDimensions
{
    FCk_AutoTest_Shape_Capsule_Add_RoundTripsDimensions_SpawnParams Params()
    {
        return FCk_AutoTest_Shape_Capsule_Add_RoundTripsDimensions_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Shape_Sphere_Add_RoundTripsRadius_SpawnParams
{
}

namespace UCk_AutoTest_Shape_Sphere_Add_RoundTripsRadius
{
    FCk_AutoTest_Shape_Sphere_Add_RoundTripsRadius_SpawnParams Params()
    {
        return FCk_AutoTest_Shape_Sphere_Add_RoundTripsRadius_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_StateMachine_AddOverrideState_ReplacesBaseState_SpawnParams
{
}

namespace UCk_AutoTest_StateMachine_AddOverrideState_ReplacesBaseState
{
    FCk_AutoTest_StateMachine_AddOverrideState_ReplacesBaseState_SpawnParams Params()
    {
        return FCk_AutoTest_StateMachine_AddOverrideState_ReplacesBaseState_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_StateMachine_AlwaysTrueCondition_PassesImmediately_SpawnParams
{
}

namespace UCk_AutoTest_StateMachine_AlwaysTrueCondition_PassesImmediately
{
    FCk_AutoTest_StateMachine_AlwaysTrueCondition_PassesImmediately_SpawnParams Params()
    {
        return FCk_AutoTest_StateMachine_AlwaysTrueCondition_PassesImmediately_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_StateMachine_BasicTransition_SpawnParams
{
}

namespace UCk_AutoTest_StateMachine_BasicTransition
{
    FCk_AutoTest_StateMachine_BasicTransition_SpawnParams Params()
    {
        return FCk_AutoTest_StateMachine_BasicTransition_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_StateMachine_DivergenceFirstBranch_SpawnParams
{
}

namespace UCk_AutoTest_StateMachine_DivergenceFirstBranch
{
    FCk_AutoTest_StateMachine_DivergenceFirstBranch_SpawnParams Params()
    {
        return FCk_AutoTest_StateMachine_DivergenceFirstBranch_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_StateMachine_DivergenceFirstBranchTimed_SpawnParams
{
}

namespace UCk_AutoTest_StateMachine_DivergenceFirstBranchTimed
{
    FCk_AutoTest_StateMachine_DivergenceFirstBranchTimed_SpawnParams Params()
    {
        return FCk_AutoTest_StateMachine_DivergenceFirstBranchTimed_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_StateMachine_EventDrivenMultiCondition_SpawnParams
{
}

namespace UCk_AutoTest_StateMachine_EventDrivenMultiCondition
{
    FCk_AutoTest_StateMachine_EventDrivenMultiCondition_SpawnParams Params()
    {
        return FCk_AutoTest_StateMachine_EventDrivenMultiCondition_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_StateMachine_HierarchicalFirstTransition_SpawnParams
{
}

namespace UCk_AutoTest_StateMachine_HierarchicalFirstTransition
{
    FCk_AutoTest_StateMachine_HierarchicalFirstTransition_SpawnParams Params()
    {
        return FCk_AutoTest_StateMachine_HierarchicalFirstTransition_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_StateMachine_NegatedEventDrivenCondition_SpawnParams
{
}

namespace UCk_AutoTest_StateMachine_NegatedEventDrivenCondition
{
    FCk_AutoTest_StateMachine_NegatedEventDrivenCondition_SpawnParams Params()
    {
        return FCk_AutoTest_StateMachine_NegatedEventDrivenCondition_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_StateMachine_NoTransitionAvailable_StaysInState_SpawnParams
{
}

namespace UCk_AutoTest_StateMachine_NoTransitionAvailable_StaysInState
{
    FCk_AutoTest_StateMachine_NoTransitionAvailable_StaysInState_SpawnParams Params()
    {
        return FCk_AutoTest_StateMachine_NoTransitionAvailable_StaysInState_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_StateMachine_OnStateChanged_PayloadHasOldAndNew_SpawnParams
{
}

namespace UCk_AutoTest_StateMachine_OnStateChanged_PayloadHasOldAndNew
{
    FCk_AutoTest_StateMachine_OnStateChanged_PayloadHasOldAndNew_SpawnParams Params()
    {
        return FCk_AutoTest_StateMachine_OnStateChanged_PayloadHasOldAndNew_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_StateMachine_RacingEventDrivenTransitions_SpawnParams
{
}

namespace UCk_AutoTest_StateMachine_RacingEventDrivenTransitions
{
    FCk_AutoTest_StateMachine_RacingEventDrivenTransitions_SpawnParams Params()
    {
        return FCk_AutoTest_StateMachine_RacingEventDrivenTransitions_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_StateMachine_Stop_FiresOnStopped_SpawnParams
{
}

namespace UCk_AutoTest_StateMachine_Stop_FiresOnStopped
{
    FCk_AutoTest_StateMachine_Stop_FiresOnStopped_SpawnParams Params()
    {
        return FCk_AutoTest_StateMachine_Stop_FiresOnStopped_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_StateMachine_TransitionExitBeforeEnter_SpawnParams
{
}

namespace UCk_AutoTest_StateMachine_TransitionExitBeforeEnter
{
    FCk_AutoTest_StateMachine_TransitionExitBeforeEnter_SpawnParams Params()
    {
        return FCk_AutoTest_StateMachine_TransitionExitBeforeEnter_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_StateMachine_TransitionOrdering_SpawnParams
{
}

namespace UCk_AutoTest_StateMachine_TransitionOrdering
{
    FCk_AutoTest_StateMachine_TransitionOrdering_SpawnParams Params()
    {
        return FCk_AutoTest_StateMachine_TransitionOrdering_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Substep_Add_CreatesFeature_SpawnParams
{
}

namespace UCk_AutoTest_Substep_Add_CreatesFeature
{
    FCk_AutoTest_Substep_Add_CreatesFeature_SpawnParams Params()
    {
        return FCk_AutoTest_Substep_Add_CreatesFeature_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_TagSet_AddDuplicate_NoSignalFire_SpawnParams
{
}

namespace UCk_AutoTest_TagSet_AddDuplicate_NoSignalFire
{
    FCk_AutoTest_TagSet_AddDuplicate_NoSignalFire_SpawnParams Params()
    {
        return FCk_AutoTest_TagSet_AddDuplicate_NoSignalFire_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_TagSet_AddInitialAndQuery_SpawnParams
{
}

namespace UCk_AutoTest_TagSet_AddInitialAndQuery
{
    FCk_AutoTest_TagSet_AddInitialAndQuery_SpawnParams Params()
    {
        return FCk_AutoTest_TagSet_AddInitialAndQuery_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_TagSet_HasTag_HasAny_HasAll_SpawnParams
{
}

namespace UCk_AutoTest_TagSet_HasTag_HasAny_HasAll
{
    FCk_AutoTest_TagSet_HasTag_HasAny_HasAll_SpawnParams Params()
    {
        return FCk_AutoTest_TagSet_HasTag_HasAny_HasAll_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_TagSet_OnTagsChangedSignal_SpawnParams
{
}

namespace UCk_AutoTest_TagSet_OnTagsChangedSignal
{
    FCk_AutoTest_TagSet_OnTagsChangedSignal_SpawnParams Params()
    {
        return FCk_AutoTest_TagSet_OnTagsChangedSignal_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_TagSet_RemoveAbsent_NoSignalFire_SpawnParams
{
}

namespace UCk_AutoTest_TagSet_RemoveAbsent_NoSignalFire
{
    FCk_AutoTest_TagSet_RemoveAbsent_NoSignalFire_SpawnParams Params()
    {
        return FCk_AutoTest_TagSet_RemoveAbsent_NoSignalFire_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_TagSet_RequestAddRemove_SpawnParams
{
}

namespace UCk_AutoTest_TagSet_RequestAddRemove
{
    FCk_AutoTest_TagSet_RequestAddRemove_SpawnParams Params()
    {
        return FCk_AutoTest_TagSet_RequestAddRemove_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Targeting_CreateFromLocation_SpawnParams
{
}

namespace UCk_AutoTest_Targeting_CreateFromLocation
{
    FCk_AutoTest_Targeting_CreateFromLocation_SpawnParams Params()
    {
        return FCk_AutoTest_Targeting_CreateFromLocation_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Targeting_CreateFromLocationAndRotation_SpawnParams
{
}

namespace UCk_AutoTest_Targeting_CreateFromLocationAndRotation
{
    FCk_AutoTest_Targeting_CreateFromLocationAndRotation_SpawnParams Params()
    {
        return FCk_AutoTest_Targeting_CreateFromLocationAndRotation_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Targeting_CreateHappyPath_SpawnParams
{
}

namespace UCk_AutoTest_Targeting_CreateHappyPath
{
    FCk_AutoTest_Targeting_CreateHappyPath_SpawnParams Params()
    {
        return FCk_AutoTest_Targeting_CreateHappyPath_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Targeting_CreateTransientFromLocation_SpawnParams
{
}

namespace UCk_AutoTest_Targeting_CreateTransientFromLocation
{
    FCk_AutoTest_Targeting_CreateTransientFromLocation_SpawnParams Params()
    {
        return FCk_AutoTest_Targeting_CreateTransientFromLocation_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Targeting_CreateTransientFromLocationAndRotation_SpawnParams
{
}

namespace UCk_AutoTest_Targeting_CreateTransientFromLocationAndRotation
{
    FCk_AutoTest_Targeting_CreateTransientFromLocationAndRotation_SpawnParams Params()
    {
        return FCk_AutoTest_Targeting_CreateTransientFromLocationAndRotation_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Targeting_CreateTransientHappyPath_SpawnParams
{
}

namespace UCk_AutoTest_Targeting_CreateTransientHappyPath
{
    FCk_AutoTest_Targeting_CreateTransientHappyPath_SpawnParams Params()
    {
        return FCk_AutoTest_Targeting_CreateTransientHappyPath_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Targeting_LifetimeAfterOneFrameDestroysEntity_SpawnParams
{
}

namespace UCk_AutoTest_Targeting_LifetimeAfterOneFrameDestroysEntity
{
    FCk_AutoTest_Targeting_LifetimeAfterOneFrameDestroysEntity_SpawnParams Params()
    {
        return FCk_AutoTest_Targeting_LifetimeAfterOneFrameDestroysEntity_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Timer_BasicCompletion_SpawnParams
{
}

namespace UCk_AutoTest_Timer_BasicCompletion
{
    FCk_AutoTest_Timer_BasicCompletion_SpawnParams Params()
    {
        return FCk_AutoTest_Timer_BasicCompletion_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Timer_ChangeCountDirection_SpawnParams
{
}

namespace UCk_AutoTest_Timer_ChangeCountDirection
{
    FCk_AutoTest_Timer_ChangeCountDirection_SpawnParams Params()
    {
        return FCk_AutoTest_Timer_ChangeCountDirection_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Timer_CountdownCompletion_SpawnParams
{
}

namespace UCk_AutoTest_Timer_CountdownCompletion
{
    FCk_AutoTest_Timer_CountdownCompletion_SpawnParams Params()
    {
        return FCk_AutoTest_Timer_CountdownCompletion_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Timer_Get_CurrentTimerValue_DuringPause_SpawnParams
{
}

namespace UCk_AutoTest_Timer_Get_CurrentTimerValue_DuringPause
{
    FCk_AutoTest_Timer_Get_CurrentTimerValue_DuringPause_SpawnParams Params()
    {
        return FCk_AutoTest_Timer_Get_CurrentTimerValue_DuringPause_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Timer_Jump_Forward_SpawnParams
{
}

namespace UCk_AutoTest_Timer_Jump_Forward
{
    FCk_AutoTest_Timer_Jump_Forward_SpawnParams Params()
    {
        return FCk_AutoTest_Timer_Jump_Forward_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Timer_MultipleConcurrent_SpawnParams
{
}

namespace UCk_AutoTest_Timer_MultipleConcurrent
{
    FCk_AutoTest_Timer_MultipleConcurrent_SpawnParams Params()
    {
        return FCk_AutoTest_Timer_MultipleConcurrent_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Timer_OnUpdate_FiresEveryTickWhileActive_SpawnParams
{
}

namespace UCk_AutoTest_Timer_OnUpdate_FiresEveryTickWhileActive
{
    FCk_AutoTest_Timer_OnUpdate_FiresEveryTickWhileActive_SpawnParams Params()
    {
        return FCk_AutoTest_Timer_OnUpdate_FiresEveryTickWhileActive_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Timer_PauseHaltsElapsed_SpawnParams
{
}

namespace UCk_AutoTest_Timer_PauseHaltsElapsed
{
    FCk_AutoTest_Timer_PauseHaltsElapsed_SpawnParams Params()
    {
        return FCk_AutoTest_Timer_PauseHaltsElapsed_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Timer_RequestComplete_SpawnParams
{
}

namespace UCk_AutoTest_Timer_RequestComplete
{
    FCk_AutoTest_Timer_RequestComplete_SpawnParams Params()
    {
        return FCk_AutoTest_Timer_RequestComplete_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Timer_RequestConsume_SpawnParams
{
}

namespace UCk_AutoTest_Timer_RequestConsume
{
    FCk_AutoTest_Timer_RequestConsume_SpawnParams Params()
    {
        return FCk_AutoTest_Timer_RequestConsume_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Timer_ResetMidFlight_SpawnParams
{
}

namespace UCk_AutoTest_Timer_ResetMidFlight
{
    FCk_AutoTest_Timer_ResetMidFlight_SpawnParams Params()
    {
        return FCk_AutoTest_Timer_ResetMidFlight_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Timer_ResetOnDone_SpawnParams
{
}

namespace UCk_AutoTest_Timer_ResetOnDone
{
    FCk_AutoTest_Timer_ResetOnDone_SpawnParams Params()
    {
        return FCk_AutoTest_Timer_ResetOnDone_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Timer_ResumeAfterPause_SpawnParams
{
}

namespace UCk_AutoTest_Timer_ResumeAfterPause
{
    FCk_AutoTest_Timer_ResumeAfterPause_SpawnParams Params()
    {
        return FCk_AutoTest_Timer_ResumeAfterPause_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Timer_ReverseDirection_MidFlight_SpawnParams
{
}

namespace UCk_AutoTest_Timer_ReverseDirection_MidFlight
{
    FCk_AutoTest_Timer_ReverseDirection_MidFlight_SpawnParams Params()
    {
        return FCk_AutoTest_Timer_ReverseDirection_MidFlight_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Timer_StopOnDone_SpawnParams
{
}

namespace UCk_AutoTest_Timer_StopOnDone
{
    FCk_AutoTest_Timer_StopOnDone_SpawnParams Params()
    {
        return FCk_AutoTest_Timer_StopOnDone_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Timer_TryGet_Timer_ByName_AmongMultiple_SpawnParams
{
}

namespace UCk_AutoTest_Timer_TryGet_Timer_ByName_AmongMultiple
{
    FCk_AutoTest_Timer_TryGet_Timer_ByName_AmongMultiple_SpawnParams Params()
    {
        return FCk_AutoTest_Timer_TryGet_Timer_ByName_AmongMultiple_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Transform_AddInitial_SpawnParams
{
}

namespace UCk_AutoTest_Transform_AddInitial
{
    FCk_AutoTest_Transform_AddInitial_SpawnParams Params()
    {
        return FCk_AutoTest_Transform_AddInitial_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Transform_AddLocationOffset_SpawnParams
{
}

namespace UCk_AutoTest_Transform_AddLocationOffset
{
    FCk_AutoTest_Transform_AddLocationOffset_SpawnParams Params()
    {
        return FCk_AutoTest_Transform_AddLocationOffset_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Transform_ForceRefreshRebroadcasts_SpawnParams
{
}

namespace UCk_AutoTest_Transform_ForceRefreshRebroadcasts
{
    FCk_AutoTest_Transform_ForceRefreshRebroadcasts_SpawnParams Params()
    {
        return FCk_AutoTest_Transform_ForceRefreshRebroadcasts_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Transform_OnUpdateFires_SpawnParams
{
}

namespace UCk_AutoTest_Transform_OnUpdateFires
{
    FCk_AutoTest_Transform_OnUpdateFires_SpawnParams Params()
    {
        return FCk_AutoTest_Transform_OnUpdateFires_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Transform_SetLocation_SpawnParams
{
}

namespace UCk_AutoTest_Transform_SetLocation
{
    FCk_AutoTest_Transform_SetLocation_SpawnParams Params()
    {
        return FCk_AutoTest_Transform_SetLocation_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Transform_SetLocationAndRotationAtomic_SpawnParams
{
}

namespace UCk_AutoTest_Transform_SetLocationAndRotationAtomic
{
    FCk_AutoTest_Transform_SetLocationAndRotationAtomic_SpawnParams Params()
    {
        return FCk_AutoTest_Transform_SetLocationAndRotationAtomic_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Transform_SetRotation_SpawnParams
{
}

namespace UCk_AutoTest_Transform_SetRotation
{
    FCk_AutoTest_Transform_SetRotation_SpawnParams Params()
    {
        return FCk_AutoTest_Transform_SetRotation_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Transform_SetScale_SpawnParams
{
}

namespace UCk_AutoTest_Transform_SetScale
{
    FCk_AutoTest_Transform_SetScale_SpawnParams Params()
    {
        return FCk_AutoTest_Transform_SetScale_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_TransformInterpolation_LocationLerps_SpawnParams
{
}

namespace UCk_AutoTest_TransformInterpolation_LocationLerps
{
    FCk_AutoTest_TransformInterpolation_LocationLerps_SpawnParams Params()
    {
        return FCk_AutoTest_TransformInterpolation_LocationLerps_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Tween_CompletionBehavior_KeepEntity_SpawnParams
{
}

namespace UCk_AutoTest_Tween_CompletionBehavior_KeepEntity
{
    FCk_AutoTest_Tween_CompletionBehavior_KeepEntity_SpawnParams Params()
    {
        return FCk_AutoTest_Tween_CompletionBehavior_KeepEntity_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Tween_EasingCurve_OutCubic_VsLinear_SpawnParams
{
}

namespace UCk_AutoTest_Tween_EasingCurve_OutCubic_VsLinear
{
    FCk_AutoTest_Tween_EasingCurve_OutCubic_VsLinear_SpawnParams Params()
    {
        return FCk_AutoTest_Tween_EasingCurve_OutCubic_VsLinear_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Tween_FloatCompletion_SpawnParams
{
}

namespace UCk_AutoTest_Tween_FloatCompletion
{
    FCk_AutoTest_Tween_FloatCompletion_SpawnParams Params()
    {
        return FCk_AutoTest_Tween_FloatCompletion_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Tween_FloatUpdateCallback_SpawnParams
{
}

namespace UCk_AutoTest_Tween_FloatUpdateCallback
{
    FCk_AutoTest_Tween_FloatUpdateCallback_SpawnParams Params()
    {
        return FCk_AutoTest_Tween_FloatUpdateCallback_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Tween_LinearColorCompletion_SpawnParams
{
}

namespace UCk_AutoTest_Tween_LinearColorCompletion
{
    FCk_AutoTest_Tween_LinearColorCompletion_SpawnParams Params()
    {
        return FCk_AutoTest_Tween_LinearColorCompletion_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Tween_LoopCount_Finite_SpawnParams
{
}

namespace UCk_AutoTest_Tween_LoopCount_Finite
{
    FCk_AutoTest_Tween_LoopCount_Finite_SpawnParams Params()
    {
        return FCk_AutoTest_Tween_LoopCount_Finite_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Tween_LoopRestart_SpawnParams
{
}

namespace UCk_AutoTest_Tween_LoopRestart
{
    FCk_AutoTest_Tween_LoopRestart_SpawnParams Params()
    {
        return FCk_AutoTest_Tween_LoopRestart_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Tween_RotatorCompletion_SpawnParams
{
}

namespace UCk_AutoTest_Tween_RotatorCompletion
{
    FCk_AutoTest_Tween_RotatorCompletion_SpawnParams Params()
    {
        return FCk_AutoTest_Tween_RotatorCompletion_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Tween_SelfDestructOnComplete_SpawnParams
{
}

namespace UCk_AutoTest_Tween_SelfDestructOnComplete
{
    FCk_AutoTest_Tween_SelfDestructOnComplete_SpawnParams Params()
    {
        return FCk_AutoTest_Tween_SelfDestructOnComplete_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Tween_VectorCompletion_SpawnParams
{
}

namespace UCk_AutoTest_Tween_VectorCompletion
{
    FCk_AutoTest_Tween_VectorCompletion_SpawnParams Params()
    {
        return FCk_AutoTest_Tween_VectorCompletion_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Tween_YoyoLoop_SpawnParams
{
}

namespace UCk_AutoTest_Tween_YoyoLoop
{
    FCk_AutoTest_Tween_YoyoLoop_SpawnParams Params()
    {
        return FCk_AutoTest_Tween_YoyoLoop_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_UnrealComponent_AddHappyPath_SpawnParams
{
}

namespace UCk_AutoTest_UnrealComponent_AddHappyPath
{
    FCk_AutoTest_UnrealComponent_AddHappyPath_SpawnParams Params()
    {
        return FCk_AutoTest_UnrealComponent_AddHappyPath_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_UnrealComponent_GetAllComponentsListsAdded_SpawnParams
{
}

namespace UCk_AutoTest_UnrealComponent_GetAllComponentsListsAdded
{
    FCk_AutoTest_UnrealComponent_GetAllComponentsListsAdded_SpawnParams Params()
    {
        return FCk_AutoTest_UnrealComponent_GetAllComponentsListsAdded_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_UnrealComponent_GetAllHandlesListsAdded_SpawnParams
{
}

namespace UCk_AutoTest_UnrealComponent_GetAllHandlesListsAdded
{
    FCk_AutoTest_UnrealComponent_GetAllHandlesListsAdded_SpawnParams Params()
    {
        return FCk_AutoTest_UnrealComponent_GetAllHandlesListsAdded_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_UnrealComponent_GetOwningEntity_SpawnParams
{
}

namespace UCk_AutoTest_UnrealComponent_GetOwningEntity
{
    FCk_AutoTest_UnrealComponent_GetOwningEntity_SpawnParams Params()
    {
        return FCk_AutoTest_UnrealComponent_GetOwningEntity_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_UnrealComponent_RequestRemoveAfterFrame_SpawnParams
{
}

namespace UCk_AutoTest_UnrealComponent_RequestRemoveAfterFrame
{
    FCk_AutoTest_UnrealComponent_RequestRemoveAfterFrame_SpawnParams Params()
    {
        return FCk_AutoTest_UnrealComponent_RequestRemoveAfterFrame_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_UnrealComponent_TryGetHandleByTypeFound_SpawnParams
{
}

namespace UCk_AutoTest_UnrealComponent_TryGetHandleByTypeFound
{
    FCk_AutoTest_UnrealComponent_TryGetHandleByTypeFound_SpawnParams Params()
    {
        return FCk_AutoTest_UnrealComponent_TryGetHandleByTypeFound_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_UnrealComponent_TryGetHandleByTypeNotFound_SpawnParams
{
}

namespace UCk_AutoTest_UnrealComponent_TryGetHandleByTypeNotFound
{
    FCk_AutoTest_UnrealComponent_TryGetHandleByTypeNotFound_SpawnParams Params()
    {
        return FCk_AutoTest_UnrealComponent_TryGetHandleByTypeNotFound_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_UnrealComponent_TryGetOwningHandleFromComponent_SpawnParams
{
}

namespace UCk_AutoTest_UnrealComponent_TryGetOwningHandleFromComponent
{
    FCk_AutoTest_UnrealComponent_TryGetOwningHandleFromComponent_SpawnParams Params()
    {
        return FCk_AutoTest_UnrealComponent_TryGetOwningHandleFromComponent_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Variables_Bool_SetGetRoundTrip_SpawnParams
{
}

namespace UCk_AutoTest_Variables_Bool_SetGetRoundTrip
{
    FCk_AutoTest_Variables_Bool_SetGetRoundTrip_SpawnParams Params()
    {
        return FCk_AutoTest_Variables_Bool_SetGetRoundTrip_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Variables_Float_SetGetRoundTrip_SpawnParams
{
}

namespace UCk_AutoTest_Variables_Float_SetGetRoundTrip
{
    FCk_AutoTest_Variables_Float_SetGetRoundTrip_SpawnParams Params()
    {
        return FCk_AutoTest_Variables_Float_SetGetRoundTrip_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Variables_GameplayTag_SetGetRoundTrip_SpawnParams
{
}

namespace UCk_AutoTest_Variables_GameplayTag_SetGetRoundTrip
{
    FCk_AutoTest_Variables_GameplayTag_SetGetRoundTrip_SpawnParams Params()
    {
        return FCk_AutoTest_Variables_GameplayTag_SetGetRoundTrip_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Variables_Int32_SetGetRoundTrip_SpawnParams
{
}

namespace UCk_AutoTest_Variables_Int32_SetGetRoundTrip
{
    FCk_AutoTest_Variables_Int32_SetGetRoundTrip_SpawnParams Params()
    {
        return FCk_AutoTest_Variables_Int32_SetGetRoundTrip_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Variables_SetOverwritesPrior_SpawnParams
{
}

namespace UCk_AutoTest_Variables_SetOverwritesPrior
{
    FCk_AutoTest_Variables_SetOverwritesPrior_SpawnParams Params()
    {
        return FCk_AutoTest_Variables_SetOverwritesPrior_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Variables_String_SetGetRoundTrip_SpawnParams
{
}

namespace UCk_AutoTest_Variables_String_SetGetRoundTrip
{
    FCk_AutoTest_Variables_String_SetGetRoundTrip_SpawnParams Params()
    {
        return FCk_AutoTest_Variables_String_SetGetRoundTrip_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTest_Variables_Vector_SetGetRoundTrip_SpawnParams
{
}

namespace UCk_AutoTest_Variables_Vector_SetGetRoundTrip
{
    FCk_AutoTest_Variables_Vector_SetGetRoundTrip_SpawnParams Params()
    {
        return FCk_AutoTest_Variables_Vector_SetGetRoundTrip_SpawnParams();
    }
}

USTRUCT()
struct FCk_AutoTestCue_AfterOneFrame_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_AutoTestCue_AfterOneFrame_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_AutoTestCue_AfterOneFrame
{
    FCk_AutoTestCue_AfterOneFrame_SpawnParams Params()
    {
        return FCk_AutoTestCue_AfterOneFrame_SpawnParams();
    }

    FCk_AutoTestCue_AfterOneFrame_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_AutoTestCue_AfterOneFrame_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_AutoTestCue_Persistent_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_AutoTestCue_Persistent_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_AutoTestCue_Persistent
{
    FCk_AutoTestCue_Persistent_SpawnParams Params()
    {
        return FCk_AutoTestCue_Persistent_SpawnParams();
    }

    FCk_AutoTestCue_Persistent_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_AutoTestCue_Persistent_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_AutoTestCue_Timed_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_AutoTestCue_Timed_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_AutoTestCue_Timed
{
    FCk_AutoTestCue_Timed_SpawnParams Params()
    {
        return FCk_AutoTestCue_Timed_SpawnParams();
    }

    FCk_AutoTestCue_Timed_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_AutoTestCue_Timed_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_CueGym_Cue_AfterOneFrame_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_CueGym_Cue_AfterOneFrame_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_CueGym_Cue_AfterOneFrame
{
    FCk_CueGym_Cue_AfterOneFrame_SpawnParams Params()
    {
        return FCk_CueGym_Cue_AfterOneFrame_SpawnParams();
    }

    FCk_CueGym_Cue_AfterOneFrame_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_CueGym_Cue_AfterOneFrame_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_CueGym_Cue_Custom_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_CueGym_Cue_Custom_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_CueGym_Cue_Custom
{
    FCk_CueGym_Cue_Custom_SpawnParams Params()
    {
        return FCk_CueGym_Cue_Custom_SpawnParams();
    }

    FCk_CueGym_Cue_Custom_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_CueGym_Cue_Custom_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_CueGym_Cue_Multiple_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_CueGym_Cue_Multiple_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_CueGym_Cue_Multiple
{
    FCk_CueGym_Cue_Multiple_SpawnParams Params()
    {
        return FCk_CueGym_Cue_Multiple_SpawnParams();
    }

    FCk_CueGym_Cue_Multiple_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_CueGym_Cue_Multiple_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_CueGym_Cue_OwnerDestruction_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_CueGym_Cue_OwnerDestruction_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_CueGym_Cue_OwnerDestruction
{
    FCk_CueGym_Cue_OwnerDestruction_SpawnParams Params()
    {
        return FCk_CueGym_Cue_OwnerDestruction_SpawnParams();
    }

    FCk_CueGym_Cue_OwnerDestruction_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_CueGym_Cue_OwnerDestruction_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_CueGym_Cue_OwnerRequire_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_CueGym_Cue_OwnerRequire_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_CueGym_Cue_OwnerRequire
{
    FCk_CueGym_Cue_OwnerRequire_SpawnParams Params()
    {
        return FCk_CueGym_Cue_OwnerRequire_SpawnParams();
    }

    FCk_CueGym_Cue_OwnerRequire_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_CueGym_Cue_OwnerRequire_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_CueGym_Cue_OwnerSkip_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_CueGym_Cue_OwnerSkip_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_CueGym_Cue_OwnerSkip
{
    FCk_CueGym_Cue_OwnerSkip_SpawnParams Params()
    {
        return FCk_CueGym_Cue_OwnerSkip_SpawnParams();
    }

    FCk_CueGym_Cue_OwnerSkip_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_CueGym_Cue_OwnerSkip_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_CueGym_Cue_Persistent_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_CueGym_Cue_Persistent_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_CueGym_Cue_Persistent
{
    FCk_CueGym_Cue_Persistent_SpawnParams Params()
    {
        return FCk_CueGym_Cue_Persistent_SpawnParams();
    }

    FCk_CueGym_Cue_Persistent_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_CueGym_Cue_Persistent_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_CueGym_Cue_Restart_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_CueGym_Cue_Restart_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_CueGym_Cue_Restart
{
    FCk_CueGym_Cue_Restart_SpawnParams Params()
    {
        return FCk_CueGym_Cue_Restart_SpawnParams();
    }

    FCk_CueGym_Cue_Restart_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_CueGym_Cue_Restart_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_CueGym_Cue_Restartable_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_CueGym_Cue_Restartable_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_CueGym_Cue_Restartable
{
    FCk_CueGym_Cue_Restartable_SpawnParams Params()
    {
        return FCk_CueGym_Cue_Restartable_SpawnParams();
    }

    FCk_CueGym_Cue_Restartable_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_CueGym_Cue_Restartable_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_CueGym_Cue_Timed_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_CueGym_Cue_Timed_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_CueGym_Cue_Timed
{
    FCk_CueGym_Cue_Timed_SpawnParams Params()
    {
        return FCk_CueGym_Cue_Timed_SpawnParams();
    }

    FCk_CueGym_Cue_Timed_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_CueGym_Cue_Timed_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_CueGym_Cue_Transient_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_CueGym_Cue_Transient_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_CueGym_Cue_Transient
{
    FCk_CueGym_Cue_Transient_SpawnParams Params()
    {
        return FCk_CueGym_Cue_Transient_SpawnParams();
    }

    FCk_CueGym_Cue_Transient_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_CueGym_Cue_Transient_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_EntityScript_AStarGym_Station_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    UPROPERTY()
    FString StationTitle = "";

    UPROPERTY()
    FString StationDescription = "";

    UPROPERTY()
    int GridWidth = 10;

    UPROPERTY()
    int GridHeight = 10;

    UPROPERTY()
    int StartX = 0;

    UPROPERTY()
    int StartY = 0;

    UPROPERTY()
    int GoalX = 9;

    UPROPERTY()
    int GoalY = 9;

    UPROPERTY()
    int64 BudgetMicroseconds = 0;

    UPROPERTY()
    float32 CostThreshold = 0.0f;

    UPROPERTY()
    TArray<FIntPoint> BlockedCells;

    UPROPERTY()
    float RestartIntervalSeconds = 5.0;

    FCk_EntityScript_AStarGym_Station_SpawnParams(FTransform InInitialTransform, FString InStationTitle, FString InStationDescription, int InGridWidth, int InGridHeight, int InStartX, int InStartY, int InGoalX, int InGoalY, int64 InBudgetMicroseconds, float32 InCostThreshold, TArray<FIntPoint> InBlockedCells, float InRestartIntervalSeconds)
    {
        InitialTransform = InInitialTransform;
        StationTitle = InStationTitle;
        StationDescription = InStationDescription;
        GridWidth = InGridWidth;
        GridHeight = InGridHeight;
        StartX = InStartX;
        StartY = InStartY;
        GoalX = InGoalX;
        GoalY = InGoalY;
        BudgetMicroseconds = InBudgetMicroseconds;
        CostThreshold = InCostThreshold;
        BlockedCells = InBlockedCells;
        RestartIntervalSeconds = InRestartIntervalSeconds;
    }
}

namespace UCk_EntityScript_AStarGym_Station
{
    FCk_EntityScript_AStarGym_Station_SpawnParams Params()
    {
        return FCk_EntityScript_AStarGym_Station_SpawnParams();
    }

    FCk_EntityScript_AStarGym_Station_SpawnParams Params(FTransform InInitialTransform, FString InStationTitle, FString InStationDescription, int InGridWidth, int InGridHeight, int InStartX, int InStartY, int InGoalX, int InGoalY, int64 InBudgetMicroseconds, float32 InCostThreshold, TArray<FIntPoint> InBlockedCells, float InRestartIntervalSeconds)
    {
        return FCk_EntityScript_AStarGym_Station_SpawnParams(InInitialTransform, InStationTitle, InStationDescription, InGridWidth, InGridHeight, InStartX, InStartY, InGoalX, InGoalY, InBudgetMicroseconds, InCostThreshold, InBlockedCells, InRestartIntervalSeconds);
    }
}

USTRUCT()
struct FCk_EntityScript_AttributeGym_BasicAttributes_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    UPROPERTY()
    FString StationName = "BasicAttributes";

    FCk_EntityScript_AttributeGym_BasicAttributes_SpawnParams(FTransform InInitialTransform, FString InStationName)
    {
        InitialTransform = InInitialTransform;
        StationName = InStationName;
    }
}

namespace UCk_EntityScript_AttributeGym_BasicAttributes
{
    FCk_EntityScript_AttributeGym_BasicAttributes_SpawnParams Params()
    {
        return FCk_EntityScript_AttributeGym_BasicAttributes_SpawnParams();
    }

    FCk_EntityScript_AttributeGym_BasicAttributes_SpawnParams Params(FTransform InInitialTransform, FString InStationName)
    {
        return FCk_EntityScript_AttributeGym_BasicAttributes_SpawnParams(InInitialTransform, InStationName);
    }
}

USTRUCT()
struct FCk_EntityScript_AttributeGym_ByteClamping_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_EntityScript_AttributeGym_ByteClamping_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_EntityScript_AttributeGym_ByteClamping
{
    FCk_EntityScript_AttributeGym_ByteClamping_SpawnParams Params()
    {
        return FCk_EntityScript_AttributeGym_ByteClamping_SpawnParams();
    }

    FCk_EntityScript_AttributeGym_ByteClamping_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_EntityScript_AttributeGym_ByteClamping_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_EntityScript_AttributeGym_ByteMinMaxCurrent_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_EntityScript_AttributeGym_ByteMinMaxCurrent_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_EntityScript_AttributeGym_ByteMinMaxCurrent
{
    FCk_EntityScript_AttributeGym_ByteMinMaxCurrent_SpawnParams Params()
    {
        return FCk_EntityScript_AttributeGym_ByteMinMaxCurrent_SpawnParams();
    }

    FCk_EntityScript_AttributeGym_ByteMinMaxCurrent_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_EntityScript_AttributeGym_ByteMinMaxCurrent_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_EntityScript_AttributeGym_ByteModifiers_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_EntityScript_AttributeGym_ByteModifiers_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_EntityScript_AttributeGym_ByteModifiers
{
    FCk_EntityScript_AttributeGym_ByteModifiers_SpawnParams Params()
    {
        return FCk_EntityScript_AttributeGym_ByteModifiers_SpawnParams();
    }

    FCk_EntityScript_AttributeGym_ByteModifiers_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_EntityScript_AttributeGym_ByteModifiers_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_EntityScript_AttributeGym_ByteMultiple_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_EntityScript_AttributeGym_ByteMultiple_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_EntityScript_AttributeGym_ByteMultiple
{
    FCk_EntityScript_AttributeGym_ByteMultiple_SpawnParams Params()
    {
        return FCk_EntityScript_AttributeGym_ByteMultiple_SpawnParams();
    }

    FCk_EntityScript_AttributeGym_ByteMultiple_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_EntityScript_AttributeGym_ByteMultiple_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_EntityScript_AttributeGym_ByteSignals_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_EntityScript_AttributeGym_ByteSignals_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_EntityScript_AttributeGym_ByteSignals
{
    FCk_EntityScript_AttributeGym_ByteSignals_SpawnParams Params()
    {
        return FCk_EntityScript_AttributeGym_ByteSignals_SpawnParams();
    }

    FCk_EntityScript_AttributeGym_ByteSignals_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_EntityScript_AttributeGym_ByteSignals_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_EntityScript_AttributeGym_ByteValues_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_EntityScript_AttributeGym_ByteValues_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_EntityScript_AttributeGym_ByteValues
{
    FCk_EntityScript_AttributeGym_ByteValues_SpawnParams Params()
    {
        return FCk_EntityScript_AttributeGym_ByteValues_SpawnParams();
    }

    FCk_EntityScript_AttributeGym_ByteValues_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_EntityScript_AttributeGym_ByteValues_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_EntityScript_AttributeGym_FloatClamping_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_EntityScript_AttributeGym_FloatClamping_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_EntityScript_AttributeGym_FloatClamping
{
    FCk_EntityScript_AttributeGym_FloatClamping_SpawnParams Params()
    {
        return FCk_EntityScript_AttributeGym_FloatClamping_SpawnParams();
    }

    FCk_EntityScript_AttributeGym_FloatClamping_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_EntityScript_AttributeGym_FloatClamping_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_EntityScript_AttributeGym_FloatIncrementDecrement_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_EntityScript_AttributeGym_FloatIncrementDecrement_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_EntityScript_AttributeGym_FloatIncrementDecrement
{
    FCk_EntityScript_AttributeGym_FloatIncrementDecrement_SpawnParams Params()
    {
        return FCk_EntityScript_AttributeGym_FloatIncrementDecrement_SpawnParams();
    }

    FCk_EntityScript_AttributeGym_FloatIncrementDecrement_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_EntityScript_AttributeGym_FloatIncrementDecrement_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_EntityScript_AttributeGym_FloatMinMaxCurrent_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_EntityScript_AttributeGym_FloatMinMaxCurrent_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_EntityScript_AttributeGym_FloatMinMaxCurrent
{
    FCk_EntityScript_AttributeGym_FloatMinMaxCurrent_SpawnParams Params()
    {
        return FCk_EntityScript_AttributeGym_FloatMinMaxCurrent_SpawnParams();
    }

    FCk_EntityScript_AttributeGym_FloatMinMaxCurrent_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_EntityScript_AttributeGym_FloatMinMaxCurrent_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_EntityScript_AttributeGym_FloatModifiers_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_EntityScript_AttributeGym_FloatModifiers_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_EntityScript_AttributeGym_FloatModifiers
{
    FCk_EntityScript_AttributeGym_FloatModifiers_SpawnParams Params()
    {
        return FCk_EntityScript_AttributeGym_FloatModifiers_SpawnParams();
    }

    FCk_EntityScript_AttributeGym_FloatModifiers_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_EntityScript_AttributeGym_FloatModifiers_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_EntityScript_AttributeGym_FloatMultiple_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_EntityScript_AttributeGym_FloatMultiple_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_EntityScript_AttributeGym_FloatMultiple
{
    FCk_EntityScript_AttributeGym_FloatMultiple_SpawnParams Params()
    {
        return FCk_EntityScript_AttributeGym_FloatMultiple_SpawnParams();
    }

    FCk_EntityScript_AttributeGym_FloatMultiple_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_EntityScript_AttributeGym_FloatMultiple_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_EntityScript_AttributeGym_FloatRefill_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_EntityScript_AttributeGym_FloatRefill_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_EntityScript_AttributeGym_FloatRefill
{
    FCk_EntityScript_AttributeGym_FloatRefill_SpawnParams Params()
    {
        return FCk_EntityScript_AttributeGym_FloatRefill_SpawnParams();
    }

    FCk_EntityScript_AttributeGym_FloatRefill_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_EntityScript_AttributeGym_FloatRefill_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_EntityScript_AttributeGym_FloatSignals_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_EntityScript_AttributeGym_FloatSignals_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_EntityScript_AttributeGym_FloatSignals
{
    FCk_EntityScript_AttributeGym_FloatSignals_SpawnParams Params()
    {
        return FCk_EntityScript_AttributeGym_FloatSignals_SpawnParams();
    }

    FCk_EntityScript_AttributeGym_FloatSignals_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_EntityScript_AttributeGym_FloatSignals_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_EntityScript_AttributeGym_FloatValues_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_EntityScript_AttributeGym_FloatValues_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_EntityScript_AttributeGym_FloatValues
{
    FCk_EntityScript_AttributeGym_FloatValues_SpawnParams Params()
    {
        return FCk_EntityScript_AttributeGym_FloatValues_SpawnParams();
    }

    FCk_EntityScript_AttributeGym_FloatValues_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_EntityScript_AttributeGym_FloatValues_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_EntityScript_CueGym_Concurrency_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_EntityScript_CueGym_Concurrency_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_EntityScript_CueGym_Concurrency
{
    FCk_EntityScript_CueGym_Concurrency_SpawnParams Params()
    {
        return FCk_EntityScript_CueGym_Concurrency_SpawnParams();
    }

    FCk_EntityScript_CueGym_Concurrency_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_EntityScript_CueGym_Concurrency_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_EntityScript_CueGym_DestructionOwner_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_EntityScript_CueGym_DestructionOwner_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_EntityScript_CueGym_DestructionOwner
{
    FCk_EntityScript_CueGym_DestructionOwner_SpawnParams Params()
    {
        return FCk_EntityScript_CueGym_DestructionOwner_SpawnParams();
    }

    FCk_EntityScript_CueGym_DestructionOwner_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_EntityScript_CueGym_DestructionOwner_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_EntityScript_CueGym_Lifetime_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_EntityScript_CueGym_Lifetime_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_EntityScript_CueGym_Lifetime
{
    FCk_EntityScript_CueGym_Lifetime_SpawnParams Params()
    {
        return FCk_EntityScript_CueGym_Lifetime_SpawnParams();
    }

    FCk_EntityScript_CueGym_Lifetime_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_EntityScript_CueGym_Lifetime_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_EntityScript_CueGym_OwnerDestruction_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_EntityScript_CueGym_OwnerDestruction_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_EntityScript_CueGym_OwnerDestruction
{
    FCk_EntityScript_CueGym_OwnerDestruction_SpawnParams Params()
    {
        return FCk_EntityScript_CueGym_OwnerDestruction_SpawnParams();
    }

    FCk_EntityScript_CueGym_OwnerDestruction_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_EntityScript_CueGym_OwnerDestruction_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_EntityScript_CueGym_OwnerValidation_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_EntityScript_CueGym_OwnerValidation_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_EntityScript_CueGym_OwnerValidation
{
    FCk_EntityScript_CueGym_OwnerValidation_SpawnParams Params()
    {
        return FCk_EntityScript_CueGym_OwnerValidation_SpawnParams();
    }

    FCk_EntityScript_CueGym_OwnerValidation_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_EntityScript_CueGym_OwnerValidation_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_EntityScript_CueGym_Restart_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_EntityScript_CueGym_Restart_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_EntityScript_CueGym_Restart
{
    FCk_EntityScript_CueGym_Restart_SpawnParams Params()
    {
        return FCk_EntityScript_CueGym_Restart_SpawnParams();
    }

    FCk_EntityScript_CueGym_Restart_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_EntityScript_CueGym_Restart_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_EntityScript_CueGym_TempOwner_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_EntityScript_CueGym_TempOwner_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_EntityScript_CueGym_TempOwner
{
    FCk_EntityScript_CueGym_TempOwner_SpawnParams Params()
    {
        return FCk_EntityScript_CueGym_TempOwner_SpawnParams();
    }

    FCk_EntityScript_CueGym_TempOwner_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_EntityScript_CueGym_TempOwner_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_EntityScript_CueGym_Transient_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_EntityScript_CueGym_Transient_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_EntityScript_CueGym_Transient
{
    FCk_EntityScript_CueGym_Transient_SpawnParams Params()
    {
        return FCk_EntityScript_CueGym_Transient_SpawnParams();
    }

    FCk_EntityScript_CueGym_Transient_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_EntityScript_CueGym_Transient_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_EntityScript_EntityLifecycleGym_ActorBridge_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_EntityScript_EntityLifecycleGym_ActorBridge_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_EntityScript_EntityLifecycleGym_ActorBridge
{
    FCk_EntityScript_EntityLifecycleGym_ActorBridge_SpawnParams Params()
    {
        return FCk_EntityScript_EntityLifecycleGym_ActorBridge_SpawnParams();
    }

    FCk_EntityScript_EntityLifecycleGym_ActorBridge_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_EntityScript_EntityLifecycleGym_ActorBridge_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_EntityScript_EntityLifecycleGym_DeferredSetup_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_EntityScript_EntityLifecycleGym_DeferredSetup_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_EntityScript_EntityLifecycleGym_DeferredSetup
{
    FCk_EntityScript_EntityLifecycleGym_DeferredSetup_SpawnParams Params()
    {
        return FCk_EntityScript_EntityLifecycleGym_DeferredSetup_SpawnParams();
    }

    FCk_EntityScript_EntityLifecycleGym_DeferredSetup_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_EntityScript_EntityLifecycleGym_DeferredSetup_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_EntityScript_EntityLifecycleGym_DestroyCallbacks_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_EntityScript_EntityLifecycleGym_DestroyCallbacks_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_EntityScript_EntityLifecycleGym_DestroyCallbacks
{
    FCk_EntityScript_EntityLifecycleGym_DestroyCallbacks_SpawnParams Params()
    {
        return FCk_EntityScript_EntityLifecycleGym_DestroyCallbacks_SpawnParams();
    }

    FCk_EntityScript_EntityLifecycleGym_DestroyCallbacks_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_EntityScript_EntityLifecycleGym_DestroyCallbacks_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_EntityScript_EntityLifecycleGym_HandleAndEntity_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_EntityScript_EntityLifecycleGym_HandleAndEntity_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_EntityScript_EntityLifecycleGym_HandleAndEntity
{
    FCk_EntityScript_EntityLifecycleGym_HandleAndEntity_SpawnParams Params()
    {
        return FCk_EntityScript_EntityLifecycleGym_HandleAndEntity_SpawnParams();
    }

    FCk_EntityScript_EntityLifecycleGym_HandleAndEntity_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_EntityScript_EntityLifecycleGym_HandleAndEntity_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_EntityScript_EntityLifecycleGym_OwnershipTree_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_EntityScript_EntityLifecycleGym_OwnershipTree_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_EntityScript_EntityLifecycleGym_OwnershipTree
{
    FCk_EntityScript_EntityLifecycleGym_OwnershipTree_SpawnParams Params()
    {
        return FCk_EntityScript_EntityLifecycleGym_OwnershipTree_SpawnParams();
    }

    FCk_EntityScript_EntityLifecycleGym_OwnershipTree_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_EntityScript_EntityLifecycleGym_OwnershipTree_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_EntityScript_EntityLifecycleGym_ScriptSpawnCast_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_EntityScript_EntityLifecycleGym_ScriptSpawnCast_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_EntityScript_EntityLifecycleGym_ScriptSpawnCast
{
    FCk_EntityScript_EntityLifecycleGym_ScriptSpawnCast_SpawnParams Params()
    {
        return FCk_EntityScript_EntityLifecycleGym_ScriptSpawnCast_SpawnParams();
    }

    FCk_EntityScript_EntityLifecycleGym_ScriptSpawnCast_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_EntityScript_EntityLifecycleGym_ScriptSpawnCast_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_EntityScript_EntityLifecycleGym_SpawnTarget_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_EntityScript_EntityLifecycleGym_SpawnTarget_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_EntityScript_EntityLifecycleGym_SpawnTarget
{
    FCk_EntityScript_EntityLifecycleGym_SpawnTarget_SpawnParams Params()
    {
        return FCk_EntityScript_EntityLifecycleGym_SpawnTarget_SpawnParams();
    }

    FCk_EntityScript_EntityLifecycleGym_SpawnTarget_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_EntityScript_EntityLifecycleGym_SpawnTarget_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_EntityScript_EntityLifecycleGym_TagSystem_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_EntityScript_EntityLifecycleGym_TagSystem_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_EntityScript_EntityLifecycleGym_TagSystem
{
    FCk_EntityScript_EntityLifecycleGym_TagSystem_SpawnParams Params()
    {
        return FCk_EntityScript_EntityLifecycleGym_TagSystem_SpawnParams();
    }

    FCk_EntityScript_EntityLifecycleGym_TagSystem_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_EntityScript_EntityLifecycleGym_TagSystem_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_EntityScript_EntityScriptGym_Spawn_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    UPROPERTY()
    FName TestName = n"None";

    UPROPERTY()
    int TestInt = 0;

    UPROPERTY()
    float32 TestFloat = 0.0f;

    FCk_EntityScript_EntityScriptGym_Spawn_SpawnParams(FTransform InInitialTransform, FName InTestName, int InTestInt, float32 InTestFloat)
    {
        InitialTransform = InInitialTransform;
        TestName = InTestName;
        TestInt = InTestInt;
        TestFloat = InTestFloat;
    }
}

namespace UCk_EntityScript_EntityScriptGym_Spawn
{
    FCk_EntityScript_EntityScriptGym_Spawn_SpawnParams Params()
    {
        return FCk_EntityScript_EntityScriptGym_Spawn_SpawnParams();
    }

    FCk_EntityScript_EntityScriptGym_Spawn_SpawnParams Params(FTransform InInitialTransform, FName InTestName, int InTestInt, float32 InTestFloat)
    {
        return FCk_EntityScript_EntityScriptGym_Spawn_SpawnParams(InInitialTransform, InTestName, InTestInt, InTestFloat);
    }
}

USTRUCT()
struct FCk_EntityScript_EntityScriptGym_SpawnReplicated_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    UPROPERTY()
    FName TestName = n"None";

    UPROPERTY()
    int TestInt = 0;

    UPROPERTY()
    float32 TestFloat = 0.0f;

    FCk_EntityScript_EntityScriptGym_SpawnReplicated_SpawnParams(FTransform InInitialTransform, FName InTestName, int InTestInt, float32 InTestFloat)
    {
        InitialTransform = InInitialTransform;
        TestName = InTestName;
        TestInt = InTestInt;
        TestFloat = InTestFloat;
    }
}

namespace UCk_EntityScript_EntityScriptGym_SpawnReplicated
{
    FCk_EntityScript_EntityScriptGym_SpawnReplicated_SpawnParams Params()
    {
        return FCk_EntityScript_EntityScriptGym_SpawnReplicated_SpawnParams();
    }

    FCk_EntityScript_EntityScriptGym_SpawnReplicated_SpawnParams Params(FTransform InInitialTransform, FName InTestName, int InTestInt, float32 InTestFloat)
    {
        return FCk_EntityScript_EntityScriptGym_SpawnReplicated_SpawnParams(InInitialTransform, InTestName, InTestInt, InTestFloat);
    }
}

USTRUCT()
struct FCk_EntityScript_EqsGym_Station_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    UPROPERTY()
    FString StationTitle = "";

    UPROPERTY()
    FString StationDescription = "";

    UPROPERTY()
    ECkEqsGym_Scenario Scenario = ECkEqsGym_Scenario::SimpleGrid_Distance;

    UPROPERTY()
    float RestartIntervalSeconds = 5.0;

    FCk_EntityScript_EqsGym_Station_SpawnParams(FTransform InInitialTransform, FString InStationTitle, FString InStationDescription, ECkEqsGym_Scenario InScenario, float InRestartIntervalSeconds)
    {
        InitialTransform = InInitialTransform;
        StationTitle = InStationTitle;
        StationDescription = InStationDescription;
        Scenario = InScenario;
        RestartIntervalSeconds = InRestartIntervalSeconds;
    }
}

namespace UCk_EntityScript_EqsGym_Station
{
    FCk_EntityScript_EqsGym_Station_SpawnParams Params()
    {
        return FCk_EntityScript_EqsGym_Station_SpawnParams();
    }

    FCk_EntityScript_EqsGym_Station_SpawnParams Params(FTransform InInitialTransform, FString InStationTitle, FString InStationDescription, ECkEqsGym_Scenario InScenario, float InRestartIntervalSeconds)
    {
        return FCk_EntityScript_EqsGym_Station_SpawnParams(InInitialTransform, InStationTitle, InStationDescription, InScenario, InRestartIntervalSeconds);
    }
}

USTRUCT()
struct FCk_EntityScript_GoapEmpire_Station_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_EntityScript_GoapEmpire_Station_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_EntityScript_GoapEmpire_Station
{
    FCk_EntityScript_GoapEmpire_Station_SpawnParams Params()
    {
        return FCk_EntityScript_GoapEmpire_Station_SpawnParams();
    }

    FCk_EntityScript_GoapEmpire_Station_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_EntityScript_GoapEmpire_Station_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_EntityScript_GoapGym_AutoReplan_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_EntityScript_GoapGym_AutoReplan_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_EntityScript_GoapGym_AutoReplan
{
    FCk_EntityScript_GoapGym_AutoReplan_SpawnParams Params()
    {
        return FCk_EntityScript_GoapGym_AutoReplan_SpawnParams();
    }

    FCk_EntityScript_GoapGym_AutoReplan_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_EntityScript_GoapGym_AutoReplan_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_EntityScript_GoapGym_CircularDep_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_EntityScript_GoapGym_CircularDep_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_EntityScript_GoapGym_CircularDep
{
    FCk_EntityScript_GoapGym_CircularDep_SpawnParams Params()
    {
        return FCk_EntityScript_GoapGym_CircularDep_SpawnParams();
    }

    FCk_EntityScript_GoapGym_CircularDep_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_EntityScript_GoapGym_CircularDep_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_EntityScript_GoapGym_Combat_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_EntityScript_GoapGym_Combat_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_EntityScript_GoapGym_Combat
{
    FCk_EntityScript_GoapGym_Combat_SpawnParams Params()
    {
        return FCk_EntityScript_GoapGym_Combat_SpawnParams();
    }

    FCk_EntityScript_GoapGym_Combat_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_EntityScript_GoapGym_Combat_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_EntityScript_GoapGym_Door_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_EntityScript_GoapGym_Door_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_EntityScript_GoapGym_Door
{
    FCk_EntityScript_GoapGym_Door_SpawnParams Params()
    {
        return FCk_EntityScript_GoapGym_Door_SpawnParams();
    }

    FCk_EntityScript_GoapGym_Door_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_EntityScript_GoapGym_Door_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_EntityScript_GoapGym_NoPlan_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_EntityScript_GoapGym_NoPlan_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_EntityScript_GoapGym_NoPlan
{
    FCk_EntityScript_GoapGym_NoPlan_SpawnParams Params()
    {
        return FCk_EntityScript_GoapGym_NoPlan_SpawnParams();
    }

    FCk_EntityScript_GoapGym_NoPlan_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_EntityScript_GoapGym_NoPlan_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_EntityScript_GoapGym_Priorities_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_EntityScript_GoapGym_Priorities_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_EntityScript_GoapGym_Priorities
{
    FCk_EntityScript_GoapGym_Priorities_SpawnParams Params()
    {
        return FCk_EntityScript_GoapGym_Priorities_SpawnParams();
    }

    FCk_EntityScript_GoapGym_Priorities_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_EntityScript_GoapGym_Priorities_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_EntityScript_GoapGym_Tea_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_EntityScript_GoapGym_Tea_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_EntityScript_GoapGym_Tea
{
    FCk_EntityScript_GoapGym_Tea_SpawnParams Params()
    {
        return FCk_EntityScript_GoapGym_Tea_SpawnParams();
    }

    FCk_EntityScript_GoapGym_Tea_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_EntityScript_GoapGym_Tea_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_EntityScript_GymStation_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    UPROPERTY()
    float Width = 6.0;

    UPROPERTY()
    float Depth = 5.0;

    UPROPERTY()
    float Height = 5.0;

    UPROPERTY()
    float WallThickness = 15.0;

    UPROPERTY()
    float FloorThickness = 15.0;

    UPROPERTY()
    float TrimDepth = 30.0;

    UPROPERTY()
    float AgentSpawnOffset = 0.0;

    UPROPERTY()
    FLinearColor BodyColour = FLinearColor(0.019999999552965164f, 0.019999999552965164f, 0.019999999552965164f, 1.0f);

    UPROPERTY()
    FLinearColor TrimColour = FLinearColor(0.30000001192092896f, 0.30000001192092896f, 0.30000001192092896f, 1.0f);

    UPROPERTY()
    FText TitleText = FText::FromString("Title");

    UPROPERTY()
    float TitleScale = 20.0;

    UPROPERTY()
    FColor TitleColour = FColor(255, 255, 255, 255);

    UPROPERTY()
    TArray<FText> DescriptionText;

    UPROPERTY()
    float DescriptionScale = 12.0;

    UPROPERTY()
    FColor DescriptionColour = FColor(255, 255, 255, 255);

    UPROPERTY()
    EHorizTextAligment TextAlignment = EHorizTextAligment::EHTA_Left;

    UPROPERTY()
    TArray<FText> FloorDescriptionText;

    UPROPERTY()
    float FloorDescriptionScale = 12.0;

    UPROPERTY()
    FColor FloorDescriptionColour = FColor(255, 255, 255, 255);

    UPROPERTY()
    EHorizTextAligment FloorTextAlignment = EHorizTextAligment::EHTA_Left;

    UPROPERTY()
    ECk_GymStation_FloorTextPlacement FloorTextPlacement = ECk_GymStation_FloorTextPlacement::Front;

    UPROPERTY()
    bool ShowSpotlight = true;

    UPROPERTY()
    bool ShowAnchors = false;

    UPROPERTY()
    bool ShowDebugOverlays = false;

    UPROPERTY()
    bool AutoSize = false;

    UPROPERTY()
    TArray<FName> StationTags;

    FCk_EntityScript_GymStation_SpawnParams(FTransform InInitialTransform, float InWidth, float InDepth, float InHeight, float InWallThickness, float InFloorThickness, float InTrimDepth, float InAgentSpawnOffset, FLinearColor InBodyColour, FLinearColor InTrimColour, FText InTitleText, float InTitleScale, FColor InTitleColour, TArray<FText> InDescriptionText, float InDescriptionScale, FColor InDescriptionColour, EHorizTextAligment InTextAlignment, TArray<FText> InFloorDescriptionText, float InFloorDescriptionScale, FColor InFloorDescriptionColour, EHorizTextAligment InFloorTextAlignment, ECk_GymStation_FloorTextPlacement InFloorTextPlacement, bool InShowSpotlight, bool InShowAnchors, bool InShowDebugOverlays, bool InAutoSize, TArray<FName> InStationTags)
    {
        InitialTransform = InInitialTransform;
        Width = InWidth;
        Depth = InDepth;
        Height = InHeight;
        WallThickness = InWallThickness;
        FloorThickness = InFloorThickness;
        TrimDepth = InTrimDepth;
        AgentSpawnOffset = InAgentSpawnOffset;
        BodyColour = InBodyColour;
        TrimColour = InTrimColour;
        TitleText = InTitleText;
        TitleScale = InTitleScale;
        TitleColour = InTitleColour;
        DescriptionText = InDescriptionText;
        DescriptionScale = InDescriptionScale;
        DescriptionColour = InDescriptionColour;
        TextAlignment = InTextAlignment;
        FloorDescriptionText = InFloorDescriptionText;
        FloorDescriptionScale = InFloorDescriptionScale;
        FloorDescriptionColour = InFloorDescriptionColour;
        FloorTextAlignment = InFloorTextAlignment;
        FloorTextPlacement = InFloorTextPlacement;
        ShowSpotlight = InShowSpotlight;
        ShowAnchors = InShowAnchors;
        ShowDebugOverlays = InShowDebugOverlays;
        AutoSize = InAutoSize;
        StationTags = InStationTags;
    }
}

namespace UCk_EntityScript_GymStation
{
    FCk_EntityScript_GymStation_SpawnParams Params()
    {
        return FCk_EntityScript_GymStation_SpawnParams();
    }

    FCk_EntityScript_GymStation_SpawnParams Params(FTransform InInitialTransform, float InWidth, float InDepth, float InHeight, float InWallThickness, float InFloorThickness, float InTrimDepth, float InAgentSpawnOffset, FLinearColor InBodyColour, FLinearColor InTrimColour, FText InTitleText, float InTitleScale, FColor InTitleColour, TArray<FText> InDescriptionText, float InDescriptionScale, FColor InDescriptionColour, EHorizTextAligment InTextAlignment, TArray<FText> InFloorDescriptionText, float InFloorDescriptionScale, FColor InFloorDescriptionColour, EHorizTextAligment InFloorTextAlignment, ECk_GymStation_FloorTextPlacement InFloorTextPlacement, bool InShowSpotlight, bool InShowAnchors, bool InShowDebugOverlays, bool InAutoSize, TArray<FName> InStationTags)
    {
        return FCk_EntityScript_GymStation_SpawnParams(InInitialTransform, InWidth, InDepth, InHeight, InWallThickness, InFloorThickness, InTrimDepth, InAgentSpawnOffset, InBodyColour, InTrimColour, InTitleText, InTitleScale, InTitleColour, InDescriptionText, InDescriptionScale, InDescriptionColour, InTextAlignment, InFloorDescriptionText, InFloorDescriptionScale, InFloorDescriptionColour, InFloorTextAlignment, InFloorTextPlacement, InShowSpotlight, InShowAnchors, InShowDebugOverlays, InAutoSize, InStationTags);
    }
}

USTRUCT()
struct FCk_EntityScript_GymStation_Showcase_AutoSizeTicker_SpawnParams
{
    UPROPERTY()
    FName StationTag = n"None";

    UPROPERTY()
    FText Title = FText::FromString("AUTO-SIZE RUNTIME");

    UPROPERTY()
    TArray<FText> DescriptionLines;

    UPROPERTY()
    float LineRevealInterval = 1.0;

    FCk_EntityScript_GymStation_Showcase_AutoSizeTicker_SpawnParams(FName InStationTag, FText InTitle, TArray<FText> InDescriptionLines, float InLineRevealInterval)
    {
        StationTag = InStationTag;
        Title = InTitle;
        DescriptionLines = InDescriptionLines;
        LineRevealInterval = InLineRevealInterval;
    }
}

namespace UCk_EntityScript_GymStation_Showcase_AutoSizeTicker
{
    FCk_EntityScript_GymStation_Showcase_AutoSizeTicker_SpawnParams Params()
    {
        return FCk_EntityScript_GymStation_Showcase_AutoSizeTicker_SpawnParams();
    }

    FCk_EntityScript_GymStation_Showcase_AutoSizeTicker_SpawnParams Params(FName InStationTag, FText InTitle, TArray<FText> InDescriptionLines, float InLineRevealInterval)
    {
        return FCk_EntityScript_GymStation_Showcase_AutoSizeTicker_SpawnParams(InStationTag, InTitle, InDescriptionLines, InLineRevealInterval);
    }
}

USTRUCT()
struct FCk_EntityScript_IntegerGym_Basic_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_EntityScript_IntegerGym_Basic_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_EntityScript_IntegerGym_Basic
{
    FCk_EntityScript_IntegerGym_Basic_SpawnParams Params()
    {
        return FCk_EntityScript_IntegerGym_Basic_SpawnParams();
    }

    FCk_EntityScript_IntegerGym_Basic_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_EntityScript_IntegerGym_Basic_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_EntityScript_IntegerGym_Clamping_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_EntityScript_IntegerGym_Clamping_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_EntityScript_IntegerGym_Clamping
{
    FCk_EntityScript_IntegerGym_Clamping_SpawnParams Params()
    {
        return FCk_EntityScript_IntegerGym_Clamping_SpawnParams();
    }

    FCk_EntityScript_IntegerGym_Clamping_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_EntityScript_IntegerGym_Clamping_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_EntityScript_IntegerGym_MinMaxCurrent_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_EntityScript_IntegerGym_MinMaxCurrent_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_EntityScript_IntegerGym_MinMaxCurrent
{
    FCk_EntityScript_IntegerGym_MinMaxCurrent_SpawnParams Params()
    {
        return FCk_EntityScript_IntegerGym_MinMaxCurrent_SpawnParams();
    }

    FCk_EntityScript_IntegerGym_MinMaxCurrent_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_EntityScript_IntegerGym_MinMaxCurrent_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_EntityScript_IntegerGym_Modifiers_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_EntityScript_IntegerGym_Modifiers_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_EntityScript_IntegerGym_Modifiers
{
    FCk_EntityScript_IntegerGym_Modifiers_SpawnParams Params()
    {
        return FCk_EntityScript_IntegerGym_Modifiers_SpawnParams();
    }

    FCk_EntityScript_IntegerGym_Modifiers_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_EntityScript_IntegerGym_Modifiers_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_EntityScript_InteractionGym_DataBundle_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_EntityScript_InteractionGym_DataBundle_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_EntityScript_InteractionGym_DataBundle
{
    FCk_EntityScript_InteractionGym_DataBundle_SpawnParams Params()
    {
        return FCk_EntityScript_InteractionGym_DataBundle_SpawnParams();
    }

    FCk_EntityScript_InteractionGym_DataBundle_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_EntityScript_InteractionGym_DataBundle_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_EntityScript_InteractionGym_Instant_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_EntityScript_InteractionGym_Instant_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_EntityScript_InteractionGym_Instant
{
    FCk_EntityScript_InteractionGym_Instant_SpawnParams Params()
    {
        return FCk_EntityScript_InteractionGym_Instant_SpawnParams();
    }

    FCk_EntityScript_InteractionGym_Instant_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_EntityScript_InteractionGym_Instant_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_EntityScript_InteractionGym_Manual_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_EntityScript_InteractionGym_Manual_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_EntityScript_InteractionGym_Manual
{
    FCk_EntityScript_InteractionGym_Manual_SpawnParams Params()
    {
        return FCk_EntityScript_InteractionGym_Manual_SpawnParams();
    }

    FCk_EntityScript_InteractionGym_Manual_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_EntityScript_InteractionGym_Manual_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_EntityScript_InteractionGym_ResolverSource_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_EntityScript_InteractionGym_ResolverSource_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_EntityScript_InteractionGym_ResolverSource
{
    FCk_EntityScript_InteractionGym_ResolverSource_SpawnParams Params()
    {
        return FCk_EntityScript_InteractionGym_ResolverSource_SpawnParams();
    }

    FCk_EntityScript_InteractionGym_ResolverSource_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_EntityScript_InteractionGym_ResolverSource_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_EntityScript_InteractionGym_ResolverTarget_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_EntityScript_InteractionGym_ResolverTarget_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_EntityScript_InteractionGym_ResolverTarget
{
    FCk_EntityScript_InteractionGym_ResolverTarget_SpawnParams Params()
    {
        return FCk_EntityScript_InteractionGym_ResolverTarget_SpawnParams();
    }

    FCk_EntityScript_InteractionGym_ResolverTarget_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_EntityScript_InteractionGym_ResolverTarget_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_EntityScript_InteractionGym_TimedSource_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_EntityScript_InteractionGym_TimedSource_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_EntityScript_InteractionGym_TimedSource
{
    FCk_EntityScript_InteractionGym_TimedSource_SpawnParams Params()
    {
        return FCk_EntityScript_InteractionGym_TimedSource_SpawnParams();
    }

    FCk_EntityScript_InteractionGym_TimedSource_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_EntityScript_InteractionGym_TimedSource_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_EntityScript_InteractionGym_TimedTarget_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_EntityScript_InteractionGym_TimedTarget_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_EntityScript_InteractionGym_TimedTarget
{
    FCk_EntityScript_InteractionGym_TimedTarget_SpawnParams Params()
    {
        return FCk_EntityScript_InteractionGym_TimedTarget_SpawnParams();
    }

    FCk_EntityScript_InteractionGym_TimedTarget_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_EntityScript_InteractionGym_TimedTarget_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_EntityScript_InteractionGym_Validation_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_EntityScript_InteractionGym_Validation_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_EntityScript_InteractionGym_Validation
{
    FCk_EntityScript_InteractionGym_Validation_SpawnParams Params()
    {
        return FCk_EntityScript_InteractionGym_Validation_SpawnParams();
    }

    FCk_EntityScript_InteractionGym_Validation_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_EntityScript_InteractionGym_Validation_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_EntityScript_InvGym_DataOnlyBounded_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_EntityScript_InvGym_DataOnlyBounded_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_EntityScript_InvGym_DataOnlyBounded
{
    FCk_EntityScript_InvGym_DataOnlyBounded_SpawnParams Params()
    {
        return FCk_EntityScript_InvGym_DataOnlyBounded_SpawnParams();
    }

    FCk_EntityScript_InvGym_DataOnlyBounded_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_EntityScript_InvGym_DataOnlyBounded_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_EntityScript_InvGym_DataOnlyUnbounded_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_EntityScript_InvGym_DataOnlyUnbounded_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_EntityScript_InvGym_DataOnlyUnbounded
{
    FCk_EntityScript_InvGym_DataOnlyUnbounded_SpawnParams Params()
    {
        return FCk_EntityScript_InvGym_DataOnlyUnbounded_SpawnParams();
    }

    FCk_EntityScript_InvGym_DataOnlyUnbounded_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_EntityScript_InvGym_DataOnlyUnbounded_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_EntityScript_InvGym_ShelfDesync_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_EntityScript_InvGym_ShelfDesync_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_EntityScript_InvGym_ShelfDesync
{
    FCk_EntityScript_InvGym_ShelfDesync_SpawnParams Params()
    {
        return FCk_EntityScript_InvGym_ShelfDesync_SpawnParams();
    }

    FCk_EntityScript_InvGym_ShelfDesync_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_EntityScript_InvGym_ShelfDesync_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_EntityScript_InvGym_Spatial_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_EntityScript_InvGym_Spatial_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_EntityScript_InvGym_Spatial
{
    FCk_EntityScript_InvGym_Spatial_SpawnParams Params()
    {
        return FCk_EntityScript_InvGym_Spatial_SpawnParams();
    }

    FCk_EntityScript_InvGym_Spatial_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_EntityScript_InvGym_Spatial_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_EntityScript_InvGym_StackableTrait_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_EntityScript_InvGym_StackableTrait_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_EntityScript_InvGym_StackableTrait
{
    FCk_EntityScript_InvGym_StackableTrait_SpawnParams Params()
    {
        return FCk_EntityScript_InvGym_StackableTrait_SpawnParams();
    }

    FCk_EntityScript_InvGym_StackableTrait_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_EntityScript_InvGym_StackableTrait_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_EntityScript_InvGym_TagsTrait_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_EntityScript_InvGym_TagsTrait_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_EntityScript_InvGym_TagsTrait
{
    FCk_EntityScript_InvGym_TagsTrait_SpawnParams Params()
    {
        return FCk_EntityScript_InvGym_TagsTrait_SpawnParams();
    }

    FCk_EntityScript_InvGym_TagsTrait_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_EntityScript_InvGym_TagsTrait_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_EntityScript_IskmRendererGym_AnimBPDemo_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_EntityScript_IskmRendererGym_AnimBPDemo_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_EntityScript_IskmRendererGym_AnimBPDemo
{
    FCk_EntityScript_IskmRendererGym_AnimBPDemo_SpawnParams Params()
    {
        return FCk_EntityScript_IskmRendererGym_AnimBPDemo_SpawnParams();
    }

    FCk_EntityScript_IskmRendererGym_AnimBPDemo_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_EntityScript_IskmRendererGym_AnimBPDemo_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_EntityScript_IskmRendererGym_CustomData_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_EntityScript_IskmRendererGym_CustomData_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_EntityScript_IskmRendererGym_CustomData
{
    FCk_EntityScript_IskmRendererGym_CustomData_SpawnParams Params()
    {
        return FCk_EntityScript_IskmRendererGym_CustomData_SpawnParams();
    }

    FCk_EntityScript_IskmRendererGym_CustomData_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_EntityScript_IskmRendererGym_CustomData_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_EntityScript_IskmRendererGym_MontageBurst_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_EntityScript_IskmRendererGym_MontageBurst_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_EntityScript_IskmRendererGym_MontageBurst
{
    FCk_EntityScript_IskmRendererGym_MontageBurst_SpawnParams Params()
    {
        return FCk_EntityScript_IskmRendererGym_MontageBurst_SpawnParams();
    }

    FCk_EntityScript_IskmRendererGym_MontageBurst_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_EntityScript_IskmRendererGym_MontageBurst_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_EntityScript_IskmRendererGym_OutfitSwap_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_EntityScript_IskmRendererGym_OutfitSwap_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_EntityScript_IskmRendererGym_OutfitSwap
{
    FCk_EntityScript_IskmRendererGym_OutfitSwap_SpawnParams Params()
    {
        return FCk_EntityScript_IskmRendererGym_OutfitSwap_SpawnParams();
    }

    FCk_EntityScript_IskmRendererGym_OutfitSwap_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_EntityScript_IskmRendererGym_OutfitSwap_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_EntityScript_IskmRendererGym_RagdollDemo_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_EntityScript_IskmRendererGym_RagdollDemo_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_EntityScript_IskmRendererGym_RagdollDemo
{
    FCk_EntityScript_IskmRendererGym_RagdollDemo_SpawnParams Params()
    {
        return FCk_EntityScript_IskmRendererGym_RagdollDemo_SpawnParams();
    }

    FCk_EntityScript_IskmRendererGym_RagdollDemo_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_EntityScript_IskmRendererGym_RagdollDemo_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_EntityScript_IskmRendererGym_SpawnArmy_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_EntityScript_IskmRendererGym_SpawnArmy_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_EntityScript_IskmRendererGym_SpawnArmy
{
    FCk_EntityScript_IskmRendererGym_SpawnArmy_SpawnParams Params()
    {
        return FCk_EntityScript_IskmRendererGym_SpawnArmy_SpawnParams();
    }

    FCk_EntityScript_IskmRendererGym_SpawnArmy_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_EntityScript_IskmRendererGym_SpawnArmy_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_EntityScript_IskmRendererGym_StressArmy_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    UPROPERTY()
    int Count = 500;

    UPROPERTY()
    bool Moving = false;

    FCk_EntityScript_IskmRendererGym_StressArmy_SpawnParams(FTransform InInitialTransform, int InCount, bool InMoving)
    {
        InitialTransform = InInitialTransform;
        Count = InCount;
        Moving = InMoving;
    }
}

namespace UCk_EntityScript_IskmRendererGym_StressArmy
{
    FCk_EntityScript_IskmRendererGym_StressArmy_SpawnParams Params()
    {
        return FCk_EntityScript_IskmRendererGym_StressArmy_SpawnParams();
    }

    FCk_EntityScript_IskmRendererGym_StressArmy_SpawnParams Params(FTransform InInitialTransform, int InCount, bool InMoving)
    {
        return FCk_EntityScript_IskmRendererGym_StressArmy_SpawnParams(InInitialTransform, InCount, InMoving);
    }
}

USTRUCT()
struct FCk_EntityScript_IskmRendererGym_TransitionCycle_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_EntityScript_IskmRendererGym_TransitionCycle_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_EntityScript_IskmRendererGym_TransitionCycle
{
    FCk_EntityScript_IskmRendererGym_TransitionCycle_SpawnParams Params()
    {
        return FCk_EntityScript_IskmRendererGym_TransitionCycle_SpawnParams();
    }

    FCk_EntityScript_IskmRendererGym_TransitionCycle_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_EntityScript_IskmRendererGym_TransitionCycle_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_EntityScript_MessagingGym_Basic_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_EntityScript_MessagingGym_Basic_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_EntityScript_MessagingGym_Basic
{
    FCk_EntityScript_MessagingGym_Basic_SpawnParams Params()
    {
        return FCk_EntityScript_MessagingGym_Basic_SpawnParams();
    }

    FCk_EntityScript_MessagingGym_Basic_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_EntityScript_MessagingGym_Basic_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_EntityScript_MessagingGym_DynamicBind_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_EntityScript_MessagingGym_DynamicBind_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_EntityScript_MessagingGym_DynamicBind
{
    FCk_EntityScript_MessagingGym_DynamicBind_SpawnParams Params()
    {
        return FCk_EntityScript_MessagingGym_DynamicBind_SpawnParams();
    }

    FCk_EntityScript_MessagingGym_DynamicBind_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_EntityScript_MessagingGym_DynamicBind_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_EntityScript_MessagingGym_MultiListener_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_EntityScript_MessagingGym_MultiListener_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_EntityScript_MessagingGym_MultiListener
{
    FCk_EntityScript_MessagingGym_MultiListener_SpawnParams Params()
    {
        return FCk_EntityScript_MessagingGym_MultiListener_SpawnParams();
    }

    FCk_EntityScript_MessagingGym_MultiListener_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_EntityScript_MessagingGym_MultiListener_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_EntityScript_MessagingGym_MultiType_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_EntityScript_MessagingGym_MultiType_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_EntityScript_MessagingGym_MultiType
{
    FCk_EntityScript_MessagingGym_MultiType_SpawnParams Params()
    {
        return FCk_EntityScript_MessagingGym_MultiType_SpawnParams();
    }

    FCk_EntityScript_MessagingGym_MultiType_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_EntityScript_MessagingGym_MultiType_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_EntityScript_MessagingGym_OneShot_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_EntityScript_MessagingGym_OneShot_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_EntityScript_MessagingGym_OneShot
{
    FCk_EntityScript_MessagingGym_OneShot_SpawnParams Params()
    {
        return FCk_EntityScript_MessagingGym_OneShot_SpawnParams();
    }

    FCk_EntityScript_MessagingGym_OneShot_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_EntityScript_MessagingGym_OneShot_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_EntityScript_PlannerT1_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_EntityScript_PlannerT1_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_EntityScript_PlannerT1
{
    FCk_EntityScript_PlannerT1_SpawnParams Params()
    {
        return FCk_EntityScript_PlannerT1_SpawnParams();
    }

    FCk_EntityScript_PlannerT1_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_EntityScript_PlannerT1_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_EntityScript_PlannerT2_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_EntityScript_PlannerT2_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_EntityScript_PlannerT2
{
    FCk_EntityScript_PlannerT2_SpawnParams Params()
    {
        return FCk_EntityScript_PlannerT2_SpawnParams();
    }

    FCk_EntityScript_PlannerT2_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_EntityScript_PlannerT2_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_EntityScript_PlannerT4_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_EntityScript_PlannerT4_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_EntityScript_PlannerT4
{
    FCk_EntityScript_PlannerT4_SpawnParams Params()
    {
        return FCk_EntityScript_PlannerT4_SpawnParams();
    }

    FCk_EntityScript_PlannerT4_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_EntityScript_PlannerT4_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_EntityScript_PlannerT5_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_EntityScript_PlannerT5_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_EntityScript_PlannerT5
{
    FCk_EntityScript_PlannerT5_SpawnParams Params()
    {
        return FCk_EntityScript_PlannerT5_SpawnParams();
    }

    FCk_EntityScript_PlannerT5_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_EntityScript_PlannerT5_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_EntityScript_ProbeGym_DebugStation_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_EntityScript_ProbeGym_DebugStation_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_EntityScript_ProbeGym_DebugStation
{
    FCk_EntityScript_ProbeGym_DebugStation_SpawnParams Params()
    {
        return FCk_EntityScript_ProbeGym_DebugStation_SpawnParams();
    }

    FCk_EntityScript_ProbeGym_DebugStation_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_EntityScript_ProbeGym_DebugStation_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_EntityScript_ProbeGym_NestedSceneNodeStation_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_EntityScript_ProbeGym_NestedSceneNodeStation_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_EntityScript_ProbeGym_NestedSceneNodeStation
{
    FCk_EntityScript_ProbeGym_NestedSceneNodeStation_SpawnParams Params()
    {
        return FCk_EntityScript_ProbeGym_NestedSceneNodeStation_SpawnParams();
    }

    FCk_EntityScript_ProbeGym_NestedSceneNodeStation_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_EntityScript_ProbeGym_NestedSceneNodeStation_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_EntityScript_ProbeGym_PhysicalStation_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_EntityScript_ProbeGym_PhysicalStation_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_EntityScript_ProbeGym_PhysicalStation
{
    FCk_EntityScript_ProbeGym_PhysicalStation_SpawnParams Params()
    {
        return FCk_EntityScript_ProbeGym_PhysicalStation_SpawnParams();
    }

    FCk_EntityScript_ProbeGym_PhysicalStation_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_EntityScript_ProbeGym_PhysicalStation_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_EntityScript_ProbeGym_PhysicalStation_Single_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_EntityScript_ProbeGym_PhysicalStation_Single_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_EntityScript_ProbeGym_PhysicalStation_Single
{
    FCk_EntityScript_ProbeGym_PhysicalStation_Single_SpawnParams Params()
    {
        return FCk_EntityScript_ProbeGym_PhysicalStation_Single_SpawnParams();
    }

    FCk_EntityScript_ProbeGym_PhysicalStation_Single_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_EntityScript_ProbeGym_PhysicalStation_Single_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_EntityScript_ProbeGym_StationaryHierarchyStation_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_EntityScript_ProbeGym_StationaryHierarchyStation_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_EntityScript_ProbeGym_StationaryHierarchyStation
{
    FCk_EntityScript_ProbeGym_StationaryHierarchyStation_SpawnParams Params()
    {
        return FCk_EntityScript_ProbeGym_StationaryHierarchyStation_SpawnParams();
    }

    FCk_EntityScript_ProbeGym_StationaryHierarchyStation_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_EntityScript_ProbeGym_StationaryHierarchyStation_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_EntityScript_SceneNodeGym_Display_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    UPROPERTY()
    ACk_SceneNodeGym_Cube LinkedCube = nullptr;

    FCk_EntityScript_SceneNodeGym_Display_SpawnParams(FTransform InInitialTransform, ACk_SceneNodeGym_Cube InLinkedCube)
    {
        InitialTransform = InInitialTransform;
        LinkedCube = InLinkedCube;
    }
}

namespace UCk_EntityScript_SceneNodeGym_Display
{
    FCk_EntityScript_SceneNodeGym_Display_SpawnParams Params()
    {
        return FCk_EntityScript_SceneNodeGym_Display_SpawnParams();
    }

    FCk_EntityScript_SceneNodeGym_Display_SpawnParams Params(FTransform InInitialTransform, ACk_SceneNodeGym_Cube InLinkedCube)
    {
        return FCk_EntityScript_SceneNodeGym_Display_SpawnParams(InInitialTransform, InLinkedCube);
    }
}

USTRUCT()
struct FCk_EntityScript_SceneNodeTweenGym_ChainStation_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_EntityScript_SceneNodeTweenGym_ChainStation_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_EntityScript_SceneNodeTweenGym_ChainStation
{
    FCk_EntityScript_SceneNodeTweenGym_ChainStation_SpawnParams Params()
    {
        return FCk_EntityScript_SceneNodeTweenGym_ChainStation_SpawnParams();
    }

    FCk_EntityScript_SceneNodeTweenGym_ChainStation_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_EntityScript_SceneNodeTweenGym_ChainStation_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_EntityScript_SceneNodeTweenGym_DeepStation_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_EntityScript_SceneNodeTweenGym_DeepStation_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_EntityScript_SceneNodeTweenGym_DeepStation
{
    FCk_EntityScript_SceneNodeTweenGym_DeepStation_SpawnParams Params()
    {
        return FCk_EntityScript_SceneNodeTweenGym_DeepStation_SpawnParams();
    }

    FCk_EntityScript_SceneNodeTweenGym_DeepStation_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_EntityScript_SceneNodeTweenGym_DeepStation_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_EntityScript_SceneNodeTweenGym_SimpleStation_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_EntityScript_SceneNodeTweenGym_SimpleStation_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_EntityScript_SceneNodeTweenGym_SimpleStation
{
    FCk_EntityScript_SceneNodeTweenGym_SimpleStation_SpawnParams Params()
    {
        return FCk_EntityScript_SceneNodeTweenGym_SimpleStation_SpawnParams();
    }

    FCk_EntityScript_SceneNodeTweenGym_SimpleStation_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_EntityScript_SceneNodeTweenGym_SimpleStation_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_EntityScript_TimerGym_Basics_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_EntityScript_TimerGym_Basics_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_EntityScript_TimerGym_Basics
{
    FCk_EntityScript_TimerGym_Basics_SpawnParams Params()
    {
        return FCk_EntityScript_TimerGym_Basics_SpawnParams();
    }

    FCk_EntityScript_TimerGym_Basics_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_EntityScript_TimerGym_Basics_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_EntityScript_TimerGym_Behaviors_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_EntityScript_TimerGym_Behaviors_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_EntityScript_TimerGym_Behaviors
{
    FCk_EntityScript_TimerGym_Behaviors_SpawnParams Params()
    {
        return FCk_EntityScript_TimerGym_Behaviors_SpawnParams();
    }

    FCk_EntityScript_TimerGym_Behaviors_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_EntityScript_TimerGym_Behaviors_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_EntityScript_TimerGym_Control_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_EntityScript_TimerGym_Control_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_EntityScript_TimerGym_Control
{
    FCk_EntityScript_TimerGym_Control_SpawnParams Params()
    {
        return FCk_EntityScript_TimerGym_Control_SpawnParams();
    }

    FCk_EntityScript_TimerGym_Control_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_EntityScript_TimerGym_Control_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_EntityScript_TimerGym_Countdown_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_EntityScript_TimerGym_Countdown_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_EntityScript_TimerGym_Countdown
{
    FCk_EntityScript_TimerGym_Countdown_SpawnParams Params()
    {
        return FCk_EntityScript_TimerGym_Countdown_SpawnParams();
    }

    FCk_EntityScript_TimerGym_Countdown_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_EntityScript_TimerGym_Countdown_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_EntityScript_TimerGym_Signals_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_EntityScript_TimerGym_Signals_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_EntityScript_TimerGym_Signals
{
    FCk_EntityScript_TimerGym_Signals_SpawnParams Params()
    {
        return FCk_EntityScript_TimerGym_Signals_SpawnParams();
    }

    FCk_EntityScript_TimerGym_Signals_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_EntityScript_TimerGym_Signals_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_EntityScript_TransformGym_Display_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    UPROPERTY()
    ACk_TransformGym_Cube LinkedCube = nullptr;

    FCk_EntityScript_TransformGym_Display_SpawnParams(FTransform InInitialTransform, ACk_TransformGym_Cube InLinkedCube)
    {
        InitialTransform = InInitialTransform;
        LinkedCube = InLinkedCube;
    }
}

namespace UCk_EntityScript_TransformGym_Display
{
    FCk_EntityScript_TransformGym_Display_SpawnParams Params()
    {
        return FCk_EntityScript_TransformGym_Display_SpawnParams();
    }

    FCk_EntityScript_TransformGym_Display_SpawnParams Params(FTransform InInitialTransform, ACk_TransformGym_Cube InLinkedCube)
    {
        return FCk_EntityScript_TransformGym_Display_SpawnParams(InInitialTransform, InLinkedCube);
    }
}

USTRUCT()
struct FCk_EntityScript_UnrealComponentGym_Display_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    UPROPERTY()
    ACk_UnrealComponentGym_Driver LinkedDriver = nullptr;

    FCk_EntityScript_UnrealComponentGym_Display_SpawnParams(FTransform InInitialTransform, ACk_UnrealComponentGym_Driver InLinkedDriver)
    {
        InitialTransform = InInitialTransform;
        LinkedDriver = InLinkedDriver;
    }
}

namespace UCk_EntityScript_UnrealComponentGym_Display
{
    FCk_EntityScript_UnrealComponentGym_Display_SpawnParams Params()
    {
        return FCk_EntityScript_UnrealComponentGym_Display_SpawnParams();
    }

    FCk_EntityScript_UnrealComponentGym_Display_SpawnParams Params(FTransform InInitialTransform, ACk_UnrealComponentGym_Driver InLinkedDriver)
    {
        return FCk_EntityScript_UnrealComponentGym_Display_SpawnParams(InInitialTransform, InLinkedDriver);
    }
}

USTRUCT()
struct FCk_ReplicationGym_PawnExtra_EntityScript_SpawnParams
{
    UPROPERTY()
    const TObjectPtr<AActor> _OwningActor = nullptr;

    FCk_ReplicationGym_PawnExtra_EntityScript_SpawnParams(const TObjectPtr<AActor> In_OwningActor)
    {
        _OwningActor = In_OwningActor;
    }
}

namespace UCk_ReplicationGym_PawnExtra_EntityScript
{
    FCk_ReplicationGym_PawnExtra_EntityScript_SpawnParams Params()
    {
        return FCk_ReplicationGym_PawnExtra_EntityScript_SpawnParams();
    }

    FCk_ReplicationGym_PawnExtra_EntityScript_SpawnParams Params(const TObjectPtr<AActor> In_OwningActor)
    {
        return FCk_ReplicationGym_PawnExtra_EntityScript_SpawnParams(In_OwningActor);
    }
}

USTRUCT()
struct FCk_ReplicationGym_ReplicatedActor_EntityScript_SpawnParams
{
    UPROPERTY()
    const TObjectPtr<AActor> _OwningActor = nullptr;

    FCk_ReplicationGym_ReplicatedActor_EntityScript_SpawnParams(const TObjectPtr<AActor> In_OwningActor)
    {
        _OwningActor = In_OwningActor;
    }
}

namespace UCk_ReplicationGym_ReplicatedActor_EntityScript
{
    FCk_ReplicationGym_ReplicatedActor_EntityScript_SpawnParams Params()
    {
        return FCk_ReplicationGym_ReplicatedActor_EntityScript_SpawnParams();
    }

    FCk_ReplicationGym_ReplicatedActor_EntityScript_SpawnParams Params(const TObjectPtr<AActor> In_OwningActor)
    {
        return FCk_ReplicationGym_ReplicatedActor_EntityScript_SpawnParams(In_OwningActor);
    }
}

USTRUCT()
struct FCk_SimpleBackgroundMusicCue_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_SimpleBackgroundMusicCue_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_SimpleBackgroundMusicCue
{
    FCk_SimpleBackgroundMusicCue_SpawnParams Params()
    {
        return FCk_SimpleBackgroundMusicCue_SpawnParams();
    }

    FCk_SimpleBackgroundMusicCue_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_SimpleBackgroundMusicCue_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_SimpleSpatialAudioCue_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_SimpleSpatialAudioCue_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UCk_SimpleSpatialAudioCue
{
    FCk_SimpleSpatialAudioCue_SpawnParams Params()
    {
        return FCk_SimpleSpatialAudioCue_SpawnParams();
    }

    FCk_SimpleSpatialAudioCue_SpawnParams Params(FTransform InInitialTransform)
    {
        return FCk_SimpleSpatialAudioCue_SpawnParams(InInitialTransform);
    }
}

USTRUCT()
struct FCk_SmTest_AlwaysTrue_State_Finish_SpawnParams
{
}

namespace UCk_SmTest_AlwaysTrue_State_Finish
{
    FCk_SmTest_AlwaysTrue_State_Finish_SpawnParams Params()
    {
        return FCk_SmTest_AlwaysTrue_State_Finish_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_AlwaysTrue_State_Idle_SpawnParams
{
}

namespace UCk_SmTest_AlwaysTrue_State_Idle
{
    FCk_SmTest_AlwaysTrue_State_Idle_SpawnParams Params()
    {
        return FCk_SmTest_AlwaysTrue_State_Idle_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_Complex_State_Attack_SpawnParams
{
}

namespace UCk_SmTest_Complex_State_Attack
{
    FCk_SmTest_Complex_State_Attack_SpawnParams Params()
    {
        return FCk_SmTest_Complex_State_Attack_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_Complex_State_Chase_SpawnParams
{
}

namespace UCk_SmTest_Complex_State_Chase
{
    FCk_SmTest_Complex_State_Chase_SpawnParams Params()
    {
        return FCk_SmTest_Complex_State_Chase_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_Complex_State_Flee_SpawnParams
{
}

namespace UCk_SmTest_Complex_State_Flee
{
    FCk_SmTest_Complex_State_Flee_SpawnParams Params()
    {
        return FCk_SmTest_Complex_State_Flee_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_Complex_State_Idle_SpawnParams
{
}

namespace UCk_SmTest_Complex_State_Idle
{
    FCk_SmTest_Complex_State_Idle_SpawnParams Params()
    {
        return FCk_SmTest_Complex_State_Idle_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_Complex_State_Patrol_SpawnParams
{
}

namespace UCk_SmTest_Complex_State_Patrol
{
    FCk_SmTest_Complex_State_Patrol_SpawnParams Params()
    {
        return FCk_SmTest_Complex_State_Patrol_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_Complex_State_Search_SpawnParams
{
}

namespace UCk_SmTest_Complex_State_Search
{
    FCk_SmTest_Complex_State_Search_SpawnParams Params()
    {
        return FCk_SmTest_Complex_State_Search_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_Condition_AfterDelay_SpawnParams
{
}

namespace UCk_SmTest_Condition_AfterDelay
{
    FCk_SmTest_Condition_AfterDelay_SpawnParams Params()
    {
        return FCk_SmTest_Condition_AfterDelay_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_Condition_AlwaysTrue_SpawnParams
{
}

namespace UCk_SmTest_Condition_AlwaysTrue
{
    FCk_SmTest_Condition_AlwaysTrue_SpawnParams Params()
    {
        return FCk_SmTest_Condition_AlwaysTrue_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_Condition_LongDelay_SpawnParams
{
}

namespace UCk_SmTest_Condition_LongDelay
{
    FCk_SmTest_Condition_LongDelay_SpawnParams Params()
    {
        return FCk_SmTest_Condition_LongDelay_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_Condition_PolledFalse_SpawnParams
{
}

namespace UCk_SmTest_Condition_PolledFalse
{
    FCk_SmTest_Condition_PolledFalse_SpawnParams Params()
    {
        return FCk_SmTest_Condition_PolledFalse_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_Condition_PolledTimer_SpawnParams
{
}

namespace UCk_SmTest_Condition_PolledTimer
{
    FCk_SmTest_Condition_PolledTimer_SpawnParams Params()
    {
        return FCk_SmTest_Condition_PolledTimer_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_Condition_ShortDelay_SpawnParams
{
}

namespace UCk_SmTest_Condition_ShortDelay
{
    FCk_SmTest_Condition_ShortDelay_SpawnParams Params()
    {
        return FCk_SmTest_Condition_ShortDelay_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_Divergence_Condition_PaymentIsLeft_SpawnParams
{
}

namespace UCk_SmTest_Divergence_Condition_PaymentIsLeft
{
    FCk_SmTest_Divergence_Condition_PaymentIsLeft_SpawnParams Params()
    {
        return FCk_SmTest_Divergence_Condition_PaymentIsLeft_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_Divergence_Condition_PaymentIsRight_SpawnParams
{
}

namespace UCk_SmTest_Divergence_Condition_PaymentIsRight
{
    FCk_SmTest_Divergence_Condition_PaymentIsRight_SpawnParams Params()
    {
        return FCk_SmTest_Divergence_Condition_PaymentIsRight_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_Divergence_ParentState_SpawnParams
{
}

namespace UCk_SmTest_Divergence_ParentState
{
    FCk_SmTest_Divergence_ParentState_SpawnParams Params()
    {
        return FCk_SmTest_Divergence_ParentState_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_Divergence_State_Branch_SpawnParams
{
}

namespace UCk_SmTest_Divergence_State_Branch
{
    FCk_SmTest_Divergence_State_Branch_SpawnParams Params()
    {
        return FCk_SmTest_Divergence_State_Branch_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_Divergence_State_Enter_SpawnParams
{
}

namespace UCk_SmTest_Divergence_State_Enter
{
    FCk_SmTest_Divergence_State_Enter_SpawnParams Params()
    {
        return FCk_SmTest_Divergence_State_Enter_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_Divergence_State_Finish_SpawnParams
{
}

namespace UCk_SmTest_Divergence_State_Finish
{
    FCk_SmTest_Divergence_State_Finish_SpawnParams Params()
    {
        return FCk_SmTest_Divergence_State_Finish_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_Divergence_State_Idle_SpawnParams
{
}

namespace UCk_SmTest_Divergence_State_Idle
{
    FCk_SmTest_Divergence_State_Idle_SpawnParams Params()
    {
        return FCk_SmTest_Divergence_State_Idle_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_Divergence_State_Left_SpawnParams
{
}

namespace UCk_SmTest_Divergence_State_Left
{
    FCk_SmTest_Divergence_State_Left_SpawnParams Params()
    {
        return FCk_SmTest_Divergence_State_Left_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_Divergence_State_Right_SpawnParams
{
}

namespace UCk_SmTest_Divergence_State_Right
{
    FCk_SmTest_Divergence_State_Right_SpawnParams Params()
    {
        return FCk_SmTest_Divergence_State_Right_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_Divergence_SubSmTask_SpawnParams
{
}

namespace UCk_SmTest_Divergence_SubSmTask
{
    FCk_SmTest_Divergence_SubSmTask_SpawnParams Params()
    {
        return FCk_SmTest_Divergence_SubSmTask_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_Divergence_Task_Branch_SpawnParams
{
}

namespace UCk_SmTest_Divergence_Task_Branch
{
    FCk_SmTest_Divergence_Task_Branch_SpawnParams Params()
    {
        return FCk_SmTest_Divergence_Task_Branch_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_Divergence_Task_Enter_SpawnParams
{
}

namespace UCk_SmTest_Divergence_Task_Enter
{
    FCk_SmTest_Divergence_Task_Enter_SpawnParams Params()
    {
        return FCk_SmTest_Divergence_Task_Enter_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_Divergence_Task_Finish_SpawnParams
{
}

namespace UCk_SmTest_Divergence_Task_Finish
{
    FCk_SmTest_Divergence_Task_Finish_SpawnParams Params()
    {
        return FCk_SmTest_Divergence_Task_Finish_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_Divergence_Task_Idle_SpawnParams
{
}

namespace UCk_SmTest_Divergence_Task_Idle
{
    FCk_SmTest_Divergence_Task_Idle_SpawnParams Params()
    {
        return FCk_SmTest_Divergence_Task_Idle_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_Divergence_Task_Left_SpawnParams
{
}

namespace UCk_SmTest_Divergence_Task_Left
{
    FCk_SmTest_Divergence_Task_Left_SpawnParams Params()
    {
        return FCk_SmTest_Divergence_Task_Left_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_Divergence_Task_Right_SpawnParams
{
}

namespace UCk_SmTest_Divergence_Task_Right
{
    FCk_SmTest_Divergence_Task_Right_SpawnParams Params()
    {
        return FCk_SmTest_Divergence_Task_Right_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_DivergenceTimed_Condition_FastDelay_SpawnParams
{
}

namespace UCk_SmTest_DivergenceTimed_Condition_FastDelay
{
    FCk_SmTest_DivergenceTimed_Condition_FastDelay_SpawnParams Params()
    {
        return FCk_SmTest_DivergenceTimed_Condition_FastDelay_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_DivergenceTimed_Condition_PaymentIsLeft_SpawnParams
{
}

namespace UCk_SmTest_DivergenceTimed_Condition_PaymentIsLeft
{
    FCk_SmTest_DivergenceTimed_Condition_PaymentIsLeft_SpawnParams Params()
    {
        return FCk_SmTest_DivergenceTimed_Condition_PaymentIsLeft_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_DivergenceTimed_Condition_PaymentIsRight_SpawnParams
{
}

namespace UCk_SmTest_DivergenceTimed_Condition_PaymentIsRight
{
    FCk_SmTest_DivergenceTimed_Condition_PaymentIsRight_SpawnParams Params()
    {
        return FCk_SmTest_DivergenceTimed_Condition_PaymentIsRight_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_DivergenceTimed_ParentState_SpawnParams
{
}

namespace UCk_SmTest_DivergenceTimed_ParentState
{
    FCk_SmTest_DivergenceTimed_ParentState_SpawnParams Params()
    {
        return FCk_SmTest_DivergenceTimed_ParentState_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_DivergenceTimed_State_Branch_SpawnParams
{
}

namespace UCk_SmTest_DivergenceTimed_State_Branch
{
    FCk_SmTest_DivergenceTimed_State_Branch_SpawnParams Params()
    {
        return FCk_SmTest_DivergenceTimed_State_Branch_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_DivergenceTimed_State_Enter_SpawnParams
{
}

namespace UCk_SmTest_DivergenceTimed_State_Enter
{
    FCk_SmTest_DivergenceTimed_State_Enter_SpawnParams Params()
    {
        return FCk_SmTest_DivergenceTimed_State_Enter_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_DivergenceTimed_State_Finish_SpawnParams
{
}

namespace UCk_SmTest_DivergenceTimed_State_Finish
{
    FCk_SmTest_DivergenceTimed_State_Finish_SpawnParams Params()
    {
        return FCk_SmTest_DivergenceTimed_State_Finish_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_DivergenceTimed_State_Idle_SpawnParams
{
}

namespace UCk_SmTest_DivergenceTimed_State_Idle
{
    FCk_SmTest_DivergenceTimed_State_Idle_SpawnParams Params()
    {
        return FCk_SmTest_DivergenceTimed_State_Idle_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_DivergenceTimed_State_Left_SpawnParams
{
}

namespace UCk_SmTest_DivergenceTimed_State_Left
{
    FCk_SmTest_DivergenceTimed_State_Left_SpawnParams Params()
    {
        return FCk_SmTest_DivergenceTimed_State_Left_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_DivergenceTimed_State_Right_SpawnParams
{
}

namespace UCk_SmTest_DivergenceTimed_State_Right
{
    FCk_SmTest_DivergenceTimed_State_Right_SpawnParams Params()
    {
        return FCk_SmTest_DivergenceTimed_State_Right_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_DivergenceTimed_SubSmTask_SpawnParams
{
}

namespace UCk_SmTest_DivergenceTimed_SubSmTask
{
    FCk_SmTest_DivergenceTimed_SubSmTask_SpawnParams Params()
    {
        return FCk_SmTest_DivergenceTimed_SubSmTask_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_DivergenceTimed_Task_Branch_SpawnParams
{
}

namespace UCk_SmTest_DivergenceTimed_Task_Branch
{
    FCk_SmTest_DivergenceTimed_Task_Branch_SpawnParams Params()
    {
        return FCk_SmTest_DivergenceTimed_Task_Branch_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_DivergenceTimed_Task_Enter_SpawnParams
{
}

namespace UCk_SmTest_DivergenceTimed_Task_Enter
{
    FCk_SmTest_DivergenceTimed_Task_Enter_SpawnParams Params()
    {
        return FCk_SmTest_DivergenceTimed_Task_Enter_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_DivergenceTimed_Task_Finish_SpawnParams
{
}

namespace UCk_SmTest_DivergenceTimed_Task_Finish
{
    FCk_SmTest_DivergenceTimed_Task_Finish_SpawnParams Params()
    {
        return FCk_SmTest_DivergenceTimed_Task_Finish_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_DivergenceTimed_Task_Idle_SpawnParams
{
}

namespace UCk_SmTest_DivergenceTimed_Task_Idle
{
    FCk_SmTest_DivergenceTimed_Task_Idle_SpawnParams Params()
    {
        return FCk_SmTest_DivergenceTimed_Task_Idle_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_DivergenceTimed_Task_Left_SpawnParams
{
}

namespace UCk_SmTest_DivergenceTimed_Task_Left
{
    FCk_SmTest_DivergenceTimed_Task_Left_SpawnParams Params()
    {
        return FCk_SmTest_DivergenceTimed_Task_Left_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_DivergenceTimed_Task_Right_SpawnParams
{
}

namespace UCk_SmTest_DivergenceTimed_Task_Right
{
    FCk_SmTest_DivergenceTimed_Task_Right_SpawnParams Params()
    {
        return FCk_SmTest_DivergenceTimed_Task_Right_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_EventDrivenMultiCondition_Condition_FastEvent_SpawnParams
{
}

namespace UCk_SmTest_EventDrivenMultiCondition_Condition_FastEvent
{
    FCk_SmTest_EventDrivenMultiCondition_Condition_FastEvent_SpawnParams Params()
    {
        return FCk_SmTest_EventDrivenMultiCondition_Condition_FastEvent_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_EventDrivenMultiCondition_Condition_SlowEvent_SpawnParams
{
}

namespace UCk_SmTest_EventDrivenMultiCondition_Condition_SlowEvent
{
    FCk_SmTest_EventDrivenMultiCondition_Condition_SlowEvent_SpawnParams Params()
    {
        return FCk_SmTest_EventDrivenMultiCondition_Condition_SlowEvent_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_EventDrivenMultiCondition_State_Finish_SpawnParams
{
}

namespace UCk_SmTest_EventDrivenMultiCondition_State_Finish
{
    FCk_SmTest_EventDrivenMultiCondition_State_Finish_SpawnParams Params()
    {
        return FCk_SmTest_EventDrivenMultiCondition_State_Finish_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_EventDrivenMultiCondition_State_Idle_SpawnParams
{
}

namespace UCk_SmTest_EventDrivenMultiCondition_State_Idle
{
    FCk_SmTest_EventDrivenMultiCondition_State_Idle_SpawnParams Params()
    {
        return FCk_SmTest_EventDrivenMultiCondition_State_Idle_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_EventDrivenMultiCondition_Task_Finish_SpawnParams
{
}

namespace UCk_SmTest_EventDrivenMultiCondition_Task_Finish
{
    FCk_SmTest_EventDrivenMultiCondition_Task_Finish_SpawnParams Params()
    {
        return FCk_SmTest_EventDrivenMultiCondition_Task_Finish_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_GraphWalk_Sub_State_A_SpawnParams
{
}

namespace UCk_SmTest_GraphWalk_Sub_State_A
{
    FCk_SmTest_GraphWalk_Sub_State_A_SpawnParams Params()
    {
        return FCk_SmTest_GraphWalk_Sub_State_A_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_GraphWalk_Sub_State_B_SpawnParams
{
}

namespace UCk_SmTest_GraphWalk_Sub_State_B
{
    FCk_SmTest_GraphWalk_Sub_State_B_SpawnParams Params()
    {
        return FCk_SmTest_GraphWalk_Sub_State_B_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_GraphWalk_Sub_State_C_SpawnParams
{
}

namespace UCk_SmTest_GraphWalk_Sub_State_C
{
    FCk_SmTest_GraphWalk_Sub_State_C_SpawnParams Params()
    {
        return FCk_SmTest_GraphWalk_Sub_State_C_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_GraphWalk_Sub_State_D_SpawnParams
{
}

namespace UCk_SmTest_GraphWalk_Sub_State_D
{
    FCk_SmTest_GraphWalk_Sub_State_D_SpawnParams Params()
    {
        return FCk_SmTest_GraphWalk_Sub_State_D_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_GraphWalk_Sub_State_E_SpawnParams
{
}

namespace UCk_SmTest_GraphWalk_Sub_State_E
{
    FCk_SmTest_GraphWalk_Sub_State_E_SpawnParams Params()
    {
        return FCk_SmTest_GraphWalk_Sub_State_E_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_GraphWalk_SubSmTask_SpawnParams
{
}

namespace UCk_SmTest_GraphWalk_SubSmTask
{
    FCk_SmTest_GraphWalk_SubSmTask_SpawnParams Params()
    {
        return FCk_SmTest_GraphWalk_SubSmTask_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_GraphWalk_SubSmWrapper_State_SpawnParams
{
}

namespace UCk_SmTest_GraphWalk_SubSmWrapper_State
{
    FCk_SmTest_GraphWalk_SubSmWrapper_State_SpawnParams Params()
    {
        return FCk_SmTest_GraphWalk_SubSmWrapper_State_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_GraphWalk_Top_State_A_SpawnParams
{
}

namespace UCk_SmTest_GraphWalk_Top_State_A
{
    FCk_SmTest_GraphWalk_Top_State_A_SpawnParams Params()
    {
        return FCk_SmTest_GraphWalk_Top_State_A_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_GraphWalk_Top_State_B_SpawnParams
{
}

namespace UCk_SmTest_GraphWalk_Top_State_B
{
    FCk_SmTest_GraphWalk_Top_State_B_SpawnParams Params()
    {
        return FCk_SmTest_GraphWalk_Top_State_B_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_GraphWalk_Top_State_C_SpawnParams
{
}

namespace UCk_SmTest_GraphWalk_Top_State_C
{
    FCk_SmTest_GraphWalk_Top_State_C_SpawnParams Params()
    {
        return FCk_SmTest_GraphWalk_Top_State_C_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_GraphWalk_Top_State_D_SpawnParams
{
}

namespace UCk_SmTest_GraphWalk_Top_State_D
{
    FCk_SmTest_GraphWalk_Top_State_D_SpawnParams Params()
    {
        return FCk_SmTest_GraphWalk_Top_State_D_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_GraphWalk_Top_State_E_SpawnParams
{
}

namespace UCk_SmTest_GraphWalk_Top_State_E
{
    FCk_SmTest_GraphWalk_Top_State_E_SpawnParams Params()
    {
        return FCk_SmTest_GraphWalk_Top_State_E_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_Hier_Child_Recover_SpawnParams
{
}

namespace UCk_SmTest_Hier_Child_Recover
{
    FCk_SmTest_Hier_Child_Recover_SpawnParams Params()
    {
        return FCk_SmTest_Hier_Child_Recover_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_Hier_Child_Strike_SpawnParams
{
}

namespace UCk_SmTest_Hier_Child_Strike
{
    FCk_SmTest_Hier_Child_Strike_SpawnParams Params()
    {
        return FCk_SmTest_Hier_Child_Strike_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_Hier_Child_WindUp_SpawnParams
{
}

namespace UCk_SmTest_Hier_Child_WindUp
{
    FCk_SmTest_Hier_Child_WindUp_SpawnParams Params()
    {
        return FCk_SmTest_Hier_Child_WindUp_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_Hier_Heal_Channel_SpawnParams
{
}

namespace UCk_SmTest_Hier_Heal_Channel
{
    FCk_SmTest_Hier_Heal_Channel_SpawnParams Params()
    {
        return FCk_SmTest_Hier_Heal_Channel_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_Hier_Heal_Gather_SpawnParams
{
}

namespace UCk_SmTest_Hier_Heal_Gather
{
    FCk_SmTest_Hier_Heal_Gather_SpawnParams Params()
    {
        return FCk_SmTest_Hier_Heal_Gather_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_Hier_Heal_Restore_SpawnParams
{
}

namespace UCk_SmTest_Hier_Heal_Restore
{
    FCk_SmTest_Hier_Heal_Restore_SpawnParams Params()
    {
        return FCk_SmTest_Hier_Heal_Restore_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_Hier_HealSubSmTask_SpawnParams
{
}

namespace UCk_SmTest_Hier_HealSubSmTask
{
    FCk_SmTest_Hier_HealSubSmTask_SpawnParams Params()
    {
        return FCk_SmTest_Hier_HealSubSmTask_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_Hier_Parent_Approach_SpawnParams
{
}

namespace UCk_SmTest_Hier_Parent_Approach
{
    FCk_SmTest_Hier_Parent_Approach_SpawnParams Params()
    {
        return FCk_SmTest_Hier_Parent_Approach_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_Hier_Parent_Engage_SpawnParams
{
}

namespace UCk_SmTest_Hier_Parent_Engage
{
    FCk_SmTest_Hier_Parent_Engage_SpawnParams Params()
    {
        return FCk_SmTest_Hier_Parent_Engage_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_Hier_Parent_Flee_SpawnParams
{
}

namespace UCk_SmTest_Hier_Parent_Flee
{
    FCk_SmTest_Hier_Parent_Flee_SpawnParams Params()
    {
        return FCk_SmTest_Hier_Parent_Flee_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_Hier_Parent_Heal_SpawnParams
{
}

namespace UCk_SmTest_Hier_Parent_Heal
{
    FCk_SmTest_Hier_Parent_Heal_SpawnParams Params()
    {
        return FCk_SmTest_Hier_Parent_Heal_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_Hier_Parent_Retreat_SpawnParams
{
}

namespace UCk_SmTest_Hier_Parent_Retreat
{
    FCk_SmTest_Hier_Parent_Retreat_SpawnParams Params()
    {
        return FCk_SmTest_Hier_Parent_Retreat_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_Hier_Parent_Spawn_SpawnParams
{
}

namespace UCk_SmTest_Hier_Parent_Spawn
{
    FCk_SmTest_Hier_Parent_Spawn_SpawnParams Params()
    {
        return FCk_SmTest_Hier_Parent_Spawn_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_Hier_SubSmTask_SpawnParams
{
}

namespace UCk_SmTest_Hier_SubSmTask
{
    FCk_SmTest_Hier_SubSmTask_SpawnParams Params()
    {
        return FCk_SmTest_Hier_SubSmTask_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_Negated_Condition_AfterDelay_SpawnParams
{
}

namespace UCk_SmTest_Negated_Condition_AfterDelay
{
    FCk_SmTest_Negated_Condition_AfterDelay_SpawnParams Params()
    {
        return FCk_SmTest_Negated_Condition_AfterDelay_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_Negated_State_Finish_SpawnParams
{
}

namespace UCk_SmTest_Negated_State_Finish
{
    FCk_SmTest_Negated_State_Finish_SpawnParams Params()
    {
        return FCk_SmTest_Negated_State_Finish_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_Negated_State_Idle_SpawnParams
{
}

namespace UCk_SmTest_Negated_State_Idle
{
    FCk_SmTest_Negated_State_Idle_SpawnParams Params()
    {
        return FCk_SmTest_Negated_State_Idle_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_NoTransition_State_Sink_SpawnParams
{
}

namespace UCk_SmTest_NoTransition_State_Sink
{
    FCk_SmTest_NoTransition_State_Sink_SpawnParams Params()
    {
        return FCk_SmTest_NoTransition_State_Sink_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_Ordering_Condition_QuickDelay_SpawnParams
{
}

namespace UCk_SmTest_Ordering_Condition_QuickDelay
{
    FCk_SmTest_Ordering_Condition_QuickDelay_SpawnParams Params()
    {
        return FCk_SmTest_Ordering_Condition_QuickDelay_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_Ordering_State_A_SpawnParams
{
}

namespace UCk_SmTest_Ordering_State_A
{
    FCk_SmTest_Ordering_State_A_SpawnParams Params()
    {
        return FCk_SmTest_Ordering_State_A_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_Ordering_State_B_SpawnParams
{
}

namespace UCk_SmTest_Ordering_State_B
{
    FCk_SmTest_Ordering_State_B_SpawnParams Params()
    {
        return FCk_SmTest_Ordering_State_B_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_Ordering_Task_A_SpawnParams
{
}

namespace UCk_SmTest_Ordering_Task_A
{
    FCk_SmTest_Ordering_Task_A_SpawnParams Params()
    {
        return FCk_SmTest_Ordering_Task_A_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_Ordering_Task_B_SpawnParams
{
}

namespace UCk_SmTest_Ordering_Task_B
{
    FCk_SmTest_Ordering_Task_B_SpawnParams Params()
    {
        return FCk_SmTest_Ordering_Task_B_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_Override_Base_SpawnParams
{
}

namespace UCk_SmTest_Override_Base
{
    FCk_SmTest_Override_Base_SpawnParams Params()
    {
        return FCk_SmTest_Override_Base_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_Override_Replacement_SpawnParams
{
}

namespace UCk_SmTest_Override_Replacement
{
    FCk_SmTest_Override_Replacement_SpawnParams Params()
    {
        return FCk_SmTest_Override_Replacement_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_Racing_Condition_FastTimer_SpawnParams
{
}

namespace UCk_SmTest_Racing_Condition_FastTimer
{
    FCk_SmTest_Racing_Condition_FastTimer_SpawnParams Params()
    {
        return FCk_SmTest_Racing_Condition_FastTimer_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_Racing_Condition_SlowTimer_SpawnParams
{
}

namespace UCk_SmTest_Racing_Condition_SlowTimer
{
    FCk_SmTest_Racing_Condition_SlowTimer_SpawnParams Params()
    {
        return FCk_SmTest_Racing_Condition_SlowTimer_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_Racing_State_DestA_SpawnParams
{
}

namespace UCk_SmTest_Racing_State_DestA
{
    FCk_SmTest_Racing_State_DestA_SpawnParams Params()
    {
        return FCk_SmTest_Racing_State_DestA_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_Racing_State_DestB_SpawnParams
{
}

namespace UCk_SmTest_Racing_State_DestB
{
    FCk_SmTest_Racing_State_DestB_SpawnParams Params()
    {
        return FCk_SmTest_Racing_State_DestB_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_Racing_State_Idle_SpawnParams
{
}

namespace UCk_SmTest_Racing_State_Idle
{
    FCk_SmTest_Racing_State_Idle_SpawnParams Params()
    {
        return FCk_SmTest_Racing_State_Idle_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_Racing_Task_DestA_SpawnParams
{
}

namespace UCk_SmTest_Racing_Task_DestA
{
    FCk_SmTest_Racing_Task_DestA_SpawnParams Params()
    {
        return FCk_SmTest_Racing_Task_DestA_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_Racing_Task_DestB_SpawnParams
{
}

namespace UCk_SmTest_Racing_Task_DestB
{
    FCk_SmTest_Racing_Task_DestB_SpawnParams Params()
    {
        return FCk_SmTest_Racing_Task_DestB_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_State_Alert_SpawnParams
{
}

namespace UCk_SmTest_State_Alert
{
    FCk_SmTest_State_Alert_SpawnParams Params()
    {
        return FCk_SmTest_State_Alert_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_State_Idle_SpawnParams
{
}

namespace UCk_SmTest_State_Idle
{
    FCk_SmTest_State_Idle_SpawnParams Params()
    {
        return FCk_SmTest_State_Idle_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_State_Patrol_SpawnParams
{
}

namespace UCk_SmTest_State_Patrol
{
    FCk_SmTest_State_Patrol_SpawnParams Params()
    {
        return FCk_SmTest_State_Patrol_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_Task_EnterCount_Sub_A_SpawnParams
{
}

namespace UCk_SmTest_Task_EnterCount_Sub_A
{
    FCk_SmTest_Task_EnterCount_Sub_A_SpawnParams Params()
    {
        return FCk_SmTest_Task_EnterCount_Sub_A_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_Task_EnterCount_Sub_B_SpawnParams
{
}

namespace UCk_SmTest_Task_EnterCount_Sub_B
{
    FCk_SmTest_Task_EnterCount_Sub_B_SpawnParams Params()
    {
        return FCk_SmTest_Task_EnterCount_Sub_B_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_Task_EnterCount_Sub_C_SpawnParams
{
}

namespace UCk_SmTest_Task_EnterCount_Sub_C
{
    FCk_SmTest_Task_EnterCount_Sub_C_SpawnParams Params()
    {
        return FCk_SmTest_Task_EnterCount_Sub_C_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_Task_EnterCount_Sub_D_SpawnParams
{
}

namespace UCk_SmTest_Task_EnterCount_Sub_D
{
    FCk_SmTest_Task_EnterCount_Sub_D_SpawnParams Params()
    {
        return FCk_SmTest_Task_EnterCount_Sub_D_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_Task_EnterCount_Top_A_SpawnParams
{
}

namespace UCk_SmTest_Task_EnterCount_Top_A
{
    FCk_SmTest_Task_EnterCount_Top_A_SpawnParams Params()
    {
        return FCk_SmTest_Task_EnterCount_Top_A_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_Task_EnterCount_Top_B_SpawnParams
{
}

namespace UCk_SmTest_Task_EnterCount_Top_B
{
    FCk_SmTest_Task_EnterCount_Top_B_SpawnParams Params()
    {
        return FCk_SmTest_Task_EnterCount_Top_B_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_Task_EnterCount_Top_C_SpawnParams
{
}

namespace UCk_SmTest_Task_EnterCount_Top_C
{
    FCk_SmTest_Task_EnterCount_Top_C_SpawnParams Params()
    {
        return FCk_SmTest_Task_EnterCount_Top_C_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_Task_EnterCount_Top_D_SpawnParams
{
}

namespace UCk_SmTest_Task_EnterCount_Top_D
{
    FCk_SmTest_Task_EnterCount_Top_D_SpawnParams Params()
    {
        return FCk_SmTest_Task_EnterCount_Top_D_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_Task_LogOnly_SpawnParams
{
}

namespace UCk_SmTest_Task_LogOnly
{
    FCk_SmTest_Task_LogOnly_SpawnParams Params()
    {
        return FCk_SmTest_Task_LogOnly_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_Task_RequestStopOwning_Sub_SpawnParams
{
}

namespace UCk_SmTest_Task_RequestStopOwning_Sub
{
    FCk_SmTest_Task_RequestStopOwning_Sub_SpawnParams Params()
    {
        return FCk_SmTest_Task_RequestStopOwning_Sub_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_Task_RequestStopOwning_Top_SpawnParams
{
}

namespace UCk_SmTest_Task_RequestStopOwning_Top
{
    FCk_SmTest_Task_RequestStopOwning_Top_SpawnParams Params()
    {
        return FCk_SmTest_Task_RequestStopOwning_Top_SpawnParams();
    }
}

USTRUCT()
struct FCk_SmTest_Task_TimedWork_SpawnParams
{
}

namespace UCk_SmTest_Task_TimedWork
{
    FCk_SmTest_Task_TimedWork_SpawnParams Params()
    {
        return FCk_SmTest_Task_TimedWork_SpawnParams();
    }
}

USTRUCT()
struct FCkAudioGym_Advanced_AttenuationStation_SpawnParams
{
    UPROPERTY()
    FTransform Transform = FTransform::Identity;

    FCkAudioGym_Advanced_AttenuationStation_SpawnParams(FTransform InTransform)
    {
        Transform = InTransform;
    }
}

namespace UCkAudioGym_Advanced_AttenuationStation
{
    FCkAudioGym_Advanced_AttenuationStation_SpawnParams Params()
    {
        return FCkAudioGym_Advanced_AttenuationStation_SpawnParams();
    }

    FCkAudioGym_Advanced_AttenuationStation_SpawnParams Params(FTransform InTransform)
    {
        return FCkAudioGym_Advanced_AttenuationStation_SpawnParams(InTransform);
    }
}

USTRUCT()
struct FCkAudioGym_Advanced_AudioPickup_SpawnParams
{
    UPROPERTY()
    FTransform Transform = FTransform::Identity;

    FCkAudioGym_Advanced_AudioPickup_SpawnParams(FTransform InTransform)
    {
        Transform = InTransform;
    }
}

namespace UCkAudioGym_Advanced_AudioPickup
{
    FCkAudioGym_Advanced_AudioPickup_SpawnParams Params()
    {
        return FCkAudioGym_Advanced_AudioPickup_SpawnParams();
    }

    FCkAudioGym_Advanced_AudioPickup_SpawnParams Params(FTransform InTransform)
    {
        return FCkAudioGym_Advanced_AudioPickup_SpawnParams(InTransform);
    }
}

USTRUCT()
struct FCkAudioGym_Advanced_Base_SpawnParams
{
    UPROPERTY()
    FTransform Transform = FTransform::Identity;

    FCkAudioGym_Advanced_Base_SpawnParams(FTransform InTransform)
    {
        Transform = InTransform;
    }
}

namespace UCkAudioGym_Advanced_Base
{
    FCkAudioGym_Advanced_Base_SpawnParams Params()
    {
        return FCkAudioGym_Advanced_Base_SpawnParams();
    }

    FCkAudioGym_Advanced_Base_SpawnParams Params(FTransform InTransform)
    {
        return FCkAudioGym_Advanced_Base_SpawnParams(InTransform);
    }
}

USTRUCT()
struct FCkAudioGym_Advanced_BasicStation_SpawnParams
{
    UPROPERTY()
    FTransform Transform = FTransform::Identity;

    FCkAudioGym_Advanced_BasicStation_SpawnParams(FTransform InTransform)
    {
        Transform = InTransform;
    }
}

namespace UCkAudioGym_Advanced_BasicStation
{
    FCkAudioGym_Advanced_BasicStation_SpawnParams Params()
    {
        return FCkAudioGym_Advanced_BasicStation_SpawnParams();
    }

    FCkAudioGym_Advanced_BasicStation_SpawnParams Params(FTransform InTransform)
    {
        return FCkAudioGym_Advanced_BasicStation_SpawnParams(InTransform);
    }
}

USTRUCT()
struct FCkAudioGym_Advanced_ConcurrencyStation_SpawnParams
{
    UPROPERTY()
    FTransform Transform = FTransform::Identity;

    FCkAudioGym_Advanced_ConcurrencyStation_SpawnParams(FTransform InTransform)
    {
        Transform = InTransform;
    }
}

namespace UCkAudioGym_Advanced_ConcurrencyStation
{
    FCkAudioGym_Advanced_ConcurrencyStation_SpawnParams Params()
    {
        return FCkAudioGym_Advanced_ConcurrencyStation_SpawnParams();
    }

    FCkAudioGym_Advanced_ConcurrencyStation_SpawnParams Params(FTransform InTransform)
    {
        return FCkAudioGym_Advanced_ConcurrencyStation_SpawnParams(InTransform);
    }
}

USTRUCT()
struct FCkAudioGym_Advanced_FeaturesStation_SpawnParams
{
    UPROPERTY()
    FTransform Transform = FTransform::Identity;

    FCkAudioGym_Advanced_FeaturesStation_SpawnParams(FTransform InTransform)
    {
        Transform = InTransform;
    }
}

namespace UCkAudioGym_Advanced_FeaturesStation
{
    FCkAudioGym_Advanced_FeaturesStation_SpawnParams Params()
    {
        return FCkAudioGym_Advanced_FeaturesStation_SpawnParams();
    }

    FCkAudioGym_Advanced_FeaturesStation_SpawnParams Params(FTransform InTransform)
    {
        return FCkAudioGym_Advanced_FeaturesStation_SpawnParams(InTransform);
    }
}

USTRUCT()
struct FCkAudioGym_Advanced_InterfacePickup_SpawnParams
{
    UPROPERTY()
    FTransform Transform = FTransform::Identity;

    FCkAudioGym_Advanced_InterfacePickup_SpawnParams(FTransform InTransform)
    {
        Transform = InTransform;
    }
}

namespace UCkAudioGym_Advanced_InterfacePickup
{
    FCkAudioGym_Advanced_InterfacePickup_SpawnParams Params()
    {
        return FCkAudioGym_Advanced_InterfacePickup_SpawnParams();
    }

    FCkAudioGym_Advanced_InterfacePickup_SpawnParams Params(FTransform InTransform)
    {
        return FCkAudioGym_Advanced_InterfacePickup_SpawnParams(InTransform);
    }
}

USTRUCT()
struct FCkAudioGym_Advanced_LevelUpPickup_SpawnParams
{
    UPROPERTY()
    FTransform Transform = FTransform::Identity;

    FCkAudioGym_Advanced_LevelUpPickup_SpawnParams(FTransform InTransform)
    {
        Transform = InTransform;
    }
}

namespace UCkAudioGym_Advanced_LevelUpPickup
{
    FCkAudioGym_Advanced_LevelUpPickup_SpawnParams Params()
    {
        return FCkAudioGym_Advanced_LevelUpPickup_SpawnParams();
    }

    FCkAudioGym_Advanced_LevelUpPickup_SpawnParams Params(FTransform InTransform)
    {
        return FCkAudioGym_Advanced_LevelUpPickup_SpawnParams(InTransform);
    }
}

USTRUCT()
struct FCkAudioGym_Advanced_NotificationsPickup_SpawnParams
{
    UPROPERTY()
    FTransform Transform = FTransform::Identity;

    FCkAudioGym_Advanced_NotificationsPickup_SpawnParams(FTransform InTransform)
    {
        Transform = InTransform;
    }
}

namespace UCkAudioGym_Advanced_NotificationsPickup
{
    FCkAudioGym_Advanced_NotificationsPickup_SpawnParams Params()
    {
        return FCkAudioGym_Advanced_NotificationsPickup_SpawnParams();
    }

    FCkAudioGym_Advanced_NotificationsPickup_SpawnParams Params(FTransform InTransform)
    {
        return FCkAudioGym_Advanced_NotificationsPickup_SpawnParams(InTransform);
    }
}

USTRUCT()
struct FCkAudioGym_Advanced_SpatialStation_SpawnParams
{
    UPROPERTY()
    FTransform Transform = FTransform::Identity;

    FCkAudioGym_Advanced_SpatialStation_SpawnParams(FTransform InTransform)
    {
        Transform = InTransform;
    }
}

namespace UCkAudioGym_Advanced_SpatialStation
{
    FCkAudioGym_Advanced_SpatialStation_SpawnParams Params()
    {
        return FCkAudioGym_Advanced_SpatialStation_SpawnParams();
    }

    FCkAudioGym_Advanced_SpatialStation_SpawnParams Params(FTransform InTransform)
    {
        return FCkAudioGym_Advanced_SpatialStation_SpawnParams(InTransform);
    }
}

USTRUCT()
struct FTestEntt_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FTestEntt_SpawnParams(FTransform InInitialTransform)
    {
        InitialTransform = InInitialTransform;
    }
}

namespace UTestEntt
{
    FTestEntt_SpawnParams Params()
    {
        return FTestEntt_SpawnParams();
    }

    FTestEntt_SpawnParams Params(FTransform InInitialTransform)
    {
        return FTestEntt_SpawnParams(InInitialTransform);
    }
}

