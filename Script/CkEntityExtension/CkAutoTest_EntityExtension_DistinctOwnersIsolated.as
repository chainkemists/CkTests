// Language=angelscript
//
// CK ENTITY EXTENSION — AUTOMATION TEST: distinct owners' extensions are isolated
// Two unrelated owners each get their own extension; ForEach on owner A does
// not surface owner B's extension and vice versa.

class UCk_AutoTest_EntityExtension_DistinctOwnersIsolated : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto OwnerA = utils_entity_lifetime::Request_CreateEntity(InHandle);
        auto OwnerB = utils_entity_lifetime::Request_CreateEntity(InHandle);

        auto ChildA = utils_entity_lifetime::Request_CreateEntity(InHandle);
        auto ChildB = utils_entity_lifetime::Request_CreateEntity(InHandle);

        auto ExtA = utils_entity_extension::Add(OwnerA, ChildA);
        auto ExtB = utils_entity_extension::Add(OwnerB, ChildB);

        auto AsOfA = utils_entity_extension::ForEach_EntityExtension(
            OwnerA, FInstancedStruct(), FCk_Lambda_InHandle());
        auto AsOfB = utils_entity_extension::ForEach_EntityExtension(
            OwnerB, FInstancedStruct(), FCk_Lambda_InHandle());

        Assert_Equals_Int(AsOfA.Num(), 1, "Owner A should report exactly 1 extension");
        Assert_Equals_Int(AsOfB.Num(), 1, "Owner B should report exactly 1 extension");

        Assert_True(utils_handle::IsEqual(AsOfA[0], ExtA),
            "Owner A's extension list should contain ExtA");
        Assert_True(utils_handle::IsEqual(AsOfB[0], ExtB),
            "Owner B's extension list should contain ExtB");

        FinishSuccess();
    }
}
