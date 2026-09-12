#include "CkSlateLayout/CkUiColorPicker.h"
#include "CkSlateLayout/SCkUiSurface.h"

#include "Framework/Application/SlateApplication.h"
#include "HAL/PlatformProcess.h"
#include "HAL/PlatformTime.h"
#include "Input/Events.h"
#include "InputCoreTypes.h"
#include "Layout/Children.h"
#include "Layout/WidgetPath.h"
#include "Misc/AutomationTest.h"
#include "Styling/CoreStyle.h"
#include "Widgets/Colors/SColorPicker.h"
#include "Widgets/Input/SEditableTextBox.h"
#include "Widgets/Input/SButton.h"
#include "Widgets/SWindow.h"
#include "Widgets/Text/STextBlock.h"

#include <limits>

#if WITH_DEV_AUTOMATION_TESTS

namespace ck_tests_ui_color_picker
{
    auto Markup(const TCHAR* InValue = TEXT("value"), const TCHAR* InCommitted = TEXT("committed"), const bool bUseAlpha = false) -> FString
    {
        return FString::Printf(TEXT("<ui version=\"1\"><region name=\"main\"><column id=\"root\"><color-picker id=\"picker\" value-bind=\"%s\" committed=\"%s\" enabled-bind=\"enabled\" read-only-bind=\"read-only\" alpha=\"%s\"/></column></region></ui>"),
            InValue, InCommitted, bUseAlpha ? TEXT("true") : TEXT("false"));
    }

    auto TemplateMarkup() -> FString
    {
        return TEXT("<ui version=\"1\"><template name=\"picker-template\"><param name=\"value\" type=\"color-binding\"/><param name=\"committed\" type=\"color-committed\"/><color-picker id=\"picker\" value-bind-param=\"value\" committed-param=\"committed\"/></template><region name=\"main\"><use id=\"instance\" template=\"picker-template\" value-bind=\"value\" committed=\"committed\"/></region></ui>");
    }

    auto FindButton(const TSharedRef<SWidget>& InRoot) -> TSharedPtr<SButton>
    {
        if (InRoot->GetTag() == TEXT("picker") && InRoot->GetTypeAsString() == TEXT("SButton")) { return StaticCastSharedRef<SButton>(InRoot); }
        const FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<SButton> Found = FindButton(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index))); Found.IsValid()) { return Found; }
        }
        return {};
    }

    auto ContainsText(const TSharedRef<SWidget>& InRoot, const FString& InText) -> bool
    {
        if (InRoot->GetTypeAsString() == TEXT("STextBlock") && StaticCastSharedRef<STextBlock>(InRoot)->GetText().ToString() == InText) { return true; }
        const FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            if (ContainsText(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InText)) { return true; }
        }
        return false;
    }

    auto FindButton(const TSharedRef<SWidget>& InRoot, const FString& InText) -> TSharedPtr<SButton>
    {
        if (InRoot->GetTypeAsString() == TEXT("SButton") && ContainsText(InRoot, InText)) { return StaticCastSharedRef<SButton>(InRoot); }
        const FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<SButton> Found = FindButton(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InText); Found.IsValid()) { return Found; }
        }
        return {};
    }

    auto FindNativePicker(const TSharedRef<SWidget>& InRoot) -> TSharedPtr<SColorPicker>
    {
        if (InRoot->GetTypeAsString() == TEXT("SColorPicker")) { return StaticCastSharedRef<SColorPicker>(InRoot); }
        const FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<SColorPicker> Found = FindNativePicker(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index))); Found.IsValid()) { return Found; }
        }
        return {};
    }

    auto FindHexEditor(const TSharedRef<SWidget>& InRoot) -> TSharedPtr<SEditableTextBox>
    {
        if (InRoot->GetTypeAsString() == TEXT("SEditableTextBox"))
        {
            const TSharedRef<SEditableTextBox> Editor = StaticCastSharedRef<SEditableTextBox>(InRoot);
            const FString Text = Editor->GetText().ToString();
            bool Hex = Text.Len() == 8;
            for (const TCHAR Character : Text)
            { Hex &= (Character >= TEXT('0') && Character <= TEXT('9')) || (Character >= TEXT('a') && Character <= TEXT('f')) || (Character >= TEXT('A') && Character <= TEXT('F')); }
            if (Hex) { return Editor; }
        }
        const FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<SEditableTextBox> Found = FindHexEditor(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index))); Found.IsValid()) { return Found; }
        }
        return {};
    }

    auto FindPopup(FSlateApplication& InSlate) -> TSharedPtr<SColorPicker>
    {
        TArray<TSharedRef<SWindow>> Windows;
        InSlate.GetAllVisibleWindowsOrdered(Windows);
        for (const TSharedRef<SWindow>& Window : Windows)
        {
            if (const TSharedPtr<SColorPicker> Picker = FindNativePicker(Window); Picker.IsValid()) { return Picker; }
        }
        return {};
    }

    auto FindPopupWindow(FSlateApplication& InSlate) -> TSharedPtr<SWindow>
    {
        TArray<TSharedRef<SWindow>> Windows;
        InSlate.GetAllVisibleWindowsOrdered(Windows);
        for (const TSharedRef<SWindow>& Window : Windows)
        {
            if (FindNativePicker(Window).IsValid()) { return Window; }
        }
        return {};
    }

    auto Tick(FSlateApplication& InSlate) -> void
    {
        InSlate.PumpMessages();
        InSlate.Tick();
        InSlate.Tick();
    }

    auto AwaitInitialColorAnimation(FSlateApplication& InSlate, const TSharedRef<SColorPicker>& InPicker) -> bool
    {
        // SColorPicker starts a 250ms active-timer transition in Construct; do not race a native hex commit against it.
        const double Deadline = FPlatformTime::Seconds() + 2.0;
        while (InPicker->HasActiveTimers() && FPlatformTime::Seconds() < Deadline)
        {
            FPlatformProcess::Sleep(0.01f);
            Tick(InSlate);
        }
        return !InPicker->HasActiveTimers();
    }

    auto Key(const FKey InKey) -> FKeyEvent { return FKeyEvent{InKey, FModifierKeysState{}, 0, false, 0, 0}; }

    auto ReplaceText(FSlateApplication& InSlate, const TSharedRef<SEditableTextBox>& InEditor, const FString& InText) -> bool
    {
        InSlate.SetUserFocus(0, InEditor, EFocusCause::SetDirectly);
        Tick(InSlate);
        const FModifierKeysState Control{false, false, true, false, false, false, false, false, false};
        if (!InSlate.ProcessKeyDownEvent(FKeyEvent{EKeys::A, Control, 0, false, 0, 0})) { return false; }
        for (const TCHAR Character : InText)
        { if (!InSlate.ProcessKeyCharEvent(FCharacterEvent{Character, FModifierKeysState{}, 0, false})) { return false; } }
        Tick(InSlate);
        return true;
    }

    auto Click(FSlateApplication& InSlate, const TSharedRef<SWindow>& InWindow, const TSharedRef<SButton>& InButton) -> bool
    {
        if (!InWindow->GetNativeWindow().IsValid()) { return false; }
        const FGeometry Geometry = InButton->GetCachedGeometry();
        const FVector2D Position = Geometry.LocalToAbsolute(Geometry.GetLocalSize() * 0.5f);
        if (Geometry.GetLocalSize().X <= 0.0f || Geometry.GetLocalSize().Y <= 0.0f || !Geometry.IsUnderLocation(Position)) { return false; }
        const TSet<FKey> MoveButtons;
        const TSet<FKey> DownButtons{EKeys::LeftMouseButton};
        const TSet<FKey> UpButtons;
        InSlate.SetCursorPos(Position);
        InSlate.ProcessMouseMoveEvent(FPointerEvent(0, FSlateApplication::CursorPointerIndex, Position, Position, MoveButtons, EKeys::Invalid, 0.0f, FModifierKeysState{}));
        const bool Down = InSlate.ProcessMouseButtonDownEvent(InWindow->GetNativeWindow(), FPointerEvent(0, FSlateApplication::CursorPointerIndex, Position, Position, DownButtons, EKeys::LeftMouseButton, 0.0f, FModifierKeysState{}));
        const bool Up = InSlate.ProcessMouseButtonUpEvent(FPointerEvent(0, FSlateApplication::CursorPointerIndex, Position, Position, UpButtons, EKeys::LeftMouseButton, 0.0f, FModifierKeysState{}));
        Tick(InSlate);
        return Down && Up;
    }

    struct FWindowScope final
    {
        explicit FWindowScope(FSlateApplication& InSlate) : Slate(InSlate), PreviousCursor(InSlate.GetCursorPos()) {}
        ~FWindowScope() { if (Window.IsValid()) { Slate.DestroyWindowImmediately(Window.ToSharedRef()); } Slate.SetCursorPos(PreviousCursor); }
        FSlateApplication& Slate;
        FVector2D PreviousCursor;
        TSharedPtr<SWindow> Window;
    };
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiColorPicker_Runtime,
    "Ck.UiAuthoring.ColorPicker.RetainedOwnedPopup",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiColorPicker_Runtime::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_color_picker;
    if (!FSlateApplication::IsInitialized()) { AddError(TEXT("Color picker test requires Slate.")); return false; }

    auto ProductionRegistry = FCkUiWidgetRegistry{};
    if (!TestTrue(TEXT("Shared color-picker registration succeeds"), FCkUiColorPicker::Register(ProductionRegistry).Succeeded)) { return false; }
    const TSharedRef<const FCkUiWidgetRegistrySnapshot> ProductionSnapshot = ProductionRegistry.CreateSnapshot();
    const FCkUiCustomWidgetRegistration* ProductionRegistration = ProductionSnapshot->Find(TEXT("color-picker"));
    if (!TestTrue(TEXT("Shared color-picker registration exposes its retained factory"), ProductionRegistration != nullptr && ProductionRegistration->RetainedFactory)) { return false; }
    const TSharedRef<FCkUiOnColorCommitted> CapturedCommitted = MakeShared<FCkUiOnColorCommitted>();
    FCkUiCustomWidgetRegistration InterceptedRegistration = *ProductionRegistration;
    const FCkUiRetainedWidgetFactory ProductionFactory = InterceptedRegistration.RetainedFactory;
    InterceptedRegistration.RetainedFactory = [CapturedCommitted, ProductionFactory](const FCkUiCustomWidgetArguments& InArguments, FString& OutFailure) -> TSharedPtr<ICkUiRetainedWidget>
    {
        if (const FCkUiOnColorCommitted* Committed = InArguments.ColorCommitted.Find(TEXT("committed")); Committed != nullptr && Committed->IsBound())
        { *CapturedCommitted = *Committed; }
        return ProductionFactory(InArguments, OutFailure);
    };
    auto Registry = FCkUiWidgetRegistry{};
    if (!TestTrue(TEXT("Intercepted color-picker registration succeeds"), Registry.Register(MoveTemp(InterceptedRegistration)).Succeeded)) { return false; }
    auto ParsedTemplate = FCkUiDocument{};
    TestTrue(TEXT("Typed template forwards color-committed into a registered picker"), FCkUiDocumentParser::TryParse(TemplateMarkup(), TEXT(""), {}, ParsedTemplate, TEXT("UiColorPickerTemplate"), Registry.CreateSnapshot()).Succeeded);

    FLinearColor Value(0.15f, 0.25f, 0.35f, 0.45f);
    bool Enabled = true;
    bool ReadOnly = false;
    int32 CommitCalls = 0;
    auto Data = FCkUiView::FDataBindings{};
    Data.Color.Add(TEXT("value"), TAttribute<FLinearColor>::CreateLambda([&Value] { return Value; }));
    Data.Visibility.Add(TEXT("enabled"), TAttribute<bool>::CreateLambda([&Enabled] { return Enabled; }));
    Data.Visibility.Add(TEXT("read-only"), TAttribute<bool>::CreateLambda([&ReadOnly] { return ReadOnly; }));
    Data.ColorCommitted.Add(TEXT("committed"), FCkUiOnColorCommitted::CreateLambda([&Value, &CommitCalls](const FLinearColor InValue)
    {
        ++CommitCalls;
        Value = InValue;
    }));
    Data.ColorCommitted.Add(TEXT("unbound"), FCkUiOnColorCommitted{});
    Data.SlateUserIndex = 0;

    TSharedPtr<FCkUiView> View = FCkUiView::Create({}, {}, {}, FCoreStyle::GetDefaultFontStyle(TEXT("Regular"), 12), MoveTemp(Data), Registry.CreateSnapshot());
    TSharedPtr<SWidget> Region = View->GetRegion(TEXT("main"));
    FSlateApplication& Slate = FSlateApplication::Get();
    FWindowScope Scope{Slate};
    Scope.Window = SNew(SWindow).AutoCenter(EAutoCenter::None).ClientSize(FVector2D(360.0f, 140.0f)).CreateTitleBar(false).HasCloseButton(false)[Region.ToSharedRef()];
    Slate.AddWindow(Scope.Window.ToSharedRef(), true);
    if (!TestTrue(TEXT("Registered color picker loads"), View->TryReload(Markup(), TEXT(""), TEXT("UiColorPicker")).Succeeded)) { return false; }
    Tick(Slate);

    const TSharedPtr<SButton> Button = FindButton(Region.ToSharedRef());
    if (!TestTrue(TEXT("Authored color picker exposes its native swatch button"), Button.IsValid())) { return false; }
    TestEqual(TEXT("Construction emits no color commit"), CommitCalls, 0);

    const FLinearColor InitialValue = Value;
    Value = FLinearColor(std::numeric_limits<float>::quiet_NaN(), 0.2f, 0.3f, 1.0f);
    Tick(Slate);
    Click(Slate, Scope.Window.ToSharedRef(), Button.ToSharedRef());
    TestTrue(TEXT("Non-finite model value disables the swatch before opening a popup"), !Button->IsEnabled() && !FindPopup(Slate).IsValid() && CommitCalls == 0);
    Value = InitialValue;
    Enabled = false;
    Tick(Slate);
    Click(Slate, Scope.Window.ToSharedRef(), Button.ToSharedRef());
    TestTrue(TEXT("Disabled swatch rejects pointer activation"), !Button->IsEnabled() && !FindPopup(Slate).IsValid() && CommitCalls == 0);
    Enabled = true;
    Tick(Slate);

    if (!TestTrue(TEXT("Native pointer opens the owned color picker popup"), Click(Slate, Scope.Window.ToSharedRef(), Button.ToSharedRef()))) { return false; }
    const TSharedPtr<SColorPicker> Picker = FindPopup(Slate);
    if (!TestTrue(TEXT("Popup contains a real SColorPicker"), Picker.IsValid())) { return false; }
    if (!TestTrue(TEXT("Native color picker finishes its initial active-timer transition"), AwaitInitialColorAnimation(Slate, Picker.ToSharedRef()))) { return false; }
    const TSharedPtr<SEditableTextBox> FocusEditor = FindHexEditor(Picker.ToSharedRef());
    if (!TestTrue(TEXT("Owned picker exposes its native hexadecimal editor"), FocusEditor.IsValid())) { return false; }
    Slate.SetUserFocus(0, FocusEditor.ToSharedRef(), EFocusCause::SetDirectly);
    Tick(Slate);
    FWidgetPath PickerFocusPath;
    const TSharedPtr<SWidget> FocusBeforeCommit = Slate.GetUserFocusedWidget(0);
    const bool FocusPathValid = FocusBeforeCommit.IsValid() && Slate.GeneratePathToWidgetUnchecked(FocusBeforeCommit.ToSharedRef(), PickerFocusPath);
    bool PickerInFocusPath = false;
    bool EditorInFocusPath = false;
    for (int32 Index = 0; Index < PickerFocusPath.Widgets.Num(); ++Index)
    {
        PickerInFocusPath |= PickerFocusPath.Widgets[Index].Widget == Picker;
        EditorInFocusPath |= PickerFocusPath.Widgets[Index].Widget == FocusEditor;
    }
    const bool PickerOwnsFocusedEditor = FocusPathValid && PickerInFocusPath && EditorInFocusPath;
    TestTrue(TEXT("Focused native editor belongs to the owned popup"), PickerOwnsFocusedEditor);

    const int64 CompatibleRevision = View->GetRevision();
    if (!TestTrue(TEXT("Compatible color-picker reload succeeds while popup is open"), View->TryReload(Markup(), TEXT(""), TEXT("UiColorPickerCompatible")).Succeeded)) { return false; }
    Tick(Slate);
    TestTrue(TEXT("Compatible reload retains swatch, owned popup, and popup focus"), View->GetRevision() == CompatibleRevision + 1 && FindButton(Region.ToSharedRef()) == Button && FindPopup(Slate) == Picker && Slate.GetUserFocusedWidget(0) == FocusBeforeCommit);

    const FCkUiLoadResult MissingCallback = View->TryReload(Markup(TEXT("value"), TEXT("missing")), TEXT(""), TEXT("UiColorPickerMissingCallback"));
    const FCkUiLoadResult UnboundCallback = View->TryReload(Markup(TEXT("value"), TEXT("unbound")), TEXT(""), TEXT("UiColorPickerUnboundCallback"));
    TestTrue(TEXT("Missing and unbound color callbacks reject before publication"), !MissingCallback.Succeeded && !UnboundCallback.Succeeded && View->GetRevision() == CompatibleRevision + 1 && FindButton(Region.ToSharedRef()) == Button && FindPopup(Slate) == Picker);

    if (!TestTrue(TEXT("Native keyboard replaces picker hexadecimal draft"), ReplaceText(Slate, FocusEditor.ToSharedRef(), TEXT("FF0000FF")))) { return false; }
    FocusEditor->SelectAllText();
    TestEqual(TEXT("Native hexadecimal editable buffer is exact before Enter"), FocusEditor->GetSelectedText().ToString(), FString(TEXT("FF0000FF")));
    if (!TestTrue(TEXT("Native Enter applies the hexadecimal draft"), Slate.ProcessKeyDownEvent(Key(EKeys::Enter)))) { return false; }
    Tick(Slate);
    TestTrue(TEXT("Owned native-child picker remains open after committing its hexadecimal draft"), FindPopup(Slate) == Picker);
    TestEqual(TEXT("Native hexadecimal draft remains applied before OK"), FocusEditor->GetText().ToString(), FString(TEXT("FF0000FF")));
    const TSharedPtr<SButton> CommitButton = FindButton(Picker.ToSharedRef(), TEXT("OK"));
    const TSharedPtr<SWindow> PopupWindow = FindPopupWindow(Slate);
    if (!TestTrue(TEXT("Owned picker exposes its native OK button"), CommitButton.IsValid() && PopupWindow.IsValid())) { return false; }
    if (!TestTrue(TEXT("Native pointer activates the picker OK button"), Click(Slate, PopupWindow.ToSharedRef(), CommitButton.ToSharedRef()))) { return false; }
    TestEqual(TEXT("Finite picker native OK invokes exactly one committed callback"), CommitCalls, 1);
    TestTrue(FString::Printf(TEXT("Finite picker callback clamps channels and honors alpha=false; actual %s"), *Value.ToString()), Value.Equals(FLinearColor::Red));
    TestTrue(TEXT("Native picker OK closes only its owned popup"), !FindPopup(Slate).IsValid());

    if (!TestTrue(TEXT("Native pointer reopens the owned picker for read-only coverage"), Click(Slate, Scope.Window.ToSharedRef(), Button.ToSharedRef()))) { return false; }
    const TSharedPtr<SColorPicker> ReadOnlyPicker = FindPopup(Slate);
    if (!TestTrue(TEXT("Reopened picker finishes its initial active-timer transition"), ReadOnlyPicker.IsValid() && AwaitInitialColorAnimation(Slate, ReadOnlyPicker.ToSharedRef()))) { return false; }
    const TSharedPtr<SEditableTextBox> ReadOnlyEditor = ReadOnlyPicker.IsValid() ? FindHexEditor(ReadOnlyPicker.ToSharedRef()) : nullptr;
    const TSharedPtr<SButton> ReadOnlyCommit = ReadOnlyPicker.IsValid() ? FindButton(ReadOnlyPicker.ToSharedRef(), TEXT("OK")) : nullptr;
    const TSharedPtr<SWindow> ReadOnlyWindow = FindPopupWindow(Slate);
    if (!TestTrue(TEXT("Reopened owned picker provides native draft and commit controls"), ReadOnlyEditor.IsValid() && ReadOnlyCommit.IsValid() && ReadOnlyWindow.IsValid())) { return false; }
    ReadOnly = true;
    if (!TestTrue(TEXT("Read-only picker accepts an isolated native draft"), ReplaceText(Slate, ReadOnlyEditor.ToSharedRef(), TEXT("00FF00FF")) && Slate.ProcessKeyDownEvent(Key(EKeys::Enter)))) { return false; }
    if (!TestTrue(TEXT("Read-only picker routes its native OK activation"), Click(Slate, ReadOnlyWindow.ToSharedRef(), ReadOnlyCommit.ToSharedRef()))) { return false; }
    TestEqual(TEXT("Read-only picker callback is inert after a real commit attempt"), CommitCalls, 1);
    TestTrue(TEXT("Read-only native OK closes the owned popup"), !FindPopup(Slate).IsValid());
    ReadOnly = false;
    Tick(Slate);

    const int32 CallsBeforeLiveDispatch = CommitCalls;
    CapturedCommitted->ExecuteIfBound(FLinearColor::Blue);
    Tick(Slate);
    TestTrue(TEXT("Factory captures the current live public color dispatch binding"), CapturedCommitted->IsBound() && CommitCalls == CallsBeforeLiveDispatch + 1 && Value.Equals(FLinearColor::Blue));

    if (!TestTrue(TEXT("Native pointer reopens the owned picker for owner-release coverage"), Click(Slate, Scope.Window.ToSharedRef(), Button.ToSharedRef()))) { return false; }
    const TSharedPtr<SColorPicker> ReleasePicker = FindPopup(Slate);
    if (!TestTrue(TEXT("Owner-release picker finishes its initial active-timer transition"), ReleasePicker.IsValid() && AwaitInitialColorAnimation(Slate, ReleasePicker.ToSharedRef()))) { return false; }
    if (!TestTrue(TEXT("Owner-release coverage opens a real native picker"), ReleasePicker.IsValid())) { return false; }
    const int32 CallsBeforeRelease = CommitCalls;
    const FLinearColor ValueBeforeRelease = Value;
    const TWeakPtr<FCkUiView> WeakView = View;
    Slate.DestroyWindowImmediately(Scope.Window.ToSharedRef());
    Scope.Window.Reset();
    Region.Reset();
    View.Reset();
    Tick(Slate);
    CapturedCommitted->ExecuteIfBound(FLinearColor::Green);
    Tick(Slate);
    TestTrue(TEXT("Owner release closes its owned popup and expires the view"), !WeakView.IsValid() && !FindPopup(Slate).IsValid());
    TestTrue(TEXT("Held public color dispatch is inert after owner release"), CommitCalls == CallsBeforeRelease && Value.Equals(ValueBeforeRelease));
    return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS
