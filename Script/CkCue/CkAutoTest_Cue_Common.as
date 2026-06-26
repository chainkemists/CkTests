// Language=angelscript

//============================================================================
// CK CUE — AUTOMATION TEST: SHARED CUE SUBCLASSES + TAGS
//============================================================================
//
// Minimal cue subclasses for the CkCue first-coverage seed. Each subclass
// declares one of the lifetime behaviors (AfterOneFrame / Persistent /
// Timed) and adds a marker entity tag in DoConstruct so the test can
// count active instances via utils_entity_tag::ForEach_Entity.
//
// Discovery: cue subsystems auto-populate from subclasses of
// UCk_GenericCue_EntityScript at engine init (60-frame deferred). The
// AutoTest level loads after that window, so tag-to-class resolution
// is complete by the time tests fire.
//
// These cue subclasses are NOT shared with the gym set — separate tags
// avoid coupling test outcomes to gym evolution.
//============================================================================

namespace Ck
{
    asset Asset_AutoTest_Cue_Tags of UCk_GameplayTags
    {
        GameplayTags.Add(n"AutoTest.Cue.AfterOneFrame");
        GameplayTags.Add(n"AutoTest.Cue.Persistent");
        GameplayTags.Add(n"AutoTest.Cue.Timed");
    }
}

USTRUCT()
struct FCk_AutoTestCue_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FCk_AutoTestCue_SpawnParams() {}
    FCk_AutoTestCue_SpawnParams(FTransform InTransform) { InitialTransform = InTransform; }
}

//----------------------------------------------------------------------------
// AfterOneFrame — destroyed after one frame.
//----------------------------------------------------------------------------

class UCk_AutoTestCue_AfterOneFrame : UCk_GenericCue_EntityScript
{
    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    default _Replication = ECk_Replication::DoesNotReplicate;
    default _LifetimeBehavior = ECk_Cue_LifetimeBehavior::AfterOneFrame;
    default _ConcurrencyPolicy = ECk_Cue_ConcurrencyPolicy::AllowMultiple;

    UFUNCTION(BlueprintOverride)
    FGameplayTag Get_CueName() const
    {
        return GameplayTags::ResolveGameplayTag(n"AutoTest.Cue.AfterOneFrame");
    }

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);
        utils_entity_tag::Add(InHandle, n"TAG_AutoTestCue_AfterOneFrame");
        return ECk_EntityScript_ConstructionFlow::Finished;
    }
}

//----------------------------------------------------------------------------
// Persistent — stays alive indefinitely.
//----------------------------------------------------------------------------

class UCk_AutoTestCue_Persistent : UCk_GenericCue_EntityScript
{
    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    default _Replication = ECk_Replication::DoesNotReplicate;
    default _LifetimeBehavior = ECk_Cue_LifetimeBehavior::Persistent;
    default _ConcurrencyPolicy = ECk_Cue_ConcurrencyPolicy::AllowMultiple;

    UFUNCTION(BlueprintOverride)
    FGameplayTag Get_CueName() const
    {
        return GameplayTags::ResolveGameplayTag(n"AutoTest.Cue.Persistent");
    }

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);
        utils_entity_tag::Add(InHandle, n"TAG_AutoTestCue_Persistent");
        return ECk_EntityScript_ConstructionFlow::Finished;
    }
}

//----------------------------------------------------------------------------
// Timed — auto-destroys after _LifetimeDuration seconds.
//----------------------------------------------------------------------------

class UCk_AutoTestCue_Timed : UCk_GenericCue_EntityScript
{
    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    default _Replication = ECk_Replication::DoesNotReplicate;
    default _LifetimeBehavior = ECk_Cue_LifetimeBehavior::Timed;
    default _ConcurrencyPolicy = ECk_Cue_ConcurrencyPolicy::AllowMultiple;
    default _LifetimeDuration = FCk_Time(0.2f);

    UFUNCTION(BlueprintOverride)
    FGameplayTag Get_CueName() const
    {
        return GameplayTags::ResolveGameplayTag(n"AutoTest.Cue.Timed");
    }

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);
        utils_entity_tag::Add(InHandle, n"TAG_AutoTestCue_Timed");
        return ECk_EntityScript_ConstructionFlow::Finished;
    }
}
