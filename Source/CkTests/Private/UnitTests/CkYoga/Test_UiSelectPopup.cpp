#include "CkSlateLayout/CkUiCollection.h"
#include "CkSlateLayout/CkUiSelect.h"
#include "CkSlateLayout/SCkUiSurface.h"

#include "Framework/Application/SlateApplication.h"
#include "Framework/Application/SlateUser.h"
#include "Input/Events.h"
#include "Input/PopupMethodReply.h"
#include "InputCoreTypes.h"
#include "Layout/Children.h"
#include "Layout/WidgetPath.h"
#include "Misc/AutomationTest.h"
#include "Styling/CoreStyle.h"
#include "Widgets/Input/SMenuAnchor.h"
#include "Widgets/Layout/SBox.h"
#include "Widgets/SWindow.h"
#include "Widgets/Text/STextBlock.h"

#if WITH_DEV_AUTOMATION_TESTS
namespace ck_tests_ui_select_popup
{
    class SCurrentWindowPopupHost final : public SBox
    {
    public:
        virtual FPopupMethodReply OnQueryPopupMethod() const override
        {
            return FPopupMethodReply::UseMethod(EPopupMethod::UseCurrentWindow);
        }
    };

    auto Markup(const bool InIncludeSelect = true) -> FString
    {
        return InIncludeSelect
            ? TEXT("<ui version=\"1\"><region name=\"main\"><column id=\"root\" class=\"root\"><select id=\"select\" value-bind=\"value\" options-bind=\"options\" changed=\"changed\"/></column></region></ui>")
            : TEXT("<ui version=\"1\"><region name=\"main\"><column id=\"root\" class=\"root\"/></region></ui>");
    }

    auto Record(const TCHAR* InKey, const TCHAR* InLabel) -> FCkUiRecordData
    {
        FCkUiRecordData Result;
        Result.Key = InKey;
        Result.Fields.Add(TEXT("label"), FCkUiFieldValue{.Kind = ECkUiFieldKind::Text, .Text = FText::FromString(InLabel)});
        return Result;
    }

    auto Options() -> TArray<FCkUiRecordData>
    {
        return {Record(TEXT("a"), TEXT("Alpha")), Record(TEXT("b"), TEXT("Beta"))};
    }

    auto Tick(FSlateApplication& InSlate) -> void
    {
        InSlate.PumpMessages();
        InSlate.Tick();
        InSlate.Tick();
    }

    auto Key(const FKey InKey) -> FKeyEvent
    {
        return FKeyEvent(InKey, FModifierKeysState{}, 0, false, 0, 0);
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

    auto FindText(const TSharedRef<SWidget>& InRoot, const FString& InText) -> TSharedPtr<STextBlock>
    {
        if (InRoot->GetTypeAsString() == TEXT("STextBlock"))
        {
            const TSharedRef<STextBlock> Text = StaticCastSharedRef<STextBlock>(InRoot);
            if (Text->GetText().ToString() == InText) { return Text; }
        }
        const FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<STextBlock> Found = FindText(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InText); Found.IsValid()) { return Found; }
        }
        return {};
    }

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
            if (!FCkUiSelect::Register(Registry).Succeeded) { return false; }
            if (!FCkUiCollection::TryCreate({{TEXT("label"), ECkUiFieldKind::Text}}, Collection).Succeeded
                || !Collection->TrySetRecords(Options()).Succeeded) { return false; }
            FCkUiView::FDataBindings Data;
            Data.String.Add(TEXT("value"), TAttribute<FString>::CreateLambda([this] { return Value; }));
            Data.Collections.Add(TEXT("options"), Collection);
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
            Scope.Window = SNew(SWindow).AutoCenter(EAutoCenter::None).ClientSize(FVector2D(360.0f, 140.0f)).CreateTitleBar(false).HasCloseButton(false)[Host];
            Slate.AddWindow(Scope.Window.ToSharedRef(), true);
            if (!View->TryReload(Markup(), TEXT(".root { padding: 2px; }"), TEXT("UiSelectPopupInitial")).Succeeded) { return false; }
            Tick(Slate);
            Select = FindSelect(Region.ToSharedRef());
            Menu = StaticCastSharedPtr<SMenuAnchor>(Select);
            return Select.IsValid() && Menu.IsValid();
        }

        auto Open() -> bool
        {
            Slate.SetUserFocus(0, Select, EFocusCause::SetDirectly);
            if (Slate.GetUserFocusedWidget(0) != Select) { OpenDiagnostic = TEXT("Cannot focus select"); return false; }
            Tick(Slate);
            const bool Handled = Slate.ProcessKeyDownEvent(Key(EKeys::SpaceBar));
            Tick(Slate);
            PopupWindow = Menu->GetMenuWindow();
            OpenDiagnostic = FString::Printf(TEXT("Handled=%d Open=%d Window=%d Enabled=%d CurrentWindow=%d"),
                Handled, Menu->IsOpen(), PopupWindow.IsValid(), Select->IsEnabled(), UseCurrentWindow);
            return Handled && Menu->IsOpen() && PopupWindow.IsValid();
        }

        FSlateApplication& Slate;
        bool UseCurrentWindow = false;
        FString Value = TEXT("a");
        FString OpenDiagnostic;
        int32 ChangedCalls = 0;
        TSharedPtr<FCkUiCollection> Collection;
        TSharedPtr<FCkUiView> View;
        TSharedPtr<SWidget> Region;
        TSharedPtr<SWidget> Select;
        TSharedPtr<SMenuAnchor> Menu;
        TSharedPtr<SWindow> PopupWindow;
        FWindowScope Scope;
    };

    auto AssertCurrentFocusPath(FAutomationTestBase& InTest, FSlateApplication& InSlate, const TSharedRef<SWidget>& InFocusedLeaf) -> bool
    {
        const TSharedPtr<FSlateUser> User = InSlate.GetUser(0);
        FWidgetPath MountedPath;
        if (!User.IsValid() || !InSlate.GeneratePathToWidgetUnchecked(InFocusedLeaf, MountedPath)) { return false; }
        for (int32 Index = 0; Index < MountedPath.Widgets.Num(); ++Index)
        {
            InTest.TestTrue(TEXT("Every current popup ancestor belongs to the public focus path"), User->IsWidgetInFocusPath(MountedPath.Widgets[Index].Widget));
        }
        return true;
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiSelectPopup_Reload,
    "Ck.UiAuthoring.Select.PopupSurvivesCompatibleReload",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiSelectPopup_Reload::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_select_popup;
    if (!FSlateApplication::IsInitialized()) { AddError(TEXT("Select popup test requires Slate.")); return false; }

    for (const bool UseCurrentWindow : {false, true})
    {
        FFixture Fixture(UseCurrentWindow);
        if (!TestTrue(UseCurrentWindow ? TEXT("Current-window popup fixture loads") : TEXT("New-window popup fixture loads"), Fixture.Load())
            || !TestTrue(TEXT("Native SpaceBar opens the production select popup"), Fixture.Open())) { return false; }
        const TSharedPtr<SWidget> FocusedLeaf = Fixture.Slate.GetUserFocusedWidget(0);
        if (!TestTrue(TEXT("Opening focuses a popup descendant instead of the anchor"), FocusedLeaf.IsValid() && FocusedLeaf != Fixture.Select)) { return false; }
        const TSharedPtr<SWindow> PopupWindow = Fixture.PopupWindow;
        TestTrue(TEXT("Popup host uses the requested Slate popup method"), (Fixture.Menu->GetMenuWindow() == Fixture.Scope.Window) == UseCurrentWindow);
        FWidgetPath FocusPathBeforeReload;
        if (!TestTrue(TEXT("Open popup focused leaf has a pre-reload path"), Fixture.Slate.GeneratePathToWidgetUnchecked(FocusedLeaf.ToSharedRef(), FocusPathBeforeReload))) { return false; }
        const FVector2D SelectPositionBeforeReload = Fixture.Select->GetCachedGeometry().GetAbsolutePosition();
        const int64 Revision = Fixture.View->GetRevision();
        if (!TestTrue(TEXT("Actual parent-padding reload succeeds while popup is open"), Fixture.View->TryReload(Markup(), TEXT(".root { padding: 13px; }"), TEXT("UiSelectPopupPaddingReload")).Succeeded)) { return false; }
        Tick(Fixture.Slate);
        TestTrue(TEXT("Compatible reload advances the view exactly once"), Fixture.View->GetRevision() == Revision + 1);
        TestTrue(TEXT("Compatible reload retains the exact native select"), FindSelect(Fixture.Region.ToSharedRef()) == Fixture.Select);
        const FVector2D SelectPositionAfterReload = Fixture.Select->GetCachedGeometry().GetAbsolutePosition();
        TestTrue(TEXT("Changed parent padding moves the retained select anchor"), !SelectPositionAfterReload.Equals(SelectPositionBeforeReload));
        TestTrue(TEXT("Compatible reload keeps the same open popup window"), Fixture.Menu->IsOpen() && Fixture.Menu->GetMenuWindow() == PopupWindow);
        TestTrue(TEXT("Compatible reload keeps the exact focused popup leaf"), Fixture.Slate.GetUserFocusedWidget(0) == FocusedLeaf);
        if (!TestTrue(TEXT("Current popup ancestry is rebuilt for the focused leaf"), AssertCurrentFocusPath(*this, Fixture.Slate, FocusedLeaf.ToSharedRef()))) { return false; }
        FWidgetPath FocusPathAfterReload;
        if (!TestTrue(TEXT("Open popup focused leaf has a current path"), Fixture.Slate.GeneratePathToWidgetUnchecked(FocusedLeaf.ToSharedRef(), FocusPathAfterReload))) { return false; }
        for (int32 PreviousIndex = 0; PreviousIndex < FocusPathBeforeReload.Widgets.Num(); ++PreviousIndex)
        {
            const TSharedRef<SWidget> Previous = FocusPathBeforeReload.Widgets[PreviousIndex].Widget;
            bool StillMounted = false;
            for (int32 CurrentIndex = 0; CurrentIndex < FocusPathAfterReload.Widgets.Num(); ++CurrentIndex)
            { StillMounted |= FocusPathAfterReload.Widgets[CurrentIndex].Widget == Previous; }
            if (!StillMounted) { TestFalse(TEXT("Detached pre-reload popup ancestor leaves the public focus path"), Fixture.Slate.GetUser(0)->IsWidgetInFocusPath(Previous)); }
        }

        if (!TestTrue(TEXT("Removing the open selected option publishes"), Fixture.Collection->TrySetRecords({Record(TEXT("b"), TEXT("Beta refreshed"))}).Succeeded)) { return false; }
        Tick(Fixture.Slate);
        TestTrue(TEXT("Selected-option removal leaves its popup open without a callback"), Fixture.Menu->IsOpen()
            && Fixture.ChangedCalls == 0 && FindText(PopupWindow.ToSharedRef(), TEXT("Beta refreshed")).IsValid());
        Fixture.Value = TEXT("b");
        Tick(Fixture.Slate);
        TestTrue(TEXT("External bound-key synchronization leaves the popup open and silent"), Fixture.Menu->IsOpen() && Fixture.ChangedCalls == 0);
        if (!TestTrue(TEXT("Restoring the open option collection publishes fresh rows"), Fixture.Collection->TrySetRecords({Record(TEXT("a"), TEXT("Alpha restored")), Record(TEXT("b"), TEXT("Beta restored"))}).Succeeded)) { return false; }
        Tick(Fixture.Slate);
        TestTrue(TEXT("Restored option labels reach the already open popup"), Fixture.Menu->IsOpen()
            && FindText(PopupWindow.ToSharedRef(), TEXT("Alpha restored")).IsValid()
            && FindText(PopupWindow.ToSharedRef(), TEXT("Beta restored")).IsValid());

        Fixture.Value = TEXT("a");
        Tick(Fixture.Slate);
        TestTrue(TEXT("External reset before pointer selection leaves the popup open and silent"), Fixture.Menu->IsOpen() && Fixture.ChangedCalls == 0);
        const TSharedPtr<STextBlock> Beta = FindText(PopupWindow.ToSharedRef(), TEXT("Beta restored"));
        if (!TestTrue(TEXT("Rendered popup exposes the production Beta row label"), Beta.IsValid())) { return false; }
        const FGeometry Geometry = Beta->GetCachedGeometry();
        const FVector2D Position = Geometry.LocalToAbsolute(Geometry.GetLocalSize() * 0.5f);
        const TSet<FKey> PressedButtons{EKeys::LeftMouseButton};
        const FPointerEvent Down(0, FSlateApplication::CursorPointerIndex, Position, Position, PressedButtons, EKeys::LeftMouseButton, 0.0f, FModifierKeysState{});
        const TSet<FKey> UpButtons;
        const FPointerEvent Up(0, FSlateApplication::CursorPointerIndex, Position, Position, UpButtons, EKeys::LeftMouseButton, 0.0f, FModifierKeysState{});
        const TSharedPtr<SWidget> CaptorBeforeClick = Fixture.Slate.GetCursorUser()->GetPointerCaptor(FSlateApplication::CursorPointerIndex);
        TestTrue(TEXT("Slate routes a real pointer-down to the rendered Beta popup row"), Fixture.Slate.ProcessMouseButtonDownEvent(PopupWindow->GetNativeWindow(), Down));
        TestTrue(TEXT("Slate routes the matching pointer-up to release the native click"), Fixture.Slate.ProcessMouseButtonUpEvent(Up));
        Tick(Fixture.Slate);
        TestTrue(TEXT("Pointer selection dispatches exactly one stable Beta key"), Fixture.ChangedCalls == 1 && Fixture.Value == TEXT("b"));
        TestTrue(TEXT("Completed popup click leaves no orphaned cursor capture"), Fixture.Slate.GetCursorUser()->GetPointerCaptor(FSlateApplication::CursorPointerIndex) == CaptorBeforeClick);

        Fixture.Value = TEXT("a");
        Tick(Fixture.Slate);
        const bool Reopened = Fixture.Open();
        if (!TestTrue(*FString::Printf(TEXT("Native SpaceBar reopens the popup for stale-row selection: %s"), *Fixture.OpenDiagnostic), Reopened)) { return false; }
        const TSharedPtr<STextBlock> StaleBeta = FindText(Fixture.PopupWindow.ToSharedRef(), TEXT("Beta restored"));
        if (!TestTrue(TEXT("Reopened popup exposes a rendered Beta row before collection removal"), StaleBeta.IsValid())) { return false; }
        const FGeometry StaleGeometry = StaleBeta->GetCachedGeometry();
        const FVector2D StalePosition = StaleGeometry.LocalToAbsolute(StaleGeometry.GetLocalSize() * 0.5f);
        const FPointerEvent StaleDown(0, FSlateApplication::CursorPointerIndex, StalePosition, StalePosition, PressedButtons, EKeys::LeftMouseButton, 0.0f, FModifierKeysState{});
        const TSet<FKey> StaleUpButtons;
        const FPointerEvent StaleUp(0, FSlateApplication::CursorPointerIndex, StalePosition, StalePosition, StaleUpButtons, EKeys::LeftMouseButton, 0.0f, FModifierKeysState{});
        if (!TestTrue(TEXT("Removing the selected row publishes before stale pointer routing"), Fixture.Collection->TrySetRecords({Record(TEXT("a"), TEXT("Alpha restored"))}).Succeeded)) { return false; }
        TestTrue(TEXT("Stale rendered row still receives the queued pointer event"), Fixture.Slate.ProcessMouseButtonDownEvent(Fixture.PopupWindow->GetNativeWindow(), StaleDown));
        Fixture.Slate.ProcessMouseButtonUpEvent(StaleUp);
        Tick(Fixture.Slate);
        TestTrue(TEXT("Stale rendered row cannot dispatch after its stable key is removed"), Fixture.ChangedCalls == 1 && Fixture.Value == TEXT("a"));
    }
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiSelectPopup_Removal,
    "Ck.UiAuthoring.Select.PopupClosesOnRemoval",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiSelectPopup_Removal::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_select_popup;
    if (!FSlateApplication::IsInitialized()) { AddError(TEXT("Select popup removal test requires Slate.")); return false; }

    for (const bool UseCurrentWindow : {false, true})
    {
        FFixture Fixture(UseCurrentWindow);
        if (!TestTrue(TEXT("Removal fixture loads"), Fixture.Load()) || !TestTrue(TEXT("Removal fixture opens a native popup"), Fixture.Open())) { return false; }
        const TSharedPtr<SMenuAnchor> HeldMenu = Fixture.Menu;
        const TSharedPtr<SWidget> HeldSelect = Fixture.Select;
        const TSharedPtr<SWidget> HeldFocusedLeaf = Fixture.Slate.GetUserFocusedWidget(0);
        FWidgetPath FocusPathBeforeRemoval;
        if (!TestTrue(TEXT("Focused popup leaf has a path before select removal"), HeldFocusedLeaf.IsValid()
            && Fixture.Slate.GeneratePathToWidgetUnchecked(HeldFocusedLeaf.ToSharedRef(), FocusPathBeforeRemoval))) { return false; }
        const int32 CallsBeforeRemoval = Fixture.ChangedCalls;
        if (!TestTrue(TEXT("Removing the authored select succeeds"), Fixture.View->TryReload(Markup(false), TEXT(".root { padding: 13px; }"), TEXT("UiSelectPopupRemoval")).Succeeded)) { return false; }
        Tick(Fixture.Slate);
        TestFalse(TEXT("Held native menu anchor is closed when its select is removed"), HeldMenu->IsOpen());
        TestTrue(TEXT("Removal clears focus from the held popup leaf"), Fixture.Slate.GetUserFocusedWidget(0) != HeldFocusedLeaf);
        const TSharedPtr<FSlateUser> User = Fixture.Slate.GetUser(0);
        if (!TestTrue(TEXT("User zero remains available after popup removal"), User.IsValid())) { return false; }
        FWidgetPath FocusPathAfterRemoval;
        const TSharedPtr<SWidget> FocusedAfterRemoval = Fixture.Slate.GetUserFocusedWidget(0);
        if (FocusedAfterRemoval.IsValid())
        { TestTrue(TEXT("Any redirected focus remains mounted after removal"), Fixture.Slate.GeneratePathToWidgetUnchecked(FocusedAfterRemoval.ToSharedRef(), FocusPathAfterRemoval)); }
        for (int32 Index = 0; Index < FocusPathBeforeRemoval.Widgets.Num(); ++Index)
        {
            bool StillMounted = false;
            for (int32 CurrentIndex = 0; CurrentIndex < FocusPathAfterRemoval.Widgets.Num(); ++CurrentIndex)
            { StillMounted |= FocusPathAfterRemoval.Widgets[CurrentIndex].Widget == FocusPathBeforeRemoval.Widgets[Index].Widget; }
            if (!StillMounted) { TestFalse(TEXT("Removed popup-only ancestor leaves the public focus path"), User->IsWidgetInFocusPath(FocusPathBeforeRemoval.Widgets[Index].Widget)); }
        }
        const FReply HeldInput = HeldSelect->OnKeyDown(HeldSelect->GetCachedGeometry(), Key(EKeys::Down));
        TestFalse(TEXT("Held removed native select safely rejects later input"), HeldInput.IsEventHandled());
        TestEqual(TEXT("Held removed select cannot invoke the old consumer callback"), Fixture.ChangedCalls, CallsBeforeRemoval);
    }
    return true;
}
#endif // WITH_DEV_AUTOMATION_TESTS
