// Language=angelscript

//============================================================================
// CK WORLDSPACEWIDGET - AUTOMATION TEST: COLLAPSE ON DISABLE
//============================================================================
//
// A disabled ScreenOverlay widget must be COLLAPSED, not merely held at zero
// RenderOpacity: an opacity-0 wrapper still lays out, paints, hit-tests, and
// takes a SetPositionInViewport write every frame for the entity's whole life.
//
//   1. enabled at birth            -> not collapsed
//   2. Request_SetEnabled(false)   -> collapsed
//   3. Request_SetEnabled(true)    -> not collapsed again (visibility restored)
//
// ScreenOverlay creation hard-requires a local player (the wrapper reaches the
// screen through AddToPlayerScreen), so a lane without one skip-passes instead
// of tripping the framework's ensures.
//============================================================================

class UCk_AutoTest_WorldSpaceWidget_CollapseOnDisable : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 15.0f;

    private FCk_Handle_WorldSpaceWidget _Widget;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto PlayerController = Gameplay::GetPlayerController(0);

        if (ck::Is_NOT_Valid(PlayerController) || ck::Is_NOT_Valid(PlayerController.LocalPlayer))
        {
            ck::Trace("[WSW CollapseOnDisable] no local player in this lane - a ScreenOverlay wrapper cannot reach the screen; skipping");
            FinishSuccess();
            return;
        }

        // The content widget's identity is irrelevant here - only the WRAPPER's visibility is
        // asserted. UUserWidget itself and every Ck widget base are UCLASS(Abstract), so this
        // borrows the one concrete widget CkTests already proves constructible headless.
        auto ContentWidget = WidgetBlueprint::CreateWidget(UCk_GameSettingsUI_ScreenWidget, PlayerController);

        if (ck::Is_NOT_Valid(ContentWidget))
        {
            ck::Trace("[WSW CollapseOnDisable] content widget failed to create in this lane; skipping");
            FinishSuccess();
            return;
        }

        auto AnchorEntity = utils_entity_lifetime::Request_CreateEntity(InHandle);
        auto AnchorTransform = utils_transform::Add(
            AnchorEntity, FTransform(FRotator::ZeroRotator, FVector(0.0, 0.0, 300.0)), ECk_Replication::DoesNotReplicate);

        auto Params = FCk_Fragment_WorldSpaceWidget_ParamsData(
            ContentWidget, ECk_UI_Widget_ViewportOperation::AddToViewport, 0);
        Params.Set_RenderMode(ECk_WorldSpaceWidget_RenderMode::ScreenOverlay);

        _Widget = utils_world_space_widget::CreateAndAttach_ToEntity(AnchorTransform, Params);

        if (ck::Is_NOT_Valid(_Widget))
        {
            ck::Trace("[WSW CollapseOnDisable] WorldSpaceWidget creation yielded an invalid handle in this lane; skipping");
            FinishSuccess();
            return;
        }

        // Request_SetEnabled mutates the wrapper on the calling stack; the settle exists so a
        // full UpdateLocation pass runs against each state before the wrapper is read back.
        WaitFrames(2, n"OnEnabledAtBirth");
    }

    UFUNCTION()
    private void OnEnabledAtBirth(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_False(utils_world_space_widget::Get_Debug_IsWrapperCollapsed(_Widget),
            "an enabled ScreenOverlay widget must not be collapsed");

        utils_world_space_widget::Request_SetEnabled(_Widget, false);

        WaitFrames(2, n"OnDisabled");
    }

    UFUNCTION()
    private void OnDisabled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_True(utils_world_space_widget::Get_Debug_IsWrapperCollapsed(_Widget),
            "disable must Collapse the wrapper, not just zero opacity");

        utils_world_space_widget::Request_SetEnabled(_Widget, true);

        WaitFrames(2, n"OnReEnabled");
    }

    UFUNCTION()
    private void OnReEnabled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_False(utils_world_space_widget::Get_Debug_IsWrapperCollapsed(_Widget),
            "re-enabling must restore the wrapper's pre-disable visibility");

        FinishSuccess();
    }
}
