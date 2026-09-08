#include "CkSlateLayout/CkUiCollection.h"
#include "CkSlateLayout/CkUiSelect.h"
#include "CkSlateLayout/SCkUiSurface.h"

#include "Framework/Application/SlateApplication.h"
#include "Input/Events.h"
#include "InputCoreTypes.h"
#include "Layout/Children.h"
#include "Misc/AutomationTest.h"
#include "Styling/CoreStyle.h"
#include "Widgets/SWindow.h"
#include "Widgets/Text/STextBlock.h"

#if WITH_DEV_AUTOMATION_TESTS
namespace ck_tests_ui_select_reentry
{
    auto Markup(const bool InIncludeSelect = true) -> FString
    {
        return InIncludeSelect
            ? TEXT("<ui version=\"1\"><region name=\"main\"><column id=\"root\"><select id=\"select\" value-bind=\"value\" options-bind=\"options\" changed=\"changed\"/></column></region></ui>")
            : TEXT("<ui version=\"1\"><region name=\"main\"><column id=\"root\"/></region></ui>");
    }

    auto Record(const TCHAR* InKey, const TCHAR* InLabel) -> FCkUiRecordData
    {
        auto Result = FCkUiRecordData{};
        Result.Key = InKey;
        Result.Fields.Add(TEXT("label"), FCkUiFieldValue{.Kind = ECkUiFieldKind::Text, .Text = FText::FromString(InLabel)});
        return Result;
    }

    auto Options(const TCHAR* InAlpha = TEXT("Alpha"), const TCHAR* InBeta = TEXT("Beta")) -> TArray<FCkUiRecordData>
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

    auto Tick(FSlateApplication& InSlate) -> void
    {
        InSlate.PumpMessages();
        InSlate.Tick();
        InSlate.Tick();
    }

    auto Key(const FKey InKey) -> FKeyEvent { return FKeyEvent(InKey, FModifierKeysState{}, 0, false, 0, 0); }

    struct FWindowScope final
    {
        explicit FWindowScope(FSlateApplication& InSlate) : Slate(InSlate) {}
        ~FWindowScope() { if (Window.IsValid()) { Slate.DestroyWindowImmediately(Window.ToSharedRef()); } }

        FSlateApplication& Slate;
        TSharedPtr<SWindow> Window;
    };

    struct FFixture final
    {
        explicit FFixture(FSlateApplication& InSlate) : Slate(InSlate), Scope(InSlate) {}

        auto Load() -> bool
        {
            FCkUiWidgetRegistry Registry;
            if (!FCkUiSelect::Register(Registry).Succeeded
                || !FCkUiCollection::TryCreate({{TEXT("label"), ECkUiFieldKind::Text}}, Collection).Succeeded
                || !Collection->TrySetRecords(Options()).Succeeded) { return false; }

            FCkUiView::FDataBindings Data;
            Data.String.Add(TEXT("value"), TAttribute<FString>::CreateLambda([this] { return Value; }));
            Data.Collections.Add(TEXT("options"), Collection);
            Data.StringChanged.Add(TEXT("changed"), FCkUiOnStringChanged::CreateLambda([this](const FString& InKey)
            {
                ++ChangedCalls;
                LastKey = InKey;
                if (OnChanged) { OnChanged(InKey); }
                else { Value = InKey; }
            }));
            View = FCkUiView::Create({}, {}, {}, FCoreStyle::GetDefaultFontStyle(TEXT("Regular"), 12), MoveTemp(Data), Registry.CreateSnapshot());
            Region = View->GetRegion(TEXT("main"));
            Scope.Window = SNew(SWindow).AutoCenter(EAutoCenter::None).ClientSize(FVector2D(360.0f, 140.0f)).CreateTitleBar(false).HasCloseButton(false)[Region.ToSharedRef()];
            Slate.AddWindow(Scope.Window.ToSharedRef(), true);
            if (!View->TryReload(Markup(), TEXT(""), TEXT("UiSelectReentryInitial")).Succeeded) { return false; }
            Tick(Slate);
            Select = FindSelect(Region.ToSharedRef());
            if (!Select.IsValid()) { return false; }
            Slate.SetUserFocus(0, Select, EFocusCause::SetDirectly);
            return Slate.GetUserFocusedWidget(0) == Select;
        }

        FSlateApplication& Slate;
        FString Value = TEXT("a");
        FString LastKey;
        int32 ChangedCalls = 0;
        TFunction<void(const FString&)> OnChanged;
        TSharedPtr<FCkUiCollection> Collection;
        TSharedPtr<FCkUiView> View;
        TSharedPtr<SWidget> Region;
        TSharedPtr<SWidget> Select;
        FWindowScope Scope;
    };
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiSelectReentry_Reload,
    "Ck.UiAuthoring.Select.CallbackReentryReloadReconciles",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiSelectReentry_Reload::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_select_reentry;
    if (!FSlateApplication::IsInitialized()) { AddError(TEXT("Select callback reentry test requires Slate.")); return false; }

    FFixture Fixture(FSlateApplication::Get());
    if (!TestTrue(TEXT("Reload reentry fixture loads a mounted native select"), Fixture.Load())) { return false; }
    const TSharedPtr<SWidget> HeldSelect = Fixture.Select;
    const TSharedPtr<STextBlock> Label = FindText(HeldSelect.ToSharedRef());
    if (!TestTrue(TEXT("Mounted native select exposes its selected label"), Label.IsValid())) { return false; }

    bool ReloadSucceeded = false;
    bool OptionsSucceeded = false;
    const int64 RevisionBeforeCallback = Fixture.View->GetRevision();
    Fixture.OnChanged = [&Fixture, &ReloadSucceeded, &OptionsSucceeded](const FString&)
    {
        ReloadSucceeded = Fixture.View->TryReload(Markup(), TEXT(""), TEXT("UiSelectCallbackReload")).Succeeded;
        Fixture.Value = TEXT("a");
        OptionsSucceeded = Fixture.Collection->TrySetRecords(Options(TEXT("Alpha authoritative"), TEXT("Beta authoritative"))).Succeeded;
    };

    TestTrue(TEXT("Slate routes native Down into the mounted select callback"), Fixture.Slate.ProcessKeyDownEvent(Key(EKeys::Down)));
    TestTrue(TEXT("Callback reconciles the changed label before a later tick"), Label->GetText().ToString() == TEXT("Alpha authoritative"));
    Tick(Fixture.Slate);
    TestTrue(TEXT("Callback-compatible reload and authoritative options publish"), ReloadSucceeded && OptionsSucceeded);
    TestTrue(TEXT("Callback reload advances the view once and retains native select identity"), Fixture.View->GetRevision() == RevisionBeforeCallback + 1
        && FindSelect(Fixture.Region.ToSharedRef()) == HeldSelect);
    TestTrue(TEXT("Exactly one native callback reconciles the authoritative model and option label"), Fixture.ChangedCalls == 1
        && Fixture.LastKey == TEXT("b") && Fixture.Value == TEXT("a") && Label->GetText().ToString() == TEXT("Alpha authoritative"));
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiSelectReentry_Teardown,
    "Ck.UiAuthoring.Select.CallbackReentryTeardownRejectsHeldInput",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiSelectReentry_Teardown::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_select_reentry;
    if (!FSlateApplication::IsInitialized()) { AddError(TEXT("Select callback reentry test requires Slate.")); return false; }

    {
        FFixture Fixture(FSlateApplication::Get());
        if (!TestTrue(TEXT("Removal reentry fixture loads a mounted native select"), Fixture.Load())) { return false; }
        const TSharedPtr<SWidget> HeldSelect = Fixture.Select;
        bool RemovalSucceeded = false;
        Fixture.OnChanged = [&Fixture, &RemovalSucceeded](const FString&)
        {
            RemovalSucceeded = Fixture.View->TryReload(Markup(false), TEXT(""), TEXT("UiSelectCallbackRemoval")).Succeeded;
        };

        TestTrue(TEXT("Slate routes native Down that removes its select during callback"), Fixture.Slate.ProcessKeyDownEvent(Key(EKeys::Down)));
        Tick(Fixture.Slate);
        TestTrue(TEXT("Callback removal commits and detaches the authored select"), RemovalSucceeded && !FindSelect(Fixture.Region.ToSharedRef()).IsValid());
        TestTrue(TEXT("Removal callback dispatches exactly once with the selected stable key"), Fixture.ChangedCalls == 1 && Fixture.LastKey == TEXT("b"));
        const FReply HeldInput = HeldSelect->OnKeyDown(HeldSelect->GetCachedGeometry(), Key(EKeys::Down));
        TestFalse(TEXT("Held removed native select rejects subsequent input"), HeldInput.IsEventHandled());
        TestEqual(TEXT("Held removed select cannot reenter its callback"), Fixture.ChangedCalls, 1);
    }

    {
        FFixture Fixture(FSlateApplication::Get());
        if (!TestTrue(TEXT("View-release reentry fixture loads a mounted native select"), Fixture.Load())) { return false; }
        const TSharedPtr<SWidget> HeldSelect = Fixture.Select;
        const TWeakPtr<FCkUiView> WeakView = Fixture.View;
        Fixture.OnChanged = [&Fixture](const FString&)
        {
            Fixture.View.Reset();
        };

        TestTrue(TEXT("Slate routes native Down that releases its owning view during callback"), Fixture.Slate.ProcessKeyDownEvent(Key(EKeys::Down)));
        Tick(Fixture.Slate);
        TestTrue(TEXT("Callback releases the view after one selected stable-key dispatch"), !Fixture.View.IsValid() && !WeakView.IsValid()
            && Fixture.ChangedCalls == 1 && Fixture.LastKey == TEXT("b"));
        const FReply HeldInput = HeldSelect->OnKeyDown(HeldSelect->GetCachedGeometry(), Key(EKeys::Down));
        TestFalse(TEXT("Held native select safely rejects input after callback view release"), HeldInput.IsEventHandled());
        TestEqual(TEXT("Held select remains callback-inert after its view is released"), Fixture.ChangedCalls, 1);
    }
    return true;
}
#endif // WITH_DEV_AUTOMATION_TESTS
