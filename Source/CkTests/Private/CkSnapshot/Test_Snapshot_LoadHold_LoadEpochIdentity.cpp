// GW-42 — the load epoch identifies the LOAD, not its ordinal.
//
// A client decides whether a world belongs to somebody else's load by comparing the epoch on the travel URL
// against its own: `_LoadInProgress || Epoch == _LoadEpoch` means "this is mine, do not arm a client hold".
// That comparison is only sound if equal epochs really do mean the same load — and while the epoch was a bare
// per-GameInstance COUNT it did not. A machine that had hosted one load of its own, joining a host running its
// own load number one, read the host's load as its own and refused to arm: no hold, no freeze, and a player
// walking around a world being rebuilt underneath them, with nothing in any log saying why.
//
// So the epoch carries a session-unique salt in its high bits. The property below is what that buys, and it is
// asserted against the composition rather than against two live GameInstances, because reproducing the bug in
// the world would mean standing up two instances that have each run the same number of loads.
//
// RED before this change: the epoch was `++_LoadCount`, so Compose(SaltA, 1) and Compose(SaltB, 1) were the
// same number by construction.
// Surface in Session Frontend: Ck.Snapshot.LoadHold.LoadEpochIdentifiesTheLoadNotItsOrdinal

#include "Misc/AutomationTest.h"

#if WITH_DEV_AUTOMATION_TESTS

#include "CkSnapshot/Subsystem/CkSnapshot_Subsystem.h"

namespace ck_test_loadhold_epoch
{
    constexpr auto kFlags =
        EAutomationTestFlags::EditorContext |
        EAutomationTestFlags::ClientContext |
        EAutomationTestFlags::ProductFilter;

    // Two instances that have each run exactly this many loads. One is the case the bug needed; the rest are
    // there so a salt that only separated the first load would not pass.
    const auto SampleCounts = TArray<int32>{1, 2, 7, 64, 4095, 65535};

    // Distinct salts, drawn from the ends and the middle of the 15-bit space rather than at random: a test that
    // rolls its own inputs cannot say which input failed.
    const auto SampleSalts = TArray<int32>{1, 2, 1234, 32766, 32767};
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_LoadHold_LoadEpochIdentifiesTheLoadNotItsOrdinal,
    "Ck.Snapshot.LoadHold.LoadEpochIdentifiesTheLoadNotItsOrdinal",
    ck_test_loadhold_epoch::kFlags)

bool FCk_Snapshot_LoadHold_LoadEpochIdentifiesTheLoadNotItsOrdinal::RunTest(const FString& /*Parameters*/)
{
    using namespace ck_test_loadhold_epoch;

    auto AllGood = true;

    // THE property. Two GameInstances at the same load count must not mint the same epoch, because that is
    // exactly the pair the ownership gate has to tell apart.
    for (const auto Count : SampleCounts)
    {
        for (auto OuterIndex = 0; OuterIndex < SampleSalts.Num(); ++OuterIndex)
        {
            for (auto InnerIndex = OuterIndex + 1; InnerIndex < SampleSalts.Num(); ++InnerIndex)
            {
                const auto Left = UCk_Snapshot_Subsystem_UE::Compose_LoadEpoch(SampleSalts[OuterIndex], Count);
                const auto Right = UCk_Snapshot_Subsystem_UE::Compose_LoadEpoch(SampleSalts[InnerIndex], Count);

                AllGood &= TestTrue(
                    FString::Printf(
                        TEXT("two sessions at load count %d mint different epochs (salt %d -> %d, salt %d -> %d) ")
                        TEXT("— equal epochs must mean the same LOAD, not the same ordinal"),
                        Count, SampleSalts[OuterIndex], Left, SampleSalts[InnerIndex], Right),
                    Left != Right);
            }
        }
    }

    // ...and within ONE session the epoch still orders and still separates, which is what Get_LoadEpoch's
    // documented "monotonic within a session" claim rests on and what stops a consumer reacting twice.
    for (const auto Salt : SampleSalts)
    {
        for (auto Index = 1; Index < SampleCounts.Num(); ++Index)
        {
            const auto Earlier = UCk_Snapshot_Subsystem_UE::Compose_LoadEpoch(Salt, SampleCounts[Index - 1]);
            const auto Later = UCk_Snapshot_Subsystem_UE::Compose_LoadEpoch(Salt, SampleCounts[Index]);

            AllGood &= TestTrue(
                FString::Printf(TEXT("within one session (salt %d) load %d's epoch %d precedes load %d's %d"),
                    Salt, SampleCounts[Index - 1], Earlier, SampleCounts[Index], Later),
                Earlier < Later);
        }
    }

    // The wire form has to survive the round trip the arm gate performs on it: printed as a decimal into
    // ?CkLoad=, read back with FCString::Atoi, and rejected unless it is numeric and strictly positive. A salt
    // that spilled into the sign bit would arrive negative and every client would silently decline to arm.
    for (const auto Salt : SampleSalts)
    {
        for (const auto Count : SampleCounts)
        {
            const auto Epoch = UCk_Snapshot_Subsystem_UE::Compose_LoadEpoch(Salt, Count);
            const auto Printed = FString::Printf(TEXT("%d"), Epoch);

            AllGood &= TestTrue(
                FString::Printf(TEXT("epoch (salt %d, count %d) survives the ?CkLoad round trip as [%s]"),
                    Salt, Count, *Printed),
                Epoch > 0 && Printed.IsNumeric() && FCString::Atoi(*Printed) == Epoch);
        }
    }

    return AllGood;
}

#endif // WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------
