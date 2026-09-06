// C++ unit test for the control panel's Compact mode — the pure row filter behind H's middle
// state. Compact answers two questions and nothing else ("what can I press", "is anything wrong"),
// so it keeps every Header, every row carrying a key, and the Status rows labelled Verdict or
// flagged Warn, in declaration order. Testable without a viewport, which is why it lives as a
// static on UCkGym_Switchboard_Subsystem beside Build_Groups / Build_FilteredRows.
//
// Surface in Session Frontend: CkTests.UnitTests.CkTestsGym.GymControlPanel.<scenario>

#include "Misc/AutomationTest.h"

#include "CkGym_ControlPanelTypes.h"
#include "CkGym_Switchboard_Subsystem.h"

#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GymControlPanel_CompactRows,
    "CkTests.UnitTests.CkTestsGym.GymControlPanel.CompactRows",
    kCkUnitTestFlags)

bool FCkTest_GymControlPanel_CompactRows::RunTest(const FString& Parameters)
{
    const auto MakeRow = [](ECkGym_ControlKind InKind, const FString& InLabel,
                            const FString& InKeyLabel, bool InWarn)
    {
        auto Row = FCkGym_ControlRow{};
        Row.Kind = InKind;
        Row.Label = InLabel;
        Row.KeyLabel = InKeyLabel;
        Row.Value = TEXT("some value long enough to have wrapped in Full");
        Row.Warn = InWarn;
        return Row;
    };

    {
        const auto Rows = TArray<FCkGym_ControlRow>
        {
            MakeRow(ECkGym_ControlKind::Header, TEXT("Section"),  TEXT(""),  false),
            MakeRow(ECkGym_ControlKind::Toggle, TEXT("Banding"),  TEXT("B"), false),
            MakeRow(ECkGym_ControlKind::Status, TEXT("Verdict"),  TEXT(""),  false),
            MakeRow(ECkGym_ControlKind::Status, TEXT("Drift"),    TEXT(""),  true),
            MakeRow(ECkGym_ControlKind::Status, TEXT("Spawned"),  TEXT(""),  false),

            // The two rows that pin the rule's shape rather than its happy path. A key wins on its
            // own, whatever the kind and however quiet the row - so a keyed Status survives where the
            // keyless one above it does not. Warn is the narrower rescue: it lifts a STATUS only, so
            // a keyless Toggle is dropped even flagged, because a control you cannot press is not an
            // answer to "what can I press".
            MakeRow(ECkGym_ControlKind::Status, TEXT("Field"),    TEXT("F"), false),
            MakeRow(ECkGym_ControlKind::Toggle, TEXT("Unbound"),  TEXT(""),  true)
        };

        const auto Result = UCkGym_Switchboard_Subsystem::Build_CompactRows(Rows);

        TestEqual(TEXT("the quiet keyless status and the keyless toggle are the rows dropped"), Result.Num(), 5);

        if (Result.Num() == 5)
        {
            TestEqual(TEXT("header kept, first"),          Result[0].Label, FString{TEXT("Section")});
            TestEqual(TEXT("keyed row kept, second"),      Result[1].Label, FString{TEXT("Banding")});
            TestEqual(TEXT("Verdict status kept, third"),  Result[2].Label, FString{TEXT("Verdict")});
            TestEqual(TEXT("warning status kept, fourth"), Result[3].Label, FString{TEXT("Drift")});
            TestEqual(TEXT("keyed status kept, fifth"),    Result[4].Label, FString{TEXT("Field")});
        }
    }

    {
        const auto Result = UCkGym_Switchboard_Subsystem::Build_CompactRows(TArray<FCkGym_ControlRow>{});
        TestEqual(TEXT("no rows in, no rows out"), Result.Num(), 0);
    }

    return true;
}
