// Unit tests for CkCVar's pure-data surface: FCk_CVarRef / FCk_CVarCallback-
// Handle / FCk_CVarDefinition constructor + IsValid round-trips, plus the
// DelegateSignatureHolder and DetectCVarType type-detection helpers.

#include "Misc/AutomationTest.h"

#include "CkCVar/CkCVar_Data.h"
#include "CkCVar/Utils/CkCVar_Utils.h"

#include "HAL/IConsoleManager.h"

// --------------------------------------------------------------------------------------------------------------------

namespace
{
    constexpr auto kCVarUnitTestFlags =
        EAutomationTestFlags::EditorContext |
        EAutomationTestFlags::ClientContext |
        EAutomationTestFlags::ProductFilter;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_CVarRef_IsValid_EmptyName_False,
    "CkTests.UnitTests.CkCVar.CVarRef.IsValid_EmptyName_False",
    kCVarUnitTestFlags)

bool FCkTest_CVarRef_IsValid_EmptyName_False::RunTest(const FString& Parameters)
{
    const auto Ref = FCk_CVarRef{};
    TestFalse(TEXT("Default-constructed CVarRef (empty name) is invalid"), Ref.IsValid());
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_CVarRef_IsValid_WithName_True,
    "CkTests.UnitTests.CkCVar.CVarRef.IsValid_WithName_True",
    kCVarUnitTestFlags)

bool FCkTest_CVarRef_IsValid_WithName_True::RunTest(const FString& Parameters)
{
    const auto Ref = FCk_CVarRef{FName{TEXT("ck.test.example")}, ECk_CVarType::Float};
    TestTrue(TEXT("CVarRef with a non-empty name reports IsValid true"), Ref.IsValid());
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_CVarRef_Ctor_PreservesNameAndType,
    "CkTests.UnitTests.CkCVar.CVarRef.Ctor_PreservesNameAndType",
    kCVarUnitTestFlags)

bool FCkTest_CVarRef_Ctor_PreservesNameAndType::RunTest(const FString& Parameters)
{
    const auto Name = FName{TEXT("ck.test.preserves")};
    const auto Ref = FCk_CVarRef{Name, ECk_CVarType::Int32};
    TestEqual(TEXT("CVarRef preserves _Name"), Ref.Get_Name(), Name);
    TestEqual(TEXT("CVarRef preserves _Type"), Ref.Get_Type(), ECk_CVarType::Int32);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_CVarCallbackHandle_IsValid_DefaultIsFalse,
    "CkTests.UnitTests.CkCVar.CallbackHandle.IsValid_DefaultIsFalse",
    kCVarUnitTestFlags)

bool FCkTest_CVarCallbackHandle_IsValid_DefaultIsFalse::RunTest(const FString& Parameters)
{
    const auto Handle = FCk_CVarCallbackHandle{};
    TestFalse(TEXT("Default-constructed CallbackHandle (ID == INDEX_NONE) is invalid"), Handle.IsValid());
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_CVarCallbackHandle_IsValid_PositiveIdTrue,
    "CkTests.UnitTests.CkCVar.CallbackHandle.IsValid_PositiveIdTrue",
    kCVarUnitTestFlags)

bool FCkTest_CVarCallbackHandle_IsValid_PositiveIdTrue::RunTest(const FString& Parameters)
{
    const auto Handle = FCk_CVarCallbackHandle{42};
    TestTrue(TEXT("CallbackHandle with a positive ID is valid"), Handle.IsValid());
    TestEqual(TEXT("Stored ID round-trips"), Handle.Get_ID(), 42);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_CVarDefinition_Ctor_PreservesAllFields,
    "CkTests.UnitTests.CkCVar.CVarDefinition.Ctor_PreservesAllFields",
    kCVarUnitTestFlags)

bool FCkTest_CVarDefinition_Ctor_PreservesAllFields::RunTest(const FString& Parameters)
{
    const auto Name = FName{TEXT("ck.test.defs")};
    const auto DefaultValue = FString{TEXT("1.5")};
    const auto Help = FString{TEXT("CVar test help text")};
    const auto Def = FCk_CVarDefinition{Name, ECk_CVarType::Float, DefaultValue, Help};

    TestEqual(TEXT("CVarDefinition Name"),         Def.Get_Name(),         Name);
    TestEqual(TEXT("CVarDefinition Type"),         Def.Get_Type(),         ECk_CVarType::Float);
    TestEqual(TEXT("CVarDefinition DefaultValue"), Def.Get_DefaultValue(), DefaultValue);
    TestEqual(TEXT("CVarDefinition HelpText"),     Def.Get_HelpText(),     Help);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_CVar_DelegateSignatureHolder_Int32,
    "CkTests.UnitTests.CkCVar.DelegateSignatureHolder.GetSignatureFunctionForType_Int32",
    kCVarUnitTestFlags)

bool FCkTest_CVar_DelegateSignatureHolder_Int32::RunTest(const FString& Parameters)
{
    auto* Fn = FCk_CVar_DelegateSignatureHolder::GetSignatureFunctionForType(ECk_CVarType::Int32);
    TestNotNull(TEXT("DelegateSignatureHolder returns a UFunction* for ECk_CVarType::Int32"), Fn);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_CVar_DelegateSignatureHolder_AllTypes,
    "CkTests.UnitTests.CkCVar.DelegateSignatureHolder.GetSignatureFunctionForType_AllTypes",
    kCVarUnitTestFlags)

bool FCkTest_CVar_DelegateSignatureHolder_AllTypes::RunTest(const FString& Parameters)
{
    const ECk_CVarType Types[] = {
        ECk_CVarType::Int32,
        ECk_CVarType::Float,
        ECk_CVarType::Bool,
        ECk_CVarType::String,
        ECk_CVarType::Command,
    };
    for (const auto Type : Types)
    {
        auto* Fn = FCk_CVar_DelegateSignatureHolder::GetSignatureFunctionForType(Type);
        TestNotNull(*FString::Printf(TEXT("DelegateSignatureHolder returns non-null UFunction* for type %d"),
            static_cast<int32>(Type)), Fn);
    }
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_CVar_DetectCVarType_Unregistered_None,
    "CkTests.UnitTests.CkCVar.DetectCVarType.Unregistered_None",
    kCVarUnitTestFlags)

bool FCkTest_CVar_DetectCVarType_Unregistered_None::RunTest(const FString& Parameters)
{
    // A name that should not exist in the console manager — IConsoleManager
    // returns no matching var, DetectCVarType returns an unset TOptional.
    const auto Maybe = UCk_Utils_CVar_UE::DetectCVarType(FName{TEXT("ck.test.absolutely.does.not.exist.xyz")});
    TestFalse(TEXT("DetectCVarType on an unregistered name returns unset"), Maybe.IsSet());
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_CVar_DetectCVarType_AfterRegister_MatchesRegisteredType,
    "CkTests.UnitTests.CkCVar.DetectCVarType.AfterRegister_MatchesRegisteredType",
    kCVarUnitTestFlags)

bool FCkTest_CVar_DetectCVarType_AfterRegister_MatchesRegisteredType::RunTest(const FString& Parameters)
{
    const auto Name = TEXT("ck.unittest.detect.float.value");

    // IConsoleManager::Get().RegisterConsoleVariable returns the existing var
    // if already registered — safe to call repeatedly across test reruns.
    IConsoleManager::Get().RegisterConsoleVariable(
        Name, 1.5f, TEXT("CkTests unit-test float CVar"), ECVF_Default);

    const auto Maybe = UCk_Utils_CVar_UE::DetectCVarType(FName{Name});
    TestTrue(TEXT("DetectCVarType on a registered float CVar returns a set TOptional"), Maybe.IsSet());
    if (Maybe.IsSet())
    {
        TestEqual(TEXT("DetectCVarType reports ECk_CVarType::Float for a registered float CVar"),
            Maybe.GetValue(), ECk_CVarType::Float);
    }
    return true;
}
