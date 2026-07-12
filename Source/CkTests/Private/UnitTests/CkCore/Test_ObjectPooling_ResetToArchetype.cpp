// Unit tests for UCk_ObjectPooling_Subsystem_UE::Request_ResetToArchetype — the recycle reset
// contract: reflected properties return to archetype values, Instanced subobjects are re-instanced
// (owned copies, never aliases of the archetype's), participant binds survive, and unbinding one
// delegate removes only that bind. Pure object tests; no PIE / world required.
// Surface in Session Frontend: Ck.ObjectPooling.ResetToArchetype.<scenario>

#include "CkObjectPoolingReset_TestTypes.h"
#include "../CkUnitTest_Common.h"

#include "CkCore/ObjectPooling/CkObjectPooling_Subsystem.h"
#include "CkCore/ObjectPooling/CkObjectPoolingParticipant_Utils.h"

#include "Misc/AutomationTest.h"
#include "UObject/Package.h"

#if WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------

namespace ck_objectpooling_reset_tests
{
    struct FArchetypeAndInstance
    {
        UCk_PoolingResetTest_Host_UE* _Archetype = nullptr;
        UCk_PoolingResetTest_Host_UE* _Instance = nullptr;
    };

    inline auto
        MakeArchetypeAndInstance()
        -> FArchetypeAndInstance
    {
        auto* Archetype = NewObject<UCk_PoolingResetTest_Host_UE>(GetTransientPackage());
        Archetype->_Value = 7;
        Archetype->_SubConfig = NewObject<UCk_PoolingResetTest_SubConfig_UE>(Archetype);
        Archetype->_SubConfig->_Number = 11;

        auto* Instance = NewObject<UCk_PoolingResetTest_Host_UE>(
            GetTransientPackage(), UCk_PoolingResetTest_Host_UE::StaticClass(), NAME_None, RF_NoFlags, Archetype);

        return FArchetypeAndInstance{Archetype, Instance};
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkObjectPoolingReset_RestoresReflectedValues,
    "Ck.ObjectPooling.ResetToArchetype.RestoresReflectedValues",
    ck::tests::kCkUnitTestFlags)

bool FCkObjectPoolingReset_RestoresReflectedValues::RunTest(const FString& Parameters)
{
    const auto [Archetype, Instance] = ck_objectpooling_reset_tests::MakeArchetypeAndInstance();

    Instance->_Value = 42;

    UCk_ObjectPooling_Subsystem_UE::Request_ResetToArchetype(Instance, Archetype);

    TestEqual(TEXT("reflected value restored to the archetype's"), Instance->_Value, 7);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkObjectPoolingReset_InstancedSubobjectIsOwnedNotAliased,
    "Ck.ObjectPooling.ResetToArchetype.InstancedSubobjectIsOwnedNotAliased",
    ck::tests::kCkUnitTestFlags)

bool FCkObjectPoolingReset_InstancedSubobjectIsOwnedNotAliased::RunTest(const FString& Parameters)
{
    const auto [Archetype, Instance] = ck_objectpooling_reset_tests::MakeArchetypeAndInstance();

    // fresh-create semantics: NewObject-with-template already gives the instance its own subobject
    TestNotNull(TEXT("fresh instance has a subobject"), Instance->_SubConfig.Get());
    TestNotEqual(TEXT("fresh instance's subobject is its own copy"),
        Instance->_SubConfig.Get(), Archetype->_SubConfig.Get());

    // a recycled instance's prior life stomped its state
    Instance->_Value = 42;
    Instance->_SubConfig->_Number = 99;

    UCk_ObjectPooling_Subsystem_UE::Request_ResetToArchetype(Instance, Archetype);

    TestNotNull(TEXT("recycled instance still has a subobject"), Instance->_SubConfig.Get());
    TestNotEqual(TEXT("recycled instance must NOT alias the archetype's subobject — a write "
                      "through an alias would corrupt the archetype/CDO for every future instance"),
        Instance->_SubConfig.Get(), Archetype->_SubConfig.Get());
    TestEqual(TEXT("recycled subobject carries the archetype's values"),
        Instance->_SubConfig->_Number, 11);
    TestEqual(TEXT("recycled subobject is outered to the recycled instance (owned)"),
        Instance->_SubConfig->GetOuter(), static_cast<UObject*>(Instance));

    // the archetype must be untouched by the whole cycle
    TestEqual(TEXT("archetype value untouched"), Archetype->_Value, 7);
    TestEqual(TEXT("archetype subobject untouched"), Archetype->_SubConfig->_Number, 11);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkObjectPoolingReset_ParticipantBindsSurviveReset,
    "Ck.ObjectPooling.ResetToArchetype.ParticipantBindsSurviveReset",
    ck::tests::kCkUnitTestFlags)

bool FCkObjectPoolingReset_ParticipantBindsSurviveReset::RunTest(const FString& Parameters)
{
    const auto [Archetype, Instance] = ck_objectpooling_reset_tests::MakeArchetypeAndInstance();

    auto Delegate = FCk_Delegate_ObjectPoolingParticipant_OnAcquired{};
    Delegate.BindDynamic(Instance, &UCk_PoolingResetTest_Host_UE::OnAcquired_First);
    UCk_Utils_ObjectPoolingParticipant_UE::BindTo_OnAcquiredFromPool(Instance->_Participant, Delegate);

    // re-bind of the same (object, function) must be a no-op (Construct re-runs per acquire)
    UCk_Utils_ObjectPoolingParticipant_UE::BindTo_OnAcquiredFromPool(Instance->_Participant, Delegate);

    UCk_ObjectPooling_Subsystem_UE::Request_ResetToArchetype(Instance, Archetype);

    UCk_Utils_ObjectPoolingParticipant_UE::Broadcast_AcquiredFromPool_OnObject(Instance);

    TestEqual(TEXT("bind survived the reset AND idempotent re-bind did not double-fire"),
        Instance->_TimesFirstHandlerFired, 1);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkObjectPoolingReset_UnbindRemovesOnlyThatDelegate,
    "Ck.ObjectPooling.ResetToArchetype.UnbindRemovesOnlyThatDelegate",
    ck::tests::kCkUnitTestFlags)

bool FCkObjectPoolingReset_UnbindRemovesOnlyThatDelegate::RunTest(const FString& Parameters)
{
    const auto [Archetype, Instance] = ck_objectpooling_reset_tests::MakeArchetypeAndInstance();

    auto FirstDelegate = FCk_Delegate_ObjectPoolingParticipant_OnAcquired{};
    FirstDelegate.BindDynamic(Instance, &UCk_PoolingResetTest_Host_UE::OnAcquired_First);
    UCk_Utils_ObjectPoolingParticipant_UE::BindTo_OnAcquiredFromPool(Instance->_Participant, FirstDelegate);

    auto SecondDelegate = FCk_Delegate_ObjectPoolingParticipant_OnAcquired{};
    SecondDelegate.BindDynamic(Instance, &UCk_PoolingResetTest_Host_UE::OnAcquired_Second);
    UCk_Utils_ObjectPoolingParticipant_UE::BindTo_OnAcquiredFromPool(Instance->_Participant, SecondDelegate);

    UCk_Utils_ObjectPoolingParticipant_UE::UnbindFrom_OnAcquiredFromPool(Instance->_Participant, SecondDelegate);

    UCk_Utils_ObjectPoolingParticipant_UE::Broadcast_AcquiredFromPool_OnObject(Instance);

    TestEqual(TEXT("the delegate that stayed bound fires"), Instance->_TimesFirstHandlerFired, 1);
    TestEqual(TEXT("unbinding one delegate removes ONLY that bind, not every bind the object owns"),
        Instance->_TimesSecondHandlerFired, 0);

    return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS
