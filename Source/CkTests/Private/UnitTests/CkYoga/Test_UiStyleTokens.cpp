#include "CkSlateLayout/CkUiCollection.h"
#include "CkSlateLayout/SCkUiRepeat.h"
#include "CkSlateLayout/SCkUiSurface.h"

#include "Framework/Application/SlateApplication.h"
#include "HAL/FileManager.h"
#include "HAL/PlatformProcess.h"
#include "Misc/AutomationTest.h"
#include "Misc/FileHelper.h"
#include "Misc/Guid.h"
#include "Misc/Paths.h"
#include "Misc/ScopeExit.h"
#include "Widgets/Input/SSearchBox.h"
#include "Widgets/SWindow.h"

#if WITH_DEV_AUTOMATION_TESTS

namespace ck_tests_ui_style_tokens
{
    auto Markup() -> FString
    {
        return TEXT("<ui version=\"1\"><region name=\"main\"><column id=\"root\"><column id=\"content\" class=\"root\"><search id=\"search\" bind=\"query\"/><repeat id=\"records\" bind=\"records\"><text id=\"record-text\" class=\"record-text\" bind-field=\"label\"/></repeat></column></column></region></ui>");
    }

    auto Stylesheet() -> FString
    {
        return TEXT(".root { padding: var(--pad); } .record-text { font-size: var(--size); color: var(--tone); }");
    }

    auto Tick(FSlateApplication& InSlate) -> void { InSlate.PumpMessages(); InSlate.Tick(); InSlate.Tick(); }

    auto MakeData(const TSharedPtr<FCkUiCollection>& InRecords) -> FCkUiView::FDataBindings
    {
        auto Data = FCkUiView::FDataBindings{};
        const TSharedRef<FString> Query = MakeShared<FString>(TEXT("model query"));
        Data.Text.Add(TEXT("query"), TAttribute<FText>::CreateLambda([Query] { return FText::FromString(*Query); }));
        Data.TextChanged.Add(TEXT("query"), FOnTextChanged::CreateLambda([Query](const FText& InText) { *Query = InText.ToString(); }));
        Data.Collections.Add(TEXT("records"), InRecords);
        return Data;
    }

    auto FindSearchBox(const TSharedRef<SWidget>& InRoot) -> TSharedPtr<SSearchBox>
    {
        if (InRoot->GetTypeAsString() == TEXT("SSearchBox")) { return StaticCastSharedRef<SSearchBox>(InRoot); }
        const FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<SSearchBox> Found = FindSearchBox(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index))); Found.IsValid()) { return Found; }
        }
        return nullptr;
    }

    auto FocusPathContains(FSlateApplication& InSlate, const TSharedRef<SWidget>& InWidget) -> bool
    {
        const TSharedPtr<SWidget> Focused = InSlate.GetUserFocusedWidget(0);
        FWidgetPath Path;
        if (!Focused.IsValid() || !InSlate.GeneratePathToWidgetUnchecked(Focused.ToSharedRef(), Path)) { return false; }
        for (int32 PathIndex = 0; PathIndex < Path.Widgets.Num(); ++PathIndex)
        { if (Path.Widgets[PathIndex].Widget == InWidget) { return true; } }
        return false;
    }

    auto TypeDraft(FAutomationTestBase& InTest, FSlateApplication& InSlate, const TSharedRef<SSearchBox>& InSearch, const FString& InText) -> bool
    {
        if (!FocusPathContains(InSlate, InSearch)) { InSlate.SetKeyboardFocus(InSearch, EFocusCause::SetDirectly); }
        Tick(InSlate);
        if (!FocusPathContains(InSlate, InSearch))
        {
            const TSharedPtr<SWidget> Focused = InSlate.GetUserFocusedWidget(0);
            InTest.AddError(FString::Printf(TEXT("Token draft focus did not enter search: focused=%s search-size=%s"),
                Focused.IsValid() ? *Focused->GetTypeAsString() : TEXT("none"), *InSearch->GetCachedGeometry().GetLocalSize().ToString()));
            return false;
        }
        const FModifierKeysState Control{false, false, true, false, false, false, false, false, false};
        if (!InSlate.ProcessKeyDownEvent(FKeyEvent{EKeys::A, Control, 0, false, 0, 0}))
        { InTest.AddError(TEXT("Token draft Ctrl+A was not handled")); return false; }
        for (const TCHAR Character : InText)
        {
            if (!InSlate.ProcessKeyCharEvent(FCharacterEvent{Character, FModifierKeysState{}, 0, false}))
            { InTest.AddError(FString::Printf(TEXT("Token draft character U+%04X was not handled; text=%s"), int32(Character), *InSearch->GetText().ToString())); return false; }
        }
        // SSearchBox debounces OnTextChanged for 0.25 s; GetText reads its bound model, not the edit buffer.
        // Wait on the expected callback result rather than assuming two Slate ticks advance that timer.
        const double Deadline = FPlatformTime::Seconds() + 2.0;
        while (InSearch->GetText().ToString() != InText && FPlatformTime::Seconds() < Deadline)
        {
            Tick(InSlate);
            FPlatformProcess::Sleep(0.01f);
        }
        const bool FocusRetained = FocusPathContains(InSlate, InSearch);
        InTest.AddInfo(FString::Printf(TEXT("Token draft after tick: text=%s expected=%s focused=%s"),
            *InSearch->GetText().ToString(), *InText, FocusRetained ? TEXT("true") : TEXT("false")));
        return InSearch->GetText().ToString() == InText && FocusRetained;
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiAuthoring_StyleTokens,
    "Ck.UiAuthoring.StyleTokens.AcceptedRejectedPoll", EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiAuthoring_StyleTokens::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_style_tokens;
    if (!FSlateApplication::IsInitialized()) { AddError(TEXT("Style token test requires initialized Slate.")); return false; }

    TSharedPtr<FCkUiCollection> Records;
    if (!TestTrue(TEXT("Style token collection creates"), FCkUiCollection::TryCreate({{TEXT("label"), ECkUiFieldKind::Text}}, Records).Succeeded)) { return false; }
    FCkUiRecordData Record;
    Record.Key = TEXT("one");
    FCkUiFieldValue Label;
    Label.Kind = ECkUiFieldKind::Text;
    Label.Text = FText::FromString(TEXT("Stable text"));
    Record.Fields.Add(TEXT("label"), Label);
    if (!TestTrue(TEXT("Record publication succeeds"), Records->TrySetRecords({Record}).Succeeded)) { return false; }

    const FCkUiView::FTokens InitialTokens = {{TEXT("--pad"), TEXT("4px")}, {TEXT("--size"), TEXT("12")}, {TEXT("--tone"), TEXT("#AABBCC")}};
    const TSharedRef<FCkUiView> View = FCkUiView::Create({}, {}, InitialTokens, FSlateFontInfo{}, MakeData(Records));
    FSlateApplication& Slate = FSlateApplication::Get();
    TSharedPtr<SWindow> Window = SNew(SWindow).ClientSize(FVector2D{640.0f, 360.0f}).CreateTitleBar(false).HasCloseButton(false)[View->GetRegion(TEXT("main"))];
    Slate.AddWindow(Window.ToSharedRef(), true);
    ON_SCOPE_EXIT { if (Window.IsValid()) { Slate.DestroyWindowImmediately(Window.ToSharedRef()); } };
    const FCkUiLoadResult InitialResult = View->TryReloadWithTokens(Markup(), Stylesheet(), InitialTokens, TEXT("UiStyleTokensInitial"));
    if (!InitialResult.Succeeded) { AddError(FString::Join(InitialResult.Errors, TEXT("\n"))); }
    if (!TestTrue(TEXT("Initial token document loads"), InitialResult.Succeeded)) { return false; }
    Tick(Slate);
    const TSharedPtr<SCkUiRepeat> Repeat = View->GetRepeat(TEXT("records"));
    const TSharedPtr<SSearchBox> Search = FindSearchBox(View->GetRegion(TEXT("main")));
    if (!TestTrue(TEXT("Repeat and search mount"), Repeat.IsValid() && Search.IsValid())) { return false; }
    const TSharedPtr<SWidget> StableItem = Repeat->GetItemWidget(TEXT("one"));
    if (!TestTrue(TEXT("Repeat item mounts before its geometry is inspected"), StableItem.IsValid())) { return false; }
    if (!TestTrue(TEXT("Search receives a real focused native draft"), TypeDraft(*this, Slate, Search.ToSharedRef(), TEXT("typed draft")))) { return false; }
    const int64 Revision = View->GetRevision();
    const FVector2D Before = StableItem->GetDesiredSize();
    const auto LargerTokens = FCkUiView::FTokens{{TEXT("--pad"), TEXT("8px")}, {TEXT("--size"), TEXT("24")}, {TEXT("--tone"), TEXT("#112233")}};
    if (!TestTrue(TEXT("Accepted token reload succeeds"), View->TryReloadWithTokens(Markup(), Stylesheet(), LargerTokens, TEXT("UiStyleTokensAccepted")).Succeeded)) { return false; }
    Tick(Slate);
    const TSharedPtr<SWidget> AcceptedItem = View->GetRepeat(TEXT("records"))->GetItemWidget(TEXT("one"));
    if (!TestTrue(TEXT("Accepted token reload retains the repeat item before its geometry is inspected"), AcceptedItem.IsValid())) { return false; }
    TestTrue(TEXT("Accepted token reload changes revision and retains item identity"), View->GetRevision() == Revision + 1 && AcceptedItem == StableItem);
    TestTrue(TEXT("Accepted token reload retains the focused search path and native draft"), FocusPathContains(Slate, Search.ToSharedRef()) && Search->GetText().ToString() == TEXT("typed draft"));
    TestTrue(TEXT("Token geometry changes"), AcceptedItem->GetDesiredSize() != Before);

    const int64 RejectedRevision = View->GetRevision();
    const TSharedPtr<SWidget> RejectedItem = AcceptedItem;
    const FVector2D RejectedSize = AcceptedItem->GetDesiredSize();
    const FCkUiLoadResult Rejected = View->TryReloadWithTokens(Markup(), Stylesheet(), {{TEXT("--pad"), TEXT("var(--missing)")}, {TEXT("--size"), TEXT("24")}, {TEXT("--tone"), TEXT("#112233")}}, TEXT("UiStyleTokensRejected"));
    TestFalse(TEXT("Missing token rejects atomically"), Rejected.Succeeded);
    TestEqual(TEXT("Rejected token revision unchanged"), View->GetRevision(), RejectedRevision);
    TestTrue(TEXT("Rejected token identity unchanged"), View->GetRepeat(TEXT("records"))->GetItemWidget(TEXT("one")) == RejectedItem);
    TestTrue(TEXT("Rejected token retains the focused search path and native draft"), FocusPathContains(Slate, Search.ToSharedRef()) && Search->GetText().ToString() == TEXT("typed draft"));
    TestTrue(TEXT("Rejected token geometry unchanged"), RejectedItem->GetDesiredSize() == RejectedSize);

    const TSharedRef<FCkUiView> Other = FCkUiView::Create({}, {}, InitialTokens, FSlateFontInfo{}, MakeData(Records));
    Other->GetRegion(TEXT("main"));
    if (!TestTrue(TEXT("Second batch participant loads its baseline"), Other->TryReloadWithTokens(Markup(), Stylesheet(), InitialTokens, TEXT("UiStyleTokensBatchBaseline")).Succeeded)) { return false; }
    const int64 BatchRevision = View->GetRevision();
    FCkUiView::FReloadRequest First{View, Markup(), Stylesheet(), TEXT("UiStyleTokensBatchFirst")};
    First.Tokens = InitialTokens;
    FCkUiView::FReloadRequest Second{Other, Markup(), Stylesheet(), TEXT("UiStyleTokensBatchSecond")};
    Second.Tokens = FCkUiView::FTokens{{TEXT("--pad"), TEXT("var(--missing)")}, {TEXT("--size"), TEXT("12")}, {TEXT("--tone"), TEXT("#AABBCC")}};
    const FCkUiLoadResult BatchRejected = FCkUiView::TryReloadBatch({MoveTemp(First), MoveTemp(Second)});
    TestFalse(TEXT("Invalid second token participant rejects the entire batch"), BatchRejected.Succeeded);
    TestEqual(TEXT("Rejected token batch preserves first revision"), View->GetRevision(), BatchRevision);
    if (!TestTrue(TEXT("Ordinary reload after rejected batch still uses first participant's applied tokens"), View->TryReload(Markup(), Stylesheet(), TEXT("UiStyleTokensPostBatch")).Succeeded)) { return false; }
    Tick(Slate);
    const TSharedPtr<SWidget> PostBatchItem = View->GetRepeat(TEXT("records"))->GetItemWidget(TEXT("one"));
    if (!TestTrue(TEXT("Post-batch ordinary reload retains its repeat item before geometry is inspected"), PostBatchItem.IsValid())) { return false; }
    TestTrue(TEXT("Post-batch ordinary reload keeps the prior token geometry"), PostBatchItem->GetDesiredSize() == RejectedSize);

    const FString Directory = FPaths::Combine(FPaths::ProjectSavedDir(), TEXT("Automation"),
        FString::Printf(TEXT("UiStyleTokens-%s"), *FGuid::NewGuid().ToString(EGuidFormats::Digits)));
    if (!TestTrue(TEXT("Unique token poll directory creates"), IFileManager::Get().MakeDirectory(*Directory, true))) { return false; }
    const FString MarkupPath = FPaths::Combine(Directory, TEXT("StyleTokens.ui.html"));
    const FString StylesPath = FPaths::Combine(Directory, TEXT("StyleTokens.ui.css"));
    ON_SCOPE_EXIT
    {
        IFileManager::Get().Delete(*MarkupPath, false, true, true);
        IFileManager::Get().Delete(*StylesPath, false, true, true);
        IFileManager::Get().DeleteDirectory(*Directory, false, false);
    };
    TestTrue(TEXT("Markup fixture writes"), FFileHelper::SaveStringToFile(Markup(), *MarkupPath));
    TestTrue(TEXT("Stylesheet fixture writes"), FFileHelper::SaveStringToFile(Stylesheet(), *StylesPath));
    View->SetFiles(MarkupPath, StylesPath);
    const int64 BaselinePollRevision = View->GetRevision();
    TestTrue(TEXT("Initial file poll establishes the baseline source pair"), View->PollFiles(LargerTokens));
    TestTrue(TEXT("Baseline file poll advances revision"), View->GetRevision() == BaselinePollRevision + 1);
    const int64 PollRevision = View->GetRevision();
    TestTrue(TEXT("Unchanged file pair with changed tokens reloads"), View->PollFiles(InitialTokens));
    TestTrue(TEXT("Changed token poll advances revision"), View->GetRevision() == PollRevision + 1);
    const int64 DuplicateRevision = View->GetRevision();
    TestFalse(TEXT("Identical token poll is deduplicated"), View->PollFiles(InitialTokens));
    TestEqual(TEXT("Identical token poll preserves revision"), View->GetRevision(), DuplicateRevision);
    const auto InvalidTokens = FCkUiView::FTokens{{TEXT("--pad"), TEXT("var(--missing)")}, {TEXT("--size"), TEXT("12")}, {TEXT("--tone"), TEXT("#AABBCC")}};
    const int64 InvalidPollRevision = View->GetRevision();
    TestTrue(TEXT("Invalid token poll records its candidate failure"), View->PollFiles(InvalidTokens));
    TestFalse(TEXT("Invalid token poll rejects without publication"), View->GetLastResult().Succeeded);
    TestEqual(TEXT("Invalid token poll preserves revision"), View->GetRevision(), InvalidPollRevision);
    TestFalse(TEXT("Identical invalid token poll is deduplicated"), View->PollFiles(InvalidTokens));
    TestEqual(TEXT("Deduplicated invalid poll preserves revision"), View->GetRevision(), InvalidPollRevision);
    return true;
}

#endif
