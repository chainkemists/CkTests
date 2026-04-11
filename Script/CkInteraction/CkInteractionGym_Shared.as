// Language=angelscript

//============================================================================
// INTERACTION GYM - SHARED TYPES AND HELPERS
//============================================================================

namespace Ck
{
    asset InteractionGym_Tags of UCk_GameplayTags
    {
        GameplayTags.Add(n"InteractionChannel.InteractionGym.Default");
        GameplayTags.Add(n"InteractionChannel.InteractionGym.Secondary");
        GameplayTags.Add(n"InteractionIntent.InteractionGym.Use");
        GameplayTags.Add(n"ResolverDataBundle.InteractionGym.Damage");
        GameplayTags.Add(n"ResolverPhase.InteractionGym.Calculate");
        GameplayTags.Add(n"ResolverPhase.InteractionGym.Apply");
    }
}

//============================================================================
// SPAWN PARAMETERS
//============================================================================

USTRUCT()
struct FInteractionGymSpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FInteractionGymSpawnParams(FTransform InTransform)
    {
        InitialTransform = InTransform;
    }
}

//============================================================================
// MESSAGE TYPES
//============================================================================

// Auto mode (shared by all stations)
USTRUCT()
struct FCk_Message_InteractionGym_AutoSet
{
    UPROPERTY()
    bool Enabled = true;

    FCk_Message_InteractionGym_AutoSet() {}
    FCk_Message_InteractionGym_AutoSet(bool InEnabled) { Enabled = InEnabled; }
}

// Station 1: Instant
USTRUCT()
struct FCk_Message_InteractionGym_TriggerInstant
{
    FCk_Message_InteractionGym_TriggerInstant() {}
}

// Station 2: Timed
USTRUCT()
struct FCk_Message_InteractionGym_StartTimed
{
    FCk_Message_InteractionGym_StartTimed() {}
}

// Station 3: Manual
USTRUCT()
struct FCk_Message_InteractionGym_StartManual
{
    FCk_Message_InteractionGym_StartManual() {}
}

USTRUCT()
struct FCk_Message_InteractionGym_EndManualSuccess
{
    FCk_Message_InteractionGym_EndManualSuccess() {}
}

USTRUCT()
struct FCk_Message_InteractionGym_EndManualFail
{
    FCk_Message_InteractionGym_EndManualFail() {}
}

USTRUCT()
struct FCk_Message_InteractionGym_CancelManual
{
    FCk_Message_InteractionGym_CancelManual() {}
}

// Station 4: Validation
USTRUCT()
struct FCk_Message_InteractionGym_AttemptValidation
{
    FCk_Message_InteractionGym_AttemptValidation() {}
}

USTRUCT()
struct FCk_Message_InteractionGym_ToggleEnabled
{
    FCk_Message_InteractionGym_ToggleEnabled() {}
}

USTRUCT()
struct FCk_Message_InteractionGym_ToggleCustomValidation
{
    FCk_Message_InteractionGym_ToggleCustomValidation() {}
}

// Station 5: Resolver
USTRUCT()
struct FCk_Message_InteractionGym_StartIntent
{
    FCk_Message_InteractionGym_StartIntent() {}
}

USTRUCT()
struct FCk_Message_InteractionGym_StopIntent
{
    FCk_Message_InteractionGym_StopIntent() {}
}

USTRUCT()
struct FCk_Message_InteractionGym_AddTargets
{
    FCk_Message_InteractionGym_AddTargets() {}
}

USTRUCT()
struct FCk_Message_InteractionGym_RemoveTargets
{
    FCk_Message_InteractionGym_RemoveTargets() {}
}

// Station 6: DataBundle
USTRUCT()
struct FCk_Message_InteractionGym_InitiateResolution
{
    FCk_Message_InteractionGym_InitiateResolution() {}
}

//============================================================================
// HELPERS
//============================================================================

namespace interaction_gym_helpers
{
    FGameplayTag DefaultChannel()
    {
        return utils_gameplay_tag::ResolveGameplayTag(n"InteractionChannel.InteractionGym.Default");
    }

    FGameplayTag SecondaryChannel()
    {
        return utils_gameplay_tag::ResolveGameplayTag(n"InteractionChannel.InteractionGym.Secondary");
    }

    FGameplayTag UseIntent()
    {
        return utils_gameplay_tag::ResolveGameplayTag(n"InteractionIntent.InteractionGym.Use");
    }

    FString AutoStatusLine(bool AutoRunning)
    {
        if (AutoRunning)
        {
            return "[AUTO] Running";
        }
        return "[MANUAL]";
    }

    FString StepPrefix(int32 StepMarker, int32 Step)
    {
        return (StepMarker == Step) ? ">>" : "  ";
    }
}
