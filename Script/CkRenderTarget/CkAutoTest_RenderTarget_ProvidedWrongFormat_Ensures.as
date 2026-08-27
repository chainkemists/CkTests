// Language=angelscript

//============================================================================
// CK RENDER TARGET - AUTOMATION TEST: PROVIDED TARGET WITH WRONG FORMAT ENSURES
//============================================================================
//
// v1 is RGBA8-only: the Setup processor must trip a diagnostic
// ensure when a UseProvided target arrives with any other pixel format, and
// the feature stays inert (no drawable target is pinned).
//
// The ensure is diagnostic-only (it does not halt), so the test reaches the
// end normally; the hand-authored wrapper registers the expected log
// substring so the automation framework does not auto-fail on the
// deliberate diagnostic.
//
// (This replaces the originally-planned _DisallowedClientDraw_Ensures test,
// which cannot trip in a standalone world - every machine is
// self-authoritative there. Client-authoring rejection is covered by the
// client-authoring NET specs instead.)
//============================================================================

class UCk_AutoTest_RenderTarget_ProvidedWrongFormat_Ensures : UCk_AutoTest_Base
{
    private FCk_Handle_RenderTarget _RenderTarget;
    private int32 _TicksWaited = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;
        auto SyncName = utils_gameplay_tag::ResolveGameplayTag(n"RenderTarget.AutoTest.WrongFormat");

        auto WrongFormatTarget = Rendering::CreateRenderTarget2D(
            64, 64, ETextureRenderTargetFormat::RTF_RGBA16f);
        Assert_True(ck::IsValid(WrongFormatTarget), "Test fixture RGBA16f target should create");

        auto Params = FCk_Fragment_RenderTarget_ParamsData(SyncName);
        Params.Set_TargetMode(ECk_RenderTarget_TargetMode::UseProvided);
        Params.Set_ProvidedTarget(WrongFormatTarget);
        Params.Set_Replication(ECk_Replication::DoesNotReplicate);

        _RenderTarget = utils_render_target::Add(LocalHandle, Params);
        Assert_True(ck::IsValid(_RenderTarget), "Add itself should succeed - the format gate is Setup's");

        utils_timer::Create_Tick(LocalHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        // Give Setup a few ticks to run and trip the ensure, then assert the feature stayed
        // inert - the wrong-format target must never be pinned as drawable.
        _TicksWaited++;
        if (_TicksWaited < 5) { return; }

        Assert_True(ck::Is_NOT_Valid(_RenderTarget.Get_Target()),
            "A wrong-format provided target must NOT be pinned as the drawable target");

        FinishSuccess();
    }
}

//============================================================================
// HAND-AUTHORED WRAPPER ACTOR - registers the deliberate-ensure log pattern.
//============================================================================

class ACk_AutoTest_RenderTarget_ProvidedWrongFormat_Ensures_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_RenderTarget_ProvidedWrongFormat_Ensures;

    UFUNCTION(BlueprintOverride)
    TArray<FString> Get_ExpectedLogErrors() const
    {
        TArray<FString> Out;
        Out.Add("Only RTF_RGBA8 is supported in v1");
        return Out;
    }
}
