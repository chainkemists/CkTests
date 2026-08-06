// Gate-0 audit condition C1: the invalid-input test for CkVoiceChat's one new validation
// boundary. UCk_Utils_VoiceChannel_UE::Add with an invalid ChannelName must reject loudly
// (one ensure), return an invalid handle, and leave ZERO partial state on the host — no record,
// no label, no channel entity (root non-negotiable #3's closing requirement).

#include "Misc/AutomationTest.h"

#include "CkEcs/Registry/CkRegistry_SlotTable.h"

#include "CkLabel/CkLabel_Utils.h"

#include "CkVoiceChat/VoiceChannel/CkVoiceChannel_Utils.h"

#if WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_VoiceChat_ChannelAdd_InvalidNameRejected,
    "CkTests.UnitTests.CkVoiceChat.Channel.AddInvalidNameRejected",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::ProductFilter)

bool FCkTest_VoiceChat_ChannelAdd_InvalidNameRejected::RunTest(const FString& Parameters)
{
    // Whitelist every matching line: one CK ensure can surface through multiple log paths.
    AddExpectedError(TEXT("Cannot add a VoiceChannel to Host"), EAutomationExpectedErrorFlags::Contains, -1);

    auto BackingRegistry = ck::registry_table::EnttRegistryType{};
    const auto RegistryHandle = ck::registry_table::Allocate(&BackingRegistry);
    const auto HostEntity = BackingRegistry.create();
    auto Host = FCk_Handle{FCk_Entity{HostEntity}, RegistryHandle};

    const auto InvalidNameParams = FCk_VoiceChannel_Spec{};   // default FGameplayTag = invalid

    const auto Result = UCk_Utils_VoiceChannel_UE::Add(Host, InvalidNameParams);

    TestTrue(TEXT("Add with an invalid ChannelName returns an invalid handle"), ck::Is_NOT_Valid(Result));
    TestFalse(TEXT("The host gained no channel record"), UCk_Utils_VoiceChannel_UE::Has_Any(Host));
    TestFalse(TEXT("The host itself was not turned into a channel"), UCk_Utils_VoiceChannel_UE::Has(Host));
    TestFalse(TEXT("The host gained no label"), UCk_Utils_GameplayLabel_UE::Has(Host));

    ck::registry_table::Free(RegistryHandle);

    return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS
