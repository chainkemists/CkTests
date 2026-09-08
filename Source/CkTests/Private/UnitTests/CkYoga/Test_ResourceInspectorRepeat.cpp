#include "CkResourceInspector/CkResourceInspectorModel.h"

#include "CkSlateLayout/SCkUiRepeat.h"
#include "CkSlateLayout/SCkUiSurface.h"

#include "Framework/Application/SlateApplication.h"
#include "Interfaces/IPluginManager.h"
#include "Layout/Children.h"
#include "Misc/AutomationTest.h"
#include "Misc/Paths.h"
#include "Widgets/Input/SButton.h"
#include "Widgets/SWindow.h"

#if WITH_DEV_AUTOMATION_TESTS

namespace ck_tests_resource_inspector_repeat
{
    struct FWindowScope final
    {
        explicit FWindowScope(FSlateApplication& InSlate) : Slate(InSlate) {}
        ~FWindowScope() { if (Window.IsValid()) { Slate.DestroyWindowImmediately(Window.ToSharedRef()); } }
        FSlateApplication& Slate;
        TSharedPtr<SWindow> Window;
    };

    auto Tick(FSlateApplication& InSlate) -> void { InSlate.PumpMessages(); InSlate.Tick(); InSlate.Tick(); }

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
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkResourceInspector_PinnedSnapshots,
    "Ck.ResourceInspector.PinnedSnapshots.NativeRepeat",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkResourceInspector_PinnedSnapshots::RunTest(const FString&) -> bool
{
    using namespace ck_tests_resource_inspector_repeat;
    if (!FSlateApplication::IsInitialized()) { AddError(TEXT("Resource Inspector repeat test requires initialized Slate.")); return false; }

    const TSharedPtr<IPlugin> Plugin = IPluginManager::Get().FindPlugin(TEXT("CkTests"));
    if (!TestTrue(TEXT("CkTests plugin resolves"), Plugin.IsValid())) { return false; }
    const FString Resources = FPaths::Combine(Plugin->GetBaseDir(), TEXT("Resources/ResourceInspector"));
    TSharedPtr<FCkResourceInspectorModel> Model;
    FString Error;
    if (!TestTrue(TEXT("Resource Inspector model creates"), FCkResourceInspectorModel::TryCreate({}, Model, Error, 0)) || !Model.IsValid()) { AddError(Error); return false; }
    const TSharedPtr<FCkUiView> View = Model->GetView();
    FSlateApplication& Slate = FSlateApplication::Get();
    FWindowScope Scope{Slate};
    Scope.Window = SNew(SWindow).ClientSize(FVector2D{960.0f, 640.0f}).CreateTitleBar(false).HasCloseButton(false)[Model->GetRoot()];
    Slate.AddWindow(Scope.Window.ToSharedRef(), true);
    const FCkUiLoadResult Loaded = View->ReloadFiles(FPaths::Combine(Resources, TEXT("ResourceInspector.ui.html")), FPaths::Combine(Resources, TEXT("ResourceInspector.ui.css")));
    if (!TestTrue(TEXT("Installed Resource Inspector repeat document loads"), Loaded.Succeeded)) { AddError(FString::Join(Loaded.Errors, TEXT("\n"))); return false; }
    Tick(Slate);

    const TSharedPtr<SCkUiTable> Table = View->GetTable(TEXT("inspector-dialog/content/resources"));
    const TSharedPtr<SCkUiRepeat> Repeat = View->GetRepeat(TEXT("inspector-dialog/content/pinned-snapshots"));
    const TSharedPtr<SButton> Pin = FindButton(Model->GetRoot(), TEXT("pin-selected-resource"));
    if (!TestTrue(TEXT("Installed UI mounts resource table, pinned repeat, and pin action"), Table.IsValid() && Repeat.IsValid() && Pin.IsValid())) { return false; }
    TestTrue(TEXT("Pinned snapshot collection starts empty and the authored pin action is disabled"), Model->GetPinnedSnapshots()->GetRecords().IsEmpty() && Repeat->GetItemCount() == 0 && !Pin->IsEnabled());

    if (!TestTrue(TEXT("First resource selects through the real table"), Table->TrySelectKey(FString(TEXT("resource-00000")), true))) { return false; }
    Tick(Slate);
    TestTrue(TEXT("Pin action enables for a valid selection"), Pin->IsEnabled());
    Pin->SimulateClick();
    Tick(Slate);
    if (!TestTrue(TEXT("First authored pin creates one snapshot card"), Model->GetPinnedSnapshots()->GetRecords().Num() == 1 && Repeat->GetItemCount() == 1)) { return false; }

    if (!TestTrue(TEXT("Second resource selects through the real table"), Table->TrySelectKey(FString(TEXT("resource-00001")), true))) { return false; }
    Pin->SimulateClick();
    Tick(Slate);
    if (!TestTrue(TEXT("Second authored pin creates an independent card"), Model->GetPinnedSnapshots()->GetRecords().Num() == 2 && Repeat->GetItemCount() == 2)) { return false; }

    const TSharedPtr<SWidget> FirstCard = Repeat->GetItemWidget(TEXT("resource-00000"));
    const TSharedPtr<SWidget> SecondCard = Repeat->GetItemWidget(TEXT("resource-00001"));
    const TSharedPtr<SButton> FirstToggle = FirstCard.IsValid() ? FindButton(FirstCard.ToSharedRef(), TEXT("toggle-pinned-snapshot")) : nullptr;
    const TSharedPtr<SWidget> FirstDetails = FirstCard.IsValid() ? FindTagged(FirstCard.ToSharedRef(), TEXT("pinned-snapshot-details")) : nullptr;
    const TSharedPtr<SWidget> SecondDetails = SecondCard.IsValid() ? FindTagged(SecondCard.ToSharedRef(), TEXT("pinned-snapshot-details")) : nullptr;
    if (!TestTrue(TEXT("Each authored repeat card mounts its native toggle and details"), FirstToggle.IsValid() && FirstDetails.IsValid() && SecondDetails.IsValid())) { return false; }
    FirstToggle->SimulateClick();
    Tick(Slate);
    TestTrue(TEXT("Toggling one snapshot collapses only its own details"), FirstDetails->GetVisibility() == EVisibility::Collapsed && SecondDetails->GetVisibility() == EVisibility::Visible);

    if (!TestTrue(TEXT("First resource reselects through the real table"), Table->TrySelectKey(FString(TEXT("resource-00000")), true))) { return false; }
    Pin->SimulateClick();
    Tick(Slate);
    TestTrue(TEXT("Pinning the same stable key updates instead of duplicating and retains its local expansion choice"),
        Model->GetPinnedSnapshots()->GetRecords().Num() == 2 && Repeat->GetItemCount() == 2 && FirstDetails->GetVisibility() == EVisibility::Collapsed);

    const int64 AcceptedRevision = View->GetRevision();
    if (!TestTrue(TEXT("Compatible installed reload succeeds with pinned snapshots"), View->ReloadFiles(FPaths::Combine(Resources, TEXT("ResourceInspector.ui.html")), FPaths::Combine(Resources, TEXT("ResourceInspector.ui.css"))).Succeeded)) { return false; }
    Tick(Slate);
    TestTrue(TEXT("Accepted reload retains pinned snapshot data"), View->GetRevision() == AcceptedRevision + 1 && Model->GetPinnedSnapshots()->GetRecords().Num() == 2 && View->GetRepeat(TEXT("inspector-dialog/content/pinned-snapshots"))->GetItemCount() == 2);
    const int64 RejectedRevision = View->GetRevision();
    const FCkUiLoadResult Rejected = View->TryReload(TEXT("<ui version=\"1\"><region name=\"main\"><table id=\"resources\""), TEXT(""), TEXT("ResourceInspectorRepeatRejected"));
    TestTrue(TEXT("Rejected reload reports errors and preserves pinned snapshot data"), !Rejected.Succeeded && !Rejected.Errors.IsEmpty()
        && View->GetRevision() == RejectedRevision && Model->GetPinnedSnapshots()->GetRecords().Num() == 2);

    const TSharedPtr<SCkUiRepeat> ReloadedRepeat = View->GetRepeat(TEXT("inspector-dialog/content/pinned-snapshots"));
    const TSharedPtr<SWidget> ReloadedFirstCard = ReloadedRepeat.IsValid() ? ReloadedRepeat->GetItemWidget(TEXT("resource-00000")) : nullptr;
    const TSharedPtr<SButton> Remove = ReloadedFirstCard.IsValid() ? FindButton(ReloadedFirstCard.ToSharedRef(), TEXT("remove-pinned-snapshot")) : nullptr;
    if (!TestTrue(TEXT("Reloaded first card exposes its authored removal button"), Remove.IsValid())) { return false; }
    Remove->SimulateClick();
    Tick(Slate);
    TestTrue(TEXT("Authored removal deletes only its card"), Model->GetPinnedSnapshots()->GetRecords().Num() == 1 && !ReloadedRepeat->GetItemWidget(TEXT("resource-00000")).IsValid());
    Remove->SimulateClick();
    TestTrue(TEXT("Held removal button is inert after its keyed card is removed"), Model->GetPinnedSnapshots()->GetRecords().Num() == 1);

    TestTrue(TEXT("Category change succeeds"), Model->TrySetCategory(TEXT("shader"), Error));
    TestTrue(TEXT("Scenario change succeeds"), Model->TrySetRowCount(0, Error));
    Tick(Slate);
    TestTrue(TEXT("Category and scenario changes retain snapshots until their explicit removal"), Model->GetPinnedSnapshots()->GetRecords().Num() == 1 && ReloadedRepeat->GetItemCount() == 1);
    return true;
}

#endif
