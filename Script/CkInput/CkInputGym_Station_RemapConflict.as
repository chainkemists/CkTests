// Language=angelscript

//============================================================================
// CK INPUT KEY-BINDING GYM — REMAP + CONFLICT STATION
//
// Display half of RemapKey / RemapKeys / Get_HasKeyConflicts / SwapKeys /
// UnbindConflictAndRemap. The calls themselves live on the gym
// PlayerController — a key profile is per-local-player, not per-station — and
// this panel renders the current rows plus the report the last command left.
//
// The live preview at the bottom is Get_HasKeyConflicts run against the key
// Crouch currently holds, under BOTH scopes, WITHOUT mutating anything. That
// pair is the point of the authored categories: Jump and Crouch are both
// Movement, so they collide under either scope, while Jump and Interact are
// Movement vs Interaction and collide only under All.
//
// TEARDOWN. This station can leave the profile customized, so DoEndPlay resets
// and re-saves unless the viewer suspended teardown on the PlayerController.
//============================================================================

class UCk_EntityScript_InputGym_RemapConflict : UCk_GenericEntityScript_UE
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

    UFUNCTION(BlueprintOverride)
    void DoEndPlay(FCk_Handle InHandle)
    {
        input_gym_pc::Request_TeardownIfArmed();
    }

    UFUNCTION()
    private void OnDisplayTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        auto PlayerController = input_gym::Get_LocalPlayerController();
        if (ck::Is_NOT_Valid(PlayerController))
        { return; }

        auto Display = input_gym::Format_AllMappingRows(PlayerController);

        Display = f"{Display}\n===== Last command =====\n";
        Display = f"{Display}{input_gym_pc::Get_LastActionReport()}\n";

        Display = f"{Display}\n===== Live conflict preview (no mutation) =====\n";
        auto CrouchKey = utils_key_binding::Get_KeyForMapping(
            PlayerController, input_gym::k_Mapping_Crouch, EPlayerMappableKeySlot::First);

        if (CrouchKey.IsValid())
        {
            Display = f"{Display}{input_gym::Format_ConflictReport(PlayerController, input_gym::k_Mapping_Jump, CrouchKey)}";
        }
        else
        {
            Display = f"{Display}  Crouch is unbound — nothing to preview a collision against.\n";
        }

        CkGym_Common::Update_StationDisplay(
            ck::ToEntity(this), StationTitle, Display, StationDescription);
    }
}
