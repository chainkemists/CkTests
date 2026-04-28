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
struct FCk_ReplicationGym_PawnExtra_EntityScript_SpawnParams
{
    UPROPERTY()
    TObjectPtr<AActor> _OwningActor = nullptr;

    FCk_ReplicationGym_PawnExtra_EntityScript_SpawnParams(TObjectPtr<AActor> In_OwningActor)
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

    FCk_ReplicationGym_PawnExtra_EntityScript_SpawnParams Params(TObjectPtr<AActor> In_OwningActor)
    {
        return FCk_ReplicationGym_PawnExtra_EntityScript_SpawnParams(In_OwningActor);
    }
}

USTRUCT()
struct FCk_ReplicationGym_ReplicatedActor_EntityScript_SpawnParams
{
    UPROPERTY()
    TObjectPtr<AActor> _OwningActor = nullptr;

    FCk_ReplicationGym_ReplicatedActor_EntityScript_SpawnParams(TObjectPtr<AActor> In_OwningActor)
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

    FCk_ReplicationGym_ReplicatedActor_EntityScript_SpawnParams Params(TObjectPtr<AActor> In_OwningActor)
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

