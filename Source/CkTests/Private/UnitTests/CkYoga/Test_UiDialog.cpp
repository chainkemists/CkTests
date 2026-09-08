#include "CkSlateLayout/CkUiCollection.h"
#include "CkSlateLayout/CkUiDialog.h"
#include "CkSlateLayout/SCkUiSurface.h"
#include "CkSlateLayout/SCkUiTable.h"

#include "Framework/Application/SlateApplication.h"
#include "Framework/Application/SlateUser.h"
#include "Input/Events.h"
#include "InputCoreTypes.h"
#include "Layout/Children.h"
#include "Layout/WidgetPath.h"
#include "Misc/AutomationTest.h"
#include "Widgets/Input/SButton.h"
#include "Widgets/SOverlay.h"
#include "Widgets/Layout/SScrollBox.h"
#include "Widgets/SWindow.h"

#if WITH_DEV_AUTOMATION_TESTS

namespace ck_tests_ui_dialog
{
    constexpr uint32 UnrelatedOwnerPointerIndex = 7;

    auto Tick(FSlateApplication& InSlate) -> void
    {
        InSlate.PumpMessages();
        InSlate.Tick();
        InSlate.Tick();
    }

    auto Key(const FKey InKey, const int32 InUserIndex, const bool bRepeat = false) -> FKeyEvent
    {
        return FKeyEvent(InKey, FModifierKeysState{}, InUserIndex, bRepeat, 0, 0);
    }

    auto FindButton(const TSharedRef<SWidget>& InRoot, const FName InTag) -> TSharedPtr<SButton>
    {
        if (InRoot->GetTag() == InTag && InRoot->GetTypeAsString() == TEXT("SButton")) { return StaticCastSharedRef<SButton>(InRoot); }
        const FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<SButton> Found = FindButton(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InTag); Found.IsValid()) { return Found; }
        }
        return {};
    }

    struct FClickResult final
    {
        bool DownHandled = false;
        bool UpHandled = false;
        FVector2D Position = FVector2D::ZeroVector;
    };

    auto Click(FSlateApplication& InSlate, const TSharedRef<SWindow>& InWindow, const TSharedRef<SWidget>& InWidget, const int32 InUserIndex) -> FClickResult
    {
        FClickResult Result;
        if (!InWindow->GetNativeWindow().IsValid()) { return Result; }
        const FGeometry Geometry = InWidget->GetCachedGeometry();
        if (Geometry.GetLocalSize().X <= 0.0f || Geometry.GetLocalSize().Y <= 0.0f) { return Result; }
        const FVector2D Position = Geometry.LocalToAbsolute(Geometry.GetLocalSize() * 0.5f);
        Result.Position = Position;
        InSlate.SetCursorPos(Position);
        const FPointerEvent Move(InUserIndex, FSlateApplication::CursorPointerIndex, Position, Position, TSet<FKey>{}, EKeys::Invalid, 0.0f, FModifierKeysState{});
        const FPointerEvent Down(InUserIndex, FSlateApplication::CursorPointerIndex, Position, Position, TSet<FKey>{EKeys::LeftMouseButton}, EKeys::LeftMouseButton, 0.0f, FModifierKeysState{});
        const FPointerEvent Up(InUserIndex, FSlateApplication::CursorPointerIndex, Position, Position, TSet<FKey>{}, EKeys::LeftMouseButton, 0.0f, FModifierKeysState{});
        InSlate.ProcessMouseMoveEvent(Move, true);
        Result.DownHandled = InSlate.ProcessMouseButtonDownEvent(InWindow->GetNativeWindow(), Down);
        Result.UpHandled = InSlate.ProcessMouseButtonUpEvent(Up);
        Tick(InSlate);
        return Result;
    }

    auto PointerDown(FSlateApplication& InSlate, const TSharedRef<SWindow>& InWindow, const TSharedRef<SWidget>& InWidget, const int32 InUserIndex) -> FClickResult
    {
        FClickResult Result;
        if (!InWindow->GetNativeWindow().IsValid()) { return Result; }
        const FGeometry Geometry = InWidget->GetCachedGeometry();
        if (Geometry.GetLocalSize().X <= 0.0f || Geometry.GetLocalSize().Y <= 0.0f) { return Result; }
        const FVector2D Position = Geometry.LocalToAbsolute(Geometry.GetLocalSize() * 0.5f);
        Result.Position = Position;
        InSlate.SetCursorPos(Position);
        const FPointerEvent Move(InUserIndex, FSlateApplication::CursorPointerIndex, Position, Position, TSet<FKey>{}, EKeys::Invalid, 0.0f, FModifierKeysState{});
        const FPointerEvent Down(InUserIndex, FSlateApplication::CursorPointerIndex, Position, Position, TSet<FKey>{EKeys::LeftMouseButton}, EKeys::LeftMouseButton, 0.0f, FModifierKeysState{});
        InSlate.ProcessMouseMoveEvent(Move, true);
        Result.DownHandled = InSlate.ProcessMouseButtonDownEvent(InWindow->GetNativeWindow(), Down);
        Tick(InSlate);
        return Result;
    }

    auto Markup(const bool bValid = true) -> FString
    {
        const TCHAR* Dismiss = bValid ? TEXT("dismiss") : TEXT("missing-dismiss");
        return FString::Printf(TEXT("<ui version=\"1\"><region name=\"main\"><column id=\"host\" visible=\"host-visible\"><dialog id=\"dialog\" class=\"fill\" open-bind=\"dialog-open\" dismiss=\"%s\"><slot name=\"content\"><column id=\"content\"><row id=\"background-row\"><button id=\"background\" action=\"background-action\">Background</button></row><scroll id=\"content-scroll\" direction=\"vertical\"><table id=\"resources\" bind=\"resources\"><table-column id=\"name\" label=\"Name\"><text id=\"name-cell\" bind-field=\"name\"/></table-column></table></scroll></column></slot><slot name=\"body\"><column id=\"dialog-body\"><button id=\"confirm\" action=\"confirm\">Confirm</button><button id=\"cancel\" action=\"dismiss\">Cancel</button></column></slot></dialog></column></region></ui>"), Dismiss);
    }

    auto RemovedMarkup() -> FString
    {
        return TEXT("<ui version=\"1\"><region name=\"main\"><text id=\"replacement\">Dialog removed</text></region></ui>");
    }

    auto OwnerValidationMarkup() -> FString
    {
        return TEXT("<ui version=\"1\"><region name=\"main\"><dialog id=\"dialog\" open-bind=\"dialog-open\" dismiss=\"dismiss\"><slot name=\"content\"><text id=\"content\">Content</text></slot><slot name=\"body\"><button id=\"confirm\" action=\"dismiss\">Confirm</button></slot></dialog></region></ui>");
    }

    struct FWindowScope final
    {
        FWindowScope(FSlateApplication& InSlate, const int32 InOwner, const int32 InForeign)
            : Slate(InSlate), Owner(InOwner), Foreign(InForeign), PreviousCursor(InSlate.GetCursorPos()) {}
        ~FWindowScope()
        {
            if (const TSharedPtr<FSlateUser> User = Slate.GetUser(Owner)) { User->ReleaseCapture(FSlateApplication::CursorPointerIndex); }
            if (const TSharedPtr<FSlateUser> User = Slate.GetUser(Owner)) { User->ReleaseCapture(UnrelatedOwnerPointerIndex); }
            if (const TSharedPtr<FSlateUser> User = Slate.GetUser(Foreign)) { User->ReleaseCapture(FSlateApplication::CursorPointerIndex); }
            Slate.ClearUserFocus(Owner, EFocusCause::SetDirectly);
            Slate.ClearUserFocus(Foreign, EFocusCause::SetDirectly);
            if (Window.IsValid()) { Slate.DestroyWindowImmediately(Window.ToSharedRef()); }
            Slate.SetCursorPos(PreviousCursor);
        }
        FSlateApplication& Slate;
        int32 Owner;
        int32 Foreign;
        FVector2D PreviousCursor;
        TSharedPtr<SWindow> Window;
    };
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiDialog_Runtime,
    "Ck.UiAuthoring.Dialog.NativeRuntime",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiDialog_Runtime::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_dialog;
    if (!FSlateApplication::IsInitialized()) { AddError(TEXT("Dialog runtime test requires Slate.")); return false; }

    FSlateApplication& Slate = FSlateApplication::Get();
    const TSharedRef<FSlateVirtualUserHandle> OwnerHandle = Slate.FindOrCreateVirtualUser(93);
    const TSharedRef<FSlateVirtualUserHandle> ForeignHandle = Slate.FindOrCreateVirtualUser(94);
    const int32 Owner = OwnerHandle->GetUserIndex();
    const int32 Foreign = ForeignHandle->GetUserIndex();
    bool bOpen = true;
    bool bHostVisible = true;
    int32 ConfirmCalls = 0;
    int32 DismissCalls = 0;
    int32 BackgroundCalls = 0;
    TSharedPtr<FCkUiCollection> Resources;
    if (!TestTrue(TEXT("Dialog content collection creates"), FCkUiCollection::TryCreate({{TEXT("name"), ECkUiFieldKind::Text}}, Resources).Succeeded)) { return false; }
    FCkUiRecordData Record;
    Record.Key = TEXT("resource");
    Record.Fields.Add(TEXT("name"), FCkUiFieldValue{.Kind = ECkUiFieldKind::Text, .Text = FText::FromString(TEXT("Resource"))});
    if (!TestTrue(TEXT("Dialog content collection publishes"), Resources->TrySetRecords({Record}).Succeeded)) { return false; }

    FCkUiWidgetRegistry Registry;
    if (!TestTrue(TEXT("Shared dialog registers"), FCkUiDialog::Register(Registry).Succeeded)) { return false; }
    FCkUiView::FDataBindings Data;
    Data.SlateUserIndex = Owner;
    Data.Visibility.Add(TEXT("dialog-open"), TAttribute<bool>::CreateLambda([&bOpen]() { return bOpen; }));
    Data.Visibility.Add(TEXT("host-visible"), TAttribute<bool>::CreateLambda([&bHostVisible]() { return bHostVisible; }));
    Data.Collections.Add(TEXT("resources"), Resources);
    FCkUiView::FActions Actions;
    Actions.Add(TEXT("confirm"), FSimpleDelegate::CreateLambda([&ConfirmCalls]() { ++ConfirmCalls; }));
    Actions.Add(TEXT("dismiss"), FSimpleDelegate::CreateLambda([&DismissCalls, &bOpen]() { ++DismissCalls; bOpen = false; }));
    Actions.Add(TEXT("background-action"), FSimpleDelegate::CreateLambda([&BackgroundCalls]() { ++BackgroundCalls; }));
    TSharedPtr<FCkUiView> View = FCkUiView::Create({}, MoveTemp(Actions), {}, {}, MoveTemp(Data), Registry.CreateSnapshot());
    const TSharedRef<SWidget> Region = View->GetRegion(TEXT("main"));
    const TSharedRef<SButton> External = SNew(SButton).IsFocusable(true);
    FWindowScope Scope(Slate, Owner, Foreign);
    Scope.Window = SNew(SWindow).AutoCenter(EAutoCenter::None).ClientSize(FVector2D{520.0f, 300.0f}).CreateTitleBar(false).HasCloseButton(false)
        [SNew(SOverlay) + SOverlay::Slot()[Region] + SOverlay::Slot().HAlign(HAlign_Right).VAlign(VAlign_Bottom)[External]];
    Slate.AddWindow(Scope.Window.ToSharedRef(), true);
    Slate.SetUserFocus(Owner, External, EFocusCause::SetDirectly);
    Slate.SetUserFocus(Foreign, External, EFocusCause::SetDirectly);
    const FCkUiLoadResult InitialLoad = View->TryReload(Markup(), TEXT(".fill { flex-grow: 1; }"), TEXT("UiDialogRuntime"));
    if (!InitialLoad.Succeeded)
    {
        if (InitialLoad.Errors.IsEmpty()) { AddError(TEXT("Dialog initial load failed without returned errors.")); }
        for (const FString& Error : InitialLoad.Errors) { AddError(FString::Printf(TEXT("Dialog initial load: %s"), *Error)); }
        TestTrue(TEXT("Mounted dialog document loads"), false);
        return false;
    }
    Tick(Slate);

    const TSharedPtr<SButton> Background = FindButton(Region, TEXT("background"));
    const TSharedPtr<SButton> Confirm = FindButton(Region, TEXT("confirm"));
    const TSharedPtr<SButton> Cancel = FindButton(Region, TEXT("cancel"));
    const TSharedPtr<SCkUiTable> QualifiedTable = View->GetTable(TEXT("dialog/content/resources"));
    const TSharedPtr<SScrollBox> QualifiedScroll = View->GetScroll(TEXT("dialog/content/content-scroll"));
    if (!TestTrue(TEXT("Mounted dialog exposes its authored controls and qualified content retained widgets"), Background.IsValid() && Confirm.IsValid()
        && Cancel.IsValid() && QualifiedTable.IsValid() && QualifiedScroll.IsValid())) { return false; }
    TestFalse(TEXT("Nested dialog table does not leak through an unqualified getter"), View->GetTable(TEXT("resources")).IsValid());
    TestTrue(TEXT("Opening after mount focuses the first enabled body control for only the owner"), Slate.GetUserFocusedWidget(Owner) == Confirm
        && Slate.GetUserFocusedWidget(Foreign) == External);
    const FGeometry BackgroundGeometry = Background->GetCachedGeometry();
    const FVector2D BackgroundPosition = BackgroundGeometry.LocalToAbsolute(BackgroundGeometry.GetLocalSize() * 0.5f);
    const FGeometry ConfirmGeometry = Confirm->GetCachedGeometry();
    TestTrue(TEXT("Background target center is outside the centered modal body before routed input"), !ConfirmGeometry.IsUnderLocation(BackgroundPosition));
    const TSharedPtr<FSlateUser> OwnerUser = Slate.GetUser(Owner);
    const TSharedPtr<FSlateUser> ForeignUser = Slate.GetUser(Foreign);
    FWidgetPath ExternalPath;
    if (!TestTrue(TEXT("Dialog capture coverage has both virtual users and a mounted external path"), OwnerUser.IsValid() && ForeignUser.IsValid()
        && Slate.GeneratePathToWidgetUnchecked(External, ExternalPath))) { return false; }

    bOpen = false;
    Tick(Slate);
    if (!TestTrue(TEXT("Foreign user acquires an unrelated external pointer capture"), ForeignUser->SetPointerCaptor(FSlateApplication::CursorPointerIndex, External, ExternalPath))) { return false; }
    if (!TestTrue(TEXT("Owner acquires a separate unrelated external pointer capture"), OwnerUser->SetPointerCaptor(UnrelatedOwnerPointerIndex, External, ExternalPath))) { return false; }
    const FClickResult BackgroundDown = PointerDown(Slate, Scope.Window.ToSharedRef(), Background.ToSharedRef(), Owner);
    AddInfo(FString::Printf(TEXT("Dialog closed-content capture: position=%s down=%s background=%d confirm=%d owner-captor=%s foreign-captor=%s"),
        *BackgroundDown.Position.ToString(), BackgroundDown.DownHandled ? TEXT("handled") : TEXT("unhandled"), BackgroundCalls, ConfirmCalls,
        OwnerUser->GetPointerCaptor(FSlateApplication::CursorPointerIndex) == Background ? TEXT("background") : TEXT("other"),
        ForeignUser->GetPointerCaptor(FSlateApplication::CursorPointerIndex) == External ? TEXT("external") : TEXT("other")));
    if (!TestTrue(TEXT("Closed content button acquires owner capture through routed pointer down without firing actions"), BackgroundDown.DownHandled
        && OwnerUser->GetPointerCaptor(FSlateApplication::CursorPointerIndex) == Background && ForeignUser->GetPointerCaptor(FSlateApplication::CursorPointerIndex) == External
        && OwnerUser->GetPointerCaptor(UnrelatedOwnerPointerIndex) == External && BackgroundCalls == 0 && ConfirmCalls == 0)) { return false; }

    bOpen = true;
    Tick(Slate);
    TestTrue(TEXT("Opening releases only owner content capture while preserving foreign external capture"), !OwnerUser->GetPointerCaptor(FSlateApplication::CursorPointerIndex).IsValid()
        && OwnerUser->GetPointerCaptor(UnrelatedOwnerPointerIndex) == External && ForeignUser->GetPointerCaptor(FSlateApplication::CursorPointerIndex) == External
        && BackgroundCalls == 0 && ConfirmCalls == 0);
    const FClickResult ConfirmDown = PointerDown(Slate, Scope.Window.ToSharedRef(), Confirm.ToSharedRef(), Owner);
    AddInfo(FString::Printf(TEXT("Dialog open-body capture: position=%s down=%s confirm=%d owner-captor=%s foreign-captor=%s"),
        *ConfirmDown.Position.ToString(), ConfirmDown.DownHandled ? TEXT("handled") : TEXT("unhandled"), ConfirmCalls,
        OwnerUser->GetPointerCaptor(FSlateApplication::CursorPointerIndex) == Confirm ? TEXT("confirm") : TEXT("other"),
        ForeignUser->GetPointerCaptor(FSlateApplication::CursorPointerIndex) == External ? TEXT("external") : TEXT("other")));
    if (!TestTrue(TEXT("Open body button acquires owner capture through routed pointer down without firing confirm"), ConfirmDown.DownHandled
        && OwnerUser->GetPointerCaptor(FSlateApplication::CursorPointerIndex) == Confirm && ForeignUser->GetPointerCaptor(FSlateApplication::CursorPointerIndex) == External
        && ConfirmCalls == 0)) { return false; }

    bOpen = false;
    Tick(Slate);
    TestTrue(TEXT("Closing releases only owner body capture without dispatching confirm"), !OwnerUser->GetPointerCaptor(FSlateApplication::CursorPointerIndex).IsValid()
        && OwnerUser->GetPointerCaptor(UnrelatedOwnerPointerIndex) == External && ForeignUser->GetPointerCaptor(FSlateApplication::CursorPointerIndex) == External
        && ConfirmCalls == 0);

    Slate.SetUserFocus(Owner, External, EFocusCause::SetDirectly);
    if (!TestTrue(TEXT("Capture lifecycle restores the fixture's external prior focus while closed"), Slate.GetUserFocusedWidget(Owner) == External)) { return false; }
    bOpen = true;
    Tick(Slate);
    if (!TestTrue(TEXT("Capture lifecycle reopens onto the first body focus target"), Slate.GetUserFocusedWidget(Owner) == Confirm
        && Slate.GetUserFocusedWidget(Foreign) == External)) { return false; }
    const FClickResult BackgroundClick = Click(Slate, Scope.Window.ToSharedRef(), Background.ToSharedRef(), Owner);
    AddInfo(FString::Printf(TEXT("Dialog background input: position=%s down=%s up=%s background=%d confirm=%d"), *BackgroundClick.Position.ToString(),
        BackgroundClick.DownHandled ? TEXT("handled") : TEXT("unhandled"), BackgroundClick.UpHandled ? TEXT("handled") : TEXT("unhandled"), BackgroundCalls, ConfirmCalls));
    TestTrue(TEXT("Modal backdrop consumes routed owner pointer input without running background action"), BackgroundClick.DownHandled && BackgroundCalls == 0 && ConfirmCalls == 0);
    const FClickResult ConfirmClick = Click(Slate, Scope.Window.ToSharedRef(), Confirm.ToSharedRef(), Owner);
    AddInfo(FString::Printf(TEXT("Dialog confirm input: position=%s down=%s up=%s confirm=%d"), *ConfirmClick.Position.ToString(),
        ConfirmClick.DownHandled ? TEXT("handled") : TEXT("unhandled"), ConfirmClick.UpHandled ? TEXT("handled") : TEXT("unhandled"), ConfirmCalls));
    TestTrue(TEXT("Modal body confirm receives routed Slate input once"), ConfirmClick.DownHandled && ConfirmClick.UpHandled && ConfirmCalls == 1);
    TestTrue(TEXT("Owner Tab reaches the next body control while foreign focus remains external"), Slate.ProcessKeyDownEvent(Key(EKeys::Tab, Owner))
        && Slate.GetUserFocusedWidget(Owner) == Cancel && Slate.GetUserFocusedWidget(Foreign) == External);
    TestTrue(TEXT("Owner Tab wraps inside the modal body"), Slate.ProcessKeyDownEvent(Key(EKeys::Tab, Owner)) && Slate.GetUserFocusedWidget(Owner) == Confirm);
    TestTrue(TEXT("Owner gamepad navigation stays in the modal body while foreign focus remains external"), Slate.ProcessKeyDownEvent(Key(EKeys::Gamepad_DPad_Down, Owner))
        && Slate.GetUserFocusedWidget(Owner) == Cancel && Slate.GetUserFocusedWidget(Foreign) == External);
    const FClickResult CancelClick = Click(Slate, Scope.Window.ToSharedRef(), Cancel.ToSharedRef(), Owner);
    TestTrue(TEXT("Modal cancel receives routed Slate input and restores only owner focus"), CancelClick.DownHandled && CancelClick.UpHandled
        && DismissCalls == 1 && !bOpen && Slate.GetUserFocusedWidget(Owner) == External && Slate.GetUserFocusedWidget(Foreign) == External);

    bOpen = true;
    Tick(Slate);
    TestTrue(TEXT("Reopening restores owner focus to the modal body"), Slate.GetUserFocusedWidget(Owner) == Confirm && Slate.GetUserFocusedWidget(Foreign) == External);
    TestTrue(TEXT("Owner Escape invokes dismiss once"), Slate.ProcessKeyDownEvent(Key(EKeys::Escape, Owner)) && DismissCalls == 2);
    TestFalse(TEXT("Repeated Escape cannot dismiss an already closed modal"), Slate.ProcessKeyDownEvent(Key(EKeys::Escape, Owner, true)));

    bOpen = true;
    Tick(Slate);
    TestTrue(TEXT("Owner controller Back invokes dismiss once"), Slate.ProcessKeyDownEvent(Key(EKeys::Gamepad_FaceButton_Right, Owner)) && DismissCalls == 3);
    TestFalse(TEXT("Repeated controller Back cannot dismiss an already closed modal"), Slate.ProcessKeyDownEvent(Key(EKeys::Gamepad_FaceButton_Right, Owner, true)));

    bOpen = true;
    Tick(Slate);
    const int64 Revision = View->GetRevision();
    TestFalse(TEXT("Invalid dialog reload rejects before publication"), View->TryReload(Markup(false), TEXT(""), TEXT("UiDialogInvalid")).Succeeded);
    TestTrue(TEXT("Invalid reload preserves open modal focus and qualified retained identities"), View->GetRevision() == Revision && Slate.GetUserFocusedWidget(Owner) == Confirm
        && View->GetTable(TEXT("dialog/content/resources")) == QualifiedTable && View->GetScroll(TEXT("dialog/content/content-scroll")) == QualifiedScroll);
    if (!TestTrue(TEXT("Compatible dialog reload succeeds"), View->TryReload(Markup(), TEXT(".fill { flex-grow: 1; }"), TEXT("UiDialogCompatible")).Succeeded)) { return false; }
    Tick(Slate);
    const TSharedPtr<SButton> CompatibleConfirm = FindButton(Region, TEXT("confirm"));
    TestTrue(TEXT("Compatible open dialog reload preserves fresh body focus and slot-owned retained identities"), CompatibleConfirm.IsValid() && Slate.GetUserFocusedWidget(Owner) == CompatibleConfirm
        && View->GetTable(TEXT("dialog/content/resources")) == QualifiedTable && View->GetScroll(TEXT("dialog/content/content-scroll")) == QualifiedScroll);
    Slate.SetUserFocus(Owner, External, EFocusCause::SetDirectly);
    bOpen = false;
    Tick(Slate);
    TestTrue(TEXT("Closing after an external focus redirect does not overwrite that redirect"), Slate.GetUserFocusedWidget(Owner) == External
        && Slate.GetUserFocusedWidget(Foreign) == External);

    bOpen = true;
    Tick(Slate);
    bHostVisible = false;
    Tick(Slate);
    TestTrue(TEXT("Hiding a mounted dialog ancestor releases only owned focus to its valid prior target"), Slate.GetUserFocusedWidget(Owner) == External
        && Slate.GetUserFocusedWidget(Foreign) == External);

    bHostVisible = true;
    Tick(Slate);
    const TSharedPtr<SButton> RestoredConfirm = FindButton(Region, TEXT("confirm"));
    if (!TestTrue(TEXT("Restoring a visible open dialog reacquires its first body focus target"), RestoredConfirm.IsValid() && Slate.GetUserFocusedWidget(Owner) == RestoredConfirm)) { return false; }
    if (!TestTrue(TEXT("Accepted parent removal reload succeeds"), View->TryReload(RemovedMarkup(), TEXT(""), TEXT("UiDialogRemoved")).Succeeded)) { return false; }
    Tick(Slate);
    TestTrue(TEXT("Parent removal releases only dialog-owned focus and retained descendants"), Slate.GetUserFocusedWidget(Owner) == External
        && Slate.GetUserFocusedWidget(Foreign) == External && !View->GetTable(TEXT("dialog/content/resources")).IsValid());

    if (!TestTrue(TEXT("Dialog reloads before owner-release coverage"), View->TryReload(Markup(), TEXT(".fill { flex-grow: 1; }"), TEXT("UiDialogOwnerRelease")).Succeeded)) { return false; }
    Tick(Slate);
    const TSharedPtr<SButton> ReleasedConfirm = FindButton(Region, TEXT("confirm"));
    if (!TestTrue(TEXT("Reconstructed dialog owns focus before its view releases"), ReleasedConfirm.IsValid() && Slate.GetUserFocusedWidget(Owner) == ReleasedConfirm)) { return false; }
    const TSharedPtr<SWidget> HeldRoot = Region;
    View.Reset();
    Tick(Slate);
    TestTrue(TEXT("Held mounted root remains valid while released dialog owner clears only its focus"), HeldRoot.IsValid()
        && !Slate.GetUserFocusedWidget(Owner).IsValid() && Slate.GetUserFocusedWidget(Foreign) == External);
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiDialog_OwnerValidation,
    "Ck.UiAuthoring.Dialog.OwnerValidation",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiDialog_OwnerValidation::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_dialog;
    FCkUiWidgetRegistry Registry;
    if (!TestTrue(TEXT("Dialog owner-validation registry registers"), FCkUiDialog::Register(Registry).Succeeded)) { return false; }
    bool bOpen = true;
    FCkUiView::FDataBindings Data;
    Data.SlateUserIndex = INDEX_NONE;
    Data.Visibility.Add(TEXT("dialog-open"), TAttribute<bool>::CreateLambda([&bOpen]() { return bOpen; }));
    FCkUiView::FActions Actions;
    Actions.Add(TEXT("dismiss"), FSimpleDelegate::CreateLambda([]() {}));
    const TSharedRef<FCkUiView> View = FCkUiView::Create({}, MoveTemp(Actions), {}, {}, MoveTemp(Data), Registry.CreateSnapshot());
    View->GetRegion(TEXT("main"));
    const FCkUiLoadResult Result = View->TryReload(OwnerValidationMarkup(), TEXT(""), TEXT("UiDialogMissingOwner"));
    TestFalse(TEXT("Dialog rejects an absent explicit Slate owner before publication"), Result.Succeeded);
    TestTrue(TEXT("Missing dialog owner reports its specific host-context failure"), FString::Join(Result.Errors, TEXT("\n")).Contains(TEXT("nonnegative host Slate user")));
    TestEqual(TEXT("Missing dialog owner leaves revision uncommitted"), View->GetRevision(), int64{0});
    return true;
}

#endif
