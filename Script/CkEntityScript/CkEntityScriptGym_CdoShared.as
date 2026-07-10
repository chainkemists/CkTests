// Language=angelscript

//============================================================================
// ENTITY SCRIPT CDO-SHARED (NotInstanced) — SUPPORT SCRIPT FOR AUTOTESTS
//============================================================================
//
// A NotInstanced entity script shares ONE object (the class CDO) across every
// spawned entity, so it must be stateless: per-entity data arrives via
// DoGet_SpawnParams() (reads the entity's fragment) and per-callback identity
// via DoGet_ScriptEntity() (re-stamped by the lifecycle processors before each
// deferred callback). Member injection of ExposeOnSpawn properties is
// intentionally SKIPPED for CDO-shared scripts.
//
// DoBeginPlay records what the shared script observed into a verification
// fragment on the entity; the AutoTests assert those observations per entity.
//============================================================================

USTRUCT()
struct FCdoSharedGym_SpawnParams
{
    UPROPERTY()
    int32 PayloadInt = 0;

    UPROPERTY()
    FName PayloadName = n"";
}

USTRUCT()
struct FCdoSharedGym_Observed
{
    UPROPERTY()
    FCk_Handle ObservedScriptEntity;

    UPROPERTY()
    int32 ObservedInt = 0;

    UPROPERTY()
    FName ObservedName = n"";

    UPROPERTY()
    bool HadValidSpawnParams = false;
}

//============================================================================
// CDO-SHARED TEST ENTITY SCRIPT
//============================================================================

class UCk_EntityScript_CdoSharedGym : UCk_GenericEntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;
    default _InstancingPolicy = ECk_EntityScript_InstancingPolicy::NotInstanced;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        utils_entity_tag::Add(InHandle, n"TAG_CdoSharedGym_Spawned");
        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();

        // By-value handle params are read-only in AS — copy to a local for Add_Fragment.
        auto MyEntity = InHandle;

        auto Observed = FCdoSharedGym_Observed();
        Observed.ObservedScriptEntity = DoGet_ScriptEntity();

        auto ParamsInstanced = DoGet_SpawnParams();
        if (ParamsInstanced.IsValid())
        {
            auto Params = ParamsInstanced.Get(FCdoSharedGym_SpawnParams);
            Observed.HadValidSpawnParams = true;
            Observed.ObservedInt = Params.PayloadInt;
            Observed.ObservedName = Params.PayloadName;
        }

        MyEntity.Add_Fragment(Observed);
    }
}
