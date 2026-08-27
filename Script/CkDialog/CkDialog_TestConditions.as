// Language=angelscript

//============================================================================
// CK DIALOG - SHARED TEST CONDITIONS
//============================================================================
// Reusable inline condition subclasses for the Dialog autotests. Defined once
// here (a duplicate UCLASS across test files is an AS compile error). Tests
// instantiate these with NewObject and hand the instance to a line's
// FCk_DialogBank_LineData._Conditions.
//============================================================================

// Always fails - turns a line into Fail_LineCondition.
UCLASS()
class UCk_DialogTestCond_AlwaysFail : UCk_DialogCondition_EntityScript
{
    UFUNCTION(BlueprintOverride)
    ECk_Dialog_ConditionResult DoEvaluate(
        FCk_Handle InCondition,
        FCk_Handle_DialogLine InLine,
        FCk_Handle_DialogEmitter InEmitter) const
    {
        auto _CkPerfScope = ck::ScopedStat();
        return ECk_Dialog_ConditionResult::Fail;
    }
};

// Always passes - an AS-authored equivalent of the built-in UCk_DialogCondition_AlwaysTrue.
UCLASS()
class UCk_DialogTestCond_AlwaysPass : UCk_DialogCondition_EntityScript
{
    UFUNCTION(BlueprintOverride)
    ECk_Dialog_ConditionResult DoEvaluate(
        FCk_Handle InCondition,
        FCk_Handle_DialogLine InLine,
        FCk_Handle_DialogEmitter InEmitter) const
    {
        auto _CkPerfScope = ck::ScopedStat();
        return ECk_Dialog_ConditionResult::Pass;
    }
};

// Passes only when the querying emitter carries the tag it is configured with - proves the condition
// receives the CALLER (emitter) context, and that the same line can pass for one emitter and fail for another.
UCLASS()
class UCk_DialogTestCond_RequiresEmitterTag : UCk_DialogCondition_EntityScript
{
    UPROPERTY(EditAnywhere)
    FGameplayTag RequiredEmitterTag;

    UFUNCTION(BlueprintOverride)
    ECk_Dialog_ConditionResult DoEvaluate(
        FCk_Handle InCondition,
        FCk_Handle_DialogLine InLine,
        FCk_Handle_DialogEmitter InEmitter) const
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto EmitterTags = InEmitter.Get_EmitterTags();
        if (EmitterTags.HasTag(RequiredEmitterTag))
        { return ECk_Dialog_ConditionResult::Pass; }
        return ECk_Dialog_ConditionResult::Fail;
    }
};
