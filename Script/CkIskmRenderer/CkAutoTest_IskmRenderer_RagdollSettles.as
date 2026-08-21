// Language=angelscript

//============================================================================
// CK ISKM RENDERER — AUTOMATION TEST: RAGDOLL SETTLE SIGNAL
//============================================================================
//
// Get_IsRagdollSettled answers "has this ragdoll physically come to rest?" by
// asking whether any rigid body is still awake. Chaos auto-sleeps bodies at
// rest, so the signal is exact and needs no velocity threshold — but that also
// means the query is only meaningful while the proxy is actually ragdolling.
//
// The three assertions, in the order they run:
//   1. A proxy that has never ragdolled is NOT settled. A body that never fell
//      has not come to rest — reporting settled there would make every consumer
//      that gates on it fire before the ragdoll even starts.
//   2. Once the ragdoll has engaged, it is NOT settled. This is the
//      discriminator: BeginRagdoll wakes every body, so an implementation that
//      simply returned true would pass 1 and 3 and fail only here.
//   3. It eventually IS settled, waited on as a named condition rather than a
//      hop count — how long Chaos takes to sleep is a physics property, not a
//      processor-ordering one.
//
// Two things about the setup are load-bearing, both measured rather than assumed.
//
// It needs a floor: AutoTests_CkTests_Level carries a scaled BasicShapes/Cube whose
// top face sits at Z=0. A body in free fall accelerates forever and can never sleep.
//
// It also needs to spawn CLEAR of that floor, which is what the +15 Z offset below is
// for. Spawned at Z=0 the standing pose's lower bodies start interpenetrating the
// plate; Chaos depenetration then throws the ragdoll into the air and it lands in a
// self-sustaining micro-oscillation — root Z holding steady to within 1.5 mm yet never
// dropping under the solver's sleep threshold, so it stays awake indefinitely. Clear of
// the plate the same body comes to rest inside ~0.15 mm and sleeps in a few seconds.
// If this test ever hangs on the settle step, suspect the resting configuration before
// suspecting Get_IsRagdollSettled.
//
// Ragdoll failing to ENGAGE is a loud failure, not a skip: SKM_Manny_Simple has
// PA_Mannequin bound in every host, so a proxy that stays on Sequence means the
// mesh lost its PhysicsAsset binding. The genuine content-absent case is the
// RendererData null skip, same as the sibling ragdoll tests.
//
//============================================================================

class UCk_AutoTest_IskmRenderer_RagdollSettles : UCk_AutoTest_Base
{
    // Physics sleep is slower than most assertions in this suite: the body has to fall,
    // tumble, and then stay under the sleep thresholds long enough for Chaos to count it
    // down. Measured at a few seconds; the headroom is deliberate, because how long the
    // tumble takes depends on how the body happens to land.
    default _TimeoutSeconds = 15.0f;

    private FCk_Handle_IskmProxy _Proxy;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();

        UCk_IskmRenderer_Data RendererData = iskm_assets::RendererData_Demo();
        if (ck::Is_NOT_Valid(RendererData))
        { FinishSuccess(); return; }

        auto LocalHandle = InHandle;
        // Clear of the floor plate: at Z=0 the standing pose's lower bodies start interpenetrating
        // it and Chaos depenetration launches the ragdoll over a metre up before it can ever rest.
        auto TransformHandle = utils_transform::Add(LocalHandle, FTransform(FVector(0.0f, 0.0f, 15.0f)));

        auto Renderer = utils_iskm_renderer::Add(LocalHandle, RendererData);
        auto Params = FCk_Fragment_IskmProxy_ParamsData(Renderer, FTransform::Identity);
        _Proxy = utils_iskm_proxy::Add(TransformHandle, Params);

        Add_Step(          "a proxy that has never ragdolled is not settled", n"Step_AssertNotSettledBeforeRagdoll");
        Add_Step(          "ragdoll the proxy with an impulse",               n"Step_BeginRagdoll");
        Add_Step_WaitUntil("the ragdoll engages",                             n"Check_Ragdolling");
        Add_Step(          "a freshly woken ragdoll is not settled",          n"Step_AssertNotSettledWhileAwake");
        Add_Step_WaitUntil("every rigid body goes to sleep",                  n"Check_Settled", 2400);
        Run_Steps(LocalHandle);
    }

    UFUNCTION()
    private void Step_AssertNotSettledBeforeRagdoll(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_False(utils_iskm_proxy::Get_IsRagdollSettled(_Proxy),
            "A proxy that is not ragdolling reported settled");
    }

    UFUNCTION()
    private void Step_BeginRagdoll(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        FCk_Request_IskmProxy_BeginRagdoll Req;
        // Deliberately gentle: enough that the settle is a real physics outcome rather than a
        // body that never moved, small enough to keep the landing energy low. Assertion 2 does
        // not depend on its magnitude — BeginRagdoll wakes every body regardless.
        Req.Set_Impulse(FVector(100.0f, 0.0f, 0.0f));
        utils_iskm_proxy::Request_BeginRagdoll(_Proxy, Req);
    }

    UFUNCTION()
    private void Check_Ragdolling(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_iskm_proxy::Get_PoseSource(_Proxy) == ECk_IskmProxy_PoseSource::Ragdoll);
    }

    UFUNCTION()
    private void Step_AssertNotSettledWhileAwake(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(utils_iskm_proxy::Get_IsRagdolling(_Proxy),
            "Ragdoll reported as not ragdolling immediately after it engaged");
        Assert_False(utils_iskm_proxy::Get_IsRagdollSettled(_Proxy),
            "Ragdoll reported settled while its bodies were still awake");
    }

    UFUNCTION()
    private void Check_Settled(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_iskm_proxy::Get_IsRagdollSettled(_Proxy));
    }
}

class ACk_AutoTest_IskmRenderer_RagdollSettles_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_IskmRenderer_RagdollSettles;
    default _TimeoutSeconds = 15.0f;
}
