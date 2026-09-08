#include "CkSlateLayout/CkUiDocument.h"
#include "CkSlateLayout/SCkUiSplitter.h"

#include "Framework/Application/SlateApplication.h"
#include "Misc/AutomationTest.h"
#include "Widgets/Layout/SSplitter.h"
#include "Widgets/Text/STextBlock.h"

#include <limits>

#if WITH_DEV_AUTOMATION_TESTS

namespace ck_tests_ui_splitter_validation
{
    auto Parse(const FString& InMarkup, const FString& InStylesheet, FCkUiDocument& OutDocument) -> FCkUiLoadResult
    {
        return FCkUiDocumentParser::TryParse(InMarkup, InStylesheet, {}, OutDocument, TEXT("UiSplitterValidation"));
    }

    auto HasError(const FCkUiLoadResult& InResult, const TCHAR* InNeedle) -> bool
    {
        for (const FString& Error : InResult.Errors)
        {
            if (Error.Contains(InNeedle)) { return true; }
        }
        return false;
    }

    auto SplitterMarkup(const FString& InDirection = TEXT("horizontal"), const FString& InClass = TEXT("")) -> FString
    {
        return FString::Printf(TEXT("<ui version=\"1\"><region name=\"main\"><splitter id=\"split\" direction=\"%s\" class=\"%s\"><column id=\"left\" class=\"pane\"><text id=\"left-text\">Left</text></column><column id=\"right\" class=\"pane\"><text id=\"right-text\">Right</text></column></splitter></region></ui>"), *InDirection, *InClass);
    }

    auto ValidPanes(const TSharedPtr<SWidget>& InLeft, const TSharedPtr<SWidget>& InRight) -> TArray<SCkUiSplitter::FPane>
    {
        return {{TEXT("left"), InLeft, 2.0f, 11.0f}, {TEXT("right"), InRight, 3.0f, 17.0f}};
    }

    struct FSlotState
    {
        int32 Count = 0;
        float LeftWeight = 0.0f;
        float RightWeight = 0.0f;
        float LeftMinimum = 0.0f;
        float RightMinimum = 0.0f;
        const SWidget* Left = nullptr;
        const SWidget* Right = nullptr;
    };

    auto CaptureSlots(const TSharedRef<SSplitter>& InSplitter) -> FSlotState
    {
        FSlotState State;
        State.Count = InSplitter->NumSlots();
        if (State.Count == 2)
        {
            const SSplitter::FSlot& Left = InSplitter->SlotAt(0);
            const SSplitter::FSlot& Right = InSplitter->SlotAt(1);
            State.LeftWeight = Left.GetSizeValue();
            State.RightWeight = Right.GetSizeValue();
            State.LeftMinimum = Left.GetMinSize();
            State.RightMinimum = Right.GetMinSize();
            State.Left = &Left.GetWidget().Get();
            State.Right = &Right.GetWidget().Get();
        }
        return State;
    }

    auto IsUnchanged(const FSlotState& InBefore, const FSlotState& InAfter) -> bool
    {
        return InBefore.Count == InAfter.Count
            && InBefore.LeftWeight == InAfter.LeftWeight && InBefore.RightWeight == InAfter.RightWeight
            && InBefore.LeftMinimum == InAfter.LeftMinimum && InBefore.RightMinimum == InAfter.RightMinimum
            && InBefore.Left == InAfter.Left && InBefore.Right == InAfter.Right;
    }

    auto FreshText(const TCHAR* InText) -> TSharedPtr<SWidget>
    {
        return SNew(STextBlock).Text(FText::FromString(InText));
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiSplitter_ParserValidation,
    "Ck.UiAuthoring.Splitter.ParserValidation",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiSplitter_ParserValidation::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_splitter_validation;
    FCkUiDocument Document;
    const FCkUiLoadResult Valid = Parse(SplitterMarkup(), TEXT(".pane { flex-grow: 2; min-width: 40px; }"), Document);
    if (!TestTrue(TEXT("Horizontal splitter parses"), Valid.Succeeded))
    {
        for (const FString& Error : Valid.Errors) { AddError(Error); }
        return false;
    }
    const FCkUiNode* Splitter = Document.Regions.Find(TEXT("main"));
    if (!TestTrue(TEXT("Splitter node and panes are emitted"), Splitter != nullptr && Splitter->Kind == ECkUiNodeKind::Splitter && Splitter->Children.Num() == 2)) { return false; }
    TestEqual(TEXT("Splitter defaults or parses horizontal direction"), Splitter->SplitterDirection, Orient_Horizontal);
    TestEqual(TEXT("Pane retains authored flex weight"), Splitter->Children[0].Style.Grow, 2.0f);
    TestEqual(TEXT("Pane retains authored axis minimum"), Splitter->Children[0].Style.MinWidth, 40.0f);

    const auto Reject = [this, &Document](const TCHAR* InName, const FString& InMarkup, const TCHAR* InNeedle, const FString& InStyles = TEXT(""))
    {
        const FCkUiLoadResult Result = Parse(InMarkup, InStyles, Document);
        TestFalse(InName, Result.Succeeded);
        TestTrue(*FString::Printf(TEXT("%s reports its splitter diagnostic"), InName), HasError(Result, InNeedle));
        const FCkUiNode* Preserved = Document.Regions.Find(TEXT("main"));
        TestTrue(*FString::Printf(TEXT("%s preserves prior parsed output"), InName), Preserved != nullptr
            && Preserved->Kind == ECkUiNodeKind::Splitter && Preserved->Children.Num() == 2
            && Preserved->SplitterDirection == Orient_Horizontal);
    };

    Reject(TEXT("Splitter requires two children"), TEXT("<ui version=\"1\"><region name=\"main\"><splitter id=\"split\"><text id=\"only\">Only</text></splitter></region></ui>"), TEXT("invalid child count"));
    Reject(TEXT("Invalid splitter direction rejects"), SplitterMarkup(TEXT("diagonal")), TEXT("splitter direction"), TEXT(".pane {}"));
    Reject(TEXT("Splitter gap must be zero"), SplitterMarkup(TEXT("horizontal"), TEXT("split")), TEXT("splitter cannot use gap"), TEXT(".pane {} .split { gap: 1px; }"));
    Reject(TEXT("Unused template invalid splitter direction rejects"), TEXT("<ui version=\"1\"><template name=\"bad\"><splitter id=\"split\" direction=\"diagonal\"><text id=\"left\">Left</text><text id=\"right\">Right</text></splitter></template><region name=\"main\"><text id=\"ok\">Ok</text></region></ui>"), TEXT("splitter direction"));
    Reject(TEXT("Unused template type-mismatched splitter direction rejects"), TEXT("<ui version=\"1\"><template name=\"bad\"><param name=\"axis\" type=\"number\"/><splitter id=\"split\" direction-param=\"axis\"><text id=\"left\">Left</text><text id=\"right\">Right</text></splitter></template><region name=\"main\"><text id=\"ok\">Ok</text></region></ui>"), TEXT("type-mismatched template parameter"));
    Reject(TEXT("Virtualized table cell rejects splitter"), TEXT("<ui version=\"1\"><region name=\"main\"><table id=\"inventory\" bind=\"rows\"><table-column id=\"name\" label=\"Name\"><splitter id=\"split\"><text id=\"left\" bind-field=\"label\"/><text id=\"right\" bind-field=\"label\"/></splitter></table-column></table></region></ui>"), TEXT("splitter is not valid"));

    const FString TypedTemplate = TEXT("<ui version=\"1\"><template name=\"split\"><param name=\"axis\" type=\"text\"/><splitter id=\"split\" direction-param=\"axis\"><text id=\"left\">Left</text><text id=\"right\">Right</text></splitter></template><region name=\"main\"><use id=\"instance\" template=\"split\" axis=\"vertical\"/></region></ui>");
    const FCkUiLoadResult TypedResult = Parse(TypedTemplate, TEXT(""), Document);
    if (TestTrue(TEXT("Typed text direction parameter expands"), TypedResult.Succeeded))
    {
        const FCkUiNode* TypedSplitter = Document.Regions.Find(TEXT("main"));
        TestTrue(TEXT("Typed splitter is emitted"), TypedSplitter != nullptr && TypedSplitter->Kind == ECkUiNodeKind::Splitter);
        if (TypedSplitter != nullptr) { TestEqual(TEXT("Typed direction resolves to vertical"), TypedSplitter->SplitterDirection, Orient_Vertical); }
    }
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiSplitter_PrepareAtomicity,
    "Ck.UiAuthoring.Splitter.PrepareAtomicity",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiSplitter_PrepareAtomicity::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_splitter_validation;
    if (!FSlateApplication::IsInitialized())
    {
        AddError(TEXT("Splitter preparation test requires initialized Slate."));
        return false;
    }

    const TSharedRef<SCkUiSplitter> Splitter = SNew(SCkUiSplitter).Orientation(Orient_Horizontal);
    const TSharedPtr<SWidget> Left = FreshText(TEXT("Left"));
    const TSharedPtr<SWidget> Right = FreshText(TEXT("Right"));
    FString Failure;
    TUniquePtr<ICkUiPreparedWidgetUpdate> Accepted = Splitter->Prepare(ValidPanes(Left, Right), Failure);
    if (!TestTrue(TEXT("Baseline splitter preparation succeeds"), Accepted.IsValid()) || !TestTrue(TEXT("Baseline preparation has no failure"), Failure.IsEmpty())) { return false; }
    Accepted->Commit();
    const TSharedPtr<SSplitter> Native = Splitter->GetSplitter();
    if (!TestTrue(TEXT("Native splitter is available after commit"), Native.IsValid())) { return false; }
    const FSlotState Baseline = CaptureSlots(Native.ToSharedRef());
    if (!TestTrue(TEXT("Baseline commits two slots with raw authored weights"), Baseline.Count == 2 && Baseline.LeftWeight == 2.0f && Baseline.RightWeight == 3.0f)) { return false; }
    if (!TestTrue(TEXT("Baseline commits pane minima and content"), Baseline.LeftMinimum == 11.0f && Baseline.RightMinimum == 17.0f && Baseline.Left == Left.Get() && Baseline.Right == Right.Get())) { return false; }

    const auto Reject = [this, &Splitter, &Native, &Baseline](const TCHAR* InName, TArray<SCkUiSplitter::FPane> InPanes)
    {
        FString LocalFailure;
        TUniquePtr<ICkUiPreparedWidgetUpdate> Prepared = Splitter->Prepare(MoveTemp(InPanes), LocalFailure);
        TestFalse(InName, Prepared.IsValid());
        TestTrue(*FString::Printf(TEXT("%s reports a failure"), InName), !LocalFailure.IsEmpty());
        TestTrue(*FString::Printf(TEXT("%s does not mutate accepted slots"), InName), IsUnchanged(Baseline, CaptureSlots(Native.ToSharedRef())));
    };

    Reject(TEXT("Null pane content rejects"), {{TEXT("left"), {}, 1.0f, 0.0f}, {TEXT("right"), FreshText(TEXT("Right")), 1.0f, 0.0f}});
    const TSharedPtr<SWidget> Alias = FreshText(TEXT("Alias"));
    Reject(TEXT("Aliased pane content rejects"), {{TEXT("one"), Alias, 1.0f, 0.0f}, {TEXT("two"), Alias, 1.0f, 0.0f}});
    Reject(TEXT("Self-containing splitter pane rejects"), {{TEXT("self"), Splitter, 1.0f, 0.0f}, {TEXT("other"), FreshText(TEXT("Other")), 1.0f, 0.0f}});
    Reject(TEXT("Duplicate pane IDs reject"), {{TEXT("same"), FreshText(TEXT("One")), 1.0f, 0.0f}, {TEXT("same"), FreshText(TEXT("Two")), 1.0f, 0.0f}});
    Reject(TEXT("Nonfinite weight rejects"), {{TEXT("one"), FreshText(TEXT("One")), std::numeric_limits<float>::infinity(), 0.0f}, {TEXT("two"), FreshText(TEXT("Two")), 1.0f, 0.0f}});
    Reject(TEXT("Nonfinite minimum rejects"), {{TEXT("one"), FreshText(TEXT("One")), 1.0f, std::numeric_limits<float>::infinity()}, {TEXT("two"), FreshText(TEXT("Two")), 1.0f, 0.0f}});
    Reject(TEXT("Overflowing total weight rejects"), {{TEXT("one"), FreshText(TEXT("One")), std::numeric_limits<float>::max(), 0.0f}, {TEXT("two"), FreshText(TEXT("Two")), std::numeric_limits<float>::max(), 0.0f}});
    return true;
}

#endif
