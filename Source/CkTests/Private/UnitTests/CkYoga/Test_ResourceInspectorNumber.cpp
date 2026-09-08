#include "CkResourceInspector/CkResourceInspectorModel.h"

#include "Framework/Application/SlateApplication.h"
#include "Input/Events.h"
#include "Layout/WidgetPath.h"
#include "Widgets/Input/SSlider.h"
#include "InputCoreTypes.h"
#include "Interfaces/IPluginManager.h"
#include "Misc/AutomationTest.h"
#include "Misc/Paths.h"
#include "Widgets/Input/SEditableTextBox.h"
#include "Widgets/SWindow.h"

#if WITH_DEV_AUTOMATION_TESTS

namespace ck_tests_resource_inspector_number
{
    auto FindEditor(const TSharedRef<SWidget>& InRoot) -> TSharedPtr<SEditableTextBox>
    {
        if (InRoot->GetTag() == TEXT("row-count") && InRoot->GetTypeAsString() == TEXT("SCkUiTextInputBox"))
        { return StaticCastSharedRef<SEditableTextBox>(InRoot); }
        const FChildren* Children = InRoot->GetChildren();
        if (Children == nullptr) { return nullptr; }
        for (int32 Index = 0; Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<SEditableTextBox> Found = FindEditor(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index))); Found.IsValid()) { return Found; }
        }
        return nullptr;
    }

    auto FindSlider(const TSharedRef<SWidget>& InRoot) -> TSharedPtr<SSlider>
    {
        if (InRoot->GetTypeAsString() == TEXT("SCkUiSlider") && InRoot->GetTag() == TEXT("row-count-slider"))
        { return StaticCastSharedRef<SSlider>(InRoot); }
        const FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<SSlider> Found = FindSlider(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)))) { return Found; }
        }
        return {};
    }

    auto SliderPointer(FSlateApplication& InSlate, const TSharedRef<SSlider>& InSlider, bool InRelease) -> bool
    {
        const FGeometry Geometry = InSlider->GetCachedGeometry();
        const FVector2D Position = Geometry.LocalToAbsolute(FVector2D(Geometry.GetLocalSize().X * 0.6f, Geometry.GetLocalSize().Y * 0.5f));
        const TSet<FKey> Buttons = InRelease ? TSet<FKey>{} : TSet<FKey>{EKeys::LeftMouseButton};
        const FPointerEvent Event(0, FSlateApplication::CursorPointerIndex, Position, Position, Buttons, EKeys::LeftMouseButton, 0.0f, FModifierKeysState{});
        FWidgetPath Path;
        if (!InSlate.GeneratePathToWidgetUnchecked(InSlider, Path)) { return false; }
        const FReply Reply = InRelease ? InSlider->OnMouseButtonUp(Geometry, Event) : InSlider->OnMouseButtonDown(Geometry, Event);
        InSlate.ProcessReply(Path, Reply, &Path, &Event, 0);
        return Reply.IsEventHandled();
    }

    auto Tick(FSlateApplication& InSlate) -> void { InSlate.PumpMessages(); InSlate.Tick(); InSlate.Tick(); }
    auto Key(const FKey InKey) -> FKeyEvent { return FKeyEvent{InKey, FModifierKeysState{}, 0, false, 0, 0}; }

    auto ReplaceText(FSlateApplication& InSlate, const TSharedRef<SEditableTextBox>& InEditor, const FString& InText) -> bool
    {
        InSlate.SetUserFocus(0, InEditor, EFocusCause::SetDirectly);
        Tick(InSlate);
        const FModifierKeysState Control{false, false, true, false, false, false, false, false, false};
        if (!InSlate.ProcessKeyDownEvent(FKeyEvent{EKeys::A, Control, 0, false, 0, 0})) { return false; }
        for (const TCHAR Character : InText)
        {
            if (!InSlate.ProcessKeyCharEvent(FCharacterEvent{Character, FModifierKeysState{}, 0, false})) { return false; }
        }
        Tick(InSlate);
        return true;
    }

    struct FWindowScope final
    {
        explicit FWindowScope(FSlateApplication& InSlate) : Slate(InSlate) {}
        ~FWindowScope() { if (Window.IsValid()) { Slate.DestroyWindowImmediately(Window.ToSharedRef()); } }
        FSlateApplication& Slate;
        TSharedPtr<SWindow> Window;
    };
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkResourceInspector_Number,
    "Ck.ResourceInspector.Form.ResourceCount",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkResourceInspector_Number::RunTest(const FString&) -> bool
{
    using namespace ck_tests_resource_inspector_number;
    if (!FSlateApplication::IsInitialized()) { AddError(TEXT("Resource count test requires Slate.")); return false; }
    const TSharedPtr<IPlugin> Plugin = IPluginManager::Get().FindPlugin(TEXT("CkTests"));
    if (!TestTrue(TEXT("CkTests plugin is installed"), Plugin.IsValid())) { return false; }
    const FString Directory = FPaths::Combine(Plugin->GetBaseDir(), TEXT("Resources/ResourceInspector"));
    const FString MarkupPath = FPaths::Combine(Directory, TEXT("ResourceInspector.ui.html"));
    const FString StylesheetPath = FPaths::Combine(Directory, TEXT("ResourceInspector.ui.css"));
    TSharedPtr<FCkResourceInspectorModel> Model;
    FString Error;
    if (!TestTrue(TEXT("Inspector model creates"), FCkResourceInspectorModel::TryCreate({}, Model, Error, 0))) { AddError(Error); return false; }
    const TSharedRef<FCkUiView> View = Model->GetView();
    const FCkUiLoadResult Loaded = View->ReloadFiles(MarkupPath, StylesheetPath);
    if (!TestTrue(TEXT("Installed numeric form loads"), Loaded.Succeeded))
    {
        for (const FString& LoadError : Loaded.Errors) { AddError(LoadError); }
        return false;
    }
    FSlateApplication& Slate = FSlateApplication::Get();
    FWindowScope Scope{Slate};
    Scope.Window = SNew(SWindow).AutoCenter(EAutoCenter::None).ClientSize(FVector2D{960.0f, 640.0f})
        .CreateTitleBar(false).HasCloseButton(false)[Model->GetRoot()];
    Slate.AddWindow(Scope.Window.ToSharedRef(), true);
    Tick(Slate);
    const TSharedPtr<SEditableTextBox> Editor = FindEditor(Model->GetRoot());
    if (!TestTrue(TEXT("Numeric input reuses the shared native text editor"), Editor.IsValid())) { return false; }
    TestEqual(TEXT("Scenario starts with sample count"), Model->GetRowCount(), 12);
    if (!TestTrue(TEXT("Native keyboard enters custom count"), ReplaceText(Slate, Editor.ToSharedRef(), TEXT("42.6")))) { return false; }
    TestEqual(TEXT("Typing does not repopulate the collection"), Model->GetCollection()->GetRecords().Num(), 12);
    const TSharedPtr<SWidget> FocusBefore = Slate.GetUserFocusedWidget(0);
    if (!TestTrue(TEXT("Numeric draft survives installed-resource reload"), View->ReloadFiles(MarkupPath, StylesheetPath).Succeeded)) { return false; }
    Tick(Slate);
    TestTrue(TEXT("Reload retains editor, focus and numeric draft"), FindEditor(Model->GetRoot()) == Editor
        && Slate.GetUserFocusedWidget(0) == FocusBefore && Editor->GetText().ToString() == TEXT("42.6"));
    Slate.ProcessKeyDownEvent(Key(EKeys::Enter));
    Tick(Slate);
    TestTrue(TEXT("Commit rounds and repopulates the actual collection"), Model->GetRowCount() == 43 && Model->GetCollection()->GetRecords().Num() == 43);
    if (!TestTrue(TEXT("Native keyboard enters invalid count"), ReplaceText(Slate, Editor.ToSharedRef(), TEXT("42junk")))) { return false; }
    Slate.ProcessKeyDownEvent(Key(EKeys::Enter));
    Tick(Slate);
    TestTrue(TEXT("Invalid numeric input leaves count and collection intact"), Model->GetRowCount() == 43 && Model->GetCollection()->GetRecords().Num() == 43);
    if (!TestTrue(TEXT("Native keyboard enters negative count"), ReplaceText(Slate, Editor.ToSharedRef(), TEXT("-7")))) { return false; }
    Slate.ProcessKeyDownEvent(Key(EKeys::Enter));
    Tick(Slate);
    TestTrue(TEXT("Minimum clamps to empty scenario"), Model->GetRowCount() == 0 && Model->GetCollection()->GetRecords().IsEmpty());
    if (!TestTrue(TEXT("Preset-style model update succeeds"), Model->TrySetRowCount(500, Error))) { return false; }
    Tick(Slate);
    TestEqual(TEXT("External scenario change updates numeric display"), Editor->GetText().ToString(), FString(TEXT("500")));
    const TSharedPtr<SSlider> Slider = FindSlider(Model->GetRoot());
    if (!TestTrue(TEXT("Installed resources create the shared slider"), Slider.IsValid())) { return false; }
    const int32 BeforeSlider = Model->GetRowCount();
    TestTrue(TEXT("Native slider begins preview"), SliderPointer(Slate, Slider.ToSharedRef(), false));
    TestEqual(TEXT("Slider preview leaves actual collection unchanged"), Model->GetCollection()->GetRecords().Num(), BeforeSlider);
    TestTrue(TEXT("Installed layout reload retains active slider"), View->ReloadFiles(MarkupPath, StylesheetPath).Succeeded);
    TestTrue(TEXT("Native slider release commits"), SliderPointer(Slate, Slider.ToSharedRef(), true));
    Tick(Slate);
    TestTrue(TEXT("Slider commit updates actual collection and numeric editor"), Model->GetRowCount() > 5000
        && Model->GetCollection()->GetRecords().Num() == Model->GetRowCount()
        && Editor->GetText().ToString() == FString::FromInt(Model->GetRowCount()));
    return true;
}

#endif
