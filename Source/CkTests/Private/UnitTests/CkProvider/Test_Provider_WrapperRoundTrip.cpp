// Unit tests for the FCk_Provider_* wrapper structs. Pins the constructor +
// Get_Provider() round-trip per typed wrapper, plus the default-construct
// null-pointer contract. Pure-data tests — no world or registry needed.

#include "Misc/AutomationTest.h"

#include "CkProvider/CkProvider_Data.h"

// --------------------------------------------------------------------------------------------------------------------

namespace
{
    constexpr auto kProviderWrapperTestFlags =
        EAutomationTestFlags::EditorContext |
        EAutomationTestFlags::ClientContext |
        EAutomationTestFlags::ProductFilter;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_ProviderBool_WrapperGetProvider,
    "CkTests.UnitTests.CkProvider.ProviderBool.WrapperGetProvider",
    kProviderWrapperTestFlags)

bool FCkTest_ProviderBool_WrapperGetProvider::RunTest(const FString& Parameters)
{
    auto* Pda = NewObject<UCk_Provider_Bool_Literal_PDA>();
    const auto Wrapper = FCk_Provider_Bool{Pda};
    TestEqual(TEXT("Get_Provider returns the same pointer passed to the constructor"),
        Wrapper.Get_Provider().Get(), static_cast<UCk_Provider_Bool_PDA*>(Pda));
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_ProviderFloat_WrapperGetProvider,
    "CkTests.UnitTests.CkProvider.ProviderFloat.WrapperGetProvider",
    kProviderWrapperTestFlags)

bool FCkTest_ProviderFloat_WrapperGetProvider::RunTest(const FString& Parameters)
{
    auto* Pda = NewObject<UCk_Provider_Float_Literal_PDA>();
    const auto Wrapper = FCk_Provider_Float{Pda};
    TestEqual(TEXT("Get_Provider returns the same pointer passed to the constructor"),
        Wrapper.Get_Provider().Get(), static_cast<UCk_Provider_Float_PDA*>(Pda));
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_ProviderInt_WrapperGetProvider,
    "CkTests.UnitTests.CkProvider.ProviderInt.WrapperGetProvider",
    kProviderWrapperTestFlags)

bool FCkTest_ProviderInt_WrapperGetProvider::RunTest(const FString& Parameters)
{
    auto* Pda = NewObject<UCk_Provider_Int_Literal_PDA>();
    const auto Wrapper = FCk_Provider_Int{Pda};
    TestEqual(TEXT("Get_Provider returns the same pointer passed to the constructor"),
        Wrapper.Get_Provider().Get(), static_cast<UCk_Provider_Int_PDA*>(Pda));
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_ProviderGameplayTag_WrapperGetProvider,
    "CkTests.UnitTests.CkProvider.ProviderGameplayTag.WrapperGetProvider",
    kProviderWrapperTestFlags)

bool FCkTest_ProviderGameplayTag_WrapperGetProvider::RunTest(const FString& Parameters)
{
    auto* Pda = NewObject<UCk_Provider_GameplayTag_Literal_PDA>();
    const auto Wrapper = FCk_Provider_GameplayTag{Pda};
    TestEqual(TEXT("Get_Provider returns the same pointer passed to the constructor"),
        Wrapper.Get_Provider().Get(), static_cast<UCk_Provider_GameplayTag_PDA*>(Pda));
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_ProviderBool_DefaultConstruct_NullProvider,
    "CkTests.UnitTests.CkProvider.ProviderBool.DefaultConstruct_NullProvider",
    kProviderWrapperTestFlags)

bool FCkTest_ProviderBool_DefaultConstruct_NullProvider::RunTest(const FString& Parameters)
{
    const auto Wrapper = FCk_Provider_Bool{};
    TestNull(TEXT("Default-constructed wrapper should hold a null provider pointer"),
        Wrapper.Get_Provider().Get());
    return true;
}
