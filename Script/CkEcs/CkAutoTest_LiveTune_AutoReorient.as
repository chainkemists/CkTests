// Language=angelscript

//============================================================================
// CK LIVETUNE — AUTOMATION TEST: AUTOREORIENT (swept feature)
//============================================================================
//
// AutoReorient is registered with the DEFAULT re-apply: its Add stores the
// params fragment and nothing else — no derived state, no NeedsSetup tag —
// and FProcessor_AutoReorient_OrientTowardsVelocity reads that fragment every
// tick. So Replace<Params> is the entire re-apply and every field retunes.
//
// This is the per-feature bar for the sweep: prove the retune lands on the
// LIVE entity, not merely that a handler is registered.
//============================================================================

class UCk_AutoTest_LiveTune_AutoReorient : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 5.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Self = InHandle;
        auto Asset = UCk_LiveTuneTest_Utils::Create_TuningAsset(0, 0);

        auto Params = FCk_Fragment_AutoReorient_ParamsData(
            ECk_AutoReorient_Policy::NoAutoReorient);
        UCk_LiveTuneTest_Utils::Set_AutoReorientParams(Asset, Params);

        auto Entity = utils_entity_lifetime::Request_CreateEntity(Self);
        auto Reoriented = utils_auto_reorient::Add(Entity, Params);

        auto Linked = FCk_Handle(Reoriented);
        utils_live_tune::Link(Linked, Asset, n"_AutoReorientParams");

        Assert_True(UCk_LiveTuneTest_Utils::Get_AutoReorientPolicy(Linked)
                == ECk_AutoReorient_Policy::NoAutoReorient,
            "the entity should start on the policy it was added with");

        auto Retuned = FCk_Fragment_AutoReorient_ParamsData(
            ECk_AutoReorient_Policy::OrientTowardsVelocity);
        UCk_LiveTuneTest_Utils::Set_AutoReorientParams(Asset, Retuned);
        UCk_LiveTuneTest_Utils::SimulatePropertyChange(Self, Asset, n"_AutoReorientParams");

        Assert_True(UCk_LiveTuneTest_Utils::Get_AutoReorientPolicy(Linked)
                == ECk_AutoReorient_Policy::OrientTowardsVelocity,
            "the retuned policy must land on the live entity's params fragment");

        FinishSuccess();
    }
}
