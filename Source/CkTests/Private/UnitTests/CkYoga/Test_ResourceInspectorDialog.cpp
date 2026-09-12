#include "CkResourceInspector/CkResourceInspectorModel.h"

#include "CkSlateLayout/SCkUiSurface.h"
#include "CkSlateLayout/SCkUiTable.h"
#include "CkSlateLayout/CkFlexText.h"

#include "Framework/Application/SlateApplication.h"
#include "HAL/FileManager.h"
#include "ImageUtils.h"
#include "Input/Events.h"
#include "InputCoreTypes.h"
#include "Interfaces/IPluginManager.h"
#include "Layout/Children.h"
#include "Misc/AutomationTest.h"
#include "Misc/FileHelper.h"
#include "Misc/Paths.h"
#include "Widgets/SWindow.h"
#include "Widgets/Text/STextBlock.h"

#if WITH_DEV_AUTOMATION_TESTS
namespace ck_tests_resource_inspector_dialog
{
    auto Tick(FSlateApplication& InSlate) -> void { InSlate.PumpMessages(); InSlate.Tick(); InSlate.Tick(); }

    auto FindLabel(const TSharedRef<SWidget>& InRoot, const FString& InLabel) -> TSharedPtr<SWidget>
    {
        if (InRoot->GetTypeAsString() == TEXT("STextBlock") && StaticCastSharedRef<STextBlock>(InRoot)->GetText().ToString() == InLabel) { return InRoot; }
        if (InRoot->GetTypeAsString() == TEXT("SCkFlexText") && StaticCastSharedRef<SCkFlexText>(InRoot)->GetText().ToString() == InLabel) { return InRoot; }
        const FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<SWidget> Found = FindLabel(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InLabel); Found.IsValid()) { return Found; }
        }
        return {};
    }

    auto FindTagged(const TSharedRef<SWidget>& InRoot, const FName InTag) -> TSharedPtr<SWidget>
    {
        if (InRoot->GetTag() == InTag) { return InRoot; }
        const FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<SWidget> Found = FindTagged(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InTag); Found.IsValid()) { return Found; }
        }
        return {};
    }

    auto Click(FSlateApplication& InSlate, const TSharedRef<SWindow>& InWindow, const TSharedRef<SWidget>& InWidget) -> bool
    {
        const FGeometry Geometry = InWidget->GetCachedGeometry();
        if (Geometry.GetLocalSize().X <= 0.0f || Geometry.GetLocalSize().Y <= 0.0f) { return false; }
        const FVector2D Position = Geometry.LocalToAbsolute(Geometry.GetLocalSize() * 0.5f);
        InSlate.SetCursorPos(Position);
        const TSet<FKey> MoveButtons;
        const FPointerEvent Move(0, FSlateApplication::CursorPointerIndex, Position, Position, MoveButtons, EKeys::Invalid, 0, FModifierKeysState{});
        InSlate.ProcessMouseMoveEvent(Move, true);
        const TSet<FKey> DownButtons{EKeys::LeftMouseButton};
        const FPointerEvent Down(0, FSlateApplication::CursorPointerIndex, Position, Position, DownButtons, EKeys::LeftMouseButton, 0, FModifierKeysState{});
        const TSet<FKey> UpButtons;
        const FPointerEvent Up(0, FSlateApplication::CursorPointerIndex, Position, Position, UpButtons, EKeys::LeftMouseButton, 0, FModifierKeysState{});
        const bool bHandled = InSlate.ProcessMouseButtonDownEvent(InWindow->GetNativeWindow(), Down);
        InSlate.ProcessMouseButtonUpEvent(Up);
        Tick(InSlate);
        return bHandled;
    }

    auto SaveCapture(FSlateApplication& InSlate, const TSharedRef<SWidget>& InRoot, const FString& InPath) -> bool
    {
        TArray<FColor> Pixels;
        FIntVector Size = FIntVector::ZeroValue;
        if (!InSlate.TakeScreenshot(InRoot, Pixels, Size) || Size.X <= 0 || Size.Y <= 0 || Pixels.Num() < Size.X * Size.Y) { return false; }
        const FImageView Image(Pixels.GetData(), Size.X, Size.Y, ERawImageFormat::BGRA8);
        return FImageUtils::SaveImageByExtension(*InPath, Image);
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

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkResourceInspector_Dialog,
    "Ck.ResourceInspector.Dialog.NativeScenarios",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkResourceInspector_Dialog::RunTest(const FString&) -> bool
{
    using namespace ck_tests_resource_inspector_dialog;
    if (!FSlateApplication::IsInitialized()) { AddError(TEXT("Resource Inspector dialog test requires Slate.")); return false; }
    const TSharedPtr<IPlugin> Plugin = IPluginManager::Get().FindPlugin(TEXT("CkTests"));
    if (!TestTrue(TEXT("CkTests plugin resolves"), Plugin.IsValid())) { return false; }

    FString Error;
    TSharedPtr<FCkResourceInspectorModel> Model;
    if (!TestTrue(TEXT("Resource Inspector model creates"), FCkResourceInspectorModel::TryCreate({}, Model, Error, 0)) || !Model.IsValid()) { AddError(Error); return false; }
    const TSharedRef<FCkUiView> View = Model->GetView();
    FSlateApplication& Slate = FSlateApplication::Get();
    FWindowScope Scope{Slate};
    Scope.Window = SNew(SWindow).AutoCenter(EAutoCenter::None).ClientSize(FVector2D{960.0f, 640.0f}).CreateTitleBar(false).HasCloseButton(false)[Model->GetRoot()];
    Slate.AddWindow(Scope.Window.ToSharedRef(), true);

    const FString Resources = FPaths::Combine(Plugin->GetBaseDir(), TEXT("Resources/ResourceInspector"));
    const FString MarkupPath = FPaths::Combine(Resources, TEXT("ResourceInspector.ui.html"));
    const FString StylesheetPath = FPaths::Combine(Resources, TEXT("ResourceInspector.ui.css"));
    if (!TestTrue(TEXT("Installed Resource Inspector dialog document loads"), View->ReloadFiles(MarkupPath, StylesheetPath).Succeeded)) { return false; }
    Tick(Slate);

    const TSharedPtr<SCkUiTable> Table = View->GetTable(TEXT("inspector-dialog/content/resources"));
    const TSharedPtr<const FCkUiRecord> Resource = Model->GetCollection()->FindRecord(TEXT("resource-00000"));
    if (!TestTrue(TEXT("Dialog fixture has qualified table and resource"), Table.IsValid() && Resource.IsValid())) { return false; }
    TestTrue(TEXT("Select resource for clear dialog"), Table->TrySelectKey(Resource->GetKey(), true));
    TestTrue(TEXT("Create pinned snapshot for clear dialog"), Model->TryPinSelected(Error));
    Tick(Slate);
    const int32 RowCount = Model->GetPinnedSnapshots()->GetRecords().Num();
    const FString Note = TEXT("Dialog retained note");
    TestTrue(TEXT("Set retained note"), Model->TrySetSessionNote(Note, Error));

    const TSharedPtr<SWidget> Request = FindLabel(Model->GetRoot(), TEXT("Clear pinned snapshots"));
    if (!TestTrue(TEXT("Clear pinned snapshots action is present"), Request.IsValid() && Click(Slate, Scope.Window.ToSharedRef(), Request.ToSharedRef()))) { return false; }
    if (!TestTrue(TEXT("Opening clear dialog updates model state"), Model->IsClearPinsDialogOpen() && Model->GetPinnedSnapshots()->GetRecords().Num() == RowCount)) { return false; }
    const FString CaptureDirectory = FPaths::Combine(FPaths::ProjectSavedDir(), TEXT("Automation/ResourceInspector"));
    IFileManager::Get().MakeDirectory(*CaptureDirectory, true);
    TestTrue(TEXT("Dialog screenshot saves"), SaveCapture(Slate, Model->GetRoot(), FPaths::Combine(CaptureDirectory, TEXT("Dialog.png"))));

    const TSharedPtr<SWidget> Background = FindLabel(Model->GetRoot(), TEXT("Empty"));
    if (!TestTrue(TEXT("Dialog background target is present"), Background.IsValid())) { return false; }
    TestTrue(TEXT("Dialog backdrop routes background click"), Click(Slate, Scope.Window.ToSharedRef(), Background.ToSharedRef()));
    TestTrue(TEXT("Dialog backdrop blocks background action"), Model->GetRowCount() == 12 && Table->GetSelectedKey().IsSet() && Table->GetSelectedKey().GetValue() == Resource->GetKey());
    const TSharedPtr<SWidget> Cancel = FindLabel(Model->GetRoot(), TEXT("Cancel"));
    if (!TestTrue(TEXT("Cancel closes clear dialog"), Cancel.IsValid() && Click(Slate, Scope.Window.ToSharedRef(), Cancel.ToSharedRef()))) { return false; }
    TestTrue(TEXT("Cancel retains pin and session state"), !Model->IsClearPinsDialogOpen() && Model->GetPinnedSnapshots()->GetRecords().Num() == RowCount && Model->GetSessionNote() == Note);

    if (!TestTrue(TEXT("Reopen clear dialog"), Request.IsValid() && Click(Slate, Scope.Window.ToSharedRef(), Request.ToSharedRef()))) { return false; }
    const int32 ActivityCount = Model->GetActivity()->GetRecords().Num();
    const TSharedPtr<SWidget> Confirm = FindLabel(Model->GetRoot(), TEXT("Clear snapshots"));
    if (!TestTrue(TEXT("Confirm clears pinned snapshots"), Confirm.IsValid() && Click(Slate, Scope.Window.ToSharedRef(), Confirm.ToSharedRef()))) { return false; }
    TestTrue(TEXT("Confirm closes and clears exactly once"), !Model->IsClearPinsDialogOpen() && Model->GetPinnedSnapshots()->GetRecords().Num() == 0 && Model->GetActivity()->GetRecords().Num() == ActivityCount + 1);
    TestTrue(TEXT("Confirm preserves selection and note"), Table->GetSelectedKey().IsSet() && Table->GetSelectedKey().GetValue() == Resource->GetKey() && Model->GetSessionNote() == Note);

    TestTrue(TEXT("Re-pin selected resource before invalid reload"), Model->TryPinSelected(Error));
    // TryPinSelected changes the has-pins binding consumed by request-clear-pins;
    // advance the live Slate frame so its enabled state and hit grid are refreshed.
    Tick(Slate);
    if (Request.IsValid())
    {
        const FGeometry Geometry = Request->GetCachedGeometry();
        AddInfo(FString::Printf(TEXT("Dialog reopen before click: type=%s size=%.1fx%.1f abs=(%.1f,%.1f) has-pins=%d open=%d rows=%d"),
            *Request->GetTypeAsString(), Geometry.GetLocalSize().X, Geometry.GetLocalSize().Y,
            Geometry.LocalToAbsolute(Geometry.GetLocalSize() * 0.5f).X, Geometry.LocalToAbsolute(Geometry.GetLocalSize() * 0.5f).Y,
            Model->GetPinnedSnapshots()->GetRecords().Num() > 0 ? 1 : 0, Model->IsClearPinsDialogOpen() ? 1 : 0, Model->GetRowCount()));
    }
    else { AddInfo(TEXT("Dialog reopen before click: target missing")); }
    if (!TestTrue(TEXT("Reopen dialog before rejected reload"), Click(Slate, Scope.Window.ToSharedRef(), Request.ToSharedRef()) && Model->IsClearPinsDialogOpen())) { return false; }
    const FString InvalidPath = FPaths::Combine(FPaths::ProjectSavedDir(), TEXT("Automation/ResourceInspector/DialogInvalid.ui.html"));
    if (!TestTrue(TEXT("Write invalid dialog markup"), FFileHelper::SaveStringToFile(TEXT("<ui version=\"1\"><region name=\"main\"><table id=\"resources\""), *InvalidPath))) { return false; }
    TestFalse(TEXT("Invalid reload rejects atomically"), View->ReloadFiles(InvalidPath, StylesheetPath).Succeeded);
    Tick(Slate);
    TestTrue(TEXT("Rejected reload preserves open dialog and pin"), Model->IsClearPinsDialogOpen() && Model->GetPinnedSnapshots()->GetRecords().Num() == 1);
    if (!TestTrue(TEXT("Valid reload succeeds and retains table identity"), View->ReloadFiles(MarkupPath, StylesheetPath).Succeeded)) { return false; }
    Tick(Slate);
    TestTrue(TEXT("Valid reload preserves dialog table identity"), View->GetTable(TEXT("inspector-dialog/content/resources")) == Table);
    return true;
}
#endif
