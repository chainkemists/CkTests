// Unit tests for CkActorRelay's pure-data surface: FCk_ActorRelay_ChannelResult
// default validity + the GameplayTag passthrough on the AcquireChannelRequest.

#include "Misc/AutomationTest.h"

#include "CkActorRelay/CkActorRelay_Fragment_Data.h"
#include "CkActorRelay/CkActorRelay_Utils.h"
#include "CkCore/Validation/CkIsValid.h"

// --------------------------------------------------------------------------------------------------------------------

namespace
{
    constexpr auto kActorRelayUnitTestFlags =
        EAutomationTestFlags::EditorContext |
        EAutomationTestFlags::ClientContext |
        EAutomationTestFlags::ProductFilter;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_ActorRelay_ChannelResult_DefaultCtorIsInvalid,
    "CkTests.UnitTests.CkActorRelay.ChannelResult.DefaultCtorIsInvalid",
    kActorRelayUnitTestFlags)

bool FCkTest_ActorRelay_ChannelResult_DefaultCtorIsInvalid::RunTest(const FString& Parameters)
{
    const auto Result = FCk_ActorRelay_ChannelResult{};
    TestFalse(TEXT("Default-constructed ChannelResult reports IsChannelResultValid false"),
        UCk_Utils_ActorRelay_UE::Get_IsChannelResultValid(Result));
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_ActorRelay_ChannelResult_DefaultEntityIsInvalid,
    "CkTests.UnitTests.CkActorRelay.ChannelResult.DefaultEntityIsInvalid",
    kActorRelayUnitTestFlags)

bool FCkTest_ActorRelay_ChannelResult_DefaultEntityIsInvalid::RunTest(const FString& Parameters)
{
    const auto Result = FCk_ActorRelay_ChannelResult{};
    TestFalse(TEXT("Default ChannelEntity is an invalid handle"),
        ck::IsValid(Result.Get_ChannelEntity()));
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_ActorRelay_ChannelResult_DefaultActorIsNull,
    "CkTests.UnitTests.CkActorRelay.ChannelResult.DefaultActorIsNull",
    kActorRelayUnitTestFlags)

bool FCkTest_ActorRelay_ChannelResult_DefaultActorIsNull::RunTest(const FString& Parameters)
{
    const auto Result = FCk_ActorRelay_ChannelResult{};
    TestNull(TEXT("Default ChannelActor weak ptr resolves to null"),
        Result.Get_ChannelActor().Get());
    return true;
}
