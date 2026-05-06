// Regression tests for Get_IsTransientEntity / transient-identity recognition.
//
// Pre-fix (Phase-3 hotfix 0985193e9), Get_IsTransientEntity required the
// transient handle to carry a TWeakObjectPtr<UWorld> fragment as a fast-path
// filter. That fragment is only added in OnWorldBeginPlay; entities created
// in the Initialize→OnWorldBeginPlay window with the transient as the lifetime
// owner had Get_IsTransientEntity(transient) return false, fell through the
// else-if branch in Request_SetupEntityWithLifetimeOwner, and ended up
// without a ContextOwner — which downstream paths (e.g. CkProbe's overlap
// resolution) rely on.
//
// Post-#6 (transient stored in registry ctx) the workaround was unnecessary
// and was removed. These tests guard the property: the transient is
// registry-defined, recognizable from any handle bound to the registry,
// regardless of fragments on that handle.
//
// Surface in Session Frontend: Ck.Registry.TransientIdentity.<scenario>

#include "Misc/AutomationTest.h"

#include "CkEcs/ContextOwner/CkContextOwner_Utils.h"
#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/Registry/CkRegistry.h"
#include "CkEcs/World/CkEcsWorld.h"

#if WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkRegistry_TransientIdentity_RecognizedWithoutWorldFragment,
    "Ck.Registry.TransientIdentity.RecognizedWithoutWorldFragment",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FCkRegistry_TransientIdentity_RecognizedWithoutWorldFragment::RunTest(const FString& Parameters)
{
    // FEcsWorld sets up registry + transient + ctx but never adds a
    // TWeakObjectPtr<UWorld> fragment to the transient. Pre-fix, this
    // exact configuration would have made Get_IsTransientEntity return
    // false on the actual transient. Post-fix, the comparison reads
    // through registry ctx and works without any fragment dependency.
    auto EcsWorld = ck::FEcsWorld{};
    auto& Reg = EcsWorld.Get_Registry();

    const auto TransientHandle = FCk_Handle{Reg.Get_TransientEntity(), Reg.Get_RegistryHandle()};

    TestTrue(TEXT("transient does NOT have a World fragment (precondition)"),
        NOT TransientHandle.Has<TWeakObjectPtr<UWorld>>());

    TestTrue(TEXT("Get_IsTransientEntity recognizes the FEcsWorld transient"),
        UCk_Utils_EntityLifetime_UE::Get_IsTransientEntity(TransientHandle));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkRegistry_TransientIdentity_ChildOfTransientGetsContextOwner,
    "Ck.Registry.TransientIdentity.ChildOfTransientGetsContextOwner",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FCkRegistry_TransientIdentity_ChildOfTransientGetsContextOwner::RunTest(const FString& Parameters)
{
    // Higher-level integration test: spawning a child entity with the
    // transient as the lifetime owner must give the child a ContextOwner
    // (set to itself, via the else-if-transient branch in
    // Request_SetupEntityWithLifetimeOwner). Pre-fix, this branch never
    // fired because Get_IsTransientEntity returned false without the
    // World-fragment fast-path satisfied — so the child silently ended
    // up with no ContextOwner, and any downstream code that read
    // ContextOwner on a descendant of the chain fired ensure on the
    // resulting missing-fragment access.
    auto EcsWorld = ck::FEcsWorld{};
    auto& Reg = EcsWorld.Get_Registry();

    auto TransientHandle = FCk_Handle{Reg.Get_TransientEntity(), Reg.Get_RegistryHandle()};

    auto Child = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(TransientHandle, {});

    TestTrue(TEXT("child of transient has a ContextOwner fragment"),
        UCk_Utils_ContextOwner_UE::Has(Child));

    if (UCk_Utils_ContextOwner_UE::Has(Child))
    {
        const auto ChildContextOwner = UCk_Utils_ContextOwner_UE::Get_ContextOwner(Child);
        TestTrue(TEXT("child of transient is its own ContextOwner (self-context)"),
            ChildContextOwner == Child);
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkRegistry_TransientIdentity_NonTransientHandleNotMisidentified,
    "Ck.Registry.TransientIdentity.NonTransientHandleNotMisidentified",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FCkRegistry_TransientIdentity_NonTransientHandleNotMisidentified::RunTest(const FString& Parameters)
{
    // Negative test: a non-transient handle bound to the same registry must
    // NOT be reported as the transient. Guards against an over-permissive
    // implementation where the registry-defined comparison degenerates to
    // "any handle in this registry == transient".
    auto EcsWorld = ck::FEcsWorld{};
    auto& Reg = EcsWorld.Get_Registry();

    auto TransientHandle = FCk_Handle{Reg.Get_TransientEntity(), Reg.Get_RegistryHandle()};
    auto Child = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(TransientHandle, {});

    TestTrue(TEXT("transient is recognized"),
        UCk_Utils_EntityLifetime_UE::Get_IsTransientEntity(TransientHandle));

    TestFalse(TEXT("non-transient child is NOT identified as transient"),
        UCk_Utils_EntityLifetime_UE::Get_IsTransientEntity(Child));

    return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS
