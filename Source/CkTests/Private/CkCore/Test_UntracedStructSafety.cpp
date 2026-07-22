#include "CkCore/Validation/CkUntracedStructSafety.h"
#include "CkCore/SharedValues/CkSharedValues_Utils.h"
#include "CkDynamic/CkDynamic_Utils.h"
#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/World/CkEcsWorld.h"

#include "../CkSnapshot/Test_Snapshot_DynamicFragment_Fixtures.h"

#include "Misc/AutomationTest.h"
#include "UObject/UObjectGlobals.h"
#include "UObject/UnrealType.h"

#if WITH_DEV_AUTOMATION_TESTS

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_UntracedStructSafety_RecursiveClassification,
    "Ck.CkCore.UntracedStructSafety.RecursiveClassification",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkTest_UntracedStructSafety_RecursiveClassification::RunTest(const FString&)
{
    const auto PureData = ck::Analyze_UntracedStructSafety(FCk_Test_DynFrag_PureData::StaticStruct());
    TestTrue(TEXT("scalar/string reflected struct is GC-independent"), PureData.IsGcIndependent());

    const auto SafeRefs = ck::Analyze_UntracedStructSafety(FCk_Test_UntracedSafeObjectRefs::StaticStruct());
    TestTrue(TEXT("weak and soft UObject wrappers are GC-independent"), SafeRefs.IsGcIndependent());

    const auto DirectStrong = ck::Analyze_UntracedStructSafety(FCk_Test_HydrationPayloadWithObject::StaticStruct());
    TestEqual(TEXT("direct strong UObject requires tracing"),
        DirectStrong.Safety, ck::ECk_UntracedStructSafety::RequiresGcTracing);
    TestTrue(TEXT("direct failure path identifies Object"), DirectStrong.FailurePath.EndsWith(TEXT(".Object")));

    const auto NestedStrong = ck::Analyze_UntracedStructSafety(FCk_Test_UntracedNestedStrongObject::StaticStruct());
    TestEqual(TEXT("strong UObject nested in an array requires tracing"),
        NestedStrong.Safety, ck::ECk_UntracedStructSafety::RequiresGcTracing);
    TestTrue(TEXT("nested failure path identifies array element Object"),
        NestedStrong.FailurePath.EndsWith(TEXT(".Values[].Object")));

    const auto OpaqueEmpty = ck::Analyze_UntracedStructSafety(FCk_Test_UntracedOpaqueEmpty::StaticStruct());
    TestEqual(TEXT("zero-reflection native struct fails closed"),
        OpaqueEmpty.Safety, ck::ECk_UntracedStructSafety::UnprovenOpaque);

    const auto* AngelScriptEmpty = FindObject<UScriptStruct>(
        nullptr, TEXT("/Script/Angelscript.Ck_Fragment_DynamicTest_TagPayload"));
    TestNotNull(TEXT("empty AngelScript test marker is loaded"), AngelScriptEmpty);
    if (AngelScriptEmpty != nullptr)
    {
        TestEqual(TEXT("test marker is backed by the AngelScript runtime struct class"),
            AngelScriptEmpty->GetClass()->GetPathName(), FString{TEXT("/Script/AngelscriptCode.ASStruct")});
        TestFalse(TEXT("empty AngelScript marker has no reflected fields"),
            static_cast<bool>(TFieldIterator<FProperty>{AngelScriptEmpty}));
        TestEqual(TEXT("empty AngelScript marker has zero value-storage size"),
            AngelScriptEmpty->GetPropertiesSize(), 0);

        const auto AngelScriptMarkerSafety = ck::Analyze_UntracedStructSafety(AngelScriptEmpty);
        TestTrue(TEXT("zero-field AngelScript marker is GC-independent"),
            AngelScriptMarkerSafety.IsGcIndependent());
    }

    const auto InstancedCarrier = ck::Analyze_UntracedStructSafety(FCk_Test_InstancedStructArrayWrapper::StaticStruct());
    TestEqual(TEXT("FInstancedStruct carrier requires a traced holder"),
        InstancedCarrier.Safety, ck::ECk_UntracedStructSafety::RequiresGcTracing);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_UntracedStructSafety_SharedInstancedStructFailsClosed,
    "Ck.CkCore.UntracedStructSafety.SharedInstancedStructFailsClosed",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkTest_UntracedStructSafety_SharedInstancedStructFailsClosed::RunTest(const FString&)
{
    auto Initial = FCk_Test_DynFrag_PureData{};
    Initial.Count = 17;
    auto Shared = FCk_SharedInstancedStruct{FInstancedStruct::Make(Initial)};

    AddExpectedError(
        TEXT("SharedInstancedStruct rejected unsafe value"),
        EAutomationExpectedErrorFlags::Contains, 0);
    const auto RejectedConstruction = FCk_SharedInstancedStruct{
        FInstancedStruct::Make(FCk_Test_HydrationPayloadWithObject{})};
    TestFalse(TEXT("unsafe constructor input leaves the shared value unset"),
        UCk_Utils_SharedInstancedStruct_UE::Get(RejectedConstruction).IsValid());

    UCk_Utils_SharedInstancedStruct_UE::Set(
        Shared, FInstancedStruct::Make(FCk_Test_HydrationPayloadWithObject{}));

    const auto Preserved = UCk_Utils_SharedInstancedStruct_UE::Get(Shared);
    TestTrue(TEXT("rejected Set preserves the prior safe value"), Preserved.IsValid());
    TestEqual(TEXT("rejected Set performs no partial mutation"),
        Preserved.Get<FCk_Test_DynFrag_PureData>().Count, 17);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_UntracedStructSafety_DynamicAdmissionFailsClosed,
    "Ck.CkCore.UntracedStructSafety.DynamicAdmissionFailsClosed",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkTest_UntracedStructSafety_DynamicAdmissionFailsClosed::RunTest(const FString&)
{
    auto InvalidHandle = FCk_Handle{};
    AddExpectedError(TEXT("Invalid Handle passed. Unable to add Fragment"),
        EAutomationExpectedErrorFlags::Contains, 0);
    const auto InvalidAddResult = UCk_Utils_DynamicFragment_UE::Add_Fragment(
        InvalidHandle, FInstancedStruct::Make(FCk_Test_DynFrag_PureData{}));
    TestFalse(TEXT("invalid-handle Add returns an invalid result"), ck::IsValid(InvalidAddResult));

    auto EcsWorld = ck::FEcsWorld{};
    auto Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(EcsWorld.Get_Registry());
    auto OwnerRef = Owner;
    const auto UnsafeValue = FInstancedStruct::Make(FCk_Test_HydrationPayloadWithObject{});

    AddExpectedError(TEXT("Dynamic Fragment schema"), EAutomationExpectedErrorFlags::Contains, 0);
    const auto UnsafeAddResult = UCk_Utils_DynamicFragment_UE::Add_Fragment(OwnerRef, UnsafeValue);
    TestFalse(TEXT("unsafe-schema Add returns an invalid result"), ck::IsValid(UnsafeAddResult));
    TestFalse(TEXT("unsafe-schema Add publishes no fragment storage"),
        UCk_Utils_DynamicFragment_UE::Has_Fragment(
            Owner, FCk_Test_HydrationPayloadWithObject::StaticStruct()));

    TestNull(TEXT("unsafe-schema AddOrGet has a failure-representable result"),
        UCk_Utils_DynamicFragment_UE::TryAddOrGet_Fragment_TypeUnsafe(
            OwnerRef, FCk_Test_HydrationPayloadWithObject::StaticStruct()));

    AddExpectedError(TEXT("does NOT have the Dynamic Fragment"),
        EAutomationExpectedErrorFlags::Contains, 0);
    TestNull(TEXT("missing-fragment Get has a failure-representable result"),
        UCk_Utils_DynamicFragment_UE::TryGet_Fragment_TypeUnsafe(
            Owner, FCk_Test_DynFrag_PureData::StaticStruct()));

    const auto* EmptyAngelScriptMarker = FindObject<UScriptStruct>(
        nullptr, TEXT("/Script/Angelscript.Ck_Fragment_DynamicTest_TagPayload"));
    if (TestNotNull(TEXT("empty AngelScript marker is available for replication preflight"), EmptyAngelScriptMarker))
    {
        AddExpectedError(TEXT("requested to replicate, but the struct has no"),
            EAutomationExpectedErrorFlags::Contains, 0);
        const auto RejectedReplicatedTag = UCk_Utils_DynamicFragment_UE::Add_Fragment(
            OwnerRef, FInstancedStruct{EmptyAngelScriptMarker}, ECk_Replication::Replicates);
        TestFalse(TEXT("replicated tag rejection reports failure"), ck::IsValid(RejectedReplicatedTag));
        TestFalse(TEXT("replicated tag rejection publishes no named storage"),
            UCk_Utils_DynamicFragment_UE::Has_Fragment(Owner, EmptyAngelScriptMarker));
    }

    return true;
}

#endif
