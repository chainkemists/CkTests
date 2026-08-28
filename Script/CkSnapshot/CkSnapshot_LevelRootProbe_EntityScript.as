// Language=angelscript

// Minimal authored-root probe for the CkSnapshot level-root travel contracts.
// CkEntitySpawner owns its SaveKey and provenance; the entity script deliberately
// contributes no game-specific persistence behavior that could mask that contract.
class UCk_AutoTest_Snapshot_LevelRootProbe_EntityScript : UCk_GenericEntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;
}
