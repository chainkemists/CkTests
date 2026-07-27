// Language=angelscript

//============================================================================
// INTEGER MODIFIERS GYM — STEP STATES
//============================================================================
//
// The demo sequence for the Integer-attribute modifier station, as a
// CkStateMachine graph. Replaces the `AutoStep % 4` + if-else dispatch that
// used to live in the station's AutoTick.
//
//   AddWeapon -> AddBuff -> ClearAll -> AddDefaults -> (back to AddWeapon)
//
// Each state acts on the STATION ENTITY through utils_*, never on the station
// script's members: a state is its own entity script and has no business
// reaching into another object's fields. The Damage attribute is looked up by
// tag off the station entity, which is also what makes the old
// `ActiveModifiers` bookkeeping array unnecessary — the framework already
// tracks modifiers, and TryGet finds them by tag.
//============================================================================

namespace integer_gym_modifiers
{
    // Shared by every step. Returns an invalid handle if the station has not
    // composed its attribute yet; each step guards on that rather than
    // assuming, because a state can enter before the station finishes setup.
    FCk_Handle_IntegerAttribute Get_DamageAttribute(FCk_Handle InStation)
    {
        if (ck::Is_NOT_Valid(InStation)) { return FCk_Handle_IntegerAttribute(); }
        return utils_integer_attribute::TryGet(InStation,
            utils_gameplay_tag::ResolveGameplayTag(n"IntegerAttribute.Damage"));
    }

    // Add-or-replace a tagged revocable modifier. The remove-then-add shape
    // mirrors the original station helpers: re-adding the same tag without
    // removing first would stack a second modifier under one name.
    void Request_SetModifier(FCk_Handle InStation, FName InModifierTag, int32 InDelta)
    {
        auto Damage = Get_DamageAttribute(InStation);
        if (ck::Is_NOT_Valid(Damage)) { return; }

        auto Tag = utils_gameplay_tag::ResolveGameplayTag(InModifierTag);

        auto Existing = utils_integer_attribute_modifier::TryGet(Damage, Tag, ECk_MinMaxCurrent::Current);
        if (ck::IsValid(Existing))
        { utils_integer_attribute_modifier::Remove(Existing); }

        auto Params = FCk_Fragment_IntegerAttributeModifier_ParamsData();
        Params.Set_ModifierDelta(InDelta);
        utils_integer_attribute_modifier::Add_Revocable(
            Damage, Tag, ECk_AttributeModifier_Operation::Add, Params);
    }
}

// ====================================================================================================================

UCLASS()
class UCk_IntegerGym_Step_AddWeapon : UCk_Gym_StepState
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Trans = AddTransition(InHandle, UCk_IntegerGym_Step_AddBuff);
        AddCondition(Trans, UCk_Gym_Dwell);
    }

    UFUNCTION(BlueprintOverride)
    void DoEnterState(FCk_Handle_SmState InHandle, ECk_Sm_NetContext InNetContext)
    {
        auto _CkPerfScope = ck::ScopedStat();
        integer_gym_modifiers::Request_SetModifier(Get_StationEntity(), n"Modifier.Weapon", 25);
    }
}

// ----------------------------------------------------------------------------

UCLASS()
class UCk_IntegerGym_Step_AddBuff : UCk_Gym_StepState
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Trans = AddTransition(InHandle, UCk_IntegerGym_Step_ClearAll);
        AddCondition(Trans, UCk_Gym_Dwell);
    }

    UFUNCTION(BlueprintOverride)
    void DoEnterState(FCk_Handle_SmState InHandle, ECk_Sm_NetContext InNetContext)
    {
        auto _CkPerfScope = ck::ScopedStat();
        integer_gym_modifiers::Request_SetModifier(Get_StationEntity(), n"Modifier.Buff", 10);
    }
}

// ----------------------------------------------------------------------------

UCLASS()
class UCk_IntegerGym_Step_ClearAll : UCk_Gym_StepState
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Trans = AddTransition(InHandle, UCk_IntegerGym_Step_AddDefaults);
        AddCondition(Trans, UCk_Gym_Dwell);
    }

    UFUNCTION(BlueprintOverride)
    void DoEnterState(FCk_Handle_SmState InHandle, ECk_Sm_NetContext InNetContext)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Damage = integer_gym_modifiers::Get_DamageAttribute(Get_StationEntity());
        if (ck::Is_NOT_Valid(Damage)) { return; }
        utils_integer_attribute_modifier::Request_ClearAllModifiers(Damage);
    }
}

// ----------------------------------------------------------------------------

UCLASS()
class UCk_IntegerGym_Step_AddDefaults : UCk_Gym_StepState
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Trans = AddTransition(InHandle, UCk_IntegerGym_Step_AddWeapon);
        AddCondition(Trans, UCk_Gym_Dwell);
    }

    UFUNCTION(BlueprintOverride)
    void DoEnterState(FCk_Handle_SmState InHandle, ECk_Sm_NetContext InNetContext)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Station = Get_StationEntity();
        integer_gym_modifiers::Request_SetModifier(Station, n"Modifier.Weapon", 25);
        integer_gym_modifiers::Request_SetModifier(Station, n"Modifier.Buff", 10);
    }
}
