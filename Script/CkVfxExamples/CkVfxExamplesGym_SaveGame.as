// Language=angelscript

//============================================================================
// CK VFX EXAMPLES GYM - PAIR SELECTION, REMEMBERED ACROSS PIE SESSIONS
//============================================================================
//
// Judging one port takes many PIE sessions, and re-walking the V selector to
// the pair you were on is the whole cost of restarting. The active pair index
// rides a UE SaveGame slot (Saved/SaveGames), which outlives a PIE session,
// so a new session opens on the pair the last one left selected.
//
// The slot also remembers how long each pair's LAST setup took. The first
// activation of a pair in a session can block the game thread for minutes with
// nothing drawn; a measured duration from a previous session is the only way to
// warn about that BEFORE the block starts (see the PlayerController's banner).
//
// Live tuning is deliberately session-scoped: it is a look-at-this-knob tool,
// and a tuned pedestal silently restored a week later would read as a fidelity
// gap in the recreation.
//
//============================================================================

class UCk_VfxExamplesGym_SaveGame : USaveGame
{
    UPROPERTY()
    int32 ActivePairIndex = 0;

    // Pair index -> wall-seconds the last measured setup of that pair took. Keyed by index rather
    // than by name because the index is what every other part of the harness already speaks; a pair
    // removed from the roster leaves a stale entry, which is harmless (nothing reads an index the
    // roster no longer has).
    UPROPERTY()
    TMap<int32, float32> PairSetupSeconds;
}

namespace CkVfxExamplesGym_Save
{
    FString Get_SlotName()
    {
        return "CkVfxExamplesGym";
    }

    int32 Get_UserIndex()
    {
        return 0;
    }

    // One slot now carries TWO independent fields, so every write starts from what is already on
    // disk: a fresh CreateSaveGameObject is BLANK, and writing one field through it would silently
    // erase the other. Returns a blank object only when no slot exists yet (the first-run state).
    UCk_VfxExamplesGym_SaveGame TryLoad_OrCreate_Save()
    {
        auto Existing = Cast<UCk_VfxExamplesGym_SaveGame>(
            Gameplay::LoadGameFromSlot(Get_SlotName(), Get_UserIndex()));

        if (ck::IsValid(Existing))
        { return Existing; }

        return Gameplay::CreateSaveGameObject(UCk_VfxExamplesGym_SaveGame);
    }

    void Request_SaveActivePairIndex(int32 InPairIndex)
    {
        auto Save = TryLoad_OrCreate_Save();
        if (ck::Is_NOT_Valid(Save))
        { return; }

        Save.ActivePairIndex = InPairIndex;
        Gameplay::SaveGameToSlot(Save, Get_SlotName(), Get_UserIndex());
    }

    // Zero means "never measured" - an absent slot, an absent entry, and a genuinely instant setup
    // are all the same answer to the only question the caller asks (is a freeze worth announcing?).
    float32 TryGet_PairSetupSeconds(int32 InPairIndex)
    {
        auto Save = Cast<UCk_VfxExamplesGym_SaveGame>(
            Gameplay::LoadGameFromSlot(Get_SlotName(), Get_UserIndex()));

        if (ck::Is_NOT_Valid(Save))
        { return 0.0f; }

        auto Seconds = 0.0f;
        if (Save.PairSetupSeconds.Find(InPairIndex, Seconds) == false)
        { return 0.0f; }

        return Seconds;
    }

    // Overwrites rather than accumulates: the LAST measurement is the honest predictor. A pair that
    // froze once because its template was cold does not freeze again once the process is warm, and a
    // banner that kept promising the cold number would be crying wolf every session after the first.
    void Request_SavePairSetupSeconds(int32 InPairIndex, float32 InSeconds)
    {
        auto Save = TryLoad_OrCreate_Save();
        if (ck::Is_NOT_Valid(Save))
        { return; }

        Save.PairSetupSeconds.Add(InPairIndex, InSeconds);
        Gameplay::SaveGameToSlot(Save, Get_SlotName(), Get_UserIndex());
    }

    // Returns InFallbackIndex when no slot exists - an absent save is the expected
    // first-run state, not a defect, so this branch stays silent at Warning/Error
    // level. A slot written by an earlier session is CLAMPED into the current
    // roster: pairs can be removed between sessions and a stale index would
    // otherwise spawn no stations at all.
    int32 TryLoad_ActivePairIndex(int32 InFallbackIndex)
    {
        auto Save = Cast<UCk_VfxExamplesGym_SaveGame>(
            Gameplay::LoadGameFromSlot(Get_SlotName(), Get_UserIndex()));

        if (ck::Is_NOT_Valid(Save))
        { return InFallbackIndex; }

        auto Pairs = CkVfxExamples::Get_Pairs();
        if (Pairs.Num() == 0)
        { return InFallbackIndex; }

        auto Index = Save.ActivePairIndex;
        if (Index < 0)             { Index = 0; }
        if (Index >= Pairs.Num())  { Index = Pairs.Num() - 1; }

        return Index;
    }
}
