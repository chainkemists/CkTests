// Language=angelscript

//============================================================================
// CK ISKM RENDERER - VISUAL CAPTURE AUTOTEST (batched moving crowd)
//============================================================================
//
// Renders a moving batched crowd in front of the player view and takes TWO screenshots ~1.2s apart
// (HighResShot -> Saved/Screenshots/). The harness operator (human or agent) then inspects the PNGs:
//   1. instances are visible + mannequin-shaped (skinning not collapsed/exploded),
//   2. the two frames DIFFER (per-instance animation + movement actually render),
//   3. no missing/black tiles (bounds/culling sane from this vantage).
//
// The test itself passes on capture-sequence completion - image judgement is the operator's.
// Requires RHI (--no-nullrhi); under -nullrhi it still passes but writes no images.
//============================================================================

class UCk_AutoTest_IskmRenderer_BatchedVisual : UCk_AutoTest_Base
{
    private float _Elapsed = 0.0f;
    private bool _Shot1 = false;
    private bool _Shot2 = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Collection = iskm_assets::AnimCollection_Demo();
        if (ck::Is_NOT_Valid(Collection))
        {
            FinishFailure("iskm_assets::AnimCollection_Demo() invalid - registry may need regeneration.");
            return;
        }

        // HighResShot (below) rewrites these three behind our back and does not always put them
        // back; snapshot them so the base does.
        Snapshot_CVarForTest(n"r.ForceLOD");
        Snapshot_CVarForTest(n"r.SceneColorFormat");
        Snapshot_CVarForTest(n"r.PostProcessingColorFormat");

        // The barren AutoTests level has no lighting - capture in UNLIT so base color renders without lights.
        // `viewmode` is a console COMMAND, not a variable, so there is no prior value for
        // Set_CVarForTest to capture - this one has to be put back by hand (see OnTick). Leaving it
        // unlit would hand every later test in this lane a viewport that renders nothing correctly.
        System::ExecuteConsoleCommand("viewmode unlit");

        // Place the crowd in front of the current view AND aim the controller at it, so the captures frame it.
        auto SpawnXf = FTransform(FVector(1500.0f, 0.0f, 100.0f));
        auto Pawn = Gameplay::GetPlayerPawn(0);
        if (ck::IsValid(Pawn))
        {
            const auto Loc = Pawn.GetActorLocation() + Pawn.GetActorForwardVector() * 1500.0f;
            SpawnXf = FTransform(Loc);
        }

        auto PC = Gameplay::GetPlayerController(0);
        if (ck::IsValid(PC) && ck::IsValid(Pawn))
        {
            const auto ToCrowd = SpawnXf.GetTranslation() - Pawn.GetActorLocation();
            FRotator Aim = FRotator::ZeroRotator;
            Aim.Yaw = float(Math::Atan2(ToCrowd.Y, ToCrowd.X)) * (180.0f / float(Math::PI));
            Aim.Pitch = -5.0f;
            PC.SetControlRotation(Aim);
        }

        auto Params = FCkIskmBatchedGym_CrowdSpawnParams();
        Params.InitialTransform = SpawnXf;
        Params.Count = 36;
        Params.AreaExtent = 700.0f;
        Params.TileSize = 800.0f;
        utils_entity_script::Request_SpawnEntity(InHandle, UCk_EntityScript_IskmRendererBatched_MovingCrowd, FInstancedStruct::Make(Params));

        utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        _Elapsed += float(InDeltaT.Get_Seconds());

        if (!_Shot1 && _Elapsed > 2.0f)
        {
            _Shot1 = true;
            System::ExecuteConsoleCommand("HighResShot 1280x720");
        }

        if (!_Shot2 && _Elapsed > 3.2f)
        {
            _Shot2 = true;
            System::ExecuteConsoleCommand("HighResShot 1280x720");
        }

        if (_Elapsed > 4.5f)
        {
            System::ExecuteConsoleCommand("viewmode lit");
            FinishSuccess();
        }
    }
}

class ACk_AutoTest_IskmRenderer_BatchedVisual_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_IskmRenderer_BatchedVisual;
    default _TimeoutSeconds = 30.0f;
}
