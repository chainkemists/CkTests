#include "CkSlateLayout/CkUiCollection.h"
#include "CkSlateLayout/CkUiSelect.h"
#include "CkSlateLayout/CkUiSlider.h"
#include "CkSlateLayout/SCkUiSurface.h"

#include "Framework/Application/SlateApplication.h"
#include "Input/Events.h"
#include "Input/PopupMethodReply.h"
#include "InputCoreTypes.h"
#include "Layout/Children.h"
#include "Layout/WidgetPath.h"
#include "Misc/AutomationTest.h"
#include "Styling/CoreStyle.h"
#include "Widgets/Input/SMenuAnchor.h"
#include "Widgets/Input/SSlider.h"
#include "Widgets/Layout/SBox.h"
#include "Widgets/SWindow.h"

#if WITH_DEV_AUTOMATION_TESTS
namespace ck_tests_ui_tabs_interactions
{
    class SCurrentWindowPopupHost final : public SBox
    {
    public:
        virtual auto OnQueryPopupMethod() const -> FPopupMethodReply override
        { return FPopupMethodReply::UseMethod(EPopupMethod::UseCurrentWindow); }
    };

    auto Markup() -> FString
    {
        return TEXT("<ui version=\"1\"><region name=\"main\"><tabs id=\"tabs\" value-bind=\"active\" changed=\"activate\"><tab id=\"first\" key=\"first\" label=\"First\"><column id=\"first-panel\"><select id=\"select\" value-bind=\"value\" options-bind=\"options\" changed=\"changed\"/></column></tab><tab id=\"second\" key=\"second\" label=\"Second\"><column id=\"second-panel\"><text id=\"second-copy\">Second panel</text></column></tab></tabs></region></ui>");
    }

    auto Record(const TCHAR* InKey, const TCHAR* InLabel) -> FCkUiRecordData
    {
        FCkUiRecordData Result;
        Result.Key = InKey;
        Result.Fields.Add(TEXT("label"), FCkUiFieldValue{.Kind = ECkUiFieldKind::Text, .Text = FText::FromString(InLabel)});
        return Result;
    }

    auto FindSelect(const TSharedRef<SWidget>& InRoot) -> TSharedPtr<SWidget>
    {
        if (InRoot->GetTypeAsString() == TEXT("SCkUiSelect")) { return InRoot; }
        const FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<SWidget> Found = FindSelect(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index))); Found.IsValid()) { return Found; }
        }
        return {};
    }

    auto Tick(FSlateApplication& InSlate) -> void
    {
        InSlate.PumpMessages();
        InSlate.Tick();
        InSlate.Tick();
    }

    auto Key(const FKey InKey) -> FKeyEvent
    { return FKeyEvent(InKey, FModifierKeysState{}, 0, false, 0, 0); }

    struct FWindowScope final
    {
        explicit FWindowScope(FSlateApplication& InSlate) : Slate(InSlate) {}
        ~FWindowScope() { if (Window.IsValid()) { Slate.DestroyWindowImmediately(Window.ToSharedRef()); } }
        FSlateApplication& Slate;
        TSharedPtr<SWindow> Window;
    };

    struct FFixture final
    {
        explicit FFixture(const bool InUseCurrentWindow)
            : Slate(FSlateApplication::Get()), UseCurrentWindow(InUseCurrentWindow), Scope(Slate)
        {
        }

        auto Load() -> bool
        {
            FCkUiWidgetRegistry Registry;
            if (!FCkUiSelect::Register(Registry).Succeeded
                || !FCkUiCollection::TryCreate({{TEXT("label"), ECkUiFieldKind::Text}}, Collection).Succeeded
                || !Collection->TrySetRecords({Record(TEXT("a"), TEXT("Alpha")), Record(TEXT("b"), TEXT("Beta"))}).Succeeded) { return false; }

            FCkUiView::FDataBindings Data;
            Data.String.Add(TEXT("active"), TAttribute<FString>::CreateLambda([this] { return Active; }));
            Data.String.Add(TEXT("value"), TAttribute<FString>::CreateLambda([this] { return Value; }));
            Data.Collections.Add(TEXT("options"), Collection);
            Data.StringChanged.Add(TEXT("activate"), FCkUiOnStringChanged::CreateLambda([this](const FString& InKey) { Active = InKey; }));
            Data.StringChanged.Add(TEXT("changed"), FCkUiOnStringChanged::CreateLambda([this](const FString& InKey)
            {
                ++ChangedCalls;
                Value = InKey;
            }));
            View = FCkUiView::Create({}, {}, {}, FCoreStyle::GetDefaultFontStyle(TEXT("Regular"), 12), MoveTemp(Data), Registry.CreateSnapshot());
            Region = View->GetRegion(TEXT("main"));
            const TSharedRef<SWidget> Host = UseCurrentWindow
                ? StaticCastSharedRef<SWidget>(SNew(SCurrentWindowPopupHost)[Region.ToSharedRef()])
                : Region.ToSharedRef();
            Scope.Window = SNew(SWindow).AutoCenter(EAutoCenter::None).ClientSize(FVector2D(360.0f, 180.0f)).CreateTitleBar(false).HasCloseButton(false)[Host];
            Slate.AddWindow(Scope.Window.ToSharedRef(), true);
            if (!View->TryReload(Markup(), TEXT(""), TEXT("UiTabsInteractions")).Succeeded) { return false; }
            Tick(Slate);
            Select = FindSelect(Region.ToSharedRef());
            Menu = StaticCastSharedPtr<SMenuAnchor>(Select);
            return Select.IsValid() && Menu.IsValid();
        }

        auto Open() -> bool
        {
            Slate.SetUserFocus(0, Select, EFocusCause::SetDirectly);
            if (Slate.GetUserFocusedWidget(0) != Select) { return false; }
            const bool Handled = Slate.ProcessKeyDownEvent(Key(EKeys::SpaceBar));
            Tick(Slate);
            return Handled && Menu->IsOpen() && Menu->GetMenuWindow().IsValid();
        }

        FSlateApplication& Slate;
        const bool UseCurrentWindow;
        FString Active = TEXT("first");
        FString Value = TEXT("a");
        int32 ChangedCalls = 0;
        TSharedPtr<FCkUiCollection> Collection;
        TSharedPtr<FCkUiView> View;
        TSharedPtr<SWidget> Region;
        TSharedPtr<SWidget> Select;
        TSharedPtr<SMenuAnchor> Menu;
        FWindowScope Scope;
    };
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiTabs_HiddenInteractions,
    "Ck.UiAuthoring.Tabs.HiddenPanelReleasesTransientInteraction",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiTabs_HiddenInteractions::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_tabs_interactions;
    if (!FSlateApplication::IsInitialized()) { AddError(TEXT("Tabs hidden-interaction test requires Slate.")); return false; }

    for (const bool UseCurrentWindow : {false, true})
    {
        FFixture Fixture(UseCurrentWindow);
        if (!TestTrue(UseCurrentWindow ? TEXT("Current-window tabs fixture loads") : TEXT("New-window tabs fixture loads"), Fixture.Load())
            || !TestTrue(TEXT("Visible tab select opens its production popup"), Fixture.Open())) { return false; }

        const TSharedPtr<SWidget> PopupFocus = Fixture.Slate.GetUserFocusedWidget(0);
        if (!TestTrue(TEXT("Open popup owns a focused descendant"), PopupFocus.IsValid() && PopupFocus != Fixture.Select)) { return false; }
        TestTrue(TEXT("Popup uses the requested host method"), (Fixture.Menu->GetMenuWindow() == Fixture.Scope.Window) == UseCurrentWindow);

        Fixture.Active = TEXT("second");
        Tick(Fixture.Slate);
        TestFalse(TEXT("External tab-model change closes the hidden select popup"), Fixture.Menu->IsOpen());
        TestEqual(TEXT("Hidden popup cleanup does not select an option"), Fixture.ChangedCalls, 0);
        TestTrue(TEXT("Hidden popup focus is released or reassigned away from its stale leaf"), Fixture.Slate.GetUserFocusedWidget(0) != PopupFocus);
        const TSharedPtr<SWidget> FocusAfterHide = Fixture.Slate.GetUserFocusedWidget(0);
        if (FocusAfterHide.IsValid())
        {
            FWidgetPath MountedPath;
            TestTrue(TEXT("Any focus after tab hiding belongs to a mounted Slate path"), Fixture.Slate.GeneratePathToWidgetUnchecked(FocusAfterHide.ToSharedRef(), MountedPath));
        }

        Fixture.Active = TEXT("first");
        Tick(Fixture.Slate);
        TestTrue(TEXT("Returning to the retained select tab leaves it usable"), Fixture.Open());
        Fixture.Menu->SetIsOpen(false);
        Tick(Fixture.Slate);
    }
    return true;
}

namespace ck_tests_ui_tabs_slider_interactions
{
    using ck_tests_ui_tabs_interactions::Tick;
    auto Markup() -> FString
    {
        return TEXT("<ui version=\"1\"><region name=\"main\"><tabs id=\"tabs\" value-bind=\"active\" changed=\"activate\"><tab id=\"first\" key=\"first\" label=\"First\"><column id=\"first-panel\"><slider id=\"slider\" value-bind=\"value\" interaction=\"interaction\" changed=\"changed\" min=\"0\" max=\"100\" step=\"10\"/></column></tab><tab id=\"second\" key=\"second\" label=\"Second\"><column id=\"second-panel\"><text id=\"second-copy\">Second panel</text></column></tab></tabs></region></ui>");
    }

    auto FindSlider(const TSharedRef<SWidget>& InRoot) -> TSharedPtr<SSlider>
    {
        if (InRoot->GetTypeAsString() == TEXT("SCkUiSlider")) { return StaticCastSharedRef<SSlider>(InRoot); }
        const FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<SSlider> Found = FindSlider(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index))); Found.IsValid()) { return Found; }
        }
        return {};
    }

    struct FFixture final
    {
        FSlateApplication& Slate = FSlateApplication::Get();
        FString Active = TEXT("first");
        float Value = 25.0f;
        int32 ChangedCalls = 0;
        TArray<FCkUiNumberInteraction> Events;
        TSharedPtr<FCkUiView> View;
        TSharedPtr<SWindow> Window;
        TSharedPtr<SSlider> Slider;

        ~FFixture()
        {
            View.Reset();
            if (Window.IsValid()) { Slate.DestroyWindowImmediately(Window.ToSharedRef()); }
        }

        auto Load() -> bool
        {
            FCkUiWidgetRegistry Registry;
            if (!FCkUiSlider::Register(Registry).Succeeded) { return false; }
            FCkUiView::FDataBindings Data;
            Data.String.Add(TEXT("active"), TAttribute<FString>::CreateLambda([this] { return Active; }));
            Data.Number.Add(TEXT("value"), TAttribute<float>::CreateLambda([this] { return Value; }));
            Data.StringChanged.Add(TEXT("activate"), FCkUiOnStringChanged::CreateLambda([this](const FString& InKey) { Active = InKey; }));
            Data.NumberChanged.Add(TEXT("changed"), FCkUiOnNumberChanged::CreateLambda([this](float) { ++ChangedCalls; }));
            Data.NumberInteraction.Add(TEXT("interaction"), FCkUiOnNumberInteraction::CreateLambda([this](const FCkUiNumberInteraction& InEvent) { Events.Add(InEvent); }));
            View = FCkUiView::Create({}, {}, {}, {}, MoveTemp(Data), Registry.CreateSnapshot());
            Window = SNew(SWindow).AutoCenter(EAutoCenter::None).ClientSize(FVector2D(360.0f, 180.0f)).CreateTitleBar(false).HasCloseButton(false)[View->GetRegion(TEXT("main"))];
            Slate.AddWindow(Window.ToSharedRef(), true);
            if (!View->TryReload(Markup(), TEXT(".slider { min-width: 300px; max-width: 300px; min-height: 30px; max-height: 30px; }"), TEXT("UiTabsSliderInteractions")).Succeeded) { return false; }
            Tick(Slate);
            Slider = FindSlider(View->GetRegion(TEXT("main")));
            return Slider.IsValid();
        }

        auto Pointer(const float InFraction, const int32 InPhase) -> bool
        {
            const FGeometry Geometry = Slider->GetCachedGeometry();
            const FVector2D Position = Geometry.LocalToAbsolute(FVector2D(Geometry.GetLocalSize().X * InFraction, Geometry.GetLocalSize().Y * 0.5f));
            const TSet<FKey> Buttons = InPhase == 2 ? TSet<FKey>{} : TSet<FKey>{EKeys::LeftMouseButton};
            const FPointerEvent Event(0, FSlateApplication::CursorPointerIndex, Position, Position, Buttons,
                InPhase == 1 ? EKeys::Invalid : EKeys::LeftMouseButton, 0.0f, FModifierKeysState{});
            FWidgetPath Path;
            if (!Slate.GeneratePathToWidgetUnchecked(Slider.ToSharedRef(), Path)) { return false; }
            const FReply Reply = InPhase == 0 ? Slider->OnMouseButtonDown(Geometry, Event)
                : InPhase == 1 ? Slider->OnMouseMove(Geometry, Event) : Slider->OnMouseButtonUp(Geometry, Event);
            Slate.ProcessReply(Path, Reply, &Path, &Event, 0);
            return Reply.IsEventHandled();
        }
    };
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiTabs_HiddenSliderCapture,
    "Ck.UiAuthoring.Tabs.HiddenPanelReleasesSliderCapture",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiTabs_HiddenSliderCapture::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_tabs_slider_interactions;
    if (!FSlateApplication::IsInitialized()) { AddError(TEXT("Tabs hidden-slider test requires Slate.")); return false; }

    FFixture Fixture;
    if (!TestTrue(TEXT("Tabs slider fixture loads"), Fixture.Load())) { return false; }
    if (!TestTrue(TEXT("Visible tab slider pointer-down starts a production gesture"), Fixture.Pointer(0.4f, 0))) { return false; }
    Tick(Fixture.Slate);
    const FGeometry PreHideGeometry = Fixture.Slider->GetCachedGeometry();
    const FVector2D LatePointerPosition = PreHideGeometry.LocalToAbsolute(FVector2D(PreHideGeometry.GetLocalSize().X * 0.7f, PreHideGeometry.GetLocalSize().Y * 0.5f));
    const int32 ChangedCallsBeforeHide = Fixture.ChangedCalls;
    TestTrue(TEXT("Visible tab slider owns the real Slate cursor captor"), Fixture.Slate.GetCursorUser()->GetPointerCaptor(FSlateApplication::CursorPointerIndex) == Fixture.Slider);
    if (!TestTrue(TEXT("Pointer gesture emits its initial Begin"), Fixture.Events.Num() == 1 && Fixture.Events[0].Phase == ECkUiInteractionPhase::Begin)) { return false; }

    Fixture.Active = TEXT("second");
    Tick(Fixture.Slate);
    TestTrue(TEXT("Hiding the active slider panel releases the real Slate cursor captor"), Fixture.Slate.GetCursorUser()->GetPointerCaptor(FSlateApplication::CursorPointerIndex) != Fixture.Slider
        && !Fixture.Slider->HasMouseCapture());
    TestTrue(TEXT("Hidden slider capture loss emits exactly one Cancel and no Commit"), Fixture.Events.Num() == 2
        && Fixture.Events[1].Phase == ECkUiInteractionPhase::Cancel);
    TestEqual(TEXT("Hidden slider cancellation does not dispatch Changed"), Fixture.ChangedCalls, ChangedCallsBeforeHide);

    const TSet<FKey> LateMoveButtons{EKeys::LeftMouseButton};
    const FPointerEvent LateMove(0, FSlateApplication::CursorPointerIndex, LatePointerPosition, LatePointerPosition,
        LateMoveButtons, EKeys::Invalid, 0.0f, FModifierKeysState{});
    const TSet<FKey> LateUpButtons;
    const FPointerEvent LateUp(0, FSlateApplication::CursorPointerIndex, LatePointerPosition, LatePointerPosition,
        LateUpButtons, EKeys::LeftMouseButton, 0.0f, FModifierKeysState{});
    Fixture.Slate.ProcessMouseMoveEvent(LateMove);
    Fixture.Slate.ProcessMouseButtonUpEvent(LateUp);
    Tick(Fixture.Slate);
    TestTrue(TEXT("Late pointer move and up from the hidden slider cannot notify its consumer"), Fixture.Events.Num() == 2
        && Fixture.ChangedCalls == ChangedCallsBeforeHide);

    FFixture Released;
    if (!TestTrue(TEXT("View-release slider fixture loads"), Released.Load())
        || !TestTrue(TEXT("View-release slider pointer-down starts a production gesture"), Released.Pointer(0.4f, 0))) { return false; }
    Tick(Released.Slate);
    const TSharedPtr<SSlider> HeldSlider = Released.Slider;
    TestTrue(TEXT("View-release slider owns the real Slate cursor captor before destruction"), Released.Slate.GetCursorUser()->GetPointerCaptor(FSlateApplication::CursorPointerIndex) == HeldSlider);
    Released.View.Reset();
    Tick(Released.Slate);
    TestTrue(TEXT("Destroying a view with an active slider releases the real Slate cursor captor"), Released.Slate.GetCursorUser()->GetPointerCaptor(FSlateApplication::CursorPointerIndex) != HeldSlider
        && !HeldSlider->HasMouseCapture());
    return true;
}
#endif // WITH_DEV_AUTOMATION_TESTS
