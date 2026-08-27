// Language=angelscript

//============================================================================
// CK CAMERA - AUTOMATION TEST: CAMERA SHAKE ADD CREATES RECORD ENTRY
//============================================================================
//
// First-coverage seed for CkCamera. Adding a CameraShake with a tag
// name + base UCameraShakeBase class returns a valid shake handle and
// Has_Any reports true on the owning entity (the Record is created
// and populated).
//
// The actual shake playback path (Request_PlayOnTarget /
// Request_PlayAtLocation) needs an APlayerCameraManager; this seed
// only pins the Add -> Record-of-shakes contract.
//============================================================================

class UCk_AutoTest_CameraShake_Add_CreatesEntry : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 4.0f;

    private ACkAutoTest_ActorEntity_Helper _Helper;

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

        auto Params = FCk_Fragment_CameraShake_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.CameraShake.Seed"),
            UCameraShakeBase);
        auto Shake = utils_camera_shake::Add(OwnedEntity, Params);

        Assert_True(ck::IsValid(Shake),
            "utils_camera_shake::Add should return a valid FCk_Handle_CameraShake");
        Assert_True(utils_camera_shake::Has_Any(OwnedEntity),
            "After Add, Has_Any on the owning entity should report true");

        FinishSuccess();
    }
}
