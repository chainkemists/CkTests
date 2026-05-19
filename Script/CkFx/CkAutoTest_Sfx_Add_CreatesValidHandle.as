// Language=angelscript

//============================================================================
// CK FX — AUTOMATION TEST: Sfx Add creates valid handle
//============================================================================
//
// First-coverage seed for CkFx Sfx. Pins the simplest Add contract:
//
//   utils_sfx::Add(OwnerEntity, ParamsData) returns a valid
//   FCk_Handle_Sfx and the child entity carries the Sfx fragment.
//
// The Sfx Setup processor reads _SoundCue when it spawns the AudioComponent
// on the next tick. For this Add-only contract test we leave _SoundCue
// nullptr — the Add path itself doesn't validate the cue (only the name is
// used at Add time for the GameplayLabel). We exit the test before the
// next-tick Setup runs.
//============================================================================

class UCk_AutoTest_Sfx_Add_CreatesValidHandle : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 2.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto OwnerHandle = InHandle;

        auto Params = FCk_Fragment_Sfx_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Sfx.Add_Seed"),
            nullptr);

        auto SfxHandle = utils_sfx::Add(OwnerHandle, Params);

        Assert_True(ck::IsValid(SfxHandle),
            "utils_sfx::Add should return a valid FCk_Handle_Sfx");

        // utils_sfx::Has is C++-only (not UFUNCTION-exposed for AS); only
        // utils_sfx::Has_Any (record-of-Sfx on the owner) is reachable from
        // AS. After Add the owner should own a Record of Sfx children.
        Assert_True(utils_sfx::Has_Any(OwnerHandle),
            "After Add, Has_Any on the owner should report true");

        FinishSuccess();
    }
}
