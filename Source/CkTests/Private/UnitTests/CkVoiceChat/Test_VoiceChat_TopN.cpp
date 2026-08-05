// Unit tests for the audible-speaker-cap selection policy (pure, no UObjects): the cap is
// respected, louder envelope buckets win, near-equal loudness (same bucket) rotates
// least-recently-served, and the sustained-max spoof cannot starve rotation.

#include "Misc/AutomationTest.h"

#include "CkVoiceChat/Codec/CkVoiceChat_Codec.h"

#if WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_voice_chat_topn
{
    constexpr auto kVoiceChatUnitTestFlags =
        EAutomationTestFlags::EditorContext |
        EAutomationTestFlags::ClientContext |
        EAutomationTestFlags::ProductFilter;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkVoiceChatTest_TopN_CapEnvelopeAndRotation,
    "CkTests.UnitTests.CkVoiceChat.TopN.CapEnvelopeAndRotation",
    ck_test_voice_chat_topn::kVoiceChatUnitTestFlags)

bool FCkVoiceChatTest_TopN_CapEnvelopeAndRotation::RunTest(const FString& Parameters)
{
    using namespace ck::voice_chat::codec;

    // Cap respected: 6 candidates, cap 3 -> exactly 3 selected.
    {
        auto Candidates = TArray<FCk_VoiceChat_TopNCandidate>{};
        for (auto Idx = 0; Idx < 6; ++Idx)
        {
            Candidates.Emplace(FCk_VoiceChat_TopNCandidate{Idx, 0.5f, static_cast<uint64>(Idx)});
        }

        const auto Selected = Select_TopNTalkers(Candidates, 3);
        TestEqual(TEXT("cap respected"), Selected.Num(), 3);
    }

    // Loudness wins across buckets: a quiet talker never displaces a loud one, regardless of
    // how long ago the loud one was served.
    {
        auto Candidates = TArray<FCk_VoiceChat_TopNCandidate>{};
        Candidates.Emplace(FCk_VoiceChat_TopNCandidate{0, 0.95f, 1000});   // loud, recently served
        Candidates.Emplace(FCk_VoiceChat_TopNCandidate{1, 0.10f, 0});      // quiet, never served

        const auto Selected = Select_TopNTalkers(Candidates, 1);
        TestEqual(TEXT("one selected"), Selected.Num(), 1);
        TestEqual(TEXT("the loud talker wins across buckets"), Selected[0], 0);
    }

    // Same bucket rotates least-recently-served - and updating the served frame hands the slot
    // to the other talker next time (the rotation the sustained-max spoof cannot defeat).
    {
        auto Candidates = TArray<FCk_VoiceChat_TopNCandidate>{};
        Candidates.Emplace(FCk_VoiceChat_TopNCandidate{0, 1.0f, 500});   // spoofing max, served at 500
        Candidates.Emplace(FCk_VoiceChat_TopNCandidate{1, 1.0f, 100});   // spoofing max, served at 100

        const auto FirstPick = Select_TopNTalkers(Candidates, 1);
        TestEqual(TEXT("least-recently-served wins the tie"), FirstPick[0], 1);

        auto Rotated = TArray<FCk_VoiceChat_TopNCandidate>{};
        Rotated.Emplace(FCk_VoiceChat_TopNCandidate{0, 1.0f, 500});
        Rotated.Emplace(FCk_VoiceChat_TopNCandidate{1, 1.0f, 600});      // just served

        const auto SecondPick = Select_TopNTalkers(Rotated, 1);
        TestEqual(TEXT("serving updates rotation: the other talker wins next"), SecondPick[0], 0);
    }

    // Degenerate inputs select nothing / everything cleanly.
    {
        TestEqual(TEXT("non-positive cap selects nothing"),
            Select_TopNTalkers(TArray<FCk_VoiceChat_TopNCandidate>{{0, 1.0f, 0}}, 0).Num(), 0);
        TestEqual(TEXT("empty candidates select nothing"),
            Select_TopNTalkers({}, 8).Num(), 0);
        TestEqual(TEXT("cap above candidate count selects all"),
            Select_TopNTalkers(TArray<FCk_VoiceChat_TopNCandidate>{{0, 0.2f, 0}, {1, 0.4f, 0}}, 8).Num(), 2);
    }

    return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS
