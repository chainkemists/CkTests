#include "CkResourceInspector/CkResourceInspectorModel.h"

#include "CkSlateLayout/CkFlexText.h"
#include "CkSlateLayout/SCkUiSurface.h"
#include "CkSlateLayout/SCkUiTable.h"

#include "Framework/Application/SlateApplication.h"
#include "HAL/FileManager.h"
#include "ImageUtils.h"
#include "Input/Events.h"
#include "InputCoreTypes.h"
#include "Interfaces/IPluginManager.h"
#include "Layout/Children.h"
#include "Misc/AutomationTest.h"
#include "Misc/Paths.h"
#include "Widgets/Input/SSearchBox.h"
#include "Widgets/Layout/SScrollBox.h"
#include "Widgets/SWindow.h"
#include "Widgets/Text/STextBlock.h"

#if WITH_DEV_AUTOMATION_TESTS
namespace ck_tests_resource_inspector_states
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

    auto IsEffectivelyVisible(TSharedPtr<SWidget> InWidget) -> bool
    {
        while (InWidget.IsValid())
        {
            const EVisibility Visibility = InWidget->GetVisibility();
            if (Visibility == EVisibility::Collapsed || Visibility == EVisibility::Hidden) { return false; }
            InWidget = InWidget->GetParentWidget();
        }
        return true;
    }

    auto FindSearch(const TSharedRef<SWidget>& InRoot) -> TSharedPtr<SSearchBox>
    {
        if (InRoot->GetTypeAsString() == TEXT("SSearchBox")) { return StaticCastSharedRef<SSearchBox>(InRoot); }
        const FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<SSearchBox> Found = FindSearch(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index))); Found.IsValid()) { return Found; }
        }
        return {};
    }

    auto Click(FSlateApplication& InSlate, const TSharedRef<SWindow>& InWindow, const TSharedRef<SWidget>& InWidget) -> bool
    {
        const FGeometry Geometry = InWidget->GetCachedGeometry();
        if (Geometry.GetLocalSize().X <= 0.0f || Geometry.GetLocalSize().Y <= 0.0f) { return false; }
        const FVector2D Position = Geometry.LocalToAbsolute(Geometry.GetLocalSize() * 0.5f);
        InSlate.SetCursorPos(Position);
        const FPointerEvent Move(0, FSlateApplication::CursorPointerIndex, Position, Position, TSet<FKey>{}, EKeys::Invalid, 0, FModifierKeysState{});
        InSlate.ProcessMouseMoveEvent(Move, true);
        const FPointerEvent Down(0, FSlateApplication::CursorPointerIndex, Position, Position, TSet<FKey>{EKeys::LeftMouseButton}, EKeys::LeftMouseButton, 0, FModifierKeysState{});
        const FPointerEvent Up(0, FSlateApplication::CursorPointerIndex, Position, Position, TSet<FKey>{}, EKeys::LeftMouseButton, 0, FModifierKeysState{});
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

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkResourceInspector_States,
    "Ck.ResourceInspector.PresentationStates.NativeScenarios",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkResourceInspector_States::RunTest(const FString&) -> bool
{
    using namespace ck_tests_resource_inspector_states;
    if (!FSlateApplication::IsInitialized()) { AddError(TEXT("Resource Inspector presentation-state test requires Slate.")); return false; }
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
    if (!TestTrue(TEXT("Installed Resource Inspector presentation document loads"), View->ReloadFiles(
        FPaths::Combine(Resources, TEXT("ResourceInspector.ui.html")), FPaths::Combine(Resources, TEXT("ResourceInspector.ui.css"))).Succeeded)) { return false; }
    Tick(Slate);

    const TSharedPtr<SCkUiTable> Table = View->GetTable(TEXT("inspector-dialog/content/resources"));
    const TSharedPtr<SScrollBox> ResourceScroll = View->GetScroll(TEXT("inspector-dialog/content/resource-scroll"));
    const TSharedPtr<SSearchBox> Search = FindSearch(Model->GetRoot());
    if (!TestTrue(TEXT("Installed production view retains resource table, scroll, and search"), Table.IsValid() && ResourceScroll.IsValid() && Search.IsValid())) { return false; }
    TestEqual(TEXT("Presentation state defaults to ready"), Model->GetPresentationState(), FString(TEXT("ready")));
    TestTrue(TEXT("Ready presentation effectively exposes the resource table"), IsEffectivelyVisible(ResourceScroll));
    const TSharedPtr<SWidget> EmptyOverlay = FindTagged(Model->GetRoot(), TEXT("resource-empty"));
    Search->SetText(FText::FromString(TEXT("No matching resource")));
    Tick(Slate);
    if (!TestTrue(TEXT("Ready empty query exposes the authored empty overlay"), EmptyOverlay.IsValid() && IsEffectivelyVisible(EmptyOverlay))) { return false; }
    const TSharedPtr<SWidget> EmptyLoading = FindLabel(Model->GetRoot(), TEXT("Loading"));
    if (!TestTrue(TEXT("Loading control is actionable while the ready-empty overlay is visible"), EmptyLoading.IsValid() && Click(Slate, Scope.Window.ToSharedRef(), EmptyLoading.ToSharedRef()))) { return false; }
    TestTrue(TEXT("Loading presentation suppresses the ready-empty overlay"), Model->GetPresentationState() == TEXT("loading") && !IsEffectivelyVisible(EmptyOverlay));
    const TSharedPtr<SWidget> EmptyLoadingRecovery = FindTagged(Model->GetRoot(), TEXT("finish-loading"));
    if (EmptyLoadingRecovery.IsValid())
    {
        const FGeometry Geometry = EmptyLoadingRecovery->GetCachedGeometry();
        AddInfo(FString::Printf(TEXT("Loading recovery before click: type=%s size=%.1fx%.1f abs=(%.1f,%.1f) effective=%d"),
            *EmptyLoadingRecovery->GetTypeAsString(), Geometry.GetLocalSize().X, Geometry.GetLocalSize().Y,
            Geometry.LocalToAbsolute(Geometry.GetLocalSize() * 0.5f).X, Geometry.LocalToAbsolute(Geometry.GetLocalSize() * 0.5f).Y,
            IsEffectivelyVisible(EmptyLoadingRecovery) ? 1 : 0));
    }
    else { AddInfo(TEXT("Loading recovery before click: target missing")); }
    if (!TestTrue(TEXT("Loading recovery restores the ready-empty presentation"), EmptyLoadingRecovery.IsValid() && Click(Slate, Scope.Window.ToSharedRef(), EmptyLoadingRecovery.ToSharedRef()))) { return false; }
    Search->SetText(FText::FromString(TEXT("Resource_00000")));
    Tick(Slate);

    const TSharedPtr<const FCkUiRecord> RetainedResource = Model->GetCollection()->FindRecord(TEXT("resource-00000"));
    if (!TestTrue(TEXT("Stable resource exists before presentation scenarios"), RetainedResource.IsValid())) { return false; }
    TestTrue(TEXT("Production table selection succeeds"), Table->TrySelectKey(RetainedResource->GetKey(), true));
    TestTrue(TEXT("Session note establishes retained session state"), Model->TrySetSessionNote(TEXT("Keep selected resource"), Error));
    TestTrue(TEXT("Pinned snapshot establishes retained presentation companion state"), Model->TryPinSelected(Error));
    const TSharedPtr<FCkUiCollection> Activity = Model->GetActivity();
    if (!TestTrue(TEXT("Selection, note, and pin publish retained activity"), Activity.IsValid() && !Activity->GetRecords().IsEmpty())) { return false; }
    const TSharedPtr<const FCkUiRecord> RetainedActivity = Activity->GetRecords()[0];
    const TSharedPtr<const FCkUiRecord> RetainedPin = Model->GetPinnedSnapshots()->FindRecord(RetainedResource->GetKey());
    const int32 ActivityCount = Model->GetActivity()->GetRecords().Num();
    if (!TestTrue(TEXT("Selection, query, session note, pin, and activity are established"), Table->GetSelectedKey().IsSet()
        && Search->GetText().ToString() == TEXT("Resource_00000") && RetainedActivity.IsValid() && RetainedPin.IsValid())) { return false; }

    const TSharedPtr<SWidget> Loading = FindLabel(Model->GetRoot(), TEXT("Loading"));
    if (!TestTrue(TEXT("Installed Loading scenario control is present"), Loading.IsValid() && Click(Slate, Scope.Window.ToSharedRef(), Loading.ToSharedRef()))) { return false; }
    TestEqual(TEXT("Loading control selects the loading presentation"), Model->GetPresentationState(), FString(TEXT("loading")));
    const TSharedPtr<SWidget> LoadingOverlay = FindTagged(Model->GetRoot(), TEXT("resource-loading"));
    const TSharedPtr<SWidget> ErrorOverlay = FindTagged(Model->GetRoot(), TEXT("resource-failure"));
    TestTrue(TEXT("Loading presentation hides the retained table"), !IsEffectivelyVisible(ResourceScroll));
    TestTrue(TEXT("Loading presentation exposes only its authored overlay"), LoadingOverlay.IsValid() && ErrorOverlay.IsValid()
        && IsEffectivelyVisible(LoadingOverlay) && !IsEffectivelyVisible(ErrorOverlay) && FindLabel(Model->GetRoot(), TEXT("Loading resources")).IsValid());
    TestTrue(TEXT("Loading scenario preserves records, selected key, query, note, pin, and activity identity"), Model->GetCollection()->FindRecord(RetainedResource->GetKey()) == RetainedResource
        && Table->GetSelectedKey().IsSet() && Table->GetSelectedKey().GetValue() == RetainedResource->GetKey()
        && Model->GetQuery() == TEXT("Resource_00000") && Model->GetSessionNote() == TEXT("Keep selected resource")
        && Model->GetPinnedSnapshots()->FindRecord(RetainedPin->GetKey()) == RetainedPin
        && Activity->GetRecords().Num() == ActivityCount && Activity->FindRecord(RetainedActivity->GetKey()) == RetainedActivity);

    const FString CaptureDirectory = FPaths::Combine(FPaths::ProjectSavedDir(), TEXT("Automation/ResourceInspector"));
    IFileManager::Get().MakeDirectory(*CaptureDirectory, true);
    TestTrue(TEXT("Loading presentation screenshot saves"), SaveCapture(Slate, Model->GetRoot(), FPaths::Combine(CaptureDirectory, TEXT("Loading.png"))));
    const TSharedPtr<SWidget> LoadingRecovery = FindTagged(Model->GetRoot(), TEXT("finish-loading"));
    if (!TestTrue(TEXT("Loading overlay exposes its recovery action"), LoadingRecovery.IsValid() && Click(Slate, Scope.Window.ToSharedRef(), LoadingRecovery.ToSharedRef()))) { return false; }
    TestEqual(TEXT("Loading recovery restores ready presentation"), Model->GetPresentationState(), FString(TEXT("ready")));

    const TSharedPtr<SWidget> Failure = FindLabel(Model->GetRoot(), TEXT("Error"));
    if (!TestTrue(TEXT("Installed Error scenario control is present"), Failure.IsValid() && Click(Slate, Scope.Window.ToSharedRef(), Failure.ToSharedRef()))) { return false; }
    TestEqual(TEXT("Error control selects the error presentation"), Model->GetPresentationState(), FString(TEXT("error")));
    TestTrue(TEXT("Error presentation hides the retained table"), !IsEffectivelyVisible(ResourceScroll));
    TestTrue(TEXT("Error presentation exposes only its authored overlay"), !IsEffectivelyVisible(LoadingOverlay) && IsEffectivelyVisible(ErrorOverlay)
        && FindLabel(Model->GetRoot(), TEXT("Resources could not be loaded")).IsValid());
    TestTrue(TEXT("Error presentation screenshot saves"), SaveCapture(Slate, Model->GetRoot(), FPaths::Combine(CaptureDirectory, TEXT("Error.png"))));
    TestFalse(TEXT("Unknown presentation key rejects"), Model->TrySetPresentationState(TEXT("unknown")));
    TestEqual(TEXT("Unknown presentation key leaves error presentation unchanged"), Model->GetPresentationState(), FString(TEXT("error")));

    const int64 RevisionBeforeReload = View->GetRevision();
    if (!TestTrue(TEXT("Compatible installed reload succeeds while error presentation is active"), View->ReloadFiles(
        FPaths::Combine(Resources, TEXT("ResourceInspector.ui.html")), FPaths::Combine(Resources, TEXT("ResourceInspector.ui.css"))).Succeeded)) { return false; }
    Tick(Slate);
    const TSharedPtr<SWidget> ReloadedResourceScroll = FindTagged(Model->GetRoot(), TEXT("resource-scroll"));
    const TSharedPtr<SWidget> ReloadedEmptyOverlay = FindTagged(Model->GetRoot(), TEXT("resource-empty"));
    const TSharedPtr<SWidget> ReloadedErrorOverlay = FindTagged(Model->GetRoot(), TEXT("resource-failure"));
    TestTrue(TEXT("Reload retains error presentation, view identity, selection, and retained records"), View->GetRevision() == RevisionBeforeReload + 1
        && View->GetTable(TEXT("inspector-dialog/content/resources")) == Table && View->GetScroll(TEXT("inspector-dialog/content/resource-scroll")) == ResourceScroll
        && ReloadedResourceScroll.IsValid() && ReloadedEmptyOverlay.IsValid() && ReloadedErrorOverlay.IsValid()
        && Model->GetPresentationState() == TEXT("error") && !IsEffectivelyVisible(ReloadedResourceScroll) && IsEffectivelyVisible(ReloadedErrorOverlay)
        && Table->GetSelectedKey().IsSet() && Table->GetSelectedKey().GetValue() == RetainedResource->GetKey()
        && Model->GetCollection()->FindRecord(RetainedResource->GetKey()) == RetainedResource);
    const TSharedPtr<SWidget> ErrorRecovery = FindTagged(Model->GetRoot(), TEXT("recover-resources"));
    if (!TestTrue(TEXT("Error overlay exposes its recovery action"), ErrorRecovery.IsValid() && Click(Slate, Scope.Window.ToSharedRef(), ErrorRecovery.ToSharedRef()))) { return false; }
    TestTrue(TEXT("Error recovery restores ready state without changing retained selection"), Model->GetPresentationState() == TEXT("ready")
        && IsEffectivelyVisible(ReloadedResourceScroll) && Table->GetSelectedKey().IsSet()
        && Table->GetSelectedKey().GetValue() == RetainedResource->GetKey());
    return true;
}
#endif
