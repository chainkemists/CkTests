#include "CkSlateLayout/CkUiTextInput.h"
#include "CkSlateLayout/SCkUiSurface.h"

#include "Framework/Application/SlateApplication.h"
#include "Input/Events.h"
#include "InputCoreTypes.h"
#include "Layout/Children.h"
#include "Misc/AutomationTest.h"
#include "Styling/CoreStyle.h"
#include "Widgets/Input/SEditableTextBox.h"
#include "Widgets/SWindow.h"

#if WITH_DEV_AUTOMATION_TESTS

namespace ck_tests_ui_text_input
{
    auto Markup(const TCHAR* InValueBinding = TEXT("value")) -> FString
    {
        return FString::Printf(TEXT("<ui version=\"1\"><region name=\"main\"><column id=\"root\"><text-input id=\"input\" value-bind=\"%s\" committed=\"commit\" changed=\"change\" placeholder=\"Type here\" read-only-bind=\"read-only\" enabled-bind=\"enabled\" error-bind=\"error\"/></column></region></ui>"), InValueBinding);
    }

    auto FindInput(const TSharedRef<SWidget>& InRoot) -> TSharedPtr<SEditableTextBox>
    {
        if (InRoot->GetTag() == TEXT("input") && (InRoot->GetTypeAsString() == TEXT("SEditableTextBox") || InRoot->GetTypeAsString() == TEXT("SCkUiTextInputBox"))) { return StaticCastSharedRef<SEditableTextBox>(InRoot); }
        const FChildren* Children = InRoot->GetChildren();
        if (Children == nullptr) { return nullptr; }
        for (int32 Index = 0; Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<SEditableTextBox> Found = FindInput(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index))); Found.IsValid()) { return Found; }
        }
        return nullptr;
    }

    auto Tick(FSlateApplication& InSlate) -> void { InSlate.PumpMessages(); InSlate.Tick(); InSlate.Tick(); }
    auto Key(const FKey InKey) -> FKeyEvent { return FKeyEvent(InKey, FModifierKeysState{}, 0, false, 0, 0); }
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

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiTextInput_Runtime,
    "Ck.UiAuthoring.TextInput.RetainedDraftAndCommit",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiTextInput_Runtime::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_text_input;
    if (!FSlateApplication::IsInitialized()) { AddError(TEXT("Text input test requires Slate.")); return false; }

    auto Registry = FCkUiWidgetRegistry{};
    if (!TestTrue(TEXT("Shared text-input registration succeeds"), FCkUiTextInput::Register(Registry).Succeeded)) { return false; }
    FString Value = TEXT("Initial");
    FString OtherValue = TEXT("Other");
    FString Error;
    bool ReadOnly = false;
    bool Enabled = true;
    int32 ChangedCalls = 0;
    int32 CommittedCalls = 0;
    int32 CommitReloads = 0;
    bool CommitReloadSucceeded = true;
    TSharedPtr<FCkUiView> View;
    auto Data = FCkUiView::FDataBindings{};
    Data.Text.Add(TEXT("value"), TAttribute<FText>::CreateLambda([&Value]() { return FText::FromString(Value); }));
    Data.Text.Add(TEXT("other"), TAttribute<FText>::CreateLambda([&OtherValue]() { return FText::FromString(OtherValue); }));
    Data.Text.Add(TEXT("error"), TAttribute<FText>::CreateLambda([&Error]() { return FText::FromString(Error); }));
    Data.Visibility.Add(TEXT("read-only"), TAttribute<bool>::CreateLambda([&ReadOnly]() { return ReadOnly; }));
    Data.Visibility.Add(TEXT("enabled"), TAttribute<bool>::CreateLambda([&Enabled]() { return Enabled; }));
    Data.TextChanged.Add(TEXT("change"), FOnTextChanged::CreateLambda([&ChangedCalls](const FText&) { ++ChangedCalls; }));
    Data.TextCommitted.Add(TEXT("commit"), FOnTextCommitted::CreateLambda([&Value, &Error, &CommittedCalls, &CommitReloads, &CommitReloadSucceeded, &View](const FText& InText, ETextCommit::Type)
    {
        ++CommittedCalls;
        if (InText.ToString() != TEXT("Accepted"))
        {
            Error = TEXT("Rejected by model");
            return;
        }
        Value = InText.ToString();
        Error.Reset();
        ++CommitReloads;
        CommitReloadSucceeded &= View.IsValid() && View->TryReload(Markup(), TEXT(""), TEXT("UiTextInputCommitReload")).Succeeded;
    }));
    View = FCkUiView::Create({}, {}, {}, FCoreStyle::GetDefaultFontStyle(TEXT("Regular"), 12), MoveTemp(Data), Registry.CreateSnapshot());
    TSharedPtr<SWidget> Region = View->GetRegion(TEXT("main"));
    FSlateApplication& Slate = FSlateApplication::Get();
    FWindowScope Scope{Slate};
    Scope.Window = SNew(SWindow).AutoCenter(EAutoCenter::None).ClientSize(FVector2D{320.0f, 120.0f}).CreateTitleBar(false).HasCloseButton(false)[Region.ToSharedRef()];
    Slate.AddWindow(Scope.Window.ToSharedRef(), true);
    if (!TestTrue(TEXT("Registered retained text input loads"), View->TryReload(Markup(), TEXT(""), TEXT("UiTextInput")).Succeeded)) { return false; }
    Tick(Slate);
    const TSharedPtr<SEditableTextBox> Input = FindInput(Region.ToSharedRef());
    if (!TestTrue(TEXT("Authored text input exposes native editable textbox"), Input.IsValid())) { return false; }
    TestEqual(TEXT("Initial construction emits no changed events"), ChangedCalls, 0);
    ReadOnly = true;
    Enabled = false;
    Tick(Slate);
    TestTrue(TEXT("Read-only binding updates the native editor"), Input->IsReadOnly());
    TestFalse(TEXT("Enabled binding updates the native widget"), Input->IsEnabled());
    ReadOnly = false;
    Enabled = true;
    Tick(Slate);
    TestTrue(TEXT("Input returns to enabled editable state"), !Input->IsReadOnly() && Input->IsEnabled());
    if (!TestTrue(TEXT("Native keyboard enters a rejected draft"), ReplaceText(Slate, Input.ToSharedRef(), TEXT("Rejected")))) { return false; }
    TestTrue(TEXT("Native edit updates local draft and changed callback"), Input->GetText().ToString() == TEXT("Rejected") && ChangedCalls > 0);
    TestTrue(TEXT("Native Enter commits the rejected draft"), Slate.ProcessKeyDownEvent(Key(EKeys::Enter)));
    Tick(Slate);
    TestTrue(TEXT("Rejected commit restores authoritative model value and error"), CommittedCalls == 1 && Input->GetText().ToString() == TEXT("Initial") && Input->HasError());
    if (!TestTrue(TEXT("Native keyboard enters an accepted draft"), ReplaceText(Slate, Input.ToSharedRef(), TEXT("Accepted")))) { return false; }
    TestTrue(TEXT("Native Enter commits the accepted draft"), Slate.ProcessKeyDownEvent(Key(EKeys::Enter)));
    Tick(Slate);
    TestTrue(TEXT("Accepted reentrant reload displays updated authoritative value"), CommitReloadSucceeded && CommitReloads == 1 && Value == TEXT("Accepted") && Input->GetText().ToString() == TEXT("Accepted"));
    Value = TEXT("Idle external update");
    Tick(Slate);
    TestEqual(TEXT("Idle input follows external model changes"), Input->GetText().ToString(), FString(TEXT("Idle external update")));
    TestFalse(TEXT("Accepted model clears the bound error"), Input->HasError());
    Error = TEXT("External validation error");
    Tick(Slate);
    TestTrue(TEXT("Error binding updates without a text reset"), Input->HasError());
    Error.Reset();
    Tick(Slate);
    TestFalse(TEXT("Cleared error binding removes feedback"), Input->HasError());

    const int64 AcceptedRevision = View->GetRevision();
    const FCkUiLoadResult Retarget = View->TryReload(Markup(TEXT("other")), TEXT(""), TEXT("UiTextInputRetarget"));
    TestFalse(TEXT("Retargeting retained value binding rejects"), Retarget.Succeeded);
    TestEqual(TEXT("Retarget rejection preserves the view"), View->GetRevision(), AcceptedRevision);

    if (!TestTrue(TEXT("Native keyboard enters a draft before reload"), ReplaceText(Slate, Input.ToSharedRef(), TEXT("Draft")))) { return false; }
    TestTrue(TEXT("Native Left moves the draft caret"), Slate.ProcessKeyDownEvent(Key(EKeys::Left)) && Slate.ProcessKeyDownEvent(Key(EKeys::Left)));
    const TSharedPtr<SWidget> FocusBeforeReload = Slate.GetUserFocusedWidget(0);
    if (!TestTrue(TEXT("Valid reload succeeds while editing"), View->TryReload(Markup(), TEXT(""), TEXT("UiTextInputDraftReload")).Succeeded)) { return false; }
    Tick(Slate);
    TestTrue(TEXT("Accepted reload retains the editor, focus, and draft"), FindInput(Region.ToSharedRef()) == Input && Slate.GetUserFocusedWidget(0) == FocusBeforeReload && Input->GetText().ToString() == TEXT("Draft"));
    TestTrue(TEXT("Retained draft keeps its caret after reload"), Slate.ProcessKeyCharEvent(FCharacterEvent{TEXT('X'), FModifierKeysState{}, 0, false}));
    Tick(Slate);
    TestEqual(TEXT("Reload does not move the draft caret to the end"), Input->GetText().ToString(), FString(TEXT("DraXft")));
    TestEqual(TEXT("Accepted reload does not synthesize a commit"), CommittedCalls, 2);
    const FCkUiLoadResult FocusedRetarget = View->TryReload(Markup(TEXT("other")), TEXT(""), TEXT("UiTextInputFocusedRetarget"));
    Tick(Slate);
    TestTrue(TEXT("Focused retarget rejection preserves draft and focus"), !FocusedRetarget.Succeeded && FindInput(Region.ToSharedRef()) == Input && Slate.GetUserFocusedWidget(0) == FocusBeforeReload && Input->GetText().ToString() == TEXT("DraXft"));
    Value = TEXT("External");
    Tick(Slate);
    TestEqual(TEXT("External model change does not overwrite active draft"), Input->GetText().ToString(), FString(TEXT("DraXft")));
    TestTrue(TEXT("Native Escape cancels the draft"), Slate.ProcessKeyDownEvent(Key(EKeys::Escape)));
    Tick(Slate);
    TestTrue(TEXT("Escape cancels draft without committing"), Input->GetText().ToString() == TEXT("External") && CommittedCalls == 2);
    if (!TestTrue(TEXT("Native keyboard remains usable after escape"), ReplaceText(Slate, Input.ToSharedRef(), TEXT("Accepted")))) { return false; }
    TestTrue(TEXT("Native Enter commits after Escape"), Slate.ProcessKeyDownEvent(Key(EKeys::Enter)));
    Tick(Slate);
    TestTrue(TEXT("Escape does not suppress the next commit"), CommittedCalls == 3 && CommitReloads == 2 && Value == TEXT("Accepted"));
    if (!TestTrue(TEXT("Native keyboard creates a draft for focus-loss commit"), ReplaceText(Slate, Input.ToSharedRef(), TEXT("Accepted")))) { return false; }
    Slate.ClearUserFocus(0, EFocusCause::Navigation);
    Tick(Slate);
    TestEqual(TEXT("Navigation focus loss commits a new draft exactly once"), CommittedCalls, 4);
    TestTrue(TEXT("Focus-loss commit retains reentrant reload behavior"), CommitReloadSucceeded && CommitReloads == 3);
    const int32 ChangedBeforeRelease = ChangedCalls;
    Slate.DestroyWindowImmediately(Scope.Window.ToSharedRef());
    Scope.Window.Reset();
    Region.Reset();
    View.Reset();
    Input->SetText(FText::FromString(TEXT("Released")));
    TestEqual(TEXT("Released retained owner leaves no live text callback"), ChangedCalls, ChangedBeforeRelease);
    return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS
