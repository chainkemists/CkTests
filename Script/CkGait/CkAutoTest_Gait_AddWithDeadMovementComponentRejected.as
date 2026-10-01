// Language=angelscript
class UCk_AutoTest_Gait_AddWithDeadMovementComponentRejected : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;
    private FCk_GaitAutoTestFixture _F;
    private FCk_Handle _Owner;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step("spawn the test character", n"Step_Spawn");
        Add_Step_WaitUntil("character entity constructed", n"Check_EntityReady");
        Add_Step("add gaits to a plain transform entity", n"Step_AddOnRoot");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_Spawn(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _Owner = InHandle;
        _F.Spawn(this, FVector(1000.0, 30000.0, -40000.0));
        if (ck::Is_NOT_Valid(_F.Character))
        {
            return;
        }

        utils_pending_entity_script::Promise_OnConstructed(_F.Character.PendingEntity,
            FCk_Delegate_EntityScript_Constructed(this, n"OnEntityReady"));
    }

    UFUNCTION()
    private void OnEntityReady(FCk_Handle_EntityScript InEntityScript)
    {
        if (IsFinished())
        {
            return;
        }

        _F.Ready(_Owner, InEntityScript);
    }

    UFUNCTION()
    private void Check_EntityReady(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(ck::IsValid(_F.Entity) && ck::IsValid(_F.Root));
    }

    UFUNCTION()
    private void Step_AddOnRoot(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Valid(_F.Root, "the plain transform itself is valid, so only the spec's movement component can be rejected");
        const auto Rejected = utils_gait::Add(FCk_Handle(_F.Root), FCk_Gait_Spec());
        Assert_Invalid(Rejected, "Add with a spec whose movement component is unset returns an invalid handle");
        Assert_False(FCk_Handle(_F.Root).Is_Gait(), "the rejected Add left no gait on the entity");

        auto Spec = FCk_Gait_Spec();
        Spec.Set_MovementComponent(_F.Character.CharacterMovement);
        const auto Accepted = utils_gait::Add(FCk_Handle(_F.Root), Spec);
        Assert_Valid(Accepted, "a gait composes on a plain transform entity: the source is the spec's component, not an actor on the entity");
        FinishSuccess();
    }
}

class ACk_AutoTest_Gait_AddWithDeadMovementComponentRejected_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Gait_AddWithDeadMovementComponentRejected;
    default _TimeoutSeconds = 10.0f;
    UFUNCTION(BlueprintOverride)
    TArray<FString> Get_ExpectedLogErrors() const
    {
        TArray<FString> Errors;
        Errors.Add("Gait Add rejected");
        return Errors;
    }
}
