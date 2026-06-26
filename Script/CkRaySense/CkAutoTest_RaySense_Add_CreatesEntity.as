// Language=angelscript

//============================================================================
// CK RAY SENSE — AUTOMATION TEST: ADD CREATES ENTITY
//============================================================================
//
// First-coverage seed for CkRaySense. Adding a RaySense feature with a
// default-constructed params struct must return a valid handle and
// Has(parent) reports true on the same frame.
//============================================================================

class UCk_AutoTest_RaySense_Add_CreatesEntity : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;
        auto Entity = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        utils_transform::Add(Entity, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        auto Params = FCk_Fragment_RaySense_ParamsData(
            ECk_RaySense_CollisionQuality::Sweep, ECollisionChannel::ECC_Visibility);
        auto RaySense = utils_ray_sense::Add(Entity, Params);

        Assert_True(ck::IsValid(RaySense),
            "utils_ray_sense::Add should return a valid FCk_Handle_RaySense");
        Assert_True(utils_ray_sense::Has(Entity),
            "After Add, Has on the owning entity should report true");

        FinishSuccess();
    }
}
