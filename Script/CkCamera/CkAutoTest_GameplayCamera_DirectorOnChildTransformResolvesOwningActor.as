// Language=angelscript

//============================================================================
// CK CAMERA - AUTOMATION TEST: DIRECTOR ON CHILD TRANSFORM RESOLVES OWNING ACTOR
//============================================================================
//
// A director composed on a CHILD transform entity of the actor's entity (e.g. a head node) must still resolve
// the actor up the ownership chain: the boom trace ignores it and control rotation reaches its controller.
// Get_OwningActor exposes the resolved actor; resolution is synchronous, so no wait is needed.
//============================================================================

class UCk_AutoTest_GameplayCamera_DirectorOnChildTransformResolvesOwningActor : UCk_AutoTest_Base
{
    private ACkAutoTest_GameplayCamera_Helper _Helper;
    private FCk_Handle_Camera _Camera;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        _Helper = Cast<ACkAutoTest_GameplayCamera_Helper>(SpawnActor(
            ACkAutoTest_GameplayCamera_Helper, FVector::ZeroVector, FRotator::ZeroRotator));
        if (ck::Is_NOT_Valid(_Helper))
        { FinishFailure("Failed to spawn GameplayCamera helper"); return; }

        utils_pending_entity_script::Promise_OnConstructed(
            _Helper.PendingEntity,
            FCk_Delegate_EntityScript_Constructed(this, n"OnEntityReady"));
    }

    UFUNCTION()
    private void OnEntityReady(FCk_Handle_EntityScript InEntityScriptHandle)
    {
        if (IsFinished()) { return; }

        auto OwnedEntity = FCk_Handle(InEntityScriptHandle);
        auto Child = utils_transform::Create(OwnedEntity, FTransform(), ECk_Replication::DoesNotReplicate);
        _Camera = utils_camera::Add(Child, FCk_Camera_Spec(_Helper.CameraComponent));

        Assert_Valid(_Camera, "director composed on a child transform");
        Assert_True(_Camera.Get_OwningActor() == _Helper,
            "owning actor resolves up the ownership chain to the helper");

        FinishSuccess();
    }
}
