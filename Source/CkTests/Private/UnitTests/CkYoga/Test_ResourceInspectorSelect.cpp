#include "CkResourceInspector/CkResourceInspectorModel.h"

#include "CkSlateLayout/SCkUiSurface.h"

#include "Framework/Application/SlateApplication.h"
#include "Input/Events.h"
#include "InputCoreTypes.h"
#include "Interfaces/IPluginManager.h"
#include "Layout/Children.h"
#include "Misc/AutomationTest.h"
#include "Misc/Paths.h"
#include "Widgets/Input/SSearchBox.h"
#include "Widgets/SWindow.h"
#include "Widgets/Text/STextBlock.h"

#if WITH_DEV_AUTOMATION_TESTS
namespace ck_tests_resource_inspector_select
{
    struct FWindowScope final
    {
        explicit FWindowScope(FSlateApplication& InSlate) : Slate(InSlate) {}
        ~FWindowScope() { if (Window.IsValid()) { Slate.DestroyWindowImmediately(Window.ToSharedRef()); } }
        FSlateApplication& Slate;
        TSharedPtr<SWindow> Window;
    };

    auto Tick(FSlateApplication& InSlate) -> void { InSlate.PumpMessages(); InSlate.Tick(); InSlate.Tick(); }
    auto Key(const FKey InKey) -> FKeyEvent { return FKeyEvent(InKey, FModifierKeysState{}, 0, false, 0, 0); }

    auto FindType(const TSharedRef<SWidget>& InRoot, const FString& InType) -> TSharedPtr<SWidget>
    {
        if (InRoot->GetTypeAsString() == InType) { return InRoot; }
        const FChildren* Children = InRoot->GetChildren();
        if (Children == nullptr) { return nullptr; }
        for (int32 Index = 0; Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<SWidget> Found = FindType(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InType); Found.IsValid()) { return Found; }
        }
        return nullptr;
    }

    auto FindSearch(const TSharedRef<SWidget>& InRoot) -> TSharedPtr<SSearchBox>
    {
        const TSharedPtr<SWidget> Found = FindType(InRoot, TEXT("SSearchBox"));
        return Found.IsValid() ? StaticCastSharedPtr<SSearchBox>(Found) : nullptr;
    }

    auto ContainsLabel(const TSharedRef<SWidget>& InRoot, const FString& InText) -> bool
    {
        if (InRoot->GetTypeAsString() == TEXT("STextBlock") && StaticCastSharedRef<STextBlock>(InRoot)->GetText().ToString() == InText) { return true; }
        const FChildren* Children = InRoot->GetChildren();
        if (Children == nullptr) { return false; }
        for (int32 Index = 0; Index < Children->Num(); ++Index)
        {
            if (ContainsLabel(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InText)) { return true; }
        }
        return false;
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkResourceInspector_Select,
    "Ck.ResourceInspector.CategorySelect.NativeKeyboard",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkResourceInspector_Select::RunTest(const FString&) -> bool
{
    using namespace ck_tests_resource_inspector_select;
    if (!FSlateApplication::IsInitialized()) { AddError(TEXT("Resource Inspector select test requires Slate.")); return false; }
    const TSharedPtr<IPlugin> Plugin = IPluginManager::Get().FindPlugin(TEXT("CkTests"));
    if (!TestTrue(TEXT("CkTests plugin resolves"), Plugin.IsValid())) { return false; }
    const FString Resources = FPaths::Combine(Plugin->GetBaseDir(), TEXT("Resources/ResourceInspector"));
    TSharedPtr<FCkResourceInspectorModel> Model;
    FString Error;
    if (!TestTrue(*Error, FCkResourceInspectorModel::TryCreate({}, Model, Error, 0)) || !Model.IsValid()) { return false; }
    TWeakPtr<FCkResourceInspectorModel> WeakModel = Model;
    TSharedPtr<FCkUiView> View = Model->GetView();
    FSlateApplication& Slate = FSlateApplication::Get();
    FWindowScope Scope{Slate};
    Scope.Window = SNew(SWindow).AutoCenter(EAutoCenter::None).ClientSize(FVector2D{960, 640}).CreateTitleBar(false).HasCloseButton(false)[Model->GetRoot()];
    Slate.AddWindow(Scope.Window.ToSharedRef(), true);
    const FCkUiLoadResult Loaded = View->ReloadFiles(FPaths::Combine(Resources, TEXT("ResourceInspector.ui.html")), FPaths::Combine(Resources, TEXT("ResourceInspector.ui.css")));
    if (!TestTrue(TEXT("Installed Resource Inspector select document loads"), Loaded.Succeeded)) { return false; }
    Tick(Slate);
    const TSharedPtr<SWidget> Select = FindType(Model->GetRoot(), TEXT("SCkUiSelect"));
    const TSharedPtr<SSearchBox> Search = FindSearch(Model->GetRoot());
    const TSharedPtr<SCkUiTable> Table = View->GetTable(TEXT("inspector-dialog/content/resources"));
    if (!TestTrue(TEXT("Installed markup mounts native shared select, search, and table"), Select.IsValid() && Search.IsValid() && Table.IsValid())) { return false; }
    Slate.SetUserFocus(0, Select.ToSharedRef(), EFocusCause::SetDirectly);
    Tick(Slate);
    TestTrue(TEXT("Native Down selects texture"), Slate.ProcessKeyDownEvent(Key(EKeys::Down)));
    Tick(Slate);
    TestTrue(TEXT("Texture selection updates model, projection, and visible label"), Model->GetCategory() == TEXT("texture") && Table->GetVisibleRecordCount() == 3 && ContainsLabel(Select.ToSharedRef(), TEXT("Texture")));
    TestTrue(TEXT("Native next Down selects material"), Slate.ProcessKeyDownEvent(Key(EKeys::Down)));
    Tick(Slate);
    TestTrue(TEXT("Material selection updates model and projection"), Model->GetCategory() == TEXT("material") && Table->GetVisibleRecordCount() == 3);
    Search->SetText(FText::FromString(TEXT("Resource_00005")));
    Tick(Slate);
    TestEqual(TEXT("Search intersects category projection"), Table->GetVisibleRecordCount(), 1);
    TestTrue(TEXT("External category change succeeds"), Model->TrySetCategory(TEXT("shader"), Error));
    Tick(Slate);
    TestTrue(TEXT("External category change updates select label and query intersection"), ContainsLabel(Select.ToSharedRef(), TEXT("Shader")) && Table->GetVisibleRecordCount() == 0);
    const int64 Revision = View->GetRevision();
    if (!TestTrue(TEXT("Compatible installed reload succeeds"), View->ReloadFiles(FPaths::Combine(Resources, TEXT("ResourceInspector.ui.html")), FPaths::Combine(Resources, TEXT("ResourceInspector.ui.css"))).Succeeded)) { return false; }
    Tick(Slate);
    TestTrue(TEXT("Reload retains select identity and category"), View->GetRevision() == Revision + 1 && FindType(Model->GetRoot(), TEXT("SCkUiSelect")) == Select && Model->GetCategory() == TEXT("shader"));
    Scope.Slate.DestroyWindowImmediately(Scope.Window.ToSharedRef());
    Scope.Window.Reset();
    Model.Reset();
    TestFalse(TEXT("Model is released while native select is held"), WeakModel.IsValid());
    Select->OnKeyDown(Select->GetCachedGeometry(), Key(EKeys::Down));
    View.Reset();
    const FReply Released = Select->OnKeyDown(Select->GetCachedGeometry(), Key(EKeys::Down));
    TestFalse(TEXT("Held select rejects input after view release"), Released.IsEventHandled());
    return true;
}
#endif
