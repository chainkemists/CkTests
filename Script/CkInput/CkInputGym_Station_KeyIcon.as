// Language=angelscript

//============================================================================
// CK INPUT KEY-BINDING GYM — KEY ICON STATION
//
// Glyph resolution for every bound row, through Get_BrushForKey and
// Get_BrushForInputAction. Both are re-resolved on the display tick and NOTHING
// is stored: both read the live CommonUI device state at call time, so a cached
// FSlateBrush goes stale the moment the player switches keyboard <-> gamepad
// (CkInput/CLAUDE.md anti-pattern 4). Re-resolving every tick is strictly
// stronger than re-resolving on the device-change event and needs no listener.
//
// Get_ActiveControllerData is deliberately NOT called here. It ENSUREs when no
// controller data matches the current device — a legitimate miss, not an error —
// so a device-agnostic panel that polls it every tick would fire ensures at the
// viewer instead of showing them the glyph state.
//
// The station panel is procedural 3D text, not Slate, so the resolved brush is
// reported by its resource object rather than drawn. That is still enough for
// the hot-swap observation: the resource names change together when the active
// device changes, and read "<no glyph...>" when the device has no artwork for
// that key.
//
// This station never mutates the profile, so it has no teardown.
//============================================================================

class UCk_EntityScript_InputGym_KeyIcon : UCk_GenericEntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    UPROPERTY(ExposeOnSpawn)
    FString StationTitle;

    UPROPERTY(ExposeOnSpawn)
    FString StationDescription;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow
    DoConstruct(FCk_Handle& InHandle)
    {
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);
        utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"OnDisplayTick"));

        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    UFUNCTION()
    private void OnDisplayTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        auto PlayerController = input_gym::Get_LocalPlayerController();
        if (ck::Is_NOT_Valid(PlayerController))
        { return; }

        auto Display = input_gym::Format_AllGlyphRows(PlayerController);

        Display = f"{Display}\n===== Device hot-swap =====\n";
        Display = f"{Display}  Press a gamepad button, then a keyboard key.\n";
        Display = f"{Display}  Every resource name above should swap together on each change.\n";
        Display = f"{Display}  Rows read <no glyph...> when the active device has no artwork\n";
        Display = f"{Display}  for that key — an empty brush, not a failure.\n";

        CkGym_Common::Update_StationDisplay(
            ck::ToEntity(this), StationTitle, Display, StationDescription);
    }
}
