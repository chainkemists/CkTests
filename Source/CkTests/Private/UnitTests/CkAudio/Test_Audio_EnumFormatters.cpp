// Unit tests for CkAudio enum formatters. Pins stable display strings for
// the three audio-track enums; sweep verifies each value yields a distinct
// non-empty token.

#include "Misc/AutomationTest.h"

#include "CkAudio/AudioTrack/CkAudioTrack_Fragment_Data.h"
#include "CkCore/Format/CkFormat.h"

// --------------------------------------------------------------------------------------------------------------------

namespace
{
    constexpr auto kAudioUnitTestFlags =
        EAutomationTestFlags::EditorContext |
        EAutomationTestFlags::ClientContext |
        EAutomationTestFlags::ProductFilter;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Audio_OverrideBehavior_Formatter,
    "CkTests.UnitTests.CkAudio.AudioTrack_OverrideBehavior.Formatter",
    kAudioUnitTestFlags)

bool FCkTest_Audio_OverrideBehavior_Formatter::RunTest(const FString& Parameters)
{
    const auto Interrupt = ck::Format_UE(TEXT("{}"), ECk_AudioTrack_OverrideBehavior::Interrupt);
    const auto Crossfade = ck::Format_UE(TEXT("{}"), ECk_AudioTrack_OverrideBehavior::Crossfade);
    const auto Queue     = ck::Format_UE(TEXT("{}"), ECk_AudioTrack_OverrideBehavior::Queue);
    TestFalse(TEXT("Interrupt non-empty"), Interrupt.IsEmpty());
    TestFalse(TEXT("Crossfade non-empty"), Crossfade.IsEmpty());
    TestFalse(TEXT("Queue non-empty"),     Queue.IsEmpty());
    TestNotEqual(TEXT("Interrupt vs Crossfade distinct"), Interrupt, Crossfade);
    TestNotEqual(TEXT("Crossfade vs Queue distinct"),     Crossfade, Queue);
    TestNotEqual(TEXT("Interrupt vs Queue distinct"),     Interrupt, Queue);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Audio_TrackState_Formatter,
    "CkTests.UnitTests.CkAudio.AudioTrack_State.Formatter",
    kAudioUnitTestFlags)

bool FCkTest_Audio_TrackState_Formatter::RunTest(const FString& Parameters)
{
    const ECk_AudioTrack_State Values[] = {
        ECk_AudioTrack_State::Stopped,
        ECk_AudioTrack_State::Playing,
        ECk_AudioTrack_State::FadingIn,
        ECk_AudioTrack_State::FadingOut,
        ECk_AudioTrack_State::Paused,
    };
    TSet<FString> Seen;
    for (const auto V : Values)
    {
        const auto Str = ck::Format_UE(TEXT("{}"), V);
        TestFalse(*FString::Printf(TEXT("State %d formats non-empty"), static_cast<int32>(V)), Str.IsEmpty());
        TestFalse(*FString::Printf(TEXT("State %d unique among seen"), static_cast<int32>(V)), Seen.Contains(Str));
        Seen.Add(Str);
    }
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Audio_LoopBehavior_Formatter,
    "CkTests.UnitTests.CkAudio.LoopBehavior.Formatter",
    kAudioUnitTestFlags)

bool FCkTest_Audio_LoopBehavior_Formatter::RunTest(const FString& Parameters)
{
    const auto Once = ck::Format_UE(TEXT("{}"), ECk_LoopBehavior::PlayOnce);
    const auto Loop = ck::Format_UE(TEXT("{}"), ECk_LoopBehavior::Loop);
    TestFalse(TEXT("PlayOnce non-empty"), Once.IsEmpty());
    TestFalse(TEXT("Loop non-empty"),     Loop.IsEmpty());
    TestNotEqual(TEXT("PlayOnce vs Loop distinct"), Once, Loop);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Audio_TrackParamsData_Defaults,
    "CkTests.UnitTests.CkAudio.AudioTrack_ParamsData.Defaults",
    kAudioUnitTestFlags)

bool FCkTest_Audio_TrackParamsData_Defaults::RunTest(const FString& Parameters)
{
    const auto Params = FCk_AudioTrack_Spec{};
    TestEqual(TEXT("Default _Priority is 50"),      Params.Get_Priority(),       50);
    TestEqual(TEXT("Default _Volume is 1.0f"),      Params.Get_Volume(),         1.0f);
    TestEqual(TEXT("Default _LoopBehavior is Loop"), Params.Get_LoopBehavior(),  ECk_LoopBehavior::Loop);
    TestEqual(TEXT("Default _OverrideBehavior is Crossfade"),
        Params.Get_OverrideBehavior(), ECk_AudioTrack_OverrideBehavior::Crossfade);
    return true;
}
