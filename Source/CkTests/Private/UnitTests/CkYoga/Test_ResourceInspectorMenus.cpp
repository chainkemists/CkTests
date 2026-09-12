#include "CkResourceInspector/CkResourceInspectorModel.h"
#include "CkSlateLayout/SCkUiMenuButton.h"

#include "Framework/Application/SlateApplication.h"
#include "Input/Events.h"
#include "InputCoreTypes.h"
#include "Interfaces/IPluginManager.h"
#include "Layout/Children.h"
#include "Misc/AutomationTest.h"
#include "Misc/Paths.h"
#include "Widgets/SWindow.h"
#include "Widgets/Text/STextBlock.h"

#if WITH_DEV_AUTOMATION_TESTS
namespace ck_tests_resource_inspector_menus
{
    auto Tick(FSlateApplication& Slate) -> void { Slate.PumpMessages(); Slate.Tick(); Slate.Tick(); }

    auto FindText(const TSharedRef<SWidget>& Root, const FString& Label) -> TSharedPtr<STextBlock>
    {
        if (Root->GetTypeAsString() == TEXT("STextBlock"))
        {
            const auto Text = StaticCastSharedRef<STextBlock>(Root);
            if (Text->GetText().ToString() == Label) { return Text; }
        }
        const FChildren* Children = Root->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            if (auto Found = FindText(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), Label); Found.IsValid()) { return Found; }
        }
        return {};
    }

    auto Click(FSlateApplication& Slate, const TSharedRef<SWindow>& Window, const TSharedRef<SWidget>& Widget) -> bool
    {
        const FGeometry Geometry = Widget->GetCachedGeometry();
        if (Geometry.GetLocalSize().X <= 0 || Geometry.GetLocalSize().Y <= 0) { return false; }
        const FVector2D Position = Geometry.LocalToAbsolute(Geometry.GetLocalSize() * 0.5f);
        Slate.SetCursorPos(Position);
        const TSet<FKey> MoveButtons;
        const FPointerEvent Move(0, FSlateApplication::CursorPointerIndex, Position, Position, MoveButtons, EKeys::Invalid, 0, FModifierKeysState{});
        Slate.ProcessMouseMoveEvent(Move, true);
        const TSet<FKey> DownButtons{EKeys::LeftMouseButton};
        const FPointerEvent Down(0, FSlateApplication::CursorPointerIndex, Position, Position, DownButtons, EKeys::LeftMouseButton, 0, FModifierKeysState{});
        const TSet<FKey> UpButtons;
        const FPointerEvent Up(0, FSlateApplication::CursorPointerIndex, Position, Position, UpButtons, EKeys::LeftMouseButton, 0, FModifierKeysState{});
        const bool Handled = Slate.ProcessMouseButtonDownEvent(Window->GetNativeWindow(), Down);
        Slate.ProcessMouseButtonUpEvent(Up);
        Tick(Slate);
        return Handled;
    }

    struct FWindowScope
    {
        FVector2D PreviousCursor = FSlateApplication::Get().GetCursorPos();
        TSharedPtr<SWindow> Window;
        ~FWindowScope() { if (Window.IsValid()) { FSlateApplication::Get().DestroyWindowImmediately(Window.ToSharedRef()); } FSlateApplication::Get().SetCursorPos(PreviousCursor); }
    };
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkResourceInspector_Menus,
    "Ck.ResourceInspector.Menus.NativeActions",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkResourceInspector_Menus::RunTest(const FString&) -> bool
{
    using namespace ck_tests_resource_inspector_menus;
    if (!FSlateApplication::IsInitialized()) { AddError(TEXT("Menu test requires Slate.")); return false; }
    const TSharedPtr<IPlugin> Plugin = IPluginManager::Get().FindPlugin(TEXT("CkTests"));
    if (!TestTrue(TEXT("CkTests resources resolve"), Plugin.IsValid())) { return false; }
    TSharedPtr<FCkResourceInspectorModel> Model;
    FString Error;
    if (!TestTrue(TEXT("Resource Inspector model creates"), FCkResourceInspectorModel::TryCreate({}, Model, Error, 0))) { AddError(Error); return false; }
    const TSharedRef<FCkUiView> View = Model->GetView();
    FSlateApplication& Slate = FSlateApplication::Get();
    FWindowScope Scope;
    Scope.Window = SNew(SWindow).ClientSize(FVector2D{960, 640}).CreateTitleBar(false).HasCloseButton(false)[Model->GetRoot()];
    Slate.AddWindow(Scope.Window.ToSharedRef(), true);
    const FString Resources = FPaths::Combine(Plugin->GetBaseDir(), TEXT("Resources/ResourceInspector"));
    const auto Loaded = View->ReloadFiles(FPaths::Combine(Resources, TEXT("ResourceInspector.ui.html")), FPaths::Combine(Resources, TEXT("ResourceInspector.ui.css")));
    if (!TestTrue(TEXT("Installed authored menu document loads"), Loaded.Succeeded)) { for (const FString& Failure : Loaded.Errors) { AddError(Failure); } return false; }
    Tick(Slate);
    const auto Menu = View->GetMenuButton(TEXT("inspector-dialog/content/inspector-actions-button"));
    if (!TestTrue(TEXT("Installed Actions menu uses the shared presenter"), Menu.IsValid())) { return false; }
    TestTrue(TEXT("Empty scenario sets up a real observable action result"), Model->TrySetRowCount(0, Error));
    Tick(Slate);
    const auto Trigger = FindText(Menu.ToSharedRef(), TEXT("..."));
    if (!TestTrue(TEXT("Native pointer opens the overflow menu"), Trigger.IsValid() && Click(Slate, Scope.Window.ToSharedRef(), Trigger.ToSharedRef()) && Menu->IsOpen())) { return false; }
    const auto Content = Menu->GetFocusTransferTarget();
    const auto PopupWindow = Menu->GetMenuWindow();
    const auto Sample = Content.IsValid() ? FindText(Content.ToSharedRef(), TEXT("Load sample resources")) : nullptr;
    if (!TestTrue(TEXT("Sample command is mounted in an owned native popup"), Sample.IsValid() && PopupWindow.IsValid())) { return false; }
    TestTrue(TEXT("Native menu command pointer input is handled"), Click(Slate, PopupWindow.ToSharedRef(), Sample.ToSharedRef()));
    TestEqual(TEXT("Authored action populates the actual resource model"), Model->GetRowCount(), 12);
    TestEqual(TEXT("Authored action updates the actual virtualized table"), View->GetTable(TEXT("inspector-dialog/content/resources"))->GetVisibleRecordCount(), 12);
    TestFalse(TEXT("Command selection dismisses the menu"), Menu->IsOpen());
    const auto Table = View->GetTable(TEXT("inspector-dialog/content/resources"));
    const int64 RevisionBeforeStylesheetReload = View->GetRevision();
    const auto StylesheetReload = View->ReloadFiles(FPaths::Combine(Resources, TEXT("ResourceInspector.ui.html")), FPaths::Combine(Resources, TEXT("ResourceInspector.ui.css")));
    if (!TestTrue(TEXT("Compatible installed stylesheet reload succeeds for the overflow menu"), StylesheetReload.Succeeded)) { return false; }
    Tick(Slate);
    const auto ReloadedMenu = View->GetMenuButton(TEXT("inspector-dialog/content/inspector-actions-button"));
    TestTrue(TEXT("Compatible stylesheet reload retains the real overflow menu identity and closes its deferred popup"),
        View->GetRevision() == RevisionBeforeStylesheetReload + 1 && ReloadedMenu == Menu && !Menu->IsOpen());
    const FString ResourceKey = Model->GetCollection()->GetRecords()[0]->GetKey();
    TestTrue(TEXT("Resource context target selects by stable key"), Table->TrySelectKey(ResourceKey, true));
    if (!TestTrue(TEXT("Reloaded native overflow menu opens after a real selection"), Click(Slate, Scope.Window.ToSharedRef(), Menu.ToSharedRef()) && Menu->IsOpen())) { return false; }
    const TSharedPtr<SWidget> ReloadedContent = Menu->GetFocusTransferTarget();
    const TSharedPtr<SWindow> ReloadedPopup = Menu->GetMenuWindow();
    const TSharedPtr<STextBlock> ClearSelection = ReloadedContent.IsValid() ? FindText(ReloadedContent.ToSharedRef(), TEXT("Clear selection")) : nullptr;
    if (!TestTrue(TEXT("Reloaded overflow menu exposes its enabled selection command"), ClearSelection.IsValid() && ReloadedPopup.IsValid())) { return false; }
    TestTrue(TEXT("Reloaded overflow menu command dispatches through the actual model"), Click(Slate, ReloadedPopup.ToSharedRef(), ClearSelection.ToSharedRef()));
    TestFalse(TEXT("Reloaded overflow command clears the actual table selection"), Table->GetSelectedKey().IsSet());
    TestFalse(TEXT("Reloaded overflow command dismisses the menu"), Menu->IsOpen());
    TestTrue(TEXT("Resource context target reselects by stable key after overflow reload coverage"), Table->TrySelectKey(ResourceKey, true));
    Model->TrySetDetailTab(TEXT("overview"));
    Slate.SetUserFocus(0, Table->GetList(), EFocusCause::SetDirectly);
    const FKeyEvent ContextKey(EKeys::F10, FModifierKeysState(true, false, false, false, false, false, false, false, false), 0, false, 0, 0);
    TestTrue(TEXT("Native context key opens the installed resource menu"), Slate.ProcessKeyDownEvent(ContextKey));
    Tick(Slate);
    TArray<TSharedRef<SWindow>> Windows;
    Slate.GetAllVisibleWindowsOrdered(Windows);
    TSharedPtr<SWindow> ContextWindow;
    TSharedPtr<STextBlock> Properties;
    for (const TSharedRef<SWindow>& Window : Windows)
    {
        Properties = FindText(Window, TEXT("Show properties"));
        if (Properties.IsValid()) { ContextWindow = Window; break; }
    }
    if (!TestTrue(TEXT("Installed resource context command is visible"), Properties.IsValid() && ContextWindow.IsValid())) { return false; }
    TestTrue(TEXT("Pointer activates the authored resource context command"), Click(Slate, ContextWindow.ToSharedRef(), Properties.ToSharedRef()));
    TestEqual(TEXT("Context action opens actual resource properties"), Model->GetDetailTab(), FString(TEXT("properties")));
    TestTrue(TEXT("Context action retains the targeted resource"), Table->GetSelectedKey().IsSet() && Table->GetSelectedKey().GetValue() == ResourceKey);
    return true;
}
#endif
