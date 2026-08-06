// Language=angelscript

//============================================================================
// CK RENDER TARGET — AUTOMATION TEST: ADD AND QUERY
//============================================================================
//
// Smoke test for the RenderTarget feature shape. Adds a managed 64x64 target
// to the test entity and asserts:
//   - Add returns a valid typesafe handle
//   - Has_Any reports the record on the owner
//   - TryGet_RenderTarget resolves the same sync entity by sync name
//   - Get_SyncName round-trips the params tag
//   - After the Setup processor runs, Get_Target returns a live
//     UTextureRenderTarget2D with the requested dimensions (the UObject is
//     created even when the process cannot render, so this holds in CI)
//
// State polling: Setup runs in the Rendering processor group on the tick
// after Add (DoBeginPlay executes in the later Script group), so the test
// polls Get_Target each tick and finishes the moment it resolves. A target
// that never resolves is caught by the harness timeout.
//============================================================================

class UCk_AutoTest_RenderTarget_AddAndQuery : UCk_AutoTest_Base
{
    private FCk_Handle_RenderTarget _RenderTarget;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;
        auto SyncName = utils_gameplay_tag::ResolveGameplayTag(n"RenderTarget.AutoTest.AddAndQuery");

        auto Params = FCk_RenderTarget_Spec(SyncName);
        Params.Set_Size(FIntPoint(64, 64));
        Params.Set_Replication(ECk_Replication::DoesNotReplicate);

        _RenderTarget = utils_render_target::Add(LocalHandle, Params);

        Assert_True(ck::IsValid(_RenderTarget), "Add should return a valid RenderTarget handle");
        Assert_True(utils_render_target::Has_Any(LocalHandle), "Owner should report Has_Any after Add");

        auto Found = utils_render_target::TryGet_RenderTarget(LocalHandle, SyncName);
        Assert_True(ck::IsValid(Found), "TryGet_RenderTarget should resolve by sync name");
        Assert_True(Found == _RenderTarget, "TryGet_RenderTarget should resolve the SAME sync entity");

        Assert_True(_RenderTarget.Get_SyncName() == SyncName, "Get_SyncName should round-trip the params tag");

        utils_timer::Create_Tick(LocalHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto Target = _RenderTarget.Get_Target();
        if (ck::Is_NOT_Valid(Target)) { return; }

        Assert_Equals_Int(Target.SizeX, 64, "Managed target width should match params");
        Assert_Equals_Int(Target.SizeY, 64, "Managed target height should match params");

        FinishSuccess();
    }
}
