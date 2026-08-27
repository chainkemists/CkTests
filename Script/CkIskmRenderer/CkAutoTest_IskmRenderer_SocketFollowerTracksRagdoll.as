// Language=angelscript

//============================================================================
// CK ISKM RENDERER - AUTOMATION TEST: SOCKET-FOLLOWER TRACKS RAGDOLL
//============================================================================
//
// Regression guard for the NPC hair-detach-during-ragdoll bug. A cosmetic that
// socket-follows an IskM proxy (e.g. NPC hair) must stay glued to the leader's
// PHYSICS pose once the leader ragdolls - not fly off, anchored on the frozen
// death-pose entity transform.
//
// The bug: FProcessor_IskmProxy_SocketFollower_SyncTransform normally composes
//   Offset x Socket(Component) x LeaderEntityTransform.
// During ragdoll physics owns the SKMC and FProcessor_IskmProxy_UpdateTransform
// (TExclude<FTag_IskmProxy_Ragdolling>) stops pushing the entity transform onto
// it, so the entity transform freezes at the death pose while the SKMC drifts
// the composition re-anchors the live component-space socket on a stale root and
// the follower detaches. The fix branches on the leader's ragdoll tag and reads
// the WORLD socket directly:  Offset x Socket(World), dropping the
// LocalLocationOffset term (Socket(World) already carries ComponentToWorld).
//
// How this proves the fix without PIE and without relying on gravity:
//   1. Build leader-proxy + a socket-follower (follower Offset = Identity). Give
//      the leader a NON-ZERO _LocalLocationOffset so a wrongly-KEPT offset term is
//      also caught.
//   2. BeginRagdoll on the leader; LOUDLY require the pose flipped to Ragdoll (a stayed-
//      Sequence would make the discriminator vacuous - the demo mesh SKM_Manny_Simple has
//      PA_Mannequin bound in every host, so failing to engage is a real breakage, not a
//      benign env skip). The genuine content-absent case is the RendererData null skip.
//   3. Move the leader ENTITY transform by a huge delta. UpdateTransform excludes
//      ragdolling proxies, so this NEVER reaches the SKMC - the world socket is
//      unmoved, but the BUGGY entity-root composition WOULD jump by the delta.
//   4. Assert the follower still equals  Offset x Get_SocketTransform(Leader, World)
//      (tracks physics, drops the offset) and did NOT drag with the entity move.
//
// Ablating the fix (forcing the else-branch) turns this red: the follower jumps
// with the entity move -> (follower - WorldSocket) ~ MoveDist >> tolerance.
//
// Topology mirrors CkAutoTest_IskmRenderer_SocketFollowerDrivesChild.as.
//============================================================================

class UCk_AutoTest_IskmRenderer_SocketFollowerTracksRagdoll : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;

    private FCk_Handle_Transform _Leader;
    private FCk_Handle_IskmProxy _Proxy;
    private FCk_Handle_Transform _Follower;
    private FVector _FollowerPreMove = FVector::ZeroVector;
    private int32   _SettleTicks = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();

        auto RendererData = iskm_assets::RendererData_Demo();
        if (ck::Is_NOT_Valid(RendererData))
        { FinishSuccess(); return; }

        auto LocalHandle = InHandle;

        // Leader: a target-point transform carrying the proxy. The socket follows this.
        _Leader = utils_target_point::Create(LocalHandle, FTransform::Identity);

        auto Renderer = utils_iskm_renderer::Add(LocalHandle, RendererData);
        auto Params   = FCk_Fragment_IskmProxy_ParamsData(Renderer, FTransform::Identity);
        // Large & non-zero so a wrongly re-added LocalLocationOffset in the ragdoll branch
        // shifts the follower well clear of the tolerance and fails the assert. This is the
        // same field the player sets to the capsule half-height (BB_PlayerCharacter.as:276);
        // 1000 cm is an unambiguous double-count probe, comfortably above physics-fall lag.
        Params.Set_LocalLocationOffset(FVector(0.0f, 0.0f, 1000.0f));
        _Proxy = utils_iskm_proxy::Add(_Leader, Params);

        // Follower: a target point that socket-follows the proxy (Offset = Identity,
        // so it must equal the socket world transform once ragdolling).
        _Follower = utils_target_point::Create(LocalHandle, FTransform::Identity);
        utils_iskm_proxy::Add_SocketFollower(_Proxy, _Follower, n"root", FTransform::Identity);

        WaitOneFrame(n"Step_Ragdoll");
    }

    UFUNCTION()
    private void Step_Ragdoll(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        const int32 k_SettleFrames = 3;
        _SettleTicks++;
        if (_SettleTicks < k_SettleFrames)
        { WaitOneFrame(n"Step_Ragdoll"); return; }

        FCk_Request_IskmProxy_BeginRagdoll Req;
        utils_iskm_proxy::Request_BeginRagdoll(_Proxy, Req);

        _SettleTicks = 0;
        WaitOneFrame(n"Step_MoveLeader");
    }

    UFUNCTION()
    private void Step_MoveLeader(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        const int32   k_SettleFrames = 2;
        const float32 k_MoveDist     = 10000.0f;

        _SettleTicks++;
        if (_SettleTicks < k_SettleFrames)
        { WaitOneFrame(n"Step_MoveLeader"); return; }

        // Loudly guard that ragdoll actually engaged - otherwise the discriminator below
        // never runs and the test would pass vacuously. GetPhysicsAsset() != null is the
        // only precondition (independent of whether Chaos actually steps headlessly), and
        // the demo mesh SKM_Manny_Simple has PA_Mannequin bound in every host, so a stayed-
        // Sequence here means a real breakage (mesh lost its PhysicsAsset), not an env skip.
        // (The genuine content-absent case is already handled by the RendererData null skip.)
        if (utils_iskm_proxy::Get_PoseSource(_Proxy) != ECk_IskmProxy_PoseSource::Ragdoll)
        {
            FinishFailure("Ragdoll did not engage (PoseSource != Ragdoll) - SKM_Manny_Simple lost its PhysicsAsset binding; the fix's ragdoll branch was never exercised");
            return;
        }

        _FollowerPreMove = utils_transform::Get_EntityCurrentTransform(_Follower).GetLocation();

        // Move the leader entity far along X. UpdateTransform excludes ragdolling
        // proxies, so this NEVER reaches the SKMC - the world socket stays put.
        utils_transform::Request_SetTransform(_Leader, FTransform(FVector(k_MoveDist, 0.0f, 0.0f)));

        _SettleTicks = 0;
        WaitOneFrame(n"Step_Assert");
    }

    UFUNCTION()
    private void Step_Assert(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        const int32   k_SettleFrames = 3;
        const float32 k_MoveDist     = 10000.0f;
        // Tolerance sits above worst-case physics-fall lag between the follower's compute
        // and this live socket read (~tens of cm even at low headless fps), yet well below
        // the 1000 cm LocalLocationOffset probe and the 10000 cm entity move. So it passes
        // ONLY when the follower equals Offset x WorldSocket exactly (offset dropped).
        const float32 k_Tolerance    = 400.0f;

        _SettleTicks++;
        if (_SettleTicks < k_SettleFrames)
        { WaitOneFrame(n"Step_Assert"); return; }

        const auto FollowerNow = utils_transform::Get_EntityCurrentTransform(_Follower).GetLocation();
        const auto WorldSocket = utils_iskm_proxy::Get_SocketTransform(
            _Proxy, n"root", ECk_IskmProxy_TransformSpace::World).GetLocation();
        const auto LeaderNow   = utils_transform::Get_EntityCurrentTransform(_Leader).GetLocation();

        // Non-vacuity: the leader entity actually moved, so the discriminator below
        // exercises a real divergence between the two roots.
        Assert_True(float32(LeaderNow.Size()) > k_MoveDist * 0.9f,
            f"Test setup failed: leader entity did not move (at {LeaderNow.Size()} cm, expected ~{k_MoveDist})");

        // PRIMARY: the follower (Offset = Identity) must EQUAL the physics WORLD socket.
        // Without the fix the follower rides the moved entity root -> off by ~k_MoveDist.
        // If the fix wrongly KEEPS the LocalLocationOffset -> off by ~1000 cm. Either fails.
        Assert_True(float32((FollowerNow - WorldSocket).Size()) < k_Tolerance,
            f"Ragdoll follower did not track the world socket (delta {(FollowerNow - WorldSocket).Size()} cm > {k_Tolerance}) - SyncTransform ragdoll branch regression");

        // SECONDARY (lag-immune - two follower reads): the follower did NOT drag with the
        // stale entity move. The delta from its pre-move pose is only the physics fall, not
        // the 10000 cm entity translation the buggy entity-root composition would apply.
        Assert_True(float32((FollowerNow - _FollowerPreMove).Size()) < k_MoveDist * 0.2f,
            f"Ragdoll follower dragged with the stale entity transform (moved {(FollowerNow - _FollowerPreMove).Size()} cm on a {k_MoveDist} cm entity move)");

        FinishSuccess();
    }
}

class ACk_AutoTest_IskmRenderer_SocketFollowerTracksRagdoll_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_IskmRenderer_SocketFollowerTracksRagdoll;
    default _TimeoutSeconds = 10.0f;
}
