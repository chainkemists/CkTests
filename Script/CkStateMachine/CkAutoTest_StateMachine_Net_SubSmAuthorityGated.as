// Language=angelscript

//============================================================================
// CK STATE MACHINE — NET SUB-SM AUTHORITY-GATED TASK (topology only)
//============================================================================
//
// Distilled reproduction of the BusterBlock "remote clients can't sprint" bug,
// authored at the framework primitive level. Driven by the C++ spec
// Ck.StateMachine.Net.OwningClientAuth_SubSm_AuthorityGatedTask, which bridges a
// Replicates / OwningClientAuthoritative / WithHistory parent SM onto a
// client-possessed pawn (initial state = UCk_SmNetSubGatedTest_Parent_Hold).
//
//   Parent_Hold [ SubTask -> sub-SM ]                          (KeepRunning)
//     sub-SM: Sub_Idle --(InputPressed: ByteAttr==1)--> Sub_Active
//                                                        [ SpeedModifierTask ]
//
// Mirror of the real sprint path:
//   - The sub-SM transition is gated on a byte attribute (the Intent.Sprint
//     analog) that the spec sets ONLY on the owning client via Override — exactly
//     how the input profile sets the sprint intent.
//   - Sub_Active hosts an AUTHORITY-GATED task (Get_HasAuthority early-return)
//     that adds a revocable Multiply modifier to a float attribute (the
//     UBb_SmTask_SprintMultiplier analog).
//
// The bug it captures: the sub-SM is DoesNotReplicate and driven locally on every
// machine. The owning client enters Sub_Active (it has the input) but the
// authority-gated task no-ops there (no entity authority). The server HAS authority
// but never enters Sub_Active (its byte-attr copy is 0 — the client-local input
// never reaches it). So the Multiply modifier is added on NO machine, and the float
// "speed" stays at its base value everywhere. The spec asserts the owning client's
// float FinalValue reflects the multiplier — RED today.
//============================================================================

UCLASS()
class UCk_SmNetSubGatedTest_Condition_InputPressed : UCk_SmCondition_EventDriven
{
    private FCk_Handle_ByteAttribute _CachedAttribute;

    UFUNCTION(BlueprintOverride)
    void DoEnterCondition(FCk_Handle_SmCondition InHandle, ECk_Sm_NetContext InNetContext)
    {
        auto SourceEntity = ck::Ctx(InHandle);
        if (ck::Is_NOT_Valid(SourceEntity))
        { return; }

        const auto InputTag = GameplayTags::ResolveGameplayTag(n"ByteAttribute.Gyms.Intent.R");
        _CachedAttribute = utils_byte_attribute::TryGet(SourceEntity, InputTag);
        if (ck::Is_NOT_Valid(_CachedAttribute))
        { return; }

        utils_byte_attribute::BindTo_OnValueChanged(_CachedAttribute, ECk_MinMaxCurrent::Current,
            FCk_Delegate_ByteAttribute_OnValueChanged(this, n"OnInputChanged"));

        Evaluate(int32(_CachedAttribute.Get_FinalValue(ECk_MinMaxCurrent::Current)));
    }

    UFUNCTION(BlueprintOverride)
    void DoExitCondition(FCk_Handle_SmCondition InHandle, ECk_Sm_NetContext InNetContext)
    {
        if (ck::IsValid(_CachedAttribute))
        {
            utils_byte_attribute::UnbindFrom_OnValueChanged(_CachedAttribute, ECk_MinMaxCurrent::Current,
                FCk_Delegate_ByteAttribute_OnValueChanged(this, n"OnInputChanged"));
        }
    }

    UFUNCTION()
    private void OnInputChanged(FCk_Handle InOwner, FCk_Payload_ByteAttribute_OnValueChanged InPayload)
    {
        Evaluate(int32(InPayload.Get_FinalValue()));
    }

    private void Evaluate(int32 InValue)
    {
        if (InValue == 1)
        { MarkSatisfied(); }
        else
        { MarkUnsatisfied(); }
    }
}

// ----------------------------------------------------------------------------
// Authority-gated speed modifier — distilled UBb_SmTask_SprintMultiplier. Adds a
// revocable Multiply modifier on enter (only on the entity authority), removes on
// exit. Add_Revocable replicates, so when the AUTHORITY machine is in Sub_Active
// the modified FinalValue propagates to the owning client.
// ----------------------------------------------------------------------------
UCLASS()
class UCk_SmNetSubGatedTest_SpeedModifierTask : UCk_SmTask_EntityScript
{
    default _TaskMode = ECk_SmTaskMode::EnterExitOnly;

    private FCk_Handle_FloatAttributeModifier _Modifier;

    UFUNCTION(BlueprintOverride)
    void DoEnterTask(FCk_Handle_SmTask InHandle, ECk_Sm_NetContext InNetContext)
    {
        auto Entity = ck::Ctx(InHandle);
        if (ck::Is_NOT_Valid(Entity))
        { return; }

        if (utils_net::Get_HasAuthority(Entity) == false)
        { return; }

        const auto SpeedTag = GameplayTags::ResolveGameplayTag(n"FloatAttribute.Gyms.A");
        auto SpeedAttr = utils_float_attribute::TryGet(Entity, SpeedTag);
        if (ck::Is_NOT_Valid(SpeedAttr))
        { return; }

        _Modifier = SpeedAttr.Add_Revocable(
            FGameplayTag(),
            ECk_AttributeModifier_Operation::Multiply,
            FCk_Fragment_FloatAttributeModifier_ParamsData(1.5f, ECk_MinMaxCurrent::Current));
    }

    UFUNCTION(BlueprintOverride)
    void DoExitTask(FCk_Handle_SmTask InHandle, ECk_Sm_NetContext InNetContext)
    {
        if (ck::IsValid(_Modifier))
        {
            _Modifier.Remove();
            _Modifier = FCk_Handle_FloatAttributeModifier();
        }
    }
}

// ----------------------------------------------------------------------------

UCLASS()
class UCk_SmNetSubGatedTest_Sub_Active : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        AddTask(InHandle, UCk_SmNetSubGatedTest_SpeedModifierTask);
    }
}

UCLASS()
class UCk_SmNetSubGatedTest_Sub_Idle : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto Trans = AddTransition(InHandle, UCk_SmNetSubGatedTest_Sub_Active);
        AddCondition(Trans, UCk_SmNetSubGatedTest_Condition_InputPressed);
    }
}

UCLASS()
class UCk_SmNetSubGatedTest_SubTask : UCk_SmTask_SubStateMachine
{
    default _InitialStateClass = UCk_SmNetSubGatedTest_Sub_Idle;
    default _CompletionBehavior = ECk_SmTask_SubSm_CompletionBehavior::KeepRunning;
}

UCLASS()
class UCk_SmNetSubGatedTest_Parent_Hold : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        // Host the sub-SM; the parent intentionally has no outgoing transition — the
        // assertion reads the sub-SM's current state + the float attribute directly.
        AddTask(InHandle, UCk_SmNetSubGatedTest_SubTask);
    }
}
