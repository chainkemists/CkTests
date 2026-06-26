// Language=angelscript

//============================================================================
// ENTITY SCRIPT SPAWN GYM - SPAWN PARAMS & TEST ENTITY SCRIPT
//============================================================================

USTRUCT()
struct FEntityScriptGym_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    UPROPERTY()
    FName TestName = n"";

    UPROPERTY()
    int32 TestInt = 0;

    UPROPERTY()
    float32 TestFloat = 0.0f;
}

//============================================================================
// TEST ENTITY SCRIPT
//============================================================================

class UCk_EntityScript_EntityScriptGym_Spawn : UCk_GenericEntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    UPROPERTY(ExposeOnSpawn)
    FName TestName = n"";

    UPROPERTY(ExposeOnSpawn)
    int32 TestInt = 0;

    UPROPERTY(ExposeOnSpawn)
    float32 TestFloat = 0.0f;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::Replicates);
        utils_entity_tag::Add(InHandle, n"TAG_EntityScriptGym_Spawn");

        auto SpawnParamsVerification = FEntityScriptGym_SpawnParams();
        SpawnParamsVerification.InitialTransform = InitialTransform;
        SpawnParamsVerification.TestName = TestName;
        SpawnParamsVerification.TestInt = TestInt;
        SpawnParamsVerification.TestFloat = TestFloat;

        InHandle.Add_Fragment(SpawnParamsVerification);

        return ECk_EntityScript_ConstructionFlow::Finished;
    }
}

//============================================================================
// TEST ENTITY SCRIPT (REPLICATED)
//============================================================================

class UCk_EntityScript_EntityScriptGym_SpawnReplicated : UCk_GenericEntityScript_UE
{
    default _Replication = ECk_Replication::Replicates;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    UPROPERTY(ExposeOnSpawn)
    FName TestName = n"";

    UPROPERTY(ExposeOnSpawn)
    int32 TestInt = 0;

    UPROPERTY(ExposeOnSpawn)
    float32 TestFloat = 0.0f;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::Replicates);
        utils_entity_tag::Add(InHandle, n"TAG_EntityScriptGym_SpawnReplicated");

        switch (utils_net::Get_EntityNetMode(InHandle))
        {
            case ECk_Net_NetModeType::Client:
                ck::Trace("Hello");
            break;
            default:
            break;
        }

        auto SpawnParamsVerification = FEntityScriptGym_SpawnParams();
        SpawnParamsVerification.InitialTransform = InitialTransform;
        SpawnParamsVerification.TestName = TestName;
        SpawnParamsVerification.TestInt = TestInt;
        SpawnParamsVerification.TestFloat = TestFloat;

        InHandle.Add_Fragment(SpawnParamsVerification);

        return ECk_EntityScript_ConstructionFlow::Finished;
    }
}
