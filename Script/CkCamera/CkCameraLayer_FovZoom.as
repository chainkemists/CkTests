// Language=angelscript

//============================================================================
// CK CAMERA - EXAMPLE LAYER: FOV ZOOM (multiplicative)
//============================================================================
//
// A field-level FOV multiplier layered on top of whatever mode layer is active. Acquires a Multiplicative FOV
// modifier whose target is ZoomFactor; the framework eases the effective multiplier from 1.0 -> ZoomFactor by this
// layer's blend alpha, so it blends in/out smoothly with the request's BlendIn/Out time and composes
// multiplicatively with the active mode's FOV (and any other FOV layers).
//============================================================================

class UCk_CameraLayer_FovZoom : UCk_CameraLayer_EntityScript
{
    // FOV multiplier at full blend: < 1 zooms in (narrower FOV), > 1 zooms out.
    UPROPERTY(EditAnywhere)
    float32 ZoomFactor = 0.66f;

    UFUNCTION(BlueprintOverride)
    void DoEnter(FCk_Handle_CameraLayer InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Handle = InHandle;
        Handle.Acquire_CameraModifier_FOV(ECk_AttributeModifier_Operation::Multiply, ZoomFactor);
    }
}
