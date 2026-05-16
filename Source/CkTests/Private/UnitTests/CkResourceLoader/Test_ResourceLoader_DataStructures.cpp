// Unit tests for CkResourceLoader's pure-data surface — Soft/Hard object
// references, LoadedObject/PendingObject validity, batch transforms, and
// the LoadingPolicy formatter. Pins the equality + hash contracts the
// processor relies on for deduplication and cache lookup.

#include "Misc/AutomationTest.h"

#include "Engine/DataTable.h"

#include "CkCore/Format/CkFormat.h"
#include "CkCore/Validation/CkIsValid.h"
#include "CkResourceLoader/CkResourceLoader_Fragment_Data.h"
#include "CkResourceLoader/CkResourceLoader_Utils.h"

// --------------------------------------------------------------------------------------------------------------------

namespace
{
    constexpr auto kResourceLoaderUnitTestFlags =
        EAutomationTestFlags::EditorContext |
        EAutomationTestFlags::ClientContext |
        EAutomationTestFlags::ProductFilter;

    auto MakeSoftRef(const TCHAR* InPath) -> FCk_ResourceLoader_ObjectReference_Soft
    {
        return FCk_ResourceLoader_ObjectReference_Soft{FSoftObjectPath{InPath}};
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_ResourceLoader_LoadingPolicy_Formatter,
    "CkTests.UnitTests.CkResourceLoader.LoadingPolicy.Formatter",
    kResourceLoaderUnitTestFlags)

bool FCkTest_ResourceLoader_LoadingPolicy_Formatter::RunTest(const FString& Parameters)
{
    const auto Async = ck::Format_UE(TEXT("{}"), ECk_ResourceLoader_LoadingPolicy::Async);
    const auto Sync  = ck::Format_UE(TEXT("{}"), ECk_ResourceLoader_LoadingPolicy::Synchronous);
    TestFalse(TEXT("Async formats to non-empty"), Async.IsEmpty());
    TestFalse(TEXT("Synchronous formats to non-empty"), Sync.IsEmpty());
    TestNotEqual(TEXT("Async vs Synchronous produce distinct strings"), Async, Sync);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_ResourceLoader_ObjectReferenceSoft_Equality,
    "CkTests.UnitTests.CkResourceLoader.ObjectReferenceSoft.Equality",
    kResourceLoaderUnitTestFlags)

bool FCkTest_ResourceLoader_ObjectReferenceSoft_Equality::RunTest(const FString& Parameters)
{
    const auto A = MakeSoftRef(TEXT("/Game/SomePath.SomeAsset"));
    const auto B = MakeSoftRef(TEXT("/Game/SomePath.SomeAsset"));
    const auto C = MakeSoftRef(TEXT("/Game/OtherPath.OtherAsset"));

    TestTrue (TEXT("Same path → equal"),     A == B);
    TestFalse(TEXT("Different paths → not equal"), A == C);
    TestTrue (TEXT("operator!= negates =="),  A != C);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_ResourceLoader_ObjectReferenceSoft_GetTypeHash_Stable,
    "CkTests.UnitTests.CkResourceLoader.ObjectReferenceSoft.GetTypeHash_Stable",
    kResourceLoaderUnitTestFlags)

bool FCkTest_ResourceLoader_ObjectReferenceSoft_GetTypeHash_Stable::RunTest(const FString& Parameters)
{
    const auto A = MakeSoftRef(TEXT("/Game/Path.Asset"));
    const auto B = MakeSoftRef(TEXT("/Game/Path.Asset"));
    TestEqual(TEXT("Identical SoftObjectPath → identical hash"),
        GetTypeHash(A), GetTypeHash(B));
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_ResourceLoader_ObjectReferenceSoft_IsValid_EmptyPath_False,
    "CkTests.UnitTests.CkResourceLoader.ObjectReferenceSoft.IsValid_EmptyPath_False",
    kResourceLoaderUnitTestFlags)

bool FCkTest_ResourceLoader_ObjectReferenceSoft_IsValid_EmptyPath_False::RunTest(const FString& Parameters)
{
    const auto Empty = FCk_ResourceLoader_ObjectReference_Soft{};
    TestFalse(TEXT("Default-constructed soft ref (empty FSoftObjectPath) is NOT valid"),
        ck::IsValid(Empty));
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_ResourceLoader_ObjectReferenceHard_Equality_IdenticalObject,
    "CkTests.UnitTests.CkResourceLoader.ObjectReferenceHard.Equality_IdenticalObject",
    kResourceLoaderUnitTestFlags)

bool FCkTest_ResourceLoader_ObjectReferenceHard_Equality_IdenticalObject::RunTest(const FString& Parameters)
{
    // Two different UObjects → not equal; same pointer → equal; null-vs-null → equal.
    auto* ObjA = NewObject<UDataTable>();
    auto* ObjB = NewObject<UDataTable>();
    const auto HardA = FCk_ResourceLoader_ObjectReference_Hard{ObjA};
    const auto HardA_again = FCk_ResourceLoader_ObjectReference_Hard{ObjA};
    const auto HardB = FCk_ResourceLoader_ObjectReference_Hard{ObjB};

    TestTrue (TEXT("Identical UObject pointers → equal"),       HardA == HardA_again);
    TestFalse(TEXT("Different UObject pointers → not equal"),   HardA == HardB);

    const auto NullA = FCk_ResourceLoader_ObjectReference_Hard{};
    const auto NullB = FCk_ResourceLoader_ObjectReference_Hard{};
    TestTrue(TEXT("Two default (null) hard refs compare equal"), NullA == NullB);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_ResourceLoader_LoadedObject_Formatter,
    "CkTests.UnitTests.CkResourceLoader.LoadedObject.Formatter",
    kResourceLoaderUnitTestFlags)

bool FCkTest_ResourceLoader_LoadedObject_Formatter::RunTest(const FString& Parameters)
{
    const auto Soft = MakeSoftRef(TEXT("/Game/Path.Asset"));
    const auto Hard = FCk_ResourceLoader_ObjectReference_Hard{};
    const auto Loaded = FCk_ResourceLoader_LoadedObject{Soft, Hard};
    const auto Str = ck::Format_UE(TEXT("{}"), Loaded);
    TestFalse(TEXT("LoadedObject formatter produces non-empty output"), Str.IsEmpty());
    TestTrue(TEXT("Formatter mentions ObjectReference_Soft section"),
        Str.Contains(TEXT("ObjectReference_Soft")));
    TestTrue(TEXT("Formatter mentions ObjectReference_Hard section"),
        Str.Contains(TEXT("ObjectReference_Hard")));
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_ResourceLoader_LoadedObject_IsValid_RequiresBothRefs,
    "CkTests.UnitTests.CkResourceLoader.LoadedObject.IsValid_RequiresBothRefs",
    kResourceLoaderUnitTestFlags)

bool FCkTest_ResourceLoader_LoadedObject_IsValid_RequiresBothRefs::RunTest(const FString& Parameters)
{
    auto* Obj = NewObject<UDataTable>();
    const auto ValidSoft = MakeSoftRef(TEXT("/Game/Path.Asset"));
    const auto EmptySoft = FCk_ResourceLoader_ObjectReference_Soft{};
    const auto ValidHard = FCk_ResourceLoader_ObjectReference_Hard{Obj};
    const auto NullHard  = FCk_ResourceLoader_ObjectReference_Hard{};

    TestTrue (TEXT("Both valid → IsValid true"),                ck::IsValid(FCk_ResourceLoader_LoadedObject{ValidSoft, ValidHard}));
    TestFalse(TEXT("Empty soft → IsValid false"),                ck::IsValid(FCk_ResourceLoader_LoadedObject{EmptySoft, ValidHard}));
    TestFalse(TEXT("Null hard → IsValid false"),                 ck::IsValid(FCk_ResourceLoader_LoadedObject{ValidSoft, NullHard}));
    TestFalse(TEXT("Both empty/null → IsValid false"),           ck::IsValid(FCk_ResourceLoader_LoadedObject{EmptySoft, NullHard}));
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_ResourceLoader_PendingObject_IsValid_DelegatesToSoftPath,
    "CkTests.UnitTests.CkResourceLoader.PendingObject.IsValid_DelegatesToSoftPath",
    kResourceLoaderUnitTestFlags)

bool FCkTest_ResourceLoader_PendingObject_IsValid_DelegatesToSoftPath::RunTest(const FString& Parameters)
{
    const auto WithValidPath = FCk_ResourceLoader_PendingObject{MakeSoftRef(TEXT("/Game/Path.Asset"))};
    const auto WithEmptyPath = FCk_ResourceLoader_PendingObject{FCk_ResourceLoader_ObjectReference_Soft{}};
    TestTrue (TEXT("Pending with a valid soft path is valid"),       ck::IsValid(WithValidPath));
    TestFalse(TEXT("Pending with an empty soft path is NOT valid"),  ck::IsValid(WithEmptyPath));
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_ResourceLoader_Conv_TransformBatch_PreservesOrderAndCount,
    "CkTests.UnitTests.CkResourceLoader.Conv.TransformBatch_PreservesOrderAndCount",
    kResourceLoaderUnitTestFlags)

bool FCkTest_ResourceLoader_Conv_TransformBatch_PreservesOrderAndCount::RunTest(const FString& Parameters)
{
    // Build TSoftObjectPtr inputs from three known paths. The transform helper
    // must produce the corresponding FCk_ResourceLoader_ObjectReference_Soft
    // array with same count + per-index path equivalence.
    const TArray<TSoftObjectPtr<UObject>> Inputs = {
        TSoftObjectPtr<UObject>{FSoftObjectPath{TEXT("/Game/A.A")}},
        TSoftObjectPtr<UObject>{FSoftObjectPath{TEXT("/Game/B.B")}},
        TSoftObjectPtr<UObject>{FSoftObjectPath{TEXT("/Game/C.C")}},
    };
    const auto Out = UCk_Utils_ResourceLoader_UE::Transform_SoftObjectReferences_ToSoftResourceLoaderObjectReferences(Inputs);

    TestEqual(TEXT("Count preserved"), Out.Num(), Inputs.Num());
    if (Out.Num() == Inputs.Num())
    {
        for (auto Index = 0; Index < Out.Num(); ++Index)
        {
            TestEqual(*FString::Printf(TEXT("Index %d soft path matches input"), Index),
                Out[Index].Get_SoftObjectPath(), Inputs[Index].ToSoftObjectPath());
        }
    }
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_ResourceLoader_Conv_TransformBatch_EmptyInput_EmptyOutput,
    "CkTests.UnitTests.CkResourceLoader.Conv.TransformBatch_EmptyInput_EmptyOutput",
    kResourceLoaderUnitTestFlags)

bool FCkTest_ResourceLoader_Conv_TransformBatch_EmptyInput_EmptyOutput::RunTest(const FString& Parameters)
{
    const TArray<TSoftObjectPtr<UObject>> Empty;
    const auto Out = UCk_Utils_ResourceLoader_UE::Transform_SoftObjectReferences_ToSoftResourceLoaderObjectReferences(Empty);
    TestEqual(TEXT("Empty input produces empty output"), Out.Num(), 0);
    return true;
}
