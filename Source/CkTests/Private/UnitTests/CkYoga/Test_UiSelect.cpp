#include "CkSlateLayout/CkUiCollection.h"
#include "CkSlateLayout/CkUiSelect.h"
#include "CkSlateLayout/SCkUiSurface.h"

#include "Framework/Application/SlateApplication.h"
#include "Input/Events.h"
#include "InputCoreTypes.h"
#include "Layout/Children.h"
#include "Misc/AutomationTest.h"
#include "Styling/CoreStyle.h"
#include "Widgets/Text/STextBlock.h"
#include "Widgets/Input/SMenuAnchor.h"
#include "Widgets/SWindow.h"

#if WITH_DEV_AUTOMATION_TESTS
namespace ck_tests_ui_select
{
    auto Markup(const TCHAR* InValueBinding = TEXT("value"), const TCHAR* InOptionsBinding = TEXT("options")) -> FString
    {
        return FString::Printf(TEXT("<ui version=\"1\"><region name=\"main\"><column id=\"root\"><select id=\"select\" value-bind=\"%s\" options-bind=\"%s\" changed=\"changed\" placeholder-bind=\"placeholder\" enabled-bind=\"enabled\" read-only-bind=\"read-only\"/></column></region></ui>"), InValueBinding, InOptionsBinding);
    }

    auto Record(const FString& InKey, const FString& InLabel) -> FCkUiRecordData
    {
        auto Result = FCkUiRecordData{};
        Result.Key = InKey;
        Result.Fields.Add(TEXT("label"), FCkUiFieldValue{.Kind = ECkUiFieldKind::Text, .Text = FText::FromString(InLabel)});
        return Result;
    }

    auto Options(const FString& InAlpha = TEXT("Alpha"), const FString& InBeta = TEXT("Beta")) -> TArray<FCkUiRecordData>
    {
        return {Record(TEXT("a"), InAlpha), Record(TEXT("b"), InBeta)};
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

    auto FindText(const TSharedRef<SWidget>& InRoot) -> TSharedPtr<STextBlock>
    {
        if (InRoot->GetTypeAsString() == TEXT("STextBlock")) { return StaticCastSharedRef<STextBlock>(InRoot); }
        const FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<STextBlock> Found = FindText(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index))); Found.IsValid()) { return Found; }
        }
        return {};
    }

    auto ContainsText(const TSharedRef<SWidget>& InRoot, const FString& InText) -> bool
    {
        if (InRoot->GetTypeAsString() == TEXT("STextBlock") && StaticCastSharedRef<STextBlock>(InRoot)->GetText().ToString() == InText) { return true; }
        const FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            if (ContainsText(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InText)) { return true; }
        }
        return false;
    }

    auto Tick(FSlateApplication& InSlate) -> void { InSlate.PumpMessages(); InSlate.Tick(); InSlate.Tick(); }
    auto Key(const FKey InKey) -> FKeyEvent { return FKeyEvent(InKey, FModifierKeysState{}, 0, false, 0, 0); }

    struct FWindowScope final
    {
        explicit FWindowScope(FSlateApplication& InSlate) : Slate(InSlate) {}
        ~FWindowScope() { if (Window.IsValid()) { Slate.DestroyWindowImmediately(Window.ToSharedRef()); } }
        FSlateApplication& Slate;
        TSharedPtr<SWindow> Window;
    };
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiSelect_Runtime,
    "Ck.UiAuthoring.Select.RetainedCollectionKeyboard",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiSelect_Runtime::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_select;
    if (!FSlateApplication::IsInitialized()) { AddError(TEXT("Select test requires Slate.")); return false; }

    auto Registry = FCkUiWidgetRegistry{};
    if (!TestTrue(TEXT("Shared select registration succeeds"), FCkUiSelect::Register(Registry).Succeeded)) { return false; }
    TSharedPtr<FCkUiCollection> Collection;
    if (!TestTrue(TEXT("Select options collection creates"), FCkUiCollection::TryCreate({{TEXT("label"), ECkUiFieldKind::Text}}, Collection).Succeeded)
        || !TestTrue(TEXT("Select options publish stable keys"), Collection->TrySetRecords(Options()).Succeeded)) { return false; }

    FString Value = TEXT("a");
    FString OtherValue = TEXT("b");
    FString Placeholder = TEXT("No option");
    bool Enabled = true;
    bool ReadOnly = false;
    bool Accept = true;
    int32 ChangedCalls = 0;
    auto Data = FCkUiView::FDataBindings{};
    Data.String.Add(TEXT("value"), TAttribute<FString>::CreateLambda([&Value] { return Value; }));
    Data.String.Add(TEXT("other"), TAttribute<FString>::CreateLambda([&OtherValue] { return OtherValue; }));
    Data.Text.Add(TEXT("placeholder"), TAttribute<FText>::CreateLambda([&Placeholder] { return FText::FromString(Placeholder); }));
    Data.Visibility.Add(TEXT("enabled"), TAttribute<bool>::CreateLambda([&Enabled] { return Enabled; }));
    Data.Visibility.Add(TEXT("read-only"), TAttribute<bool>::CreateLambda([&ReadOnly] { return ReadOnly; }));
    Data.Collections.Add(TEXT("options"), Collection);
    Data.StringChanged.Add(TEXT("changed"), FCkUiOnStringChanged::CreateLambda([&Value, &Accept, &ChangedCalls](const FString& InValue)
    {
        ++ChangedCalls;
        if (Accept) { Value = InValue; }
    }));

    TSharedPtr<FCkUiView> View = FCkUiView::Create({}, {}, {}, FCoreStyle::GetDefaultFontStyle(TEXT("Regular"), 12), MoveTemp(Data), Registry.CreateSnapshot());
    TSharedPtr<SWidget> Region = View->GetRegion(TEXT("main"));
    FSlateApplication& Slate = FSlateApplication::Get();
    FWindowScope Scope(Slate);
    Scope.Window = SNew(SWindow).AutoCenter(EAutoCenter::None).ClientSize(FVector2D(360.0f, 140.0f)).CreateTitleBar(false).HasCloseButton(false)[Region.ToSharedRef()];
    Slate.AddWindow(Scope.Window.ToSharedRef(), true);
    if (!TestTrue(TEXT("Registered select loads"), View->TryReload(Markup(), TEXT(""), TEXT("UiSelect")).Succeeded)) { return false; }
    Tick(Slate);

    const TSharedPtr<SWidget> Select = FindSelect(Region.ToSharedRef());
    if (!TestTrue(TEXT("Authored select exposes the native select type"), Select.IsValid())) { return false; }
    const TSharedPtr<STextBlock> Label = FindText(Select.ToSharedRef());
    if (!TestTrue(TEXT("Native select exposes a selected-label text descendant"), Label.IsValid())) { return false; }
    TestEqual(TEXT("Initial model key resolves its option label"), Label->GetText().ToString(), FString(TEXT("Alpha")));
    TestEqual(TEXT("Initial select construction is silent"), ChangedCalls, 0);

    if (!TestTrue(TEXT("Slate focuses the production select"), Slate.SetUserFocus(0, Select, EFocusCause::SetDirectly))) { return false; }
    Tick(Slate);
    TestTrue(TEXT("Closed native select handles routed Down"), Slate.ProcessKeyDownEvent(Key(EKeys::Down)));
    Tick(Slate);
    TestTrue(TEXT("Accepted Down proposes stable key and refreshes selected label"), Value == TEXT("b") && ChangedCalls == 1 && Label->GetText().ToString() == TEXT("Beta"));

    Accept = false;
    TestTrue(TEXT("Closed native select handles routed Up"), Slate.ProcessKeyDownEvent(Key(EKeys::Up)));
    Tick(Slate);
    TestTrue(TEXT("Rejected selection restores authoritative key and visible label"), Value == TEXT("b") && ChangedCalls == 2 && Label->GetText().ToString() == TEXT("Beta"));
    Accept = true;

    Value = TEXT("a");
    Tick(Slate);
    TestEqual(TEXT("External key change updates native selected label without callback"), Label->GetText().ToString(), FString(TEXT("Alpha")));
    const int32 CallsBeforeExternalNavigation = ChangedCalls;
    TestTrue(TEXT("External key synchronization leaves the next native Down actionable"), Slate.ProcessKeyDownEvent(Key(EKeys::Down)));
    Tick(Slate);
    TestTrue(TEXT("Next Down after an external key update proposes the next stable key"), Value == TEXT("b") && ChangedCalls == CallsBeforeExternalNavigation + 1 && Label->GetText().ToString() == TEXT("Beta"));
    Value = TEXT("a");
    Tick(Slate);
    if (!TestTrue(TEXT("Same-key label update publishes"), Collection->TrySetRecords(Options(TEXT("Alpha updated"), TEXT("Beta updated"))).Succeeded)) { return false; }
    Tick(Slate);
    TestEqual(TEXT("Collection label update reaches native selected label"), Label->GetText().ToString(), FString(TEXT("Alpha updated")));
    if (!TestTrue(TEXT("Selected option removal publishes"), Collection->TrySetRecords({Record(TEXT("b"), TEXT("Beta updated"))}).Succeeded)) { return false; }
    Tick(Slate);
    TestTrue(TEXT("Removed selected key clears the displayed selection without model mutation"), Value == TEXT("a") && Label->GetText().ToString() == Placeholder && ChangedCalls == CallsBeforeExternalNavigation + 1);
    if (!TestTrue(TEXT("Options restore publishes"), Collection->TrySetRecords(Options(TEXT("Alpha updated"), TEXT("Beta updated"))).Succeeded)) { return false; }
    Tick(Slate);

    const int32 CallsBeforeDisabled = ChangedCalls;
    Enabled = false;
    Tick(Slate);
    Slate.ProcessKeyDownEvent(Key(EKeys::Down));
    Tick(Slate);
    TestTrue(TEXT("Disabled select has no callback or native/model drift"), !Select->IsEnabled() && Value == TEXT("a") && ChangedCalls == CallsBeforeDisabled && Label->GetText().ToString() == TEXT("Alpha updated"));
    Enabled = true;
    ReadOnly = true;
    Tick(Slate);
    Slate.ProcessKeyDownEvent(Key(EKeys::Down));
    Tick(Slate);
    TestTrue(TEXT("Read-only select has no callback or native/model drift"), !Select->IsEnabled() && Value == TEXT("a") && ChangedCalls == CallsBeforeDisabled && Label->GetText().ToString() == TEXT("Alpha updated"));
    ReadOnly = false;
    Tick(Slate);

    const int64 Revision = View->GetRevision();
    const FCkUiLoadResult Retarget = View->TryReload(Markup(TEXT("other")), TEXT(""), TEXT("UiSelectRetarget"));
    TestFalse(TEXT("Retargeting a retained select value binding rejects"), Retarget.Succeeded);
    TestTrue(TEXT("Retarget rejection is atomic"), View->GetRevision() == Revision && FindSelect(Region.ToSharedRef()) == Select && Slate.GetUserFocusedWidget(0) == Select);
    if (!TestTrue(TEXT("Compatible select reload succeeds"), View->TryReload(Markup(), TEXT(""), TEXT("UiSelectCompatibleReload")).Succeeded)) { return false; }
    Tick(Slate);
    TestTrue(TEXT("Compatible reload preserves native select identity and focus"), FindSelect(Region.ToSharedRef()) == Select && Slate.GetUserFocusedWidget(0) == Select);

    const FReply OpenPopup = Select->OnKeyDown(Select->GetCachedGeometry(), Key(EKeys::SpaceBar));
    Tick(Slate);
    const TSharedPtr<SMenuAnchor> Menu = StaticCastSharedPtr<SMenuAnchor>(Select);
    const TSharedPtr<SWindow> PopupWindow = Menu->GetMenuWindow();
    TestTrue(TEXT("Native select opens a popup from public keyboard input"), OpenPopup.IsEventHandled() && Menu->IsOpen());
    TestTrue(TEXT("Open popup renders both collection option labels"), PopupWindow.IsValid()
        && ContainsText(PopupWindow.ToSharedRef(), TEXT("Alpha updated"))
        && ContainsText(PopupWindow.ToSharedRef(), TEXT("Beta updated")));
    const int64 OpenRevision = View->GetRevision();
    TestTrue(TEXT("Open select popup accepts compatible retained reload"), View->TryReload(Markup(), TEXT(""), TEXT("UiSelectOpenReload")).Succeeded);
    Tick(Slate);
    TestTrue(TEXT("Compatible reload preserves the open popup and published select"), View->GetRevision() == OpenRevision + 1
        && FindSelect(Region.ToSharedRef()) == Select && Menu->IsOpen() && Menu->GetMenuWindow() == PopupWindow);
    Select->OnKeyDown(Select->GetCachedGeometry(), Key(EKeys::SpaceBar));
    Tick(Slate);
    Slate.SetUserFocus(0, Select, EFocusCause::SetDirectly);

    const int32 CallsBeforeRelease = ChangedCalls;
    Slate.DestroyWindowImmediately(Scope.Window.ToSharedRef());
    Scope.Window.Reset();
    Region.Reset();
    const TSharedPtr<SWidget> HeldSelect = Select;
    View.Reset();
    const FReply ReleasedKey = HeldSelect->OnKeyDown(HeldSelect->GetCachedGeometry(), Key(EKeys::Down));
    TestFalse(TEXT("Held released native select rejects input after view release"), ReleasedKey.IsEventHandled());
    TestEqual(TEXT("Held released select leaves consumer callback inert"), ChangedCalls, CallsBeforeRelease);
    return true;
}
#endif // WITH_DEV_AUTOMATION_TESTS
