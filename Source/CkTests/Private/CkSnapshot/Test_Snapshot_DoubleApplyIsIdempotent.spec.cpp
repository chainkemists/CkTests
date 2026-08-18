// Applying a payload twice must leave the SAVED state, not a stacked one.
//
// A HydrationApply is retried every load-kernel tick until it answers Applied, so any handler that mutates before
// its last NotReady applies twice — and the framework has never asserted that this is harmless. The named suspect
// is the attribute family: ApplyReplicated*Entry's Add_Revocable creates a NEW modifier per call, so a second pass
// stacks a second replication modifier on top of the first (CkAttribute_RestorePersistence.h documents the hazard
// and the guard against it; nothing tested either).
//
// The oracle is family-agnostic: PRODUCE the payload, apply it twice, then produce again. A handler that stacks
// reports different state the second time, whatever "stacked" means for that feature — a doubled modifier, a
// duplicated tag, a re-added entry. No save, no load: the contract is about the handler pair, and a round trip
// would only add travel and flake to a question that does not need either.
// Surface in Session Frontend: Ck.Snapshot.Idempotency.DoubleApplyIsIdempotent

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/World.h"

#include "CkAttribute/CkAttribute_Fragment_Data.h"                        // ECk_Attribute_RefillState
#include "CkAttribute/FloatAttribute/CkFloatAttribute_Fragment.h"         // FCk_RepData_FloatAttributes
#include "CkAttribute/FloatAttribute/CkFloatAttribute_Fragment_Data.h"    // FCk_SaveData_FloatAttributeRefill
#include "CkAttribute/FloatAttribute/CkFloatAttribute_Utils.h"

#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/Persistence/CkPersistenceHandlerRegistry.h"
#include "CkEcs/Subsystem/CkEcsWorld_Subsystem.h"

#include "CkEntityTag/CkEntityTag_Fragment_Data.h" // FCk_SaveData_EntityTags
#include "CkEntityTag/CkEntityTag_Utils.h"

#include "CkTagSet/CkTagSet_Fragment.h" // FCk_RepData_TagSet
#include "CkTagSet/CkTagSet_Utils.h"

#include "CkTests/Net/CkNetAutomation_Common.h"
#include "CkTests/Snapshot/CkSnapshot_TestHarness_Common.h"

#include "GameplayTagContainer.h"

namespace ck_test_double_apply
{
    // Tags already registered for the attribute autotests — reusing them keeps this test free of a tag-registration
    // commit, and nothing here depends on their meaning.
    constexpr auto AttributeTagName = TEXT("FloatAttribute.Health");
    constexpr auto RefillTagName    = TEXT("FloatAttribute.Energy");

    constexpr auto AttributeInitial = 42.5f;
    constexpr auto AttributeMin     = 0.0f;
    constexpr auto AttributeMax     = 100.0f;
    constexpr auto RefillFillRate   = 5.0f;

    auto Pump(UWorld* InWorld) -> void
    {
        auto* EcsWorld = InWorld != nullptr ? InWorld->GetSubsystem<UCk_EcsWorld_Subsystem_UE>() : nullptr;
        if (ck::Is_NOT_Valid(EcsWorld))
        { return; }

        // The applies drive DEFERRED requests (Request_Override, Request_ClearAllModifiers), so the state under
        // test does not exist until the queues drain.
        EcsWorld->Request_PumpToQuiescence(ck::ECk_SchedulerTickScope::Full);
    }

    auto Describe_Payload(const FInstancedStruct& InPayload) -> FString
    {
        if (ck::Is_NOT_Valid(InPayload.GetScriptStruct()))
        { return FString{TEXT("<invalid>")}; }

        auto Out = FString{};
        InPayload.GetScriptStruct()->ExportText(Out, InPayload.GetMemory(), nullptr, nullptr, PPF_None, nullptr);
        return Out;
    }

    // Produce -> apply twice -> produce. The two descriptions must match: the second produce reads whatever the
    // second apply left behind.
    auto Check_DoubleApply(
        FAutomationTestBase& InTest,
        UWorld* InWorld,
        const TCHAR* InFamilyName,
        const UScriptStruct* InPayloadType,
        FCk_Handle InSubject) -> bool
    {
        const auto* Handler = FCk_PersistenceHandlerRegistry::Resolve(InPayloadType);

        auto AllGood = InTest.TestTrue(
            FString::Printf(TEXT("[%s] the family has a registered handler"), InFamilyName),
            Handler != nullptr && static_cast<bool>(Handler->Produce) && static_cast<bool>(Handler->HydrationApply));

        if (NOT AllGood)
        { return false; }

        auto Subject = InSubject;
        const auto Produced = Handler->Produce(Subject);

        // If this fails the test is asking the wrong entity, and it says so instead of passing on an empty payload.
        AllGood &= InTest.TestTrue(
            FString::Printf(TEXT("[%s] the subject produces a payload"), InFamilyName), Produced.IsSet());

        if (NOT Produced.IsSet())
        { return false; }

        const auto Before = Describe_Payload(Produced.GetValue());

        const auto FirstApply = Handler->HydrationApply(Subject, Produced.GetValue(), {});
        Pump(InWorld);
        const auto SecondApply = Handler->HydrationApply(Subject, Produced.GetValue(), {});
        Pump(InWorld);

        AllGood &= InTest.TestTrue(
            FString::Printf(TEXT("[%s] both applies reported Applied (first=%d, second=%d)"),
                InFamilyName, static_cast<int32>(FirstApply), static_cast<int32>(SecondApply)),
            FirstApply == ECk_Persistence_ApplyResult::Applied &&
            SecondApply == ECk_Persistence_ApplyResult::Applied);

        const auto ReProduced = Handler->Produce(Subject);
        AllGood &= InTest.TestTrue(
            FString::Printf(TEXT("[%s] the subject still produces a payload after two applies"), InFamilyName),
            ReProduced.IsSet());

        if (NOT ReProduced.IsSet())
        { return false; }

        const auto After = Describe_Payload(ReProduced.GetValue());

        AllGood &= InTest.TestTrue(
            FString::Printf(TEXT("[%s] applying the SAME payload twice leaves the saved state, not a stacked one\n")
                            TEXT("  before: %s\n  after : %s"), InFamilyName, *Before, *After),
            Before == After);

        return AllGood;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_DoubleApplyIsIdempotent_Gate,
    "Ck.Snapshot.Idempotency.DoubleApplyIsIdempotent",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::ProductFilter)

bool FCk_Snapshot_DoubleApplyIsIdempotent_Gate::RunTest(const FString& /*Parameters*/)
{
    using namespace ck_test_double_apply;

    constexpr auto NumClients = 1;
    constexpr auto ReadyTimeoutSeconds = 30.0f;
    constexpr auto SettleFrames = 10;

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(NumClients, TEXT("/Engine/Maps/Entry")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(NumClients, ReadyTimeoutSeconds));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(SettleFrames));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            auto* Server = ck::auto_test::snapshot::Get_PostTravelServerWorld();
            if (NOT TestTrue(TEXT("world resolves"), Server != nullptr))
            { return true; }

            auto Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity_TransientOwner(Server);
            if (NOT TestTrue(TEXT("probe entity created"), ck::IsValid(Owner)))
            { return true; }

            // ---- Compose one probe per family, each in a non-default state so a stacked apply has something
            //      to move ------------------------------------------------------------------------------------
            const auto AttributeTag = FGameplayTag::RequestGameplayTag(FName{AttributeTagName});
            const auto RefillTag    = FGameplayTag::RequestGameplayTag(FName{RefillTagName});

            auto RefillParams = FCk_Fragment_FloatAttributeRefill_ParamsData{RefillTag, RefillFillRate};
            RefillParams.Set_StartingState(ECk_Attribute_RefillState::Paused);

            auto AttributeParams = FCk_Fragment_FloatAttribute_ParamsData{AttributeTag, AttributeInitial};
            AttributeParams.Set_MinMax(ECk_MinMax::MinMax);
            AttributeParams.Set_MinValue(AttributeMin);
            AttributeParams.Set_MaxValue(AttributeMax);
            AttributeParams.Set_EnableRefill(true);
            AttributeParams.Set_RefillParams(RefillParams);

            UCk_Utils_FloatAttribute_UE::Add(Owner, AttributeParams, ECk_Replication::DoesNotReplicate);

            auto Tags = FGameplayTagContainer{};
            Tags.AddTag(AttributeTag);
            auto TagSet = UCk_Utils_TagSet_UE::Add(Owner, Tags, ECk_Replication::DoesNotReplicate);

            UCk_Utils_EntityTag_UE::Add(Owner, FName{TEXT("CkTests.DoubleApplyProbe")});

            Pump(Server);

            auto AllGood = TestTrue(TEXT("the TagSet composed"), ck::IsValid(TagSet));

            // The attribute payload is produced on the ATTRIBUTE entity, not its owner — the family's Current
            // fragment lives on the child.
            auto AttributeEntity = UCk_Utils_FloatAttribute_UE::TryGet(Owner, AttributeTag);
            AllGood &= TestTrue(TEXT("the float attribute composed"), ck::IsValid(AttributeEntity));

            if (ck::IsValid(AttributeEntity))
            {
                AllGood &= Check_DoubleApply(*this, Server, TEXT("FloatAttribute"),
                    FCk_RepData_FloatAttributes::StaticStruct(), AttributeEntity.ConvertToHandle());

                auto RefillEntity = UCk_Utils_FloatAttribute_UE::TryGet_RefillAttribute(AttributeEntity);
                AllGood &= TestTrue(TEXT("the refill attribute composed"), ck::IsValid(RefillEntity));

                if (ck::IsValid(RefillEntity))
                {
                    AllGood &= Check_DoubleApply(*this, Server, TEXT("FloatAttributeRefill"),
                        FCk_SaveData_FloatAttributeRefill::StaticStruct(), RefillEntity.ConvertToHandle());
                }
            }

            if (ck::IsValid(TagSet))
            {
                AllGood &= Check_DoubleApply(*this, Server, TEXT("TagSet"),
                    FCk_RepData_TagSet::StaticStruct(), TagSet.ConvertToHandle());
            }

            AllGood &= Check_DoubleApply(*this, Server, TEXT("EntityTag"),
                FCk_SaveData_EntityTags::StaticStruct(), Owner);

            return AllGood;
        }),
        TEXT("double-apply idempotency per Durable handler family")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
    return true;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------
