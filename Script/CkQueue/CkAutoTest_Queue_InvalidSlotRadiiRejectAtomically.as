// Language=angelscript

class UCk_AutoTest_Queue_InvalidSlotRadiiRejectAtomically : UCk_AutoTest_Base
{
    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Owner = utils_entity_lifetime::Request_CreateEntity(InHandle);
        utils_transform::Add(Owner, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        auto Origins = TArray<FCk_Queue_Origin>();
        Origins.Add(FCk_Queue_Origin(FTransform::Identity));
        auto Params = FCk_Fragment_Queue_ParamsData(Origins);
        Params.Set_SlotClaimRadiusUu(20.0f);
        Params.Set_SlotSettleRadiusUu(40.0f);
        Params.Set_SlotReacquireRadiusUu(30.0f);

        const auto Queue = utils_queue::Add(Owner, Params);
        Assert_True(ck::Is_NOT_Valid(Queue),
            "invalid queue movement radii reject queue composition");
        Assert_True(utils_queue::Has_Any(Owner) == false,
            "invalid queue movement radii leave no partially composed Queue on the owner");

        auto NonFiniteOwner = utils_entity_lifetime::Request_CreateEntity(InHandle);
        utils_transform::Add(NonFiniteOwner, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        float32 Infinity = 3.4e38f;
        Infinity *= 2.0f;

        auto NonFiniteParams = FCk_Fragment_Queue_ParamsData(Origins);
        NonFiniteParams.Set_SlotClaimRadiusUu(Infinity);
        NonFiniteParams.Set_SlotSettleRadiusUu(10.0f);
        NonFiniteParams.Set_SlotReacquireRadiusUu(20.0f);

        const auto NonFiniteQueue = utils_queue::Add(NonFiniteOwner, NonFiniteParams);
        Assert_True(ck::Is_NOT_Valid(NonFiniteQueue),
            "non-finite queue movement radii reject queue composition");
        Assert_True(utils_queue::Has_Any(NonFiniteOwner) == false,
            "non-finite queue movement radii leave no partially composed Queue on the owner");
        FinishSuccess();
    }
}

class ACk_AutoTest_Queue_InvalidSlotRadiiRejectAtomically_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Queue_InvalidSlotRadiiRejectAtomically;

    UFUNCTION(BlueprintOverride)
    TArray<FString> Get_ExpectedLogErrors() const
    {
        TArray<FString> Out;
        Out.Add("parameters are invalid");
        return Out;
    }
}
