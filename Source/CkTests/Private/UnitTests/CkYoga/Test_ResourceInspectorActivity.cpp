#include "CkResourceInspector/CkResourceInspectorModel.h"

#include "CkSlateLayout/SCkUiRepeat.h"
#include "CkSlateLayout/CkFlexText.h"
#include "CkSlateLayout/SCkUiSurface.h"
#include "CkSlateLayout/SCkUiTable.h"
#include "CkSlateLayout/SCkUiTabs.h"

#include "Framework/Application/SlateApplication.h"
#include "HAL/FileManager.h"
#include "ImageUtils.h"
#include "Layout/WidgetPath.h"
#include "Input/Events.h"
#include "InputCoreTypes.h"
#include "Interfaces/IPluginManager.h"
#include "Layout/Children.h"
#include "Layout/WidgetPath.h"
#include "Misc/AutomationTest.h"
#include "Misc/Paths.h"
#include "Widgets/Input/SButton.h"
#include "Widgets/SWindow.h"
#include "Widgets/Text/STextBlock.h"

#if WITH_DEV_AUTOMATION_TESTS
namespace ck_tests_resource_inspector_activity
{
    auto Tick(FSlateApplication& InSlate) -> void
    {
        InSlate.PumpMessages();
        InSlate.Tick();
        InSlate.Tick();
    }

    auto ContainsText(const TSharedRef<SWidget>& InRoot, const FString& InText) -> bool
    {
        if (InRoot->GetTypeAsString() == TEXT("STextBlock") && StaticCastSharedRef<STextBlock>(InRoot)->GetText().ToString() == InText) { return true; }
        if (InRoot->GetTypeAsString() == TEXT("SCkFlexText") && StaticCastSharedRef<SCkFlexText>(InRoot)->GetText().ToString() == InText) { return true; }
        const FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            if (ContainsText(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InText)) { return true; }
        }
        return false;
    }

    auto FindButton(const TSharedRef<SWidget>& InRoot, const FString& InText) -> TSharedPtr<SButton>
    {
        const FString& Type = InRoot->GetTypeAsString();
        if ((Type == TEXT("SButton") || Type == TEXT("SCkUiStyledButton")) && ContainsText(InRoot, InText)) { return StaticCastSharedRef<SButton>(InRoot); }
        const FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<SButton> Found = FindButton(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InText); Found.IsValid()) { return Found; }
        }
        return {};
    }

    auto Click(FSlateApplication& InSlate, const TSharedRef<SWindow>& Window, const TSharedRef<SButton>& InButton) -> bool
    {
        const FGeometry Geometry = InButton->GetCachedGeometry();
        if (Geometry.GetLocalSize().X <= 0 || Geometry.GetLocalSize().Y <= 0) { return false; }
        const FVector2D Position = Geometry.LocalToAbsolute(Geometry.GetLocalSize() * 0.5f);
        InSlate.SetCursorPos(Position);
        const TSet<FKey> MoveButtons;
        const FPointerEvent Move(0, FSlateApplication::CursorPointerIndex, Position, Position, MoveButtons, EKeys::Invalid, 0, FModifierKeysState{});
        InSlate.ProcessMouseMoveEvent(Move, true);
        const TSet<FKey> DownButtons{EKeys::LeftMouseButton};
        const FPointerEvent Down(0, FSlateApplication::CursorPointerIndex, Position, Position, DownButtons, EKeys::LeftMouseButton, 0, FModifierKeysState{});
        const TSet<FKey> UpButtons;
        const FPointerEvent Up(0, FSlateApplication::CursorPointerIndex, Position, Position, UpButtons, EKeys::LeftMouseButton, 0, FModifierKeysState{});
        const bool Handled = InSlate.ProcessMouseButtonDownEvent(Window->GetNativeWindow(), Down);
        InSlate.ProcessMouseButtonUpEvent(Up);
        Tick(InSlate);
        return Handled;
    }
    struct FWindowScope final
    {
        explicit FWindowScope(FSlateApplication& InSlate) : Slate(InSlate), PreviousCursor(InSlate.GetCursorPos()) {}
        ~FWindowScope() { if (Window.IsValid()) { Slate.DestroyWindowImmediately(Window.ToSharedRef()); } Slate.SetCursorPos(PreviousCursor); }
        FSlateApplication& Slate;
        FVector2D PreviousCursor;
        TSharedPtr<SWindow> Window;
    };

    auto Message(const TSharedPtr<FCkUiCollection>& InActivity, const int32 InIndex) -> FString
    {
        const TArray<TSharedPtr<const FCkUiRecord>>& Records = InActivity->GetRecords();
        const FCkUiFieldValue* Field = Records.IsValidIndex(InIndex) && Records[InIndex].IsValid() ? Records[InIndex]->FindField(TEXT("message")) : nullptr;
        return Field != nullptr ? Field->Text.ToString() : FString{};
    }

    auto VisibilityChain(const TSharedPtr<SWidget>& InWidget) -> FString
    {
        FString Result;
        for (TSharedPtr<SWidget> Current = InWidget; Current.IsValid(); Current = Current->GetParentWidget())
        {
            Result += FString::Printf(TEXT("[%s visible=%d enabled=%d size=%.1fx%.1f]"), *Current->GetTypeAsString(),
                Current->GetVisibility().IsVisible() ? 1 : 0, Current->IsEnabled() ? 1 : 0,
                Current->GetCachedGeometry().GetLocalSize().X, Current->GetCachedGeometry().GetLocalSize().Y);
        }
        return Result;
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkResourceInspector_Activity,
    "Ck.ResourceInspector.Activity.History",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkResourceInspector_Activity::RunTest(const FString&) -> bool
{
    using namespace ck_tests_resource_inspector_activity;
    if (!FSlateApplication::IsInitialized()) { AddError(TEXT("Resource Inspector activity test requires Slate.")); return false; }
    const TSharedPtr<IPlugin> Plugin = IPluginManager::Get().FindPlugin(TEXT("CkTests"));
    if (!TestTrue(TEXT("CkTests plugin is installed"), Plugin.IsValid())) { return false; }

    TSharedPtr<FCkResourceInspectorModel> Model;
    FString Error;
    if (!TestTrue(TEXT("Resource Inspector model creates"), FCkResourceInspectorModel::TryCreate({}, Model, Error, 0))) { AddError(Error); return false; }
    const TSharedPtr<FCkUiCollection> Activity = Model->GetActivity();
    if (!TestTrue(TEXT("Activity collection is exposed"), Activity.IsValid())) { return false; }
    const TArray<FCkUiFieldSchema>& Schema = Activity->GetSchema();
    if (!TestTrue(TEXT("Activity schema is sequence and message"), Schema.Num() == 2 && Schema[0].Name == TEXT("sequence")
        && Schema[0].Kind == ECkUiFieldKind::Number && Schema[1].Name == TEXT("message") && Schema[1].Kind == ECkUiFieldKind::Text)) { return false; }

    const FString Directory = FPaths::Combine(Plugin->GetBaseDir(), TEXT("Resources/ResourceInspector"));
    const TSharedRef<FCkUiView> View = Model->GetView();
    if (!TestTrue(TEXT("Installed Resource Inspector layout loads"), View->ReloadFiles(
        FPaths::Combine(Directory, TEXT("ResourceInspector.ui.html")), FPaths::Combine(Directory, TEXT("ResourceInspector.ui.css"))).Succeeded)) { return false; }

    FSlateApplication& Slate = FSlateApplication::Get();
    FWindowScope Scope{Slate};
    Scope.Window = SNew(SWindow).AutoCenter(EAutoCenter::None).ClientSize(FVector2D{960.0f, 640.0f}).CreateTitleBar(false).HasCloseButton(false)[Model->GetRoot()];
    Slate.AddWindow(Scope.Window.ToSharedRef(), true);
    Tick(Slate);
    const TSharedPtr<SCkUiTable> Table = View->GetTable(TEXT("inspector-dialog/content/resources"));
    const TSharedPtr<SCkUiTabs> Tabs = View->GetTabs(TEXT("inspector-dialog/content/detail-tabs"));
    const TSharedPtr<SCkUiRepeat> Repeat = View->GetRepeat(TEXT("inspector-dialog/content/activity"));
    if (!TestTrue(TEXT("Installed Activity tab and repeat are retained"), Table.IsValid() && Tabs.IsValid() && Repeat.IsValid())) { return false; }
    TestEqual(TEXT("Activity starts empty"), Activity->GetRecords().Num(), 0);

    if (!TestTrue(TEXT("Production table selection selects a resource"), Table->TrySelectKey(FString(TEXT("resource-00000")), true))) { return false; }
    Tick(Slate);
    TestEqual(TEXT("Selection produces the first activity entry"), Message(Activity, 0), FString(TEXT("Selected Resource_00000.")));
    const int64 RevisionAfterSelection = Activity->GetRevision();
    TestTrue(TEXT("Repeated production selection is a no-op"), Table->TrySelectKey(FString(TEXT("resource-00000")), true));
    TestTrue(TEXT("Repeated selection does not publish activity"), Activity->GetRevision() == RevisionAfterSelection && Activity->GetRecords().Num() == 1);

    TestTrue(TEXT("Changed scenario publishes"), Model->TrySetRowCount(1, Error));
    TestTrue(TEXT("Changed category publishes"), Model->TrySetCategory(TEXT("texture"), Error));
    TestTrue(TEXT("Committed note publishes"), Model->TrySetSessionNote(TEXT("Inspect mips"), Error));
    const int32 BeforeRejectedNote = Activity->GetRecords().Num();
    TestFalse(TEXT("Overlong note rejects"), Model->TrySetSessionNote(FString::ChrN(81, TEXT('x')), Error));
    TestTrue(TEXT("Rejected note preserves the committed note and activity"), Model->GetSessionNote() == TEXT("Inspect mips")
        && !Error.IsEmpty() && Activity->GetRecords().Num() == BeforeRejectedNote);
    TestTrue(TEXT("Pin action publishes"), Model->TryPinSelected(Error));
    const int32 BeforeNoOps = Activity->GetRecords().Num();
    TestTrue(TEXT("Unchanged scenario succeeds without history"), Model->TrySetRowCount(1, Error));
    TestTrue(TEXT("Unchanged category succeeds without history"), Model->TrySetCategory(TEXT("texture"), Error));
    TestTrue(TEXT("Unchanged note succeeds without history"), Model->TrySetSessionNote(TEXT("Inspect mips"), Error));
    TestTrue(TEXT("Existing pin succeeds without history"), Model->TryPinSelected(Error));
    TestFalse(TEXT("Invalid category rejects"), Model->TrySetCategory(TEXT("unknown"), Error));
    TestFalse(TEXT("Invalid row count rejects"), Model->TrySetRowCount(-1, Error));
    TestFalse(TEXT("Overlong note rejects"), Model->TrySetSessionNote(FString::ChrN(81, TEXT('x')), Error));
    TestEqual(TEXT("Rejected note preserves committed value"), Model->GetSessionNote(), FString(TEXT("Inspect mips")));
    TestTrue(TEXT("No-op and rejection paths do not publish activity"), Activity->GetRecords().Num() == BeforeNoOps);
    TestTrue(TEXT("Overview tab restores for the production unpin control"), Model->TrySetDetailTab(TEXT("overview")));
    Tick(Slate);
    const TSharedPtr<SButton> RemovePin = FindButton(Model->GetRoot(), TEXT("Remove"));
    if (!TestTrue(TEXT("Pinned snapshot exposes its production remove action"), RemovePin.IsValid() && Click(Slate, Scope.Window.ToSharedRef(), RemovePin.ToSharedRef()))) { return false; }
    Tick(Slate);
    TestEqual(TEXT("Production unpin action records activity"), Message(Activity, 0), FString(TEXT("Unpinned Resource_00000.")));
    const TSharedPtr<SButton> ClearSelection = FindButton(Model->GetRoot(), TEXT("Clear"));
    if (!TestTrue(TEXT("Selected resource exposes the production clear action"), ClearSelection.IsValid() && Click(Slate, Scope.Window.ToSharedRef(), ClearSelection.ToSharedRef()))) { return false; }
    Tick(Slate);
    TestEqual(TEXT("Production clear action records activity"), Message(Activity, 0), FString(TEXT("Cleared selection.")));

    const TSharedPtr<SButton> ActivityHeader = FindButton(Tabs.ToSharedRef(), TEXT("Activity"));
    if (!TestTrue(TEXT("Installed Activity header is actionable"), ActivityHeader.IsValid())) { return false; }
    if (!TestTrue(TEXT("Installed Activity header handles native pointer activation"), Click(Slate, Scope.Window.ToSharedRef(), ActivityHeader.ToSharedRef()))) { return false; }
    Tick(Slate);
    TestEqual(TEXT("Installed tab action selects Activity"), Model->GetDetailTab(), FString(TEXT("activity")));
    AddInfo(FString::Printf(TEXT("Activity repeat before assertion: count=%d records=%d failure='%s' chain=%s"),
        Repeat->GetItemCount(), Activity->GetRecords().Num(), *Repeat->GetLastFailure(), *VisibilityChain(Repeat)));
    if (Repeat->GetItemCount() != Activity->GetRecords().Num())
    {
        const bool bRefreshed = Repeat->TryRefresh();
        AddInfo(FString::Printf(TEXT("Activity repeat diagnostic refresh: result=%d count=%d failure='%s'"), bRefreshed ? 1 : 0,
            Repeat->GetItemCount(), *Repeat->GetLastFailure()));
    }
    TestEqual(TEXT("Activity repeat reflects the collection"), Repeat->GetItemCount(), Activity->GetRecords().Num());
    const TSharedPtr<const FCkUiRecord> RetainedBeforeReload = Activity->GetRecords()[0];
    if (!TestTrue(TEXT("Compatible reload succeeds"), View->ReloadFiles(
        FPaths::Combine(Directory, TEXT("ResourceInspector.ui.html")), FPaths::Combine(Directory, TEXT("ResourceInspector.ui.css"))).Succeeded)) { return false; }
    Tick(Slate);
    TestTrue(TEXT("Reload retains Activity tab, repeat count, and record identity"), Model->GetDetailTab() == TEXT("activity")
        && View->GetTabs(TEXT("inspector-dialog/content/detail-tabs")) == Tabs && View->GetRepeat(TEXT("inspector-dialog/content/activity")) == Repeat
        && Repeat->GetItemCount() == Activity->GetRecords().Num() && Activity->FindRecord(RetainedBeforeReload->GetKey()) == RetainedBeforeReload);

    const FString CaptureDirectory = FPaths::Combine(FPaths::ProjectSavedDir(), TEXT("Automation/ResourceInspector"));
    IFileManager::Get().MakeDirectory(*CaptureDirectory, true);
    TArray<FColor> Pixels;
    FIntVector CaptureSize = FIntVector::ZeroValue;
    if (!TestTrue(TEXT("Native Activity screenshot captures"), Slate.TakeScreenshot(Model->GetRoot(), Pixels, CaptureSize)
        && CaptureSize.X > 0 && CaptureSize.Y > 0 && Pixels.Num() >= CaptureSize.X * CaptureSize.Y)) { return false; }
    const FImageView Capture(Pixels.GetData(), CaptureSize.X, CaptureSize.Y, ERawImageFormat::BGRA8);
    TestTrue(TEXT("Native Activity screenshot saves"), FImageUtils::SaveImageByExtension(*FPaths::Combine(CaptureDirectory, TEXT("Activity.png")), Capture));

    bool bNestedNoteSucceeded = false;
    bool bNestedNoteAttempted = false;
    const FDelegateHandle ReentryHandle = Activity->OnChanged().AddLambda([&]()
    {
        if (bNestedNoteAttempted) { return; }
        bNestedNoteAttempted = true;
        FString NestedError;
        bNestedNoteSucceeded = Model->TrySetSessionNote(TEXT("Nested note"), NestedError);
    });
    TestTrue(TEXT("Outer scenario action succeeds while activity observers run"), Model->TrySetRowCount(2, Error));
    Activity->OnChanged().Remove(ReentryHandle);
    TestTrue(TEXT("Reentrant successful model action is queued and recorded"), bNestedNoteAttempted && bNestedNoteSucceeded
        && Message(Activity, 0) == TEXT("Session note saved.") && Message(Activity, 1) == TEXT("Resource count set to 2."));

    for (int32 Index = 0; Index < 105; ++Index)
    {
        if (!TestTrue(TEXT("Alternating scenarios publish for activity retention"), Model->TrySetRowCount(Index % 2 == 0 ? 3 : 2, Error))) { return false; }
    }
    TestEqual(TEXT("Activity retains at most one hundred newest records"), Activity->GetRecords().Num(), 100);
    const TSharedPtr<const FCkUiRecord> RetainedMiddle = Activity->GetRecords()[50];
    const FString RetainedMiddleKey = RetainedMiddle->GetKey();
    TestTrue(TEXT("One more change publishes after retention fills"), Model->TrySetRowCount(4, Error));
    TestTrue(TEXT("Retained activity record keeps identity across prepend and trim"), Activity->FindRecord(RetainedMiddleKey) == RetainedMiddle);
    const FCkUiFieldValue* LatestSequence = Activity->GetRecords()[0]->FindField(TEXT("sequence"));
    const FCkUiFieldValue* NextSequence = Activity->GetRecords()[1]->FindField(TEXT("sequence"));
    TestTrue(TEXT("Newest-first activity records keep descending numeric sequence"), LatestSequence != nullptr && NextSequence != nullptr
        && LatestSequence->Number > NextSequence->Number && Activity->GetRecords()[0]->GetKey() > Activity->GetRecords()[1]->GetKey());
    return true;
}
#endif
