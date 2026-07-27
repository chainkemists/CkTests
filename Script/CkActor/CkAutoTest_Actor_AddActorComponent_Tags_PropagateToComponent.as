// Language=angelscript

//============================================================================
// CK ACTOR — AUTOMATION TEST: AddActorComponent Tags PROPAGATE TO COMPONENT
//============================================================================
//
// Pins the contract that _ComponentParams._Tags on the request struct is
// copied onto the added component's ComponentTags (in
// Request_AddNewActorComponent: `Comp->ComponentTags = InParams.Get_Tags();`).
//
// Flow:
//   1. Build AddActorComponent request with two tags on _ComponentParams.
//   2. Wait for OnComponentAdded delegate to fire.
//   3. Assert the added component's ComponentTags array contains both
//      tags in the same order.
//============================================================================

class UCk_AutoTest_Actor_AddActorComponent_Tags_PropagateToComponent : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 4.0f;

    private ACkAutoTest_ActorEntity_Helper _Helper;
    private TArray<FName> _ObservedTags;
    private bool _DelegateFired = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        _Helper = Cast<ACkAutoTest_ActorEntity_Helper>(SpawnActor(
            ACkAutoTest_ActorEntity_Helper, FVector::ZeroVector, FRotator::ZeroRotator));
        if (ck::Is_NOT_Valid(_Helper))
        {
            FinishFailure("Failed to spawn ActorEntity helper");
            return;
        }

        utils_pending_entity_script::Promise_OnConstructed(
            _Helper.PendingEntity,
            FCk_Delegate_EntityScript_Constructed(this, n"OnEntityReady"));
    }

    UFUNCTION()
    private void OnEntityReady(FCk_Handle_EntityScript InEntityScriptHandle)
    {
        if (IsFinished()) { return; }

        auto OwnedEntity = FCk_Handle(InEntityScriptHandle);

        auto Tags = TArray<FName>();
        Tags.Add(n"AutoTest.Tag.Alpha");
        Tags.Add(n"AutoTest.Tag.Beta");

        auto ComponentParams = FCk_AddActorComponent_Params(_Helper.SceneRoot);
        ComponentParams.Set_AttachmentType(ECk_ActorComponent_AttachmentPolicy::DoNotAttach);
        ComponentParams.Set_Tags(Tags);

        auto Req = FCk_Request_ActorModifier_AddActorComponent(UStaticMeshComponent);
        Req.Set_ComponentParams(ComponentParams);

        utils_actor_modifier::Request_AddActorComponent(
            OwnedEntity,
            Req,
            FInstancedStruct(),
            FCk_Delegate_ActorModifier_OnActorComponentAdded(this, n"OnComponentAdded"));

        WaitUntil(n"Check_DelegateFired", n"OnSettled");
    }

    UFUNCTION()
    private void Check_DelegateFired(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_DelegateFired);
    }

    UFUNCTION()
    private void OnComponentAdded(
        AActor InOwner,
        UActorComponent InActorComponentAdded,
        const FInstancedStruct &in InOptionalPayload)
    {
        _DelegateFired = true;
        if (ck::IsValid(InActorComponentAdded))
        {
            _ObservedTags = InActorComponentAdded.ComponentTags;
        }
    }

    UFUNCTION()
    private void OnSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        Assert_True(_DelegateFired, "OnComponentAdded should have fired");
        Assert_Equals_Int(_ObservedTags.Num(), 2,
            "Added component should carry both ComponentTags");
        if (_ObservedTags.Num() >= 2)
        {
            Assert_True(_ObservedTags[0] == n"AutoTest.Tag.Alpha",
                f"First tag should be 'AutoTest.Tag.Alpha' (got '{_ObservedTags[0]}')");
            Assert_True(_ObservedTags[1] == n"AutoTest.Tag.Beta",
                f"Second tag should be 'AutoTest.Tag.Beta' (got '{_ObservedTags[1]}')");
        }
        FinishSuccess();
    }
}
