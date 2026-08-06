// Unit tests for FCk_LiveTuneHandlerRegistry (dispatch-by-type contract) and UCk_Utils_LiveTune_UE::Link
// invalid-input rejection (loud + zero partial state). Pure C++, standalone registry — the full
// asset-edit -> subsystem -> dispatch pipeline is covered by the LiveTune AS autotests, which need a
// PIE world. Surface in Session Frontend: CkTests.UnitTests.LiveTune.<scenario>

#include "CkLiveTune_AutoTest_Utils.h"

#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/LiveTune/CkLiveTune_Fragment.h"
#include "CkEcs/LiveTune/CkLiveTune_HandlerRegistry.h"
#include "CkEcs/LiveTune/CkLiveTune_HandlerRegistry.inl.h"
#include "CkEcs/LiveTune/CkLiveTune_Utils.h"
#include "CkEcs/Registry/CkRegistry.h"
#include "CkEcs/Registry/CkRegistry_SlotTable.h"

#include "../CkUnitTest_Common.h"

#include <Misc/AutomationTest.h>
#include <UObject/Package.h>

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------

namespace ck_tests_livetune_registry
{
    // The CkTests.UnitTests.* pretty-name family (not the greenfield Ck.<Feature>.*) on purpose:
    // these ARE gate tests, and the toolbox's default full pass runs "project tests" — rows whose
    // TOP path segment is a plugin name. Ck.-rooted C++ rows (Ck.Registry.*, Ck.DebugFeatureFlags.*)
    // are engine-classified and never ride a full pass.
    constexpr auto kFlags = ck::tests::kCkUnitTestFlags;

    struct FSpecState
    {
        int32 _BInvocations = 0;
        int32 _LastBValue = 0;
    };

    auto
        Get_SpecState()
        -> FSpecState&
    {
        static auto State = FSpecState{};
        return State;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkLiveTune_Registry_DispatchByType,
    "CkTests.UnitTests.LiveTune.Registry.DispatchByType",
    ck_tests_livetune_registry::kFlags)

bool FCkLiveTune_Registry_DispatchByType::RunTest(const FString& Parameters)
{
    using namespace ck_tests_livetune_registry;

    FCk_LiveTuneHandlerRegistry::Register<FCk_LiveTuneTest_SpecParamsA>({});
    FCk_LiveTuneHandlerRegistry::Register<FCk_LiveTuneTest_SpecParamsB>({
        .Apply = [](FCk_Handle& InEntity, const FCk_LiveTuneTest_SpecParamsB& InFreshParams) -> void
        {
            ++Get_SpecState()._BInvocations;
            Get_SpecState()._LastBValue = InFreshParams.Get_Value();
        },
    });

    auto Reg = ck::registry_table::EnttRegistryType{};
    const auto SlotHandle = ck::registry_table::Allocate(&Reg);
    const auto Registry = FCk_Registry{SlotHandle};

    auto EntityA = ck::MakeHandle(FCk_Entity{Reg.create()}, Registry);
    EntityA.Add<FCk_LiveTuneTest_SpecParamsA>(FCk_LiveTuneTest_SpecParamsA{1});

    auto EntityB = ck::MakeHandle(FCk_Entity{Reg.create()}, Registry);

    const auto* HandlerA = FCk_LiveTuneHandlerRegistry::Find(FCk_LiveTuneTest_SpecParamsA::StaticStruct());
    TestNotNull(TEXT("default-Apply handler is found by its params type"), HandlerA);
    if (HandlerA == nullptr)
    { return false; }

    TestTrue(TEXT("Direct kind recorded"), HandlerA->Kind == ECk_LiveTune_ApplyKind::Direct);
    TestTrue(TEXT("the default Replace path resolves Auto to DuringScrub"),
        HandlerA->ScrubPolicy == ECk_LiveTune_ScrubPolicy::DuringScrub);
    TestTrue(TEXT("the default Replace path synthesizes HasFragment"), static_cast<bool>(HandlerA->HasFragment));
    TestTrue(TEXT("HasFragment true on an entity carrying the params"), HandlerA->HasFragment(EntityA));
    TestFalse(TEXT("HasFragment false on an entity without the params"), HandlerA->HasFragment(EntityB));

    HandlerA->Apply(EntityA, FInstancedStruct::Make(FCk_LiveTuneTest_SpecParamsA{42}));
    TestEqual(TEXT("the default Apply replaced the fragment value"),
        EntityA.Get<FCk_LiveTuneTest_SpecParamsA>().Get_Value(), 42);

    const auto* HandlerB = FCk_LiveTuneHandlerRegistry::Find(FCk_LiveTuneTest_SpecParamsB::StaticStruct());
    TestNotNull(TEXT("custom-Apply handler is found by its params type"), HandlerB);
    if (HandlerB == nullptr)
    { return false; }

    TestTrue(TEXT("Direct kind recorded for a custom Apply too"), HandlerB->Kind == ECk_LiveTune_ApplyKind::Direct);
    TestTrue(TEXT("a custom Apply resolves Auto to OnCommit"),
        HandlerB->ScrubPolicy == ECk_LiveTune_ScrubPolicy::OnCommit);
    TestFalse(TEXT("a custom Apply does NOT synthesize HasFragment"), static_cast<bool>(HandlerB->HasFragment));

    const auto BInvocationsBefore = Get_SpecState()._BInvocations;
    HandlerB->Apply(EntityB, FInstancedStruct::Make(FCk_LiveTuneTest_SpecParamsB{7}));
    TestEqual(TEXT("ViaRequest Apply reached the registered lambda exactly once"),
        Get_SpecState()._BInvocations - BInvocationsBefore, 1);
    TestEqual(TEXT("ViaRequest Apply carried the fresh typed value"), Get_SpecState()._LastBValue, 7);
    TestEqual(TEXT("dispatching B never touches A's fragment"),
        EntityA.Get<FCk_LiveTuneTest_SpecParamsA>().Get_Value(), 42);

    TestNull(TEXT("an unregistered params type resolves to no handler"),
        FCk_LiveTuneHandlerRegistry::Find(FCk_LiveTuneTest_SpecParamsUnregistered::StaticStruct()));

    Reg.clear();
    ck::registry_table::Free(SlotHandle);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkLiveTune_LinkValidation_MissingProperty,
    "CkTests.UnitTests.LiveTune.LinkValidation.MissingProperty",
    ck_tests_livetune_registry::kFlags)

bool FCkLiveTune_LinkValidation_MissingProperty::RunTest(const FString& Parameters)
{
    auto Reg = ck::registry_table::EnttRegistryType{};
    const auto SlotHandle = ck::registry_table::Allocate(&Reg);
    const auto Registry = FCk_Registry{SlotHandle};

    auto Entity = ck::MakeHandle(FCk_Entity{Reg.create()}, Registry);
    auto* Asset = NewObject<UCk_LiveTuneTest_TuningAsset>(GetTransientPackage());

    // Occurrences=0: suppress every matching line AND require at least one — the rejection must be loud.
    AddExpectedError(TEXT("has no member property named"), EAutomationExpectedErrorFlags::Contains, 0);
    UCk_Utils_LiveTune_UE::Link(Entity, Asset, TEXT("_DoesNotExist"));

    TestFalse(TEXT("rejected Link leaves NO stamp on the entity"),
        Entity.Has<ck::FFragment_LiveTune_Stamp>());

    Reg.clear();
    ck::registry_table::Free(SlotHandle);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkLiveTune_LinkValidation_NonStructMember,
    "CkTests.UnitTests.LiveTune.LinkValidation.NonStructMember",
    ck_tests_livetune_registry::kFlags)

bool FCkLiveTune_LinkValidation_NonStructMember::RunTest(const FString& Parameters)
{
    auto Reg = ck::registry_table::EnttRegistryType{};
    const auto SlotHandle = ck::registry_table::Allocate(&Reg);
    const auto Registry = FCk_Registry{SlotHandle};

    auto Entity = ck::MakeHandle(FCk_Entity{Reg.create()}, Registry);
    auto* Asset = NewObject<UCk_LiveTuneTest_TuningAsset>(GetTransientPackage());

    AddExpectedError(TEXT("is not a struct property"), EAutomationExpectedErrorFlags::Contains, -1);
    UCk_Utils_LiveTune_UE::Link(Entity, Asset, UCk_LiveTuneTest_Utils::Get_NotAStructMemberName());

    TestFalse(TEXT("rejected Link leaves NO stamp on the entity"),
        Entity.Has<ck::FFragment_LiveTune_Stamp>());

    Reg.clear();
    ck::registry_table::Free(SlotHandle);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkLiveTune_LinkValidation_UnregisteredParamsType,
    "CkTests.UnitTests.LiveTune.LinkValidation.UnregisteredParamsType",
    ck_tests_livetune_registry::kFlags)

bool FCkLiveTune_LinkValidation_UnregisteredParamsType::RunTest(const FString& Parameters)
{
    auto Reg = ck::registry_table::EnttRegistryType{};
    const auto SlotHandle = ck::registry_table::Allocate(&Reg);
    const auto Registry = FCk_Registry{SlotHandle};

    // The one failure mode a caller CANNOT notice on their own: without this refusal the stamp lands,
    // the entity looks linked, and every later edit is silently swallowed. Opting a feature in is one
    // Register_Via* line, so the refusal names that remedy rather than just reporting the state.
    auto Entity = ck::MakeHandle(FCk_Entity{Reg.create()}, Registry);
    auto* Asset = NewObject<UCk_LiveTuneTest_TuningAsset>(GetTransientPackage());

    AddExpectedError(TEXT("is not live-tunable"), EAutomationExpectedErrorFlags::Contains, -1);
    UCk_Utils_LiveTune_UE::Link(Entity, Asset, UCk_LiveTuneTest_Utils::Get_UnregisteredParamsMemberName());

    TestFalse(TEXT("rejected Link leaves NO stamp on the entity"),
        Entity.Has<ck::FFragment_LiveTune_Stamp>());

    Reg.clear();
    ck::registry_table::Free(SlotHandle);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkLiveTune_LinkValidation_MissingParamsFragment,
    "CkTests.UnitTests.LiveTune.LinkValidation.MissingParamsFragment",
    ck_tests_livetune_registry::kFlags)

bool FCkLiveTune_LinkValidation_MissingParamsFragment::RunTest(const FString& Parameters)
{
    auto Reg = ck::registry_table::EnttRegistryType{};
    const auto SlotHandle = ck::registry_table::Allocate(&Reg);
    const auto Registry = FCk_Registry{SlotHandle};

    // _ReplaceParams has a ViaReplace handler registered at static init, whose contract requires the
    // params fragment on the entity — this entity deliberately does not carry it.
    auto Entity = ck::MakeHandle(FCk_Entity{Reg.create()}, Registry);
    auto* Asset = NewObject<UCk_LiveTuneTest_TuningAsset>(GetTransientPackage());

    AddExpectedError(TEXT("does not carry params fragment"), EAutomationExpectedErrorFlags::Contains, -1);
    UCk_Utils_LiveTune_UE::Link(Entity, Asset, UCk_LiveTuneTest_Utils::Get_ReplaceParamsMemberName());

    TestFalse(TEXT("rejected Link leaves NO stamp on the entity"),
        Entity.Has<ck::FFragment_LiveTune_Stamp>());

    Reg.clear();
    ck::registry_table::Free(SlotHandle);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkLiveTune_LinkValidation_InvalidHandle,
    "CkTests.UnitTests.LiveTune.LinkValidation.InvalidHandle",
    ck_tests_livetune_registry::kFlags)

bool FCkLiveTune_LinkValidation_InvalidHandle::RunTest(const FString& Parameters)
{
    auto* Asset = NewObject<UCk_LiveTuneTest_TuningAsset>(GetTransientPackage());

    AddExpectedError(TEXT("invalid Handle"), EAutomationExpectedErrorFlags::Contains, -1);
    auto DefaultHandle = FCk_Handle{};
    const auto Returned = UCk_Utils_LiveTune_UE::Link(DefaultHandle, Asset,
        UCk_LiveTuneTest_Utils::Get_ReplaceParamsMemberName());

    TestFalse(TEXT("rejected Link returns the (still invalid) handle without crashing"), ck::IsValid(Returned));
    return true;
}

#endif
