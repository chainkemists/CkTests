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

struct FCk_Fragment_TESTONLY_IskmSocketCurrentWorldProbeResult
{
    bool Completed = false;
    bool Succeeded = false;
    FVector Location = FVector::ZeroVector;
}

struct FCk_Fragment_TESTONLY_IskmSocketCurrentWorldProbeMarker {}

// Captures in Gameplay_Camera: current entity transforms have been applied, while the proxy's
// component world transform is not pushed until PostTransform. A helper that reads SKMC world
// space therefore records the previous location and fails the test deterministically.
class UCk_TESTONLY_Processor_IskmSocketCurrentWorldProbe : UCk_Processor_Script_Base_UE
{
    default _Group = n"FGroup_Gameplay_Camera";
    default _MarkedDirtyBy = FCk_Fragment_TESTONLY_IskmSocketCurrentWorldProbeMarker;

    UFUNCTION(BlueprintOverride)
    void Configure(FCk_ScriptProcessorQuery& Query)
    {
        Query.Require(FCk_Fragment_TESTONLY_IskmSocketCurrentWorldProbeMarker);
        Query.Require(FCk_Fragment_TESTONLY_IskmSocketCurrentWorldProbeResult);
    }

    UFUNCTION(BlueprintOverride)
    void ForEachBatch(FCk_ScriptQueryBatch Batch, FCk_Time InDeltaT)
    {
        for (int32 Index = 0; Index < Batch.Num(); ++Index)
        {
            auto Entity = Batch.GetHandle(Index);
            auto& Probe = Entity.Get_Fragment(FCk_Fragment_TESTONLY_IskmSocketCurrentWorldProbeResult);
            if (Probe.Completed)
            { continue; }

            FTransform SocketWorld;
            auto Proxy = Entity.As_IskmProxy(ECk_SanityCheck::UnChecked);
            Probe.Succeeded = utils_iskm_proxy::TryGet_SocketTransform_CurrentEntityWorld(
                Proxy, n"root", SocketWorld);
            Probe.Location = SocketWorld.GetLocation();
            Probe.Completed = true;
            Entity.Request_TryRemove(FCk_Fragment_TESTONLY_IskmSocketCurrentWorldProbeMarker);
        }
    }
}

class UCk_AutoTest_IskmRenderer_SocketFollowerDrivesChild : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;

    private FCk_Handle_Transform _Leader;
    private FCk_Handle_Transform _Follower;
    private FCk_Handle_Transform _Child;
    private FCk_Handle_IskmProxy _Proxy;
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
        _Proxy = utils_iskm_proxy::Add(_Leader, Params);

        // Add publishes a valid proxy before Gameplay_Rendering has created its BaseSKMC.
        // That lifecycle window is ordinary TryGet absence, not a malformed proxy.
        FTransform PendingSocketTransform = FTransform(FVector(111.0f, 222.0f, 333.0f));
        const auto GotPendingSocket = utils_iskm_proxy::TryGet_SocketTransform_CurrentEntityWorld(
            _Proxy, n"root", PendingSocketTransform);
        Assert_False(GotPendingSocket,
            "current-entity-world socket helper must report unavailable while the proxy needs setup");
        Assert_True(PendingSocketTransform.Equals(FTransform::Identity),
            "unavailable current-entity-world socket helper must clear its output to identity");

        // Follower: the RightHand-style attach point that socket-follows the proxy.
        _Follower = utils_target_point::Create(LocalHandle, FTransform::Identity);
        utils_iskm_proxy::Add_SocketFollower(_Proxy, _Follower, n"root", FTransform::Identity);

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
        FTransform CurrentSocketTransform0;
        const auto GotCurrentSocket0 = utils_iskm_proxy::TryGet_SocketTransform_CurrentEntityWorld(
            _Proxy, n"root", CurrentSocketTransform0);
        Assert_True(GotCurrentSocket0,
            "current-entity-world socket helper must resolve the demo renderer root socket");
        const auto CurrentSocket0 = CurrentSocketTransform0.GetLocation();
        Assert_True(float32((CurrentSocket0 - _Follower0).Size()) < 1.0f,
            "current-entity-world socket helper must match the canonical socket follower before movement");

        // Move the leader far along X — the socket follower should carry the attach point with it.
        utils_transform::Request_SetTransform(_Leader, FTransform(FVector(1000.0f, 0.0f, 0.0f)));
        _Leader.AddOrGet_Fragment(FCk_Fragment_TESTONLY_IskmSocketCurrentWorldProbeResult);
        _Leader.AddOrGet_Fragment(FCk_Fragment_TESTONLY_IskmSocketCurrentWorldProbeMarker);

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
        FTransform CurrentSocketTransform;
        const auto GotCurrentSocket = utils_iskm_proxy::TryGet_SocketTransform_CurrentEntityWorld(
            _Proxy, n"root", CurrentSocketTransform);
        Assert_True(GotCurrentSocket,
            "current-entity-world socket helper must resolve after movement");
        const auto CurrentSocket = CurrentSocketTransform.GetLocation();
        const auto FollowerNow = utils_transform::Get_EntityCurrentTransform(_Follower).GetLocation();
        const auto& Probe = _Leader.Get_Fragment(FCk_Fragment_TESTONLY_IskmSocketCurrentWorldProbeResult);

        // The follower must actually have moved with the leader, else the test is vacuous.
        Assert_True(float32(FollowerDelta.Size()) > k_MoveDist * 0.9f,
            f"Socket follower did not track the leader move (follower delta {FollowerDelta.Size()} cm, expected ~{k_MoveDist})");

        // The scene-node child must have moved by the SAME world delta as its follower parent.
        // Without SyncDescendants the child freezes: ChildDelta ~ 0 while FollowerDelta ~ k_MoveDist.
        Assert_True(float32((ChildDelta - FollowerDelta).Size()) < k_Tolerance,
            f"Scene-node child did not track the socket follower (child delta {ChildDelta.Size()} cm vs follower delta {FollowerDelta.Size()} cm) — SyncDescendants regression");

        Assert_True(float32((CurrentSocket - FollowerNow).Size()) < 1.0f,
            "current-entity-world socket helper must stay aligned with the canonical follower after movement");

        Assert_True(Probe.Completed && Probe.Succeeded,
            "Gameplay_Camera probe must resolve the current-entity-world socket before PostTransform");
        Assert_True(float32((Probe.Location - FollowerNow).Size()) < 1.0f,
            "Gameplay_Camera probe must follow the live entity transform before proxy component placement");

        FinishSuccess();
    }
}

class ACk_AutoTest_IskmRenderer_SocketFollowerDrivesChild_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_IskmRenderer_SocketFollowerDrivesChild;
    default _TimeoutSeconds = 10.0f;
}
