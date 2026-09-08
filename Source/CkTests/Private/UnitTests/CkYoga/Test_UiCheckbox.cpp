#include "CkSlateLayout/CkUiCheckbox.h"
#include "CkSlateLayout/SCkUiSurface.h"

#include "Framework/Application/SlateApplication.h"
#include "Input/Events.h"
#include "InputCoreTypes.h"
#include "Layout/Children.h"
#include "Misc/AutomationTest.h"
#include "Styling/CoreStyle.h"
#include "Widgets/Input/SCheckBox.h"
#include "Widgets/Text/STextBlock.h"
#include "Widgets/SWindow.h"

#if WITH_DEV_AUTOMATION_TESTS

namespace ck_tests_ui_checkbox
{
    auto Markup(const TCHAR* InValueBinding = TEXT("value")) -> FString
    {
        return FString::Printf(TEXT("<ui version=\"1\"><region name=\"main\"><column id=\"root\"><checkbox id=\"checkbox\" value-bind=\"%s\" changed=\"changed\" label-bind=\"label\" enabled-bind=\"enabled\" read-only-bind=\"read-only\"/></column></region></ui>"), InValueBinding);
    }

    auto FindCheckbox(const TSharedRef<SWidget>& InRoot) -> TSharedPtr<SCheckBox>
    {
        if (InRoot->GetTag() == TEXT("checkbox") && InRoot->GetTypeAsString() == TEXT("SCheckBox")) { return StaticCastSharedRef<SCheckBox>(InRoot); }
        const FChildren* Children = InRoot->GetChildren();
        if (Children == nullptr) { return nullptr; }
        for (int32 Index = 0; Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<SCheckBox> Found = FindCheckbox(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index))); Found.IsValid()) { return Found; }
        }
        return nullptr;
    }

    auto FindLabel(const TSharedRef<SWidget>& InRoot) -> TSharedPtr<STextBlock>
    {
        if (InRoot->GetTypeAsString() == TEXT("STextBlock")) { return StaticCastSharedRef<STextBlock>(InRoot); }
        const FChildren* Children = InRoot->GetChildren();
        if (Children == nullptr) { return nullptr; }
        for (int32 Index = 0; Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<STextBlock> Found = FindLabel(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index))); Found.IsValid()) { return Found; }
        }
        return nullptr;
    }

    auto Tick(FSlateApplication& InSlate) -> void { InSlate.PumpMessages(); InSlate.Tick(); InSlate.Tick(); }
    auto Key(const FKey InKey) -> FKeyEvent { return FKeyEvent(InKey, FModifierKeysState{}, 0, false, 0, 0); }
    auto ToggleByKeyboard(FSlateApplication& InSlate) -> bool
    {
        return InSlate.ProcessKeyDownEvent(Key(EKeys::SpaceBar)) && InSlate.ProcessKeyUpEvent(Key(EKeys::SpaceBar));
    }

    struct FWindowScope final
    {
        explicit FWindowScope(FSlateApplication& InSlate) : Slate(InSlate) {}
        ~FWindowScope() { if (Window.IsValid()) { Slate.DestroyWindowImmediately(Window.ToSharedRef()); } }
        FSlateApplication& Slate;
        TSharedPtr<SWindow> Window;
    };
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiCheckbox_Runtime,
    "Ck.UiAuthoring.Checkbox.RetainedModelBoundKeyboard",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiCheckbox_Runtime::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_checkbox;
    if (!FSlateApplication::IsInitialized()) { AddError(TEXT("Checkbox test requires Slate.")); return false; }

    auto Registry = FCkUiWidgetRegistry{};
    if (!TestTrue(TEXT("Shared checkbox registration succeeds"), FCkUiCheckbox::Register(Registry).Succeeded)) { return false; }
    FString LabelValue = TEXT("Enable feature");
    bool Value = false;
    bool OtherValue = true;
    bool Enabled = true;
    bool ReadOnly = false;
    int32 ChangedCalls = 0;
    int32 AcceptedReloads = 0;
    bool AcceptedReloadSucceeded = true;
    TSharedPtr<FCkUiView> View;
    auto Data = FCkUiView::FDataBindings{};
    Data.Text.Add(TEXT("label"), TAttribute<FText>::CreateLambda([&LabelValue] { return FText::FromString(LabelValue); }));
    Data.Visibility.Add(TEXT("value"), TAttribute<bool>::CreateLambda([&Value] { return Value; }));
    Data.Visibility.Add(TEXT("other"), TAttribute<bool>::CreateLambda([&OtherValue] { return OtherValue; }));
    Data.Visibility.Add(TEXT("enabled"), TAttribute<bool>::CreateLambda([&Enabled] { return Enabled; }));
    Data.Visibility.Add(TEXT("read-only"), TAttribute<bool>::CreateLambda([&ReadOnly] { return ReadOnly; }));
    Data.BoolChanged.Add(TEXT("changed"), FCkUiOnBoolChanged::CreateLambda([&Value, &ChangedCalls, &AcceptedReloads, &AcceptedReloadSucceeded, &View](const bool InValue)
    {
        ++ChangedCalls;
        if (!InValue) { return; }
        Value = true;
        ++AcceptedReloads;
        AcceptedReloadSucceeded &= View.IsValid() && View->TryReload(Markup(), TEXT(""), TEXT("UiCheckboxAcceptedReload")).Succeeded;
    }));
    View = FCkUiView::Create({}, {}, {}, FCoreStyle::GetDefaultFontStyle(TEXT("Regular"), 12), MoveTemp(Data), Registry.CreateSnapshot());
    TSharedPtr<SWidget> Region = View->GetRegion(TEXT("main"));
    FSlateApplication& Slate = FSlateApplication::Get();
    FWindowScope Scope{Slate};
    Scope.Window = SNew(SWindow).AutoCenter(EAutoCenter::None).ClientSize(FVector2D{320.0f, 120.0f}).CreateTitleBar(false).HasCloseButton(false)[Region.ToSharedRef()];
    Slate.AddWindow(Scope.Window.ToSharedRef(), true);
    if (!TestTrue(TEXT("Registered retained checkbox loads"), View->TryReload(Markup(), TEXT(""), TEXT("UiCheckbox")).Succeeded)) { return false; }
    Tick(Slate);
    const TSharedPtr<SCheckBox> Checkbox = FindCheckbox(Region.ToSharedRef());
    if (!TestTrue(TEXT("Authored checkbox exposes native checkbox"), Checkbox.IsValid())) { return false; }
    const TSharedPtr<STextBlock> Label = FindLabel(Checkbox.ToSharedRef());
    if (!TestTrue(TEXT("Authored checkbox exposes native label"), Label.IsValid())) { return false; }
    TestEqual(TEXT("Live label binding renders through native checkbox content"), Label->GetText().ToString(), FString(TEXT("Enable feature")));
    TestEqual(TEXT("Initial construction dispatches no changed event"), ChangedCalls, 0);
    Slate.SetUserFocus(0, Checkbox.ToSharedRef(), EFocusCause::SetDirectly);
    Tick(Slate);
    TestTrue(TEXT("Native keyboard accepts model-approved toggle"), ToggleByKeyboard(Slate));
    Tick(Slate);
    TestTrue(TEXT("Accepted toggle updates authoritative value and retained widget"), Value && Checkbox->IsChecked() && ChangedCalls == 1 && AcceptedReloads == 1 && AcceptedReloadSucceeded);
    TestTrue(TEXT("Accepted reentrant reload retains native widget and focus"), FindCheckbox(Region.ToSharedRef()) == Checkbox && Slate.GetUserFocusedWidget(0) == Checkbox);

    TestTrue(TEXT("Native keyboard offers rejected toggle"), ToggleByKeyboard(Slate));
    Tick(Slate);
    TestTrue(TEXT("Rejected toggle leaves model and native state authoritative"), Value && Checkbox->IsChecked() && ChangedCalls == 2);
    Value = false;
    LabelValue = TEXT("Enable inspection");
    Tick(Slate);
    TestEqual(TEXT("Changed label attribute reaches the existing native label"), Label->GetText().ToString(), LabelValue);
    TestTrue(TEXT("External model change updates native state without callback"), !Checkbox->IsChecked() && ChangedCalls == 2);

    ReadOnly = true;
    Tick(Slate);
    ToggleByKeyboard(Slate);
    Tick(Slate);
    TestTrue(TEXT("Read-only checkbox cannot mutate the model"), !Value && !Checkbox->IsChecked() && ChangedCalls == 2);
    ReadOnly = false;
    Enabled = false;
    Tick(Slate);
    ToggleByKeyboard(Slate);
    Tick(Slate);
    TestTrue(TEXT("Disabled checkbox cannot mutate the model"), !Value && !Checkbox->IsChecked() && ChangedCalls == 2);
    Enabled = true;
    Tick(Slate);

    const int64 AcceptedRevision = View->GetRevision();
    const FCkUiLoadResult Retarget = View->TryReload(Markup(TEXT("other")), TEXT(""), TEXT("UiCheckboxRetarget"));
    TestFalse(TEXT("Retargeting retained value binding rejects"), Retarget.Succeeded);
    TestEqual(TEXT("Retarget rejection preserves the view"), View->GetRevision(), AcceptedRevision);
    const TSharedPtr<SWidget> FocusBeforeReload = Slate.GetUserFocusedWidget(0);
    if (!TestTrue(TEXT("Compatible reload succeeds"), View->TryReload(Markup(), TEXT(""), TEXT("UiCheckboxCompatibleReload")).Succeeded)) { return false; }
    Tick(Slate);
    TestTrue(TEXT("Compatible reload retains native identity and focus"), FindCheckbox(Region.ToSharedRef()) == Checkbox && Slate.GetUserFocusedWidget(0) == FocusBeforeReload);

    const int32 ChangedBeforeRelease = ChangedCalls;
    Slate.DestroyWindowImmediately(Scope.Window.ToSharedRef());
    Scope.Window.Reset();
    Region.Reset();
    View.Reset();
    const bool ValueBeforeRelease = Value;
    const FReply ReleasedKeyDown = Checkbox->OnKeyDown(Checkbox->GetCachedGeometry(), Key(EKeys::SpaceBar));
    const FReply ReleasedKeyUp = Checkbox->OnKeyUp(Checkbox->GetCachedGeometry(), Key(EKeys::SpaceBar));
    TestTrue(TEXT("Held native checkbox receives its direct keyboard lifecycle after owner release"), ReleasedKeyDown.IsEventHandled() && ReleasedKeyUp.IsEventHandled());
    TestTrue(TEXT("Released retained owner leaves model and callback inert"), Value == ValueBeforeRelease && ChangedCalls == ChangedBeforeRelease);
    return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS
