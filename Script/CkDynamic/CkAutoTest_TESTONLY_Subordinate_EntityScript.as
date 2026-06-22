// Language=angelscript

//============================================================================
// CK DYNAMIC — TEST-ONLY REPLICATED SUBORDINATE ENTITY SCRIPT (B)
//============================================================================
//
// Minimal REPLICATED entity script used by the StoreDriver-shaped dynamic-handle repro
// (CkAutoTest_Net_DynamicFragment_DriverCarrierReplicates). Mirrors a real subordinate
// like UBb_StoreCustomization_EntityScript: Replicates, composes a feature fragment in
// DoConstruct (which runs on BOTH worlds via the entity-script replication path) so that
// FCk_Handle_TESTONLY_Subordinate validates on the client.
//
// Spawned by the test UNDER the (actor-bridged) subject so it inherits an owning-actor
// chain — required for its handle to net-translate through the driver's replicated carrier
// (the production StoreDriver spawns subordinates under the driver for exactly this reason).
//============================================================================

class UBb_AutoTest_TESTONLY_Subordinate_EntityScript : UCk_GenericEntityScript_UE
{
    default _Replication = ECk_Replication::Replicates;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow
    DoConstruct(FCk_Handle& InHandle)
    {
        InHandle.Add_Fragment(FCk_Fragment_TESTONLY_SubordinateFeature());
        return ECk_EntityScript_ConstructionFlow::Finished;
    }
}
