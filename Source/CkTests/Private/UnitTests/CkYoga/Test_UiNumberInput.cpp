#include "CkSlateLayout/CkUiNumberInput.h"
#include "CkSlateLayout/SCkUiSurface.h"

#include "Framework/Application/SlateApplication.h"
#include "Input/Events.h"
#include "InputCoreTypes.h"
#include "Misc/AutomationTest.h"
#include "Styling/CoreStyle.h"
#include "Widgets/Input/SEditableTextBox.h"
#include "Widgets/SWindow.h"

#include <limits>

#if WITH_DEV_AUTOMATION_TESTS

namespace ck_tests_ui_number_input
{
    auto Markup(const FString& InAttributes = TEXT("")) -> FString
    {
        return FString::Printf(TEXT("<ui version=\"1\"><region name=\"main\"><column id=\"root\"><number-input id=\"input\" value-bind=\"value\" committed=\"commit\" changed=\"change\" enabled-bind=\"enabled\" read-only-bind=\"readonly\" error-bind=\"error\" %s/></column></region></ui>"), *InAttributes);
    }

    auto FindInput(const TSharedRef<SWidget>& InRoot) -> TSharedPtr<SEditableTextBox>
    {
        if (InRoot->GetTag() == TEXT("input") && InRoot->GetTypeAsString() == TEXT("SCkUiTextInputBox"))
        { return StaticCastSharedRef<SEditableTextBox>(InRoot); }
        const FChildren* Children = InRoot->GetChildren();
        if (Children == nullptr) { return nullptr; }
        for (int32 Index = 0; Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<SEditableTextBox> Found = FindInput(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index))); Found.IsValid()) { return Found; }
        }
        return nullptr;
    }

    auto Tick(FSlateApplication& InSlate) -> void { InSlate.PumpMessages(); InSlate.Tick(); InSlate.Tick(); }
    auto Key(const FKey InKey) -> FKeyEvent { return FKeyEvent{InKey, FModifierKeysState{}, 0, false, 0, 0}; }

    struct FFixture final
    {
        FFixture() : Slate(FSlateApplication::Get()) {}
        ~FFixture()
        {
            if (Window.IsValid()) { Slate.DestroyWindowImmediately(Window.ToSharedRef()); }
            View.Reset();
        }

        auto Initialize(const FString& InAttributes = TEXT("")) -> bool
        {
            auto Registry = FCkUiWidgetRegistry{};
            if (!FCkUiNumberInput::Register(Registry).Succeeded) { return false; }
            auto Data = FCkUiView::FDataBindings{};
            Data.Number.Add(TEXT("value"), TAttribute<float>::CreateLambda([this]() { return Value; }));
            Data.Number.Add(TEXT("other"), TAttribute<float>(2.0f));
            Data.Visibility.Add(TEXT("enabled"), TAttribute<bool>::CreateLambda([this]() { return Enabled; }));
            Data.Visibility.Add(TEXT("readonly"), TAttribute<bool>::CreateLambda([this]() { return ReadOnly; }));
            Data.Text.Add(TEXT("error"), TAttribute<FText>::CreateLambda([this]() { return FText::FromString(Error); }));
            Data.NumberChanged.Add(TEXT("change"), FCkUiOnNumberChanged::CreateLambda([this](const float InValue)
            { ++ChangedCalls; LastChanged = InValue; }));
            Data.NumberCommitted.Add(TEXT("commit"), FCkUiOnNumberCommitted::CreateLambda([this](const float InValue, const ETextCommit::Type InReason)
            {
                ++CommittedCalls;
                Reason = InReason;
                if (!RejectCommit) { Value = InValue; }
                if (ReloadOnCommit) { CommitReloadSucceeded &= View->TryReload(Markup(), TEXT(""), TEXT("NumberCommitReload")).Succeeded; }
            }));
            View = FCkUiView::Create({}, {}, {}, FCoreStyle::GetDefaultFontStyle(TEXT("Regular"), 12), MoveTemp(Data), Registry.CreateSnapshot());
            Region = View->GetRegion(TEXT("main"));
            Window = SNew(SWindow).AutoCenter(EAutoCenter::None).ClientSize(FVector2D{320.0f, 120.0f})
                .CreateTitleBar(false).HasCloseButton(false)[Region.ToSharedRef()];
            Slate.AddWindow(Window.ToSharedRef(), true);
            if (!View->TryReload(Markup(InAttributes), TEXT(""), TEXT("NumberInputInitial")).Succeeded) { return false; }
            Tick(Slate);
            Input = FindInput(Region.ToSharedRef());
            return Input.IsValid();
        }

        auto Replace(const FString& InText) -> bool
        {
            Slate.SetUserFocus(0, Input.ToSharedRef(), EFocusCause::SetDirectly);
            Tick(Slate);
            const FModifierKeysState Control{false, false, true, false, false, false, false, false, false};
            if (!Slate.ProcessKeyDownEvent(FKeyEvent{EKeys::A, Control, 0, false, 0, 0})) { return false; }
            for (const TCHAR Character : InText)
            {
                if (!Slate.ProcessKeyCharEvent(FCharacterEvent{Character, FModifierKeysState{}, 0, false})) { return false; }
            }
            Tick(Slate);
            return true;
        }

        auto Enter() -> void { Slate.ProcessKeyDownEvent(Key(EKeys::Enter)); Tick(Slate); }

        FSlateApplication& Slate;
        float Value = 1.5f;
        float LastChanged = 0.0f;
        bool Enabled = true;
        bool ReadOnly = false;
        bool RejectCommit = false;
        bool ReloadOnCommit = false;
        bool CommitReloadSucceeded = true;
        int32 ChangedCalls = 0;
        int32 CommittedCalls = 0;
        ETextCommit::Type Reason = ETextCommit::Default;
        FString Error;
        TSharedPtr<FCkUiView> View;
        TSharedPtr<SWidget> Region;
        TSharedPtr<SWindow> Window;
        TSharedPtr<SEditableTextBox> Input;
    };
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiNumberInput_Runtime,
    "Ck.UiAuthoring.NumberInput.RetainedNative",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiNumberInput_Runtime::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_number_input;
    if (!FSlateApplication::IsInitialized()) { AddError(TEXT("Numeric input requires Slate.")); return false; }
    FFixture Fixture;
    if (!TestTrue(TEXT("Registered numeric editor mounts"), Fixture.Initialize())) { return false; }
    TestEqual(TEXT("Construction emits no numeric events"), Fixture.ChangedCalls + Fixture.CommittedCalls, 0);
    if (!TestTrue(TEXT("Native keyboard drafts float"), Fixture.Replace(TEXT("2.25")))) { return false; }
    TestEqual(TEXT("Changed event proposes raw valid float"), Fixture.LastChanged, 2.25f);
    Fixture.Value = 8.0f;
    Tick(Fixture.Slate);
    TestEqual(TEXT("External model update cannot overwrite draft"), Fixture.Input->GetText().ToString(), FString(TEXT("2.25")));
    const TSharedPtr<SWidget> Focus = Fixture.Slate.GetUserFocusedWidget(0);
    if (!TestTrue(TEXT("Presentation reload succeeds with active draft"), Fixture.View->TryReload(Markup(TEXT("placeholder=\"Enter value\"")), TEXT(""), TEXT("NumberDraftReload")).Succeeded)) { return false; }
    Tick(Fixture.Slate);
    TestTrue(TEXT("Reload preserves native identity focus and draft"), FindInput(Fixture.Region.ToSharedRef()) == Fixture.Input
        && Fixture.Slate.GetUserFocusedWidget(0) == Focus && Fixture.Input->GetText().ToString() == TEXT("2.25"));
    TestEqual(TEXT("Reload applies new placeholder to retained child"), Fixture.Input->GetHintText().ToString(), FString(TEXT("Enter value")));
    Fixture.ReloadOnCommit = true;
    Fixture.Enter();
    TestTrue(TEXT("Enter commits once with reason and reentrant reload"), Fixture.Value == 2.25f && Fixture.CommittedCalls == 1
        && Fixture.Reason == ETextCommit::OnEnter && Fixture.CommitReloadSucceeded);
    Fixture.ReloadOnCommit = false;

    for (const FString Invalid : {FString(TEXT("12junk")), FString(TEXT("nan")), FString(TEXT("inf")), FString(TEXT("1e999")), FString(TEXT("1e-999")), FString(TEXT("+-1")), FString(TEXT("."))})
    {
        if (!TestTrue(TEXT("Invalid draft can be entered"), Fixture.Replace(Invalid))) { return false; }
        const int32 BeforeCommit = Fixture.CommittedCalls;
        Fixture.Enter();
        TestEqual(*(Invalid + TEXT(" emits no commit")), Fixture.CommittedCalls, BeforeCommit);
        TestTrue(*(Invalid + TEXT(" preserves model value")), Fixture.Value == 2.25f);
        TestTrue(*(Invalid + TEXT(" retains native validation feedback")), Fixture.Input->HasError());
    }
    TestTrue(TEXT("Presentation reload retains invalid-number feedback"), Fixture.View->TryReload(Markup(), TEXT(""), TEXT("NumberErrorReload")).Succeeded);
    Tick(Fixture.Slate);
    TestTrue(TEXT("Reload does not silently clear validation error"), Fixture.Input->HasError());

    Fixture.RejectCommit = true;
    if (!TestTrue(TEXT("Model-rejected draft enters"), Fixture.Replace(TEXT("9")))) { return false; }
    Fixture.Enter();
    TestTrue(TEXT("Rejected proposal restores authoritative display"), Fixture.Value == 2.25f && Fixture.Input->GetText().ToString() == TEXT("2.25"));
    Fixture.RejectCommit = false;
    const int32 BeforeCancel = Fixture.CommittedCalls;
    if (!TestTrue(TEXT("Cancellable draft enters"), Fixture.Replace(TEXT("7")))) { return false; }
    Fixture.Slate.ProcessKeyDownEvent(Key(EKeys::Escape));
    Tick(Fixture.Slate);
    TestTrue(TEXT("Escape restores model without numeric commit"), Fixture.CommittedCalls == BeforeCancel && Fixture.Input->GetText().ToString() == TEXT("2.25"));

    for (const float RoundTrip : {1.0e-8f, 1.2345678e20f})
    {
        Fixture.Value = RoundTrip;
        Tick(Fixture.Slate);
        Fixture.Slate.SetUserFocus(0, Fixture.Input.ToSharedRef(), EFocusCause::SetDirectly);
        Tick(Fixture.Slate);
        Fixture.Enter();
        TestTrue(TEXT("Unedited displayed finite float round-trips exactly"), Fixture.Value == RoundTrip);
    }
    Fixture.Value = std::numeric_limits<float>::infinity();
    Tick(Fixture.Slate);
    TestTrue(TEXT("Nonfinite model is empty with validation feedback"), Fixture.Input->GetText().IsEmpty() && Fixture.Input->HasError());
    Fixture.Value = 3.0f;
    Tick(Fixture.Slate);
    if (!TestTrue(TEXT("Draft enters before readonly transition"), Fixture.Replace(TEXT("6")))) { return false; }
    Fixture.ReadOnly = true;
    Tick(Fixture.Slate);
    const int32 BeforeReadOnly = Fixture.CommittedCalls;
    Fixture.Slate.ClearKeyboardFocus(EFocusCause::Navigation);
    Tick(Fixture.Slate);
    TestEqual(TEXT("Readonly transition prevents pending numeric commit on blur"), Fixture.CommittedCalls, BeforeReadOnly);
    Fixture.ReadOnly = false;
    Fixture.Enabled = false;
    Tick(Fixture.Slate);
    TestFalse(TEXT("Enabled binding disables native editor"), Fixture.Input->IsEnabled());
    Fixture.Slate.ProcessKeyDownEvent(Key(EKeys::Enter));
    TestEqual(TEXT("Disabled input emits no numeric commit"), Fixture.CommittedCalls, BeforeReadOnly);
    Fixture.Enabled = true;
    Tick(Fixture.Slate);

    const int64 Revision = Fixture.View->GetRevision();
    const FString Retarget = Markup().Replace(TEXT("value-bind=\"value\""), TEXT("value-bind=\"other\""));
    TestFalse(TEXT("Retarget rejects under surviving id"), Fixture.View->TryReload(Retarget, TEXT(""), TEXT("NumberRetarget")).Succeeded);
    TestFalse(TEXT("Kind change rejects under surviving id"), Fixture.View->TryReload(Markup(TEXT("kind=\"integer\"")), TEXT(""), TEXT("NumberKindRetarget")).Succeeded);
    TestEqual(TEXT("Rejected configurations preserve revision"), Fixture.View->GetRevision(), Revision);
    const int32 BeforeRelease = Fixture.ChangedCalls + Fixture.CommittedCalls;
    Fixture.View.Reset();
    Fixture.Input->SetText(FText::FromString(TEXT("5")));
    Fixture.Slate.ProcessKeyDownEvent(Key(EKeys::Enter));
    Tick(Fixture.Slate);
    TestEqual(TEXT("Released numeric owner makes held native edit callbacks inert"), Fixture.ChangedCalls + Fixture.CommittedCalls, BeforeRelease);
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiNumberInput_Integer,
    "Ck.UiAuthoring.NumberInput.IntegerBounds",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiNumberInput_Integer::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_number_input;
    if (!FSlateApplication::IsInitialized()) { AddError(TEXT("Integer input requires Slate.")); return false; }
    FFixture Fixture;
    if (!TestTrue(TEXT("Integer editor mounts with fractional bounds"), Fixture.Initialize(TEXT("kind=\"integer\" min=\"0.2\" max=\"4.8\"")))) { return false; }
    for (const TPair<FString, float>& Case : {TPair<FString, float>{TEXT("-5"), 1.0f}, {TEXT("9"), 4.0f}, {TEXT("2.6"), 3.0f}})
    {
        if (!TestTrue(TEXT("Integer draft enters natively"), Fixture.Replace(Case.Key))) { return false; }
        const int32 BeforeCommit = Fixture.CommittedCalls;
        const int32 ChangedBeforeCommit = Fixture.ChangedCalls;
        Fixture.Enter();
        TestEqual(TEXT("Commit normalization emits no synthetic changed event"), Fixture.ChangedCalls, ChangedBeforeCommit);
        TestTrue(TEXT("Integer commit rounds within representable bounds exactly once"), Fixture.Value == Case.Value && Fixture.CommittedCalls == BeforeCommit + 1);
        const int32 ChangedAfterCommit = Fixture.ChangedCalls;
        Fixture.Value = 2.0f;
        Tick(Fixture.Slate);
        TestTrue(TEXT("External model update after normalization stays live without edit echo"), Fixture.Input->GetText().ToString() == TEXT("2") && Fixture.ChangedCalls == ChangedAfterCommit);
    }
    if (!TestTrue(TEXT("Unchanged value enters"), Fixture.Replace(TEXT("2")))) { return false; }
    Fixture.Enter();
    Fixture.Value = 3.0f;
    Tick(Fixture.Slate);
    if (!TestTrue(TEXT("Old committed value is a new edit after external update"), Fixture.Replace(TEXT("2")))) { return false; }
    TestEqual(TEXT("New draft is not mistaken for a stale commit echo"), Fixture.Input->GetText().ToString(), FString(TEXT("2")));
    Fixture.Enter();
    TestTrue(TEXT("Old value can be explicitly committed again"), Fixture.Value == 2.0f);
    const int64 Revision = Fixture.View->GetRevision();
    for (const FString Invalid : {FString(TEXT("kind=\"integer\" min=\"0.2\" max=\"0.8\"")), FString(TEXT("kind=\"integer\" min=\"5\" max=\"2\""))})
    {
        TestFalse(TEXT("Invalid integral interval rejects"), Fixture.View->TryReload(Markup(Invalid), TEXT(""), TEXT("IntegerInvalidBounds")).Succeeded);
        TestEqual(TEXT("Interval rejection preserves revision"), Fixture.View->GetRevision(), Revision);
        TestTrue(TEXT("Interval rejection preserves editor"), FindInput(Fixture.Region.ToSharedRef()) == Fixture.Input);
    }
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiNumberInput_FractionalDigits,
    "Ck.UiAuthoring.NumberInput.FractionalDigits",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiNumberInput_FractionalDigits::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_number_input;
    if (!FSlateApplication::IsInitialized()) { AddError(TEXT("Fractional numeric input requires Slate.")); return false; }
    FFixture Fixture;
    Fixture.Value = 1.2345678f;
    if (!TestTrue(TEXT("Default formatter editor mounts"), Fixture.Initialize())) { return false; }
    const FString DefaultDisplay = FString::Printf(TEXT("%.9g"), static_cast<double>(Fixture.Value));
    TestEqual(TEXT("Omitted fractional-digits preserves round-trip display"), Fixture.Input->GetText().ToString(), DefaultDisplay);

    const int32 ChangedBeforeFormatting = Fixture.ChangedCalls;
    const int32 CommittedBeforeFormatting = Fixture.CommittedCalls;
    const float ValueBeforeFormatting = Fixture.Value;
    const TSharedPtr<SEditableTextBox> Input = Fixture.Input;
    if (!TestTrue(TEXT("Fixed fractional presentation reload succeeds"), Fixture.View->TryReload(Markup(TEXT("fractional-digits=\"2\"")), TEXT(""), TEXT("NumberFixedFractionalDigits")).Succeeded)) { return false; }
    Tick(Fixture.Slate);
    TestTrue(TEXT("Fixed display rounds only presentation without model mutation"), Fixture.Input == Input && Fixture.Input->GetText().ToString() == TEXT("1.23")
        && Fixture.Value == ValueBeforeFormatting && Fixture.ChangedCalls == ChangedBeforeFormatting && Fixture.CommittedCalls == CommittedBeforeFormatting);

    Fixture.Value = 4.5f;
    Tick(Fixture.Slate);
    TestTrue(TEXT("Fixed fractional presentation follows live model values without an edit callback"), Fixture.Input->GetText().ToString() == TEXT("4.50")
        && Fixture.ChangedCalls == ChangedBeforeFormatting && Fixture.CommittedCalls == CommittedBeforeFormatting);
    const float ValueBeforeDraft = Fixture.Value;

    if (!TestTrue(TEXT("Fixed formatter accepts a live draft"), Fixture.Replace(TEXT("3.45678")))) { return false; }
    const TSharedPtr<SWidget> Focus = Fixture.Slate.GetUserFocusedWidget(0);
    if (!TestTrue(TEXT("Fractional precision reload accepts active draft"), Fixture.View->TryReload(Markup(TEXT("fractional-digits=\"4\"")), TEXT(""), TEXT("NumberDraftFractionalDigits")).Succeeded)) { return false; }
    Tick(Fixture.Slate);
    TestTrue(TEXT("Precision reload retains identity focus draft and authoritative model"), Fixture.Input == Input && Fixture.Slate.GetUserFocusedWidget(0) == Focus
        && Fixture.Input->GetText().ToString() == TEXT("3.45678") && Fixture.Value == ValueBeforeDraft);

    const int64 Revision = Fixture.View->GetRevision();
    for (const FString Invalid : {FString(TEXT("fractional-digits=\"2.5\"")), FString(TEXT("fractional-digits=\"7\""))})
    {
        TestFalse(TEXT("Invalid fractional-digits reload rejects atomically"), Fixture.View->TryReload(Markup(Invalid), TEXT(""), TEXT("NumberInvalidFractionalDigits")).Succeeded);
        TestTrue(TEXT("Invalid fractional-digits preserves revision native draft focus and model"), Fixture.View->GetRevision() == Revision
            && Fixture.Input == Input && Fixture.Slate.GetUserFocusedWidget(0) == Focus && Fixture.Input->GetText().ToString() == TEXT("3.45678") && Fixture.Value == ValueBeforeDraft);
    }

    FFixture IntegerFixture;
    IntegerFixture.Value = 2.0f;
    if (!TestTrue(TEXT("Integer formatter accepts zero fractional digits"), IntegerFixture.Initialize(TEXT("kind=\"integer\" fractional-digits=\"0\"")))) { return false; }
    const int64 IntegerRevision = IntegerFixture.View->GetRevision();
    TestFalse(TEXT("Integer formatter rejects nonzero fractional digits"), IntegerFixture.View->TryReload(Markup(TEXT("kind=\"integer\" fractional-digits=\"1\"")), TEXT(""), TEXT("NumberIntegerFractionalDigits")).Succeeded);
    TestTrue(TEXT("Integer fractional rejection preserves accepted native editor and revision"), IntegerFixture.View->GetRevision() == IntegerRevision
        && FindInput(IntegerFixture.Region.ToSharedRef()) == IntegerFixture.Input && IntegerFixture.Input->GetText().ToString() == TEXT("2"));
    return true;
}

#endif
