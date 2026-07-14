// Language=angelscript

//============================================================================
// CK ISKM RENDERER — AUTOMATION TEST: SOCKET-FOLLOWER DRIVES SCENE-NODE CHILD
//============================================================================
//
// Regression guard for the held-item no-follow bug. A scene-node child parented
// UNDER an IskM socket-follower's output transform must track the follower every
// frame. The socket follower (FProcessor_IskmProxy_SocketFollower_SyncTransform)
// runs in FGroup_Transform_Finalize so scene-node-driven LEADERS are read fresh —
// but that is AFTER TProcessor_SceneNode_Update (FGroup_Transform), so a scene-node
// child's parent carries no FTag_Transform_Updated when the child recomputes, and
// the child freezes at its construct pose after the one-shot settle.
// FProcessor_IskmProxy_SocketFollower_SyncDescendants closes that gap; this test
// pins it (without the fix the child stays put -> ChildDelta ~ 0 while the follower
// moved -> assertion fails).
//
// Topology mirrors the player's held weapon:
//   proxy (leader) --socket-follower--> attach point --scene-node child--> weapon.
//
// Skips gracefully when the demo renderer content is unavailable (registry not
// generated), matching the sibling Plan-1 IskM tests.
//============================================================================

class UCk_AutoTest_IskmRenderer_SocketFollowerDrivesChild : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;

    private FCk_Handle_Transform _Leader;
    private FCk_Handle_Transform _Follower;
    private FCk_Handle_Transform _Child;
    private FVector _Follower0 = FVector::ZeroVector;
    private FVector _Child0    = FVector::ZeroVector;
    private int32   _SettleTicks = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();

        auto RendererData = iskm_assets::RendererData_Demo();
        if (ck::Is_NOT_Valid(RendererData))
        { FinishSuccess(); return; }

        auto LocalHandle = InHandle;

        // Leader: a target-point transform carrying the proxy. Moving this moves the socket.
        _Leader = utils_target_point::Create(LocalHandle, FTransform::Identity);

        auto Renderer = utils_iskm_renderer::Add(LocalHandle, RendererData);
        auto Params   = FCk_Fragment_IskmProxy_ParamsData(Renderer, FTransform::Identity);
        auto Proxy    = utils_iskm_proxy::Add(_Leader, Params);

        // Follower: the RightHand-style attach point that socket-follows the proxy.
        _Follower = utils_target_point::Create(LocalHandle, FTransform::Identity);
        utils_iskm_proxy::Add_SocketFollower(Proxy, _Follower, n"root", FTransform::Identity);

        // Child: a scene-node child of the follower at a fixed local offset (the held weapon).
        _Child = utils_target_point::Create(LocalHandle, FTransform::Identity);
        utils_scene_node::Add(_Child, _Follower, FTransform(FVector(0.0f, 0.0f, 50.0f)));

        WaitOneFrame(n"Step_CaptureBaseline");
    }

    UFUNCTION()
    private void Step_CaptureBaseline(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        const int32 k_SettleFrames = 3;
        _SettleTicks++;
        if (_SettleTicks < k_SettleFrames)
        { WaitOneFrame(n"Step_CaptureBaseline"); return; }

        _Follower0 = utils_transform::Get_EntityCurrentTransform(_Follower).GetLocation();
        _Child0    = utils_transform::Get_EntityCurrentTransform(_Child).GetLocation();

        // Move the leader far along X — the socket follower should carry the attach point with it.
        utils_transform::Request_SetTransform(_Leader, FTransform(FVector(1000.0f, 0.0f, 0.0f)));

        _SettleTicks = 0;
        WaitOneFrame(n"Step_AssertTracked");
    }

    UFUNCTION()
    private void Step_AssertTracked(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        const int32   k_SettleFrames = 3;
        const float32 k_MoveDist     = 1000.0f;
        const float32 k_Tolerance    = 25.0f;

        _SettleTicks++;
        if (_SettleTicks < k_SettleFrames)
        { WaitOneFrame(n"Step_AssertTracked"); return; }

        const auto FollowerDelta = utils_transform::Get_EntityCurrentTransform(_Follower).GetLocation() - _Follower0;
        const auto ChildDelta    = utils_transform::Get_EntityCurrentTransform(_Child).GetLocation() - _Child0;

        // The follower must actually have moved with the leader, else the test is vacuous.
        Assert_True(float32(FollowerDelta.Size()) > k_MoveDist * 0.9f,
            f"Socket follower did not track the leader move (follower delta {FollowerDelta.Size()} cm, expected ~{k_MoveDist})");

        // The scene-node child must have moved by the SAME world delta as its follower parent.
        // Without SyncDescendants the child freezes: ChildDelta ~ 0 while FollowerDelta ~ k_MoveDist.
        Assert_True(float32((ChildDelta - FollowerDelta).Size()) < k_Tolerance,
            f"Scene-node child did not track the socket follower (child delta {ChildDelta.Size()} cm vs follower delta {FollowerDelta.Size()} cm) — SyncDescendants regression");

        FinishSuccess();
    }
}

class ACk_AutoTest_IskmRenderer_SocketFollowerDrivesChild_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_IskmRenderer_SocketFollowerDrivesChild;
    default _TimeoutSeconds = 10.0f;
}
