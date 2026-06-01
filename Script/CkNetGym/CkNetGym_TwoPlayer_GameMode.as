// Language=angelscript

//============================================================================
// TWO-PLAYER NET GYM — GAME MODE
//============================================================================

class ACk_NetGym_TwoPlayer_GameMode : ACkTests_Gym_Base_GameMode
{
    default PlayerControllerClass = ACk_NetGym_TwoPlayer_PlayerController;
    default DefaultPawnClass = ACk_NetGym_TwoPlayer_Pawn;

    UFUNCTION(BlueprintOverride)
    void BeginPlay()
    {
        // Runs gym registration + startup resolve. GameModes exist only on the server.
        Super::BeginPlay();

        // Spawn the server-only cadence director (transient entity, tagged so it can be found
        // from anywhere). It drives the interleaved auto state + damage cadence for both pawns.
        utils_entity_script::Request_SpawnEntity(
            ck::TransientEntity(),
            UCk_NetGym_TwoPlayer_Director,
            FInstancedStruct());
    }
}
