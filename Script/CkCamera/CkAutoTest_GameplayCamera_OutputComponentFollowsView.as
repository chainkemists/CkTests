// Language=angelscript

//============================================================================
// CK CAMERA - AUTOMATION TEST: OUTPUT COMPONENT FOLLOWS VIEW
//============================================================================
//
// With _Placement = FollowView, UCk_CameraComponent::GetCameraView moves the component itself onto the composed
// view, so Unreal children attached to it render where the view renders. A 300 cm boom with collision off puts
// the view well away from the actor; the component must land on the view, not stay at the actor.
//============================================================================

class UCk_AutoTest_GameplayCamera_OutputComponentFollowsView : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;

    private ACkAutoTest_GameplayCamera_FollowViewHelper _Helper;
    private FCk_Handle_Camera _Camera;
    private APlayerController _PC;
    private int32 _Polls = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        _Helper = Cast<ACkAutoTest_GameplayCamera_FollowViewHelper>(SpawnActor(
            ACkAutoTest_GameplayCamera_FollowViewHelper, FVector(0.0, 0.0, -40000.0), FRotator::ZeroRotator));
        if (ck::Is_NOT_Valid(_Helper))
        { FinishFailure("Failed to spawn GameplayCamera FollowView helper"); return; }

        utils_pending_entity_script::Promise_OnConstructed(
            _Helper.PendingEntity,
            FCk_Delegate_EntityScript_Constructed(this, n"OnEntityReady"));
    }

    UFUNCTION()
    private void OnEntityReady(FCk_Handle_EntityScript InEntityScriptHandle)
    {
        if (IsFinished()) { return; }

        auto OwnedEntity = FCk_Handle(InEntityScriptHandle);
        auto OwnedTransform = OwnedEntity.As_Transform();

        auto Spec = FCk_Camera_Spec(_Helper.CameraComponent);
        auto Profile = Spec.Get_Profile();
        auto Rig = Profile.Get_Rig();
        Rig.Set_BoomArmLength(300.0f);
        Profile.Set_Rig(Rig);
        Profile.Set_HasCollision(false);
        Spec.Set_Profile(Profile);
        _Camera = utils_camera::Add(OwnedTransform, Spec);
        if (ck::Is_NOT_Valid(_Camera))
        { FinishFailure("Failed to add GameplayCamera"); return; }

        _PC = Gameplay::GetPlayerController(0);
        if (ck::Is_NOT_Valid(_PC))
        { FinishFailure("No player controller to make the helper the view target"); return; }

        _PC.SetViewTargetWithBlend(_Helper, 0.0f);

        WaitUntil(n"Check_Followed", n"OnFollowed", 0, 2.0f);
    }

    UFUNCTION()
    private void Check_Followed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;

        // Decision-gate diagnostic (PHASE_A 4.3): if the component never follows, this line says whether the
        // headless harness honoured the view target at all.
        ++_Polls;
        if (_Polls == 10)
        { Log(f"[CkCamera FollowView] ViewTargetIsHelper={_PC.GetViewTarget() == _Helper}"); }

        Res.Set(_Helper.CameraComponent.GetWorldLocation().Equals(_Camera.Get_ViewInfo().Location, 1.0));
    }

    UFUNCTION()
    private void OnFollowed(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_True(_Helper.CameraComponent.GetWorldLocation().Equals(_Camera.Get_ViewInfo().Location, 1.0),
            "the output component sits on the composed view");
        Assert_True((_Helper.CameraComponent.GetWorldLocation() - _Helper.GetActorLocation()).Size() > 250.0,
            "the component moved onto the boomed view, away from the actor");

        FinishSuccess();
    }
}
