#include "CkResourceInspector/CkResourceInspectorModel.h"

#include "Framework/Application/SlateApplication.h"
#include "Input/Events.h"
#include "InputCoreTypes.h"
#include "Interfaces/IPluginManager.h"
#include "Misc/AutomationTest.h"
#include "Misc/Paths.h"
#include "Widgets/Input/SEditableTextBox.h"
#include "Widgets/Input/SCheckBox.h"
#include "Widgets/SWindow.h"

#if WITH_DEV_AUTOMATION_TESTS

namespace ck_tests_resource_inspector_form
{
    auto FindEditor(const TSharedRef<SWidget>& InRoot) -> TSharedPtr<SEditableTextBox>
    {
        if (InRoot->GetTypeAsString() == TEXT("SEditableTextBox") || InRoot->GetTypeAsString() == TEXT("SCkUiTextInputBox")) { return StaticCastSharedRef<SEditableTextBox>(InRoot); }
        const FChildren* Children = InRoot->GetChildren();
        if (Children == nullptr) { return nullptr; }
        for (int32 Index = 0; Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<SEditableTextBox> Found = FindEditor(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index))); Found.IsValid()) { return Found; }
        }
        return nullptr;
    }

    auto FindCheckbox(const TSharedRef<SWidget>& InRoot) -> TSharedPtr<SCheckBox>
    {
        if (InRoot->GetTypeAsString() == TEXT("SCheckBox")) { return StaticCastSharedRef<SCheckBox>(InRoot); }
        const FChildren* Children = InRoot->GetChildren();
        if (Children == nullptr) { return nullptr; }
        for (int32 Index = 0; Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<SCheckBox> Found = FindCheckbox(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index))); Found.IsValid()) { return Found; }
        }
        return nullptr;
    }

    auto Tick(FSlateApplication& InSlate) -> void
    {
        InSlate.PumpMessages();
        InSlate.Tick();
        InSlate.Tick();
    }

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

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkResourceInspector_Form,
    "Ck.ResourceInspector.Form.SessionNote",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkResourceInspector_Form::RunTest(const FString&) -> bool
{
    using namespace ck_tests_resource_inspector_form;
    if (!FSlateApplication::IsInitialized()) { AddError(TEXT("Resource Inspector form requires Slate.")); return false; }
    const TSharedPtr<IPlugin> Plugin = IPluginManager::Get().FindPlugin(TEXT("CkTests"));
    if (!TestTrue(TEXT("CkTests plugin is installed"), Plugin.IsValid())) { return false; }
    const FString Directory = FPaths::Combine(Plugin->GetBaseDir(), TEXT("Resources/ResourceInspector"));
    const FString MarkupPath = FPaths::Combine(Directory, TEXT("ResourceInspector.ui.html"));
    const FString StylesheetPath = FPaths::Combine(Directory, TEXT("ResourceInspector.ui.css"));
    TSharedPtr<FCkResourceInspectorModel> Model;
    FString Error;
    if (!TestTrue(TEXT("Resource Inspector model creates"), FCkResourceInspectorModel::TryCreate({}, Model, Error, 0))) { AddError(Error); return false; }
    TestTrue(TEXT("Properties tab selects for form editing"), Model->TrySetDetailTab(TEXT("properties")));
    const TSharedRef<FCkUiView> View = Model->GetView();
    const FCkUiLoadResult Loaded = View->ReloadFiles(MarkupPath, StylesheetPath);
    if (!TestTrue(TEXT("Installed Resource Inspector form loads"), Loaded.Succeeded))
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
    // Search boxes also contain editable text; locate the form by its authored tag first.
    TFunction<TSharedPtr<SWidget>(const TSharedRef<SWidget>&)> FindNote;
    FindNote = [&FindNote](const TSharedRef<SWidget>& Root) -> TSharedPtr<SWidget>
    {
        if (Root->GetTag() == TEXT("session-note")) { return Root; }
        const FChildren* Children = Root->GetChildren();
        if (Children == nullptr) { return nullptr; }
        for (int32 Index = 0; Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<SWidget> Found = FindNote(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index))); Found.IsValid()) { return Found; }
        }
        return nullptr;
    };
    const TSharedPtr<SWidget> Note = FindNote(Model->GetRoot());
    const TSharedPtr<SEditableTextBox> Editor = Note.IsValid() ? FindEditor(Note.ToSharedRef()) : nullptr;
    if (!TestTrue(TEXT("Session note uses the registered native text editor"), Editor.IsValid())) { return false; }
    TestTrue(TEXT("Initial session note is empty"), Model->GetSessionNote().IsEmpty());
    if (!TestTrue(TEXT("Native keyboard edits the session note"), ReplaceText(Slate, Editor.ToSharedRef(), TEXT("  Investigate streaming  ")))) { return false; }
    TestTrue(TEXT("Typing remains a draft before commit"), Model->GetSessionNote().IsEmpty());
    const TSharedPtr<SWidget> FocusBeforeReload = Slate.GetUserFocusedWidget(0);
    if (!TestTrue(TEXT("Valid layout reload succeeds while editing"), View->ReloadFiles(MarkupPath, StylesheetPath).Succeeded)) { return false; }
    Tick(Slate);
    const TSharedPtr<SWidget> ReloadedNote = FindNote(Model->GetRoot());
    TestTrue(TEXT("Reload retains the actual form editor and focus"), ReloadedNote.IsValid()
        && FindEditor(ReloadedNote.ToSharedRef()) == Editor && Slate.GetUserFocusedWidget(0) == FocusBeforeReload);
    TestTrue(TEXT("Reload preserves the draft without committing it"), Editor->GetText().ToString() == TEXT("  Investigate streaming  ") && Model->GetSessionNote().IsEmpty());
    TestTrue(TEXT("Enter commits through the native event"), Slate.ProcessKeyDownEvent(FKeyEvent{EKeys::Enter, FModifierKeysState{}, 0, false, 0, 0}));
    Tick(Slate);
    TestEqual(TEXT("Model normalizes the accepted note"), Model->GetSessionNote(), FString(TEXT("Investigate streaming")));
    TestTrue(TEXT("Accepted note has no validation error"), Model->GetSessionNoteError().IsEmpty());
    if (!TestTrue(TEXT("Native keyboard enters an overlong note"), ReplaceText(Slate, Editor.ToSharedRef(), FString::ChrN(81, TEXT('x'))))) { return false; }
    Slate.ProcessKeyDownEvent(FKeyEvent{EKeys::Enter, FModifierKeysState{}, 0, false, 0, 0});
    Tick(Slate);
    TestEqual(TEXT("Rejected edit preserves the accepted model value"), Model->GetSessionNote(), FString(TEXT("Investigate streaming")));
    TestTrue(TEXT("Rejected edit reports validation feedback"), !Model->GetSessionNoteError().IsEmpty());
    if (!TestTrue(TEXT("Native keyboard corrects the rejected note"), ReplaceText(Slate, Editor.ToSharedRef(), TEXT("Review mips")))) { return false; }
    Slate.ProcessKeyDownEvent(FKeyEvent{EKeys::Enter, FModifierKeysState{}, 0, false, 0, 0});
    Tick(Slate);
    TestTrue(TEXT("Corrected edit publishes and clears feedback"), Model->GetSessionNote() == TEXT("Review mips") && Model->GetSessionNoteError().IsEmpty());
    if (!TestTrue(TEXT("Category and scenario can change after a form edit"), Model->TrySetCategory(TEXT("texture"), Error) && Model->TrySetRowCount(1000, Error))) { return false; }
    TestEqual(TEXT("Session annotation remains independent of resource selection and scenario"), Model->GetSessionNote(), FString(TEXT("Review mips")));
    const TSharedPtr<SCheckBox> LockNote = FindCheckbox(Model->GetRoot());
    if (!TestTrue(TEXT("Authored note lock uses a native checkbox"), LockNote.IsValid())) { return false; }
    TestFalse(TEXT("Note starts unlocked"), Model->IsSessionNoteLocked());
    Slate.SetUserFocus(0, LockNote.ToSharedRef(), EFocusCause::SetDirectly);
    Tick(Slate);
    Slate.ProcessKeyDownEvent(FKeyEvent{EKeys::SpaceBar, FModifierKeysState{}, 0, false, 0, 0});
    Slate.ProcessKeyUpEvent(FKeyEvent{EKeys::SpaceBar, FModifierKeysState{}, 0, false, 0, 0});
    Tick(Slate);
    TestTrue(TEXT("Native toggle updates model and editor read-only binding"), Model->IsSessionNoteLocked() && Editor->IsReadOnly());
    if (!TestTrue(TEXT("Reload succeeds with locked note"), View->ReloadFiles(MarkupPath, StylesheetPath).Succeeded)) { return false; }
    Tick(Slate);
    TestTrue(TEXT("Reload retains checkbox identity and locked state"), FindCheckbox(Model->GetRoot()) == LockNote && LockNote->IsChecked() && Model->IsSessionNoteLocked());
    Slate.ProcessKeyDownEvent(FKeyEvent{EKeys::SpaceBar, FModifierKeysState{}, 0, false, 0, 0});
    Slate.ProcessKeyUpEvent(FKeyEvent{EKeys::SpaceBar, FModifierKeysState{}, 0, false, 0, 0});
    Tick(Slate);
    TestTrue(TEXT("Keyboard routing after reload unlocks the note"), !Model->IsSessionNoteLocked() && !Editor->IsReadOnly());
    return true;
}

#endif
