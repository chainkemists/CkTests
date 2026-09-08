#include "CkSlateLayout/CkUiTextInput.h"
#include "CkSlateLayout/SCkUiSurface.h"
#include "CkSlateLayout/SCkUiTabs.h"

#include "Framework/Application/SlateApplication.h"
#include "Input/Events.h"
#include "InputCoreTypes.h"
#include "Layout/Children.h"
#include "Misc/AutomationTest.h"
#include "Styling/CoreStyle.h"
#include "Widgets/Input/SEditableTextBox.h"
#include "Widgets/Layout/SScrollBox.h"
#include "Widgets/SWindow.h"

#if WITH_DEV_AUTOMATION_TESTS

namespace ck_tests_ui_tabs_panel_state
{
    auto EditorPanel() -> FString
    {
        return TEXT("<tab id=\"editor\" key=\"editor\" label=\"Editor\"><column id=\"editor-panel\"><text-input id=\"note\" value-bind=\"note\" committed=\"commit-note\" placeholder=\"Draft note\"/><scroll id=\"note-scroll\" direction=\"vertical\" class=\"scroll\"><column id=\"scroll-content\"><text id=\"scroll-copy\" class=\"copy\" bind=\"body\"/></column></scroll></column></tab>");
    }

    auto OtherPanel() -> FString
    {
        return TEXT("<tab id=\"other\" key=\"other\" label=\"Other\"><column id=\"other-panel\"><text id=\"other-copy\">Other panel</text></column></tab>");
    }

    auto Markup(const bool bReverseTabs = false) -> FString
    {
        const FString First = bReverseTabs ? OtherPanel() : EditorPanel();
        const FString Second = bReverseTabs ? EditorPanel() : OtherPanel();
        return FString::Printf(TEXT("<ui version=\"1\"><region name=\"main\"><tabs id=\"tabs\" value-bind=\"active\" changed=\"activate\">%s%s</tabs></region></ui>"), *First, *Second);
    }

    auto Styles() -> FString
    {
        return TEXT(".scroll { height: 120px; } .copy { text-wrap: wrap; text-overflow: clip; }");
    }

    auto LongBody() -> FString
    {
        FString Result;
        for (int32 Index = 0; Index < 48; ++Index)
        {
            Result += TEXT("This is overflowing authored tab content that must remain mounted with its native scroll position. ");
        }
        return Result;
    }

    auto FindInput(const TSharedRef<SWidget>& InRoot) -> TSharedPtr<SEditableTextBox>
    {
        if (InRoot->GetTag() == TEXT("note") && (InRoot->GetTypeAsString() == TEXT("SEditableTextBox") || InRoot->GetTypeAsString() == TEXT("SCkUiTextInputBox"))) { return StaticCastSharedRef<SEditableTextBox>(InRoot); }
        const FChildren* Children = InRoot->GetChildren();
        if (Children == nullptr) { return nullptr; }
        for (int32 Index = 0; Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<SEditableTextBox> Found = FindInput(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index))); Found.IsValid()) { return Found; }
        }
        return nullptr;
    }

    auto Tick(FSlateApplication& InSlate) -> void { InSlate.PumpMessages(); InSlate.Tick(); InSlate.Tick(); }

    auto HasInputFocus(FSlateApplication& InSlate, const TSharedRef<SEditableTextBox>& InInput) -> bool
    {
        return InSlate.GetUserFocusedWidget(0) == InInput || InSlate.HasUserFocusedDescendants(InInput, 0);
    }

    auto ReplaceText(FSlateApplication& InSlate, const TSharedRef<SEditableTextBox>& InInput, const FString& InText) -> bool
    {
        InSlate.SetUserFocus(0, InInput, EFocusCause::SetDirectly);
        Tick(InSlate);
        const FModifierKeysState Control{false, false, true, false, false, false, false, false, false};
        if (!InSlate.ProcessKeyDownEvent(FKeyEvent{EKeys::A, Control, 0, false, 0, 0})) { return false; }
        for (const TCHAR Character : InText)
        {
            if (!InSlate.ProcessKeyCharEvent(FCharacterEvent{Character, FModifierKeysState{}, 0, false})) { return false; }
        }
        Tick(InSlate);
        return true;
    }

    struct FWindowScope final
    {
        explicit FWindowScope(FSlateApplication& InSlate) : Slate(InSlate) {}
        ~FWindowScope() { if (Window.IsValid()) { Slate.DestroyWindowImmediately(Window.ToSharedRef()); } }
        FSlateApplication& Slate;
        TSharedPtr<SWindow> Window;
    };
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiTabs_PanelState,
    "Ck.UiAuthoring.Tabs.PanelStateRetention",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiTabs_PanelState::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_tabs_panel_state;
    if (!FSlateApplication::IsInitialized()) { AddError(TEXT("Tabs panel-state test requires Slate.")); return false; }

    auto Registry = FCkUiWidgetRegistry{};
    if (!TestTrue(TEXT("Shared text input registration succeeds"), FCkUiTextInput::Register(Registry).Succeeded)) { return false; }

    FString Active = TEXT("editor");
    FString Note = TEXT("Initial note");
    FString Body = LongBody();
    int32 CommitCalls = 0;
    ETextCommit::Type CommitReason = ETextCommit::Default;
    auto Data = FCkUiView::FDataBindings{};
    Data.String.Add(TEXT("active"), TAttribute<FString>::CreateLambda([&Active]() { return Active; }));
    Data.Text.Add(TEXT("note"), TAttribute<FText>::CreateLambda([&Note]() { return FText::FromString(Note); }));
    Data.Text.Add(TEXT("body"), TAttribute<FText>::CreateLambda([&Body]() { return FText::FromString(Body); }));
    Data.StringChanged.Add(TEXT("activate"), FCkUiOnStringChanged::CreateLambda([&Active](const FString& InKey) { Active = InKey; }));
    Data.TextCommitted.Add(TEXT("commit-note"), FOnTextCommitted::CreateLambda([&Note, &CommitCalls, &CommitReason](const FText& InText, const ETextCommit::Type InReason)
    {
        Note = InText.ToString();
        ++CommitCalls;
        CommitReason = InReason;
    }));

    const TSharedRef<FCkUiView> View = FCkUiView::Create({}, {}, {}, FCoreStyle::GetDefaultFontStyle(TEXT("Regular"), 12), MoveTemp(Data), Registry.CreateSnapshot());
    const TSharedRef<SWidget> Region = View->GetRegion(TEXT("main"));
    FSlateApplication& Slate = FSlateApplication::Get();
    FWindowScope Scope{Slate};
    Scope.Window = SNew(SWindow).AutoCenter(EAutoCenter::None).ClientSize(FVector2D{320.0f, 220.0f}).CreateTitleBar(false).HasCloseButton(false)[Region];
    Slate.AddWindow(Scope.Window.ToSharedRef(), true);
    if (!TestTrue(TEXT("Production tabs with registered editor and scroll load"), View->TryReload(Markup(), Styles(), TEXT("UiTabsPanelState")).Succeeded)) { return false; }
    Tick(Slate);

    // Initial tab selection is applied on Tick; allow the newly visible subtree to arrange before measuring.
    for (int32 Frame = 0; Frame < 3; ++Frame) { Tick(Slate); }
    const TSharedPtr<SCkUiTabs> Tabs = View->GetTabs(TEXT("tabs"));
    const TSharedPtr<SEditableTextBox> Input = FindInput(Region);
    const TSharedPtr<SScrollBox> Scroll = View->GetScroll(TEXT("note-scroll"));
    if (!TestTrue(TEXT("First authored tab mounts the native editor and real scroll"), Tabs.IsValid() && Input.IsValid() && Scroll.IsValid())) { return false; }

    if (!TestTrue(*FString::Printf(TEXT("Authored scroll exceeds viewport (extent=%g, width=%g, height=%g)"), Scroll->GetScrollOffsetOfEnd(), Scroll->GetCachedGeometry().GetLocalSize().X, Scroll->GetCachedGeometry().GetLocalSize().Y), Scroll->GetScrollOffsetOfEnd() > 0.0f)) { return false; }
    Scroll->SetScrollOffset(120.0f);
    Tick(Slate);
    const float ScrollOffset = Scroll->GetScrollOffset();
    if (!TestTrue(TEXT("Overflowing authored scroll has a nonzero mounted native offset"), ScrollOffset > 0.0f)) { return false; }

    if (!TestTrue(TEXT("Native key characters create an uncommitted editor draft"), ReplaceText(Slate, Input.ToSharedRef(), TEXT("Draft before reorder")))) { return false; }
    if (!TestTrue(TEXT("Draft remains local before any native commit"), Input->GetText().ToString() == TEXT("Draft before reorder") && Note == TEXT("Initial note") && CommitCalls == 0 && HasInputFocus(Slate, Input.ToSharedRef()))) { return false; }

    const int64 RevisionBeforeReorder = View->GetRevision();
    if (!TestTrue(TEXT("Compatible reversed tab order reload succeeds while editing"), View->TryReload(Markup(true), Styles(), TEXT("UiTabsPanelStateReordered")).Succeeded)) { return false; }
    Tick(Slate);
    TestTrue(TEXT("Focused compatible reorder preserves editor identity and uncommitted draft"), View->GetRevision() == RevisionBeforeReorder + 1 && View->GetTabs(TEXT("tabs")) == Tabs
        && FindInput(Region) == Input && HasInputFocus(Slate, Input.ToSharedRef()) && Input->GetText().ToString() == TEXT("Draft before reorder") && Note == TEXT("Initial note") && CommitCalls == 0);
    TestTrue(*FString::Printf(TEXT("Focused compatible reorder preserves scroll identity and offset (expected=%g, actual=%g, extent=%g)"), ScrollOffset, Scroll->GetScrollOffset(), Scroll->GetScrollOffsetOfEnd()), View->GetScroll(TEXT("note-scroll")) == Scroll && FMath::IsNearlyEqual(Scroll->GetScrollOffset(), ScrollOffset));
    TestEqual(TEXT("Compatible reordered tabs keep the stable selected model key"), Active, FString(TEXT("editor")));

    Active = TEXT("other");
    Tick(Slate);
    TestTrue(TEXT("Switching the model away commits the focused editor through native focus loss"), Active == TEXT("other") && Note == TEXT("Draft before reorder")
        && CommitCalls == 1 && CommitReason == ETextCommit::Default && View->GetScroll(TEXT("note-scroll")) == Scroll && FMath::IsNearlyEqual(Scroll->GetScrollOffset(), ScrollOffset));

    Active = TEXT("editor");
    Tick(Slate);
    TestTrue(TEXT("Switching back retains the accepted editor identity, model text, scroll identity, and offset"), Active == TEXT("editor") && FindInput(Region) == Input
        && Input->GetText().ToString() == TEXT("Draft before reorder") && Note == TEXT("Draft before reorder") && View->GetScroll(TEXT("note-scroll")) == Scroll && FMath::IsNearlyEqual(Scroll->GetScrollOffset(), ScrollOffset));

    const int64 AcceptedRevision = View->GetRevision();
    const FCkUiLoadResult Malformed = View->TryReload(Markup(true).Replace(TEXT("value-bind=\"active\""), TEXT("value-bind=\"missing\"")), Styles(), TEXT("UiTabsPanelStateMalformed"));
    Tick(Slate);
    TestTrue(TEXT("Malformed tabs reload preserves the accepted revision and surviving state"), !Malformed.Succeeded && View->GetRevision() == AcceptedRevision && Active == TEXT("editor")
        && View->GetTabs(TEXT("tabs")) == Tabs && FindInput(Region) == Input && Input->GetText().ToString() == TEXT("Draft before reorder")
        && Note == TEXT("Draft before reorder") && View->GetScroll(TEXT("note-scroll")) == Scroll && FMath::IsNearlyEqual(Scroll->GetScrollOffset(), ScrollOffset));

    Slate.DestroyWindowImmediately(Scope.Window.ToSharedRef());
    Scope.Window.Reset();
    return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS
