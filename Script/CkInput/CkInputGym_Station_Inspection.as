// Language=angelscript

//============================================================================
// CK INPUT KEY-BINDING GYM — BINDING INSPECTION STATION
//
// The read half of the key-binding surface, all four query entry points on one
// panel: Get_AllRemappableKeys for the raw profile, Get_KeyForMapping for the
// key each row holds, Get_MappingNamesForKey for who else holds it, and
// Get_MappableKeyInfoFromInputAction for the display name and category the
// Input Action authored.
//
// Everything is read on the display tick and nothing is stored, so a remap made
// from any source — this gym's exec commands, a settings widget, a reset —
// appears here without a manual refresh.
//
// An EMPTY profile is called out explicitly rather than rendering as a blank
// panel: an unregistered mapping context and a correctly-registered one with no
// mappable rows look identical from every query in this module.
//============================================================================

class UCk_EntityScript_InputGym_Inspection : UCk_GenericEntityScript_UE
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

        auto Display = input_gym::Format_ProfileRows(PlayerController);
        Display = f"{Display}\n===== Per-mapping view =====\n";
        Display = f"{Display}{input_gym::Format_AllMappingRows(PlayerController)}";

        CkGym_Common::Update_StationDisplay(
            ck::ToEntity(this), StationTitle, Display, StationDescription);
    }
}
