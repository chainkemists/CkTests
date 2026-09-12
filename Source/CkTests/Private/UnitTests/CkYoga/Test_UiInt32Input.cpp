#include "CkSlateLayout/CkUiInt32Input.h"
#include "CkSlateLayout/CkUiCollection.h"
#include "CkSlateLayout/SCkUiSurface.h"

#include "Framework/Application/SlateApplication.h"
#include "Input/Events.h"
#include "InputCoreTypes.h"
#include "Layout/Children.h"
#include "Layout/WidgetPath.h"
#include "Misc/AutomationTest.h"
#include "Styling/CoreStyle.h"
#include "Widgets/Input/SEditableTextBox.h"
#include "Widgets/SWindow.h"

#if WITH_DEV_AUTOMATION_TESTS

namespace ck_tests_ui_int32_input
{
    auto
        Markup(
            const FString& InAttributes = TEXT(""),
            const FString& InMin = TEXT("-2147483648"),
            const FString& InMax = TEXT("2147483647"))
        -> FString
    {
        return FString::Printf(TEXT("<ui version=\"1\"><region name=\"main\"><column id=\"root\"><int32-input id=\"input\" value-bind=\"value\" committed=\"commit\" min=\"%s\" max=\"%s\" enabled-bind=\"enabled\" read-only-bind=\"readonly\" error-bind=\"error\" %s/></column></region></ui>"), *InMin, *InMax, *InAttributes);
    }

    auto
        FindInput(
            const TSharedRef<SWidget>& InRoot)
        -> TSharedPtr<SEditableTextBox>
    {
        if (InRoot->GetTag() == TEXT("input") && InRoot->GetTypeAsString() == TEXT("SCkUiTextInputBox"))
        { return StaticCastSharedRef<SEditableTextBox>(InRoot); }

        const FChildren* Children = InRoot->GetChildren();
        if (Children == nullptr) { return nullptr; }
        for (int32 Index = 0; Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<SEditableTextBox> Found = FindInput(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index))); Found.IsValid())
            { return Found; }
        }
        return nullptr;
    }

    auto
        FocusPathContains(
            FSlateApplication& InSlate,
            const TSharedRef<SWidget>& InWidget)
        -> bool
    {
        const TSharedPtr<SWidget> Focused = InSlate.GetUserFocusedWidget(0);
        if (!Focused.IsValid()) { return false; }

        FWidgetPath Path;
        if (!InSlate.GeneratePathToWidgetUnchecked(Focused.ToSharedRef(), Path)) { return false; }
        for (int32 Index = 0; Index < Path.Widgets.Num(); ++Index)
        {
            if (Path.Widgets[Index].Widget == InWidget) { return true; }
        }
        return false;
    }

    auto
        Tick(
            FSlateApplication& InSlate)
        -> void
    {
        InSlate.PumpMessages();
        InSlate.Tick();
        InSlate.Tick();
    }

    auto
        Key(
            FKey InKey)
        -> FKeyEvent
    {
        return FKeyEvent{InKey, FModifierKeysState{}, 0, false, 0, 0};
    }

    struct FFixture final
    {
        FFixture()
            : Slate(FSlateApplication::Get())
        {
        }

        ~FFixture()
        {
            if (Window.IsValid()) { Slate.DestroyWindowImmediately(Window.ToSharedRef()); }
            View.Reset();
        }

        auto
            Initialize(
                const FString& InAttributes = TEXT(""),
                const FString& InMin = TEXT("-2147483648"),
                const FString& InMax = TEXT("2147483647"))
            -> bool
        {
            auto Registry = FCkUiWidgetRegistry{};
            if (!FCkUiInt32Input::Register(Registry).Succeeded) { return false; }

            auto Data = FCkUiView::FDataBindings{};
            Data.Integer.Add(TEXT("value"), TAttribute<int32>::CreateLambda([this]() { return Value; }));
            Data.Visibility.Add(TEXT("enabled"), TAttribute<bool>::CreateLambda([this]() { return Enabled; }));
            Data.Visibility.Add(TEXT("readonly"), TAttribute<bool>::CreateLambda([this]() { return ReadOnly; }));
            Data.Text.Add(TEXT("error"), TAttribute<FText>::CreateLambda([this]() { return FText::FromString(Error); }));
            Data.IntegerCommitted.Add(TEXT("commit"), FCkUiOnIntegerCommitted::CreateLambda([this](const int32 InValue, const ETextCommit::Type InReason)
            {
                ++CommittedCalls;
                LastCommitted = InValue;
                Reason = InReason;
                Value = InValue;
            }));

            View = FCkUiView::Create({}, {}, {}, FCoreStyle::GetDefaultFontStyle(TEXT("Regular"), 12), MoveTemp(Data), Registry.CreateSnapshot());
            Region = View->GetRegion(TEXT("main"));
            Window = SNew(SWindow)
                .AutoCenter(EAutoCenter::None)
                .ClientSize(FVector2D{320.0f, 120.0f})
                .CreateTitleBar(false)
                .HasCloseButton(false)
                [Region.ToSharedRef()];
            Slate.AddWindow(Window.ToSharedRef(), true);
            if (!View->TryReload(Markup(InAttributes, InMin, InMax), TEXT(""), TEXT("Int32InputInitial")).Succeeded) { return false; }
            Tick(Slate);
            Input = FindInput(Region.ToSharedRef());
            return Input.IsValid();
        }

        auto
            Replace(
                const FString& InText)
            -> bool
        {
            if (!FocusPathContains(Slate, Input.ToSharedRef()))
            { Slate.SetUserFocus(0, Input.ToSharedRef(), EFocusCause::SetDirectly); }
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
        int32 Value = 16777217;
        int32 LastCommitted = INDEX_NONE;
        int32 CommittedCalls = 0;
        bool Enabled = true;
        bool ReadOnly = false;
        FString Error;
        ETextCommit::Type Reason = ETextCommit::Default;
        TSharedPtr<FCkUiView> View;
        TSharedPtr<SWidget> Region;
        TSharedPtr<SWindow> Window;
        TSharedPtr<SEditableTextBox> Input;
    };
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkUiInt32Input_Runtime,
    "Ck.UiAuthoring.Int32Input.RetainedNative",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto
    FCkUiInt32Input_Runtime::
    RunTest(
        const FString&)
    -> bool
{
    using namespace ck_tests_ui_int32_input;

    if (!FSlateApplication::IsInitialized())
    {
        AddError(TEXT("Int32 input requires Slate."));
        return false;
    }

    FFixture Fixture;
    if (!TestTrue(TEXT("Registered int32 editor mounts"), Fixture.Initialize())) { return false; }
    TestEqual(TEXT("Exact int32 display does not round through float"), Fixture.Input->GetText().ToString(), FString(TEXT("16777217")));
    TestEqual(TEXT("Construction emits no integer commit"), Fixture.CommittedCalls, 0);

    for (const TPair<FString, int32>& Case : {TPair<FString, int32>{TEXT("16777217"), 16777217},
             TPair<FString, int32>{TEXT("-2147483648"), TNumericLimits<int32>::Lowest()},
             TPair<FString, int32>{TEXT("2147483647"), TNumericLimits<int32>::Max()}})
    {
        if (!TestTrue(TEXT("Exact decimal draft enters natively"), Fixture.Replace(Case.Key))) { return false; }
        const int32 BeforeCommit = Fixture.CommittedCalls;
        Fixture.Enter();
        TestTrue(TEXT("Exact decimal transport preserves all int32 bits"), Fixture.Value == Case.Value && Fixture.LastCommitted == Case.Value
            && Fixture.CommittedCalls == BeforeCommit + 1 && Fixture.Reason == ETextCommit::OnEnter);
    }

    for (const TPair<FString, int32>& Case : {TPair<FString, int32>{TEXT("16777216.6"), 16777217},
             TPair<FString, int32>{TEXT("2.147483648e9"), TNumericLimits<int32>::Max()},
             TPair<FString, int32>{TEXT("-2.147483649e9"), TNumericLimits<int32>::Lowest()}})
    {
        if (!TestTrue(TEXT("Finite decimal or exponent draft enters"), Fixture.Replace(Case.Key))) { return false; }
        const int32 BeforeCommit = Fixture.CommittedCalls;
        Fixture.Enter();
        TestTrue(TEXT("Finite values round then clamp before int32 conversion"), Fixture.Value == Case.Value && Fixture.LastCommitted == Case.Value
            && Fixture.CommittedCalls == BeforeCommit + 1);
    }

    {
        FFixture BoundedFixture;
        if (!TestTrue(TEXT("Exact authored bounds mount"), BoundedFixture.Initialize(TEXT(""), TEXT("16777217"), TEXT("16777218")))) { return false; }
        for (const TPair<FString, int32>& Case : {TPair<FString, int32>{TEXT("16777216"), 16777217},
                 TPair<FString, int32>{TEXT("16777219"), 16777218}})
        {
            if (!TestTrue(TEXT("Finite out-of-bound draft enters"), BoundedFixture.Replace(Case.Key))) { return false; }
            const int32 BeforeCommit = BoundedFixture.CommittedCalls;
            BoundedFixture.Enter();
            TestTrue(TEXT("Exact authored bounds clamp before int32 conversion"), BoundedFixture.Value == Case.Value
                && BoundedFixture.LastCommitted == Case.Value && BoundedFixture.CommittedCalls == BeforeCommit + 1);
        }
    }

    Fixture.Value = 16777217;
    Tick(Fixture.Slate);
    for (const FString& Invalid : {FString(TEXT("nan")), FString(TEXT("inf")), FString(TEXT("1e999")), FString(TEXT("not-a-number")), FString(TEXT("."))})
    {
        if (!TestTrue(TEXT("Malformed integer draft enters natively"), Fixture.Replace(Invalid))) { return false; }
        const int32 BeforeCommit = Fixture.CommittedCalls;
        Fixture.Enter();
        TestTrue(*(Invalid + TEXT(" rejects without publication")), Fixture.Value == 16777217 && Fixture.CommittedCalls == BeforeCommit);
        TestTrue(*(Invalid + TEXT(" presents validation feedback")), Fixture.Input->HasError());
    }

    if (!TestTrue(TEXT("Focused exact draft enters"), Fixture.Replace(TEXT("16777217.4")))) { return false; }
    const TSharedPtr<SEditableTextBox> Input = Fixture.Input;
    const TSharedPtr<SWidget> Focus = Fixture.Slate.GetUserFocusedWidget(0);
    const int32 ModelBeforeReload = Fixture.Value;
    if (!TestTrue(TEXT("Compatible int32 reload succeeds while editing"),
        Fixture.View->TryReload(Markup(TEXT("placeholder=\"Exact count\"")), TEXT(""), TEXT("Int32DraftReload")).Succeeded)) { return false; }
    Tick(Fixture.Slate);
    TestTrue(TEXT("Compatible reload retains native identity focus exact draft and model"), Fixture.Input == Input
        && FindInput(Fixture.Region.ToSharedRef()) == Input && Fixture.Slate.GetUserFocusedWidget(0) == Focus
        && Fixture.Input->GetText().ToString() == TEXT("16777217.4") && Fixture.Value == ModelBeforeReload);

    const int64 Revision = Fixture.View->GetRevision();
    TestFalse(TEXT("Malformed exact bound reload rejects atomically"),
        Fixture.View->TryReload(Markup(TEXT(""), TEXT("not-an-int32")), TEXT(""), TEXT("Int32MalformedBounds")).Succeeded);
    TestTrue(TEXT("Malformed exact bounds preserve revision native draft focus and model"), Fixture.View->GetRevision() == Revision
        && FindInput(Fixture.Region.ToSharedRef()) == Input && Fixture.Slate.GetUserFocusedWidget(0) == Focus && Fixture.Input->GetText().ToString() == TEXT("16777217.4")
        && Fixture.Value == ModelBeforeReload);

    for (const TPair<FString, FString>& MissingBinding : {TPair<FString, FString>{TEXT("value-bind=\"value\""), TEXT("value-bind=\"missing-value\"")},
             TPair<FString, FString>{TEXT("committed=\"commit\""), TEXT("committed=\"missing-commit\"")}})
    {
        const FString Candidate = Markup().Replace(*MissingBinding.Key, *MissingBinding.Value);
        TestFalse(TEXT("Missing integer binding or callback rejects before live state changes"),
            Fixture.View->TryReload(Candidate, TEXT(""), TEXT("Int32MissingBinding")).Succeeded);
        TestTrue(TEXT("Missing integer binding or callback preserves revision native draft focus and model"), Fixture.View->GetRevision() == Revision
            && FindInput(Fixture.Region.ToSharedRef()) == Input && Fixture.Slate.GetUserFocusedWidget(0) == Focus
            && Fixture.Input->GetText().ToString() == TEXT("16777217.4") && Fixture.Value == ModelBeforeReload);
    }

    Fixture.Value = 17;
    Tick(Fixture.Slate);
    if (!TestTrue(TEXT("Draft enters before readonly transition"), Fixture.Replace(TEXT("19")))) { return false; }
    Fixture.ReadOnly = true;
    Tick(Fixture.Slate);
    const int32 BeforeReadOnly = Fixture.CommittedCalls;
    Fixture.Slate.ClearKeyboardFocus(EFocusCause::Navigation);
    Tick(Fixture.Slate);
    TestTrue(TEXT("Readonly transition prevents pending integer commit"), Fixture.Value == 17 && Fixture.CommittedCalls == BeforeReadOnly);

    Fixture.ReadOnly = false;
    Fixture.Enabled = false;
    Tick(Fixture.Slate);
    TestFalse(TEXT("Enabled binding disables native int32 editor"), Fixture.Input->IsEnabled());
    Fixture.Slate.ProcessKeyDownEvent(Key(EKeys::Enter));
    Tick(Fixture.Slate);
    TestEqual(TEXT("Disabled int32 editor emits no commit"), Fixture.CommittedCalls, BeforeReadOnly);

    Fixture.Enabled = true;
    Tick(Fixture.Slate);
    if (!TestTrue(TEXT("Held native editor is live before owner release"), Fixture.Replace(TEXT("31")))) { return false; }
    const int32 BeforeLiveEnter = Fixture.CommittedCalls;
    Fixture.Enter();
    if (!TestTrue(TEXT("Held native editor publishes while its owner is live"), Fixture.Value == 31 && Fixture.CommittedCalls == BeforeLiveEnter + 1)) { return false; }

    const TWeakPtr<FCkUiView> WeakView = Fixture.View;
    const TSharedPtr<SEditableTextBox> HeldInput = Fixture.Input;
    const int32 BeforeRelease = Fixture.CommittedCalls;
    Fixture.View.Reset();
    TestFalse(TEXT("Native input does not retain its released view"), WeakView.IsValid());
    HeldInput->SetText(FText::FromString(TEXT("37")));
    Fixture.Slate.ProcessKeyDownEvent(Key(EKeys::Enter));
    Tick(Fixture.Slate);
    TestEqual(TEXT("Released int32 owner makes held native edit callbacks inert"), Fixture.CommittedCalls, BeforeRelease);
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkUiInt32Input_CollectionInteger,
    "Ck.UiAuthoring.Int32Input.CollectionIntegerTransport",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto
    FCkUiInt32Input_CollectionInteger::
    RunTest(
        const FString&)
    -> bool
{
    auto Record = [](const FString& InKey, const int32 InValue) -> FCkUiRecordData
    {
        auto Result = FCkUiRecordData{};
        Result.Key = InKey;
        Result.Fields.Add(TEXT("value"), FCkUiFieldValue{.Kind = ECkUiFieldKind::Integer, .Integer = InValue});
        return Result;
    };

    TSharedPtr<FCkUiCollection> Collection;
    if (!TestTrue(TEXT("Integer collection schema creates"), FCkUiCollection::TryCreate({{TEXT("value"), ECkUiFieldKind::Integer}}, Collection).Succeeded)
        || !TestTrue(TEXT("Integer collection is returned"), Collection.IsValid())) { return false; }
    if (!TestTrue(TEXT("Exact integer records publish"), Collection->TrySetRecords({Record(TEXT("exact"), 16777217), Record(TEXT("maximum"), TNumericLimits<int32>::Max())}).Succeeded)) { return false; }

    const TSharedPtr<const FCkUiRecord> Exact = Collection->FindRecord(TEXT("exact"));
    const TSharedPtr<const FCkUiRecord> Maximum = Collection->FindRecord(TEXT("maximum"));
    const FCkUiFieldValue* ExactValue = Exact.IsValid() ? Exact->FindField(TEXT("value")) : nullptr;
    const FCkUiFieldValue* MaximumValue = Maximum.IsValid() ? Maximum->FindField(TEXT("value")) : nullptr;
    TestTrue(TEXT("Collection preserves exact 16777217 and int32 maximum without Number conversion"), ExactValue != nullptr && ExactValue->Kind == ECkUiFieldKind::Integer
        && ExactValue->Integer == 16777217 && MaximumValue != nullptr && MaximumValue->Kind == ECkUiFieldKind::Integer && MaximumValue->Integer == TNumericLimits<int32>::Max());

    const int64 Revision = Collection->GetRevision();
    auto WrongNumber = Record(TEXT("maximum"), 0);
    FCkUiFieldValue& WrongValue = WrongNumber.Fields.FindChecked(TEXT("value"));
    WrongValue.Kind = ECkUiFieldKind::Number;
    WrongValue.Number = 2147483647.0f;
    TestFalse(TEXT("Number field cannot substitute for Integer schema"), Collection->TrySetRecords({Record(TEXT("exact"), 9), MoveTemp(WrongNumber)}).Succeeded);
    const FCkUiFieldValue* PreservedExact = Collection->FindRecord(TEXT("exact")).IsValid() ? Collection->FindRecord(TEXT("exact"))->FindField(TEXT("value")) : nullptr;
    const FCkUiFieldValue* PreservedMaximum = Collection->FindRecord(TEXT("maximum")).IsValid() ? Collection->FindRecord(TEXT("maximum"))->FindField(TEXT("value")) : nullptr;
    TestTrue(TEXT("Wrong Number field rejection preserves all published integer records and revision"), Collection->GetRevision() == Revision
        && PreservedExact != nullptr && PreservedExact->Integer == 16777217 && PreservedMaximum != nullptr && PreservedMaximum->Integer == TNumericLimits<int32>::Max());
    return true;
}

#endif
