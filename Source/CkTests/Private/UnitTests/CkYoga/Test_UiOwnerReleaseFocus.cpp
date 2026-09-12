#include "CkSlateLayout/CkUiWidgetRegistry.h"
#include "CkSlateLayout/SCkUiSurface.h"

#include "Framework/Application/SlateApplication.h"
#include "Framework/Application/SlateUser.h"
#include "Layout/Children.h"
#include "Layout/WidgetPath.h"
#include "Misc/AutomationTest.h"
#include "Styling/CoreStyle.h"
#include "Widgets/Input/SButton.h"
#include "Widgets/Input/SSearchBox.h"
#include "Widgets/SOverlay.h"
#include "Widgets/SWindow.h"
#include "Widgets/Text/STextBlock.h"

#if WITH_DEV_AUTOMATION_TESTS

namespace ck_tests_ui_owner_release_focus
{
    class FPreparedUpdate final : public ICkUiPreparedWidgetUpdate
    {
    public:
        virtual void Commit() noexcept override {}
    };

    struct FRedirectStats final
    {
        int32 Owner = INDEX_NONE;
        int32 ReleaseCalls = 0;
    };

    class FFocusRedirect final : public ICkUiRetainedWidget
    {
    public:
        FFocusRedirect(const TSharedRef<FRedirectStats>& InStats, const int32 InOwner, const TSharedRef<SWidget>& InTarget)
            : Stats(InStats), Owner(InOwner), Target(InTarget), Widget(SNew(STextBlock).Text(FText::FromString(TEXT("Focus redirect")))) {}

        virtual auto GetWidget() const -> TSharedRef<SWidget> override { return Widget.ToSharedRef(); }
        virtual auto PrepareReload(const FCkUiCustomWidgetArguments&, FString&) const -> TUniquePtr<ICkUiPreparedWidgetUpdate> override
        { return MakeUnique<FPreparedUpdate>(); }
        virtual void ReleaseTransientInteraction() override
        {
            ++Stats->ReleaseCalls;
            if (!FSlateApplication::IsInitialized() || Owner < 0) { return; }
            if (const TSharedPtr<SWidget> RedirectTarget = Target.Pin())
            { FSlateApplication::Get().SetUserFocus(Owner, RedirectTarget.ToSharedRef(), EFocusCause::SetDirectly); }
        }

    private:
        TSharedRef<FRedirectStats> Stats;
        int32 Owner = INDEX_NONE;
        TWeakPtr<SWidget> Target;
        TSharedPtr<SWidget> Widget;
    };

    struct FWindowScope final
    {
        FWindowScope(FSlateApplication& InSlate, const int32 InOwner, const int32 InForeign)
            : Slate(InSlate), Owner(InOwner), Foreign(InForeign) {}
        ~FWindowScope()
        {
            Slate.ClearUserFocus(Owner, EFocusCause::SetDirectly);
            Slate.ClearUserFocus(Foreign, EFocusCause::SetDirectly);
            if (Window.IsValid()) { Slate.DestroyWindowImmediately(Window.ToSharedRef()); }
        }

        FSlateApplication& Slate;
        int32 Owner = INDEX_NONE;
        int32 Foreign = INDEX_NONE;
        TSharedPtr<SWindow> Window;
    };

    auto Tick(FSlateApplication& InSlate) -> void
    {
        InSlate.PumpMessages();
        InSlate.Tick();
        InSlate.Tick();
    }

    auto FindSearch(const TSharedRef<SWidget>& InRoot) -> TSharedPtr<SSearchBox>
    {
        if (InRoot->GetTag() == TEXT("search") && InRoot->GetTypeAsString() == TEXT("SSearchBox"))
        { return StaticCastSharedRef<SSearchBox>(InRoot); }
        const FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<SSearchBox> Found = FindSearch(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index))); Found.IsValid()) { return Found; }
        }
        return {};
    }

    auto Markup(const bool InIncludeRedirect) -> FString
    {
        const TCHAR* Redirect = InIncludeRedirect ? TEXT("<focus-redirect id=\"redirect\" state=\"stable\"/>") : TEXT("");
        return FString::Printf(TEXT("<ui version=\"1\"><region name=\"main\"><column id=\"root\"><search id=\"search\" bind=\"query\"/>%s</column></region></ui>"), Redirect);
    }

    auto DataForOwner(FString& InOutQuery) -> FCkUiView::FDataBindings
    {
        FCkUiView::FDataBindings Data;
        Data.SlateUserIndex = 0;
        Data.Text.Add(TEXT("query"), TAttribute<FText>::CreateLambda([&InOutQuery]() { return FText::FromString(InOutQuery); }));
        Data.TextChanged.Add(TEXT("query"), FOnTextChanged::CreateLambda([&InOutQuery](const FText& InValue) { InOutQuery = InValue.ToString(); }));
        return Data;
    }

    auto RegisterFocusRedirect(const TSharedRef<FRedirectStats>& InStats, const TSharedRef<SWidget>& InTarget,
        FCkUiWidgetRegistry& InRegistry) -> bool
    {
        FCkUiCustomWidgetRegistration Registration;
        Registration.Schema.Tag = TEXT("focus-redirect");
        Registration.Schema.Properties = {{TEXT("state"), ECkUiCustomPropertyKind::Text, true}};
        Registration.Schema.StateKeyProperty = TEXT("state");
        Registration.RetainedFactory = [InStats, WeakTarget = TWeakPtr<SWidget>(InTarget)](const FCkUiCustomWidgetArguments& InArguments, FString&) -> TSharedPtr<ICkUiRetainedWidget>
        {
            InStats->Owner = InArguments.SlateUserIndex;
            const TSharedPtr<SWidget> Target = WeakTarget.Pin();
            if (!Target.IsValid()) { return nullptr; }
            return MakeShared<FFocusRedirect>(InStats, InArguments.SlateUserIndex, Target.ToSharedRef());
        };
        return InRegistry.Register(MoveTemp(Registration)).Succeeded;
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiOwnerReleaseFocus,
    "Ck.UiAuthoring.OwnerRelease.Focus",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiOwnerReleaseFocus::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_owner_release_focus;
    if (!FSlateApplication::IsInitialized()) { AddError(TEXT("Owner release focus test requires Slate.")); return false; }

    FSlateApplication& Slate = FSlateApplication::Get();
    constexpr int32 Owner = 0;
    const TSharedRef<FSlateVirtualUserHandle> VirtualUser = Slate.FindOrCreateVirtualUser(219);
    const int32 Foreign = VirtualUser->GetUserIndex();

    {
        FString Query;
        TSharedPtr<FCkUiView> View = FCkUiView::Create({}, {}, {}, FCoreStyle::GetDefaultFontStyle(TEXT("Regular"), 12), DataForOwner(Query));
        FWindowScope Scope{Slate, Owner, Foreign};
        const TSharedRef<SButton> External = SNew(SButton).IsFocusable(true);
        const TSharedRef<SWidget> HeldRoot = View->GetRegion(TEXT("main"));
        Scope.Window = SNew(SWindow).AutoCenter(EAutoCenter::None).ClientSize(FVector2D{480.0f, 240.0f}).CreateTitleBar(false).HasCloseButton(false)
            [SNew(SOverlay) + SOverlay::Slot()[HeldRoot] + SOverlay::Slot().HAlign(HAlign_Right).VAlign(VAlign_Bottom)[External]];
        Slate.AddWindow(Scope.Window.ToSharedRef(), true);
        if (!TestTrue(TEXT("Mounted search view loads"), View->TryReload(Markup(false), TEXT(""), TEXT("OwnerReleaseFocusClear")).Succeeded)) { return false; }
        Tick(Slate);
        const TSharedPtr<SSearchBox> Search = FindSearch(HeldRoot);
        if (!TestTrue(TEXT("Mounted authored search resolves"), Search.IsValid())) { return false; }
        Slate.SetUserFocus(Owner, Search.ToSharedRef(), EFocusCause::SetDirectly);
        if (!TestTrue(TEXT("Owner focuses mounted search"), Slate.GetUserFocusedWidget(Owner) == Search || Slate.HasUserFocusedDescendants(Search.ToSharedRef(), Owner))) { return false; }
        if (!TestTrue(TEXT("Foreign user focuses outside control"), Slate.SetUserFocus(Foreign, External, EFocusCause::SetDirectly))) { return false; }
        FWidgetPath SearchPath;
        if (!TestTrue(TEXT("Held root contains the focused search path"), Slate.GeneratePathToWidgetUnchecked(Search.ToSharedRef(), SearchPath))) { return false; }

        View.Reset();
        TestFalse(TEXT("Releasing the view clears only the owner focus inside its held root"), Slate.GetUserFocusedWidget(Owner).IsValid());
        TestTrue(TEXT("Releasing the view preserves foreign focus outside its held root"), Slate.GetUserFocusedWidget(Foreign) == External);
    }

    {
        FString Query;
        const TSharedRef<SButton> External = SNew(SButton).IsFocusable(true);
        const TSharedRef<FRedirectStats> RedirectStats = MakeShared<FRedirectStats>();
        FCkUiWidgetRegistry Registry;
        if (!TestTrue(TEXT("Focus redirect retained-widget registration succeeds"), RegisterFocusRedirect(RedirectStats, External, Registry))) { return false; }
        TSharedPtr<FCkUiView> View = FCkUiView::Create({}, {}, {}, FCoreStyle::GetDefaultFontStyle(TEXT("Regular"), 12), DataForOwner(Query), Registry.CreateSnapshot());
        FWindowScope Scope{Slate, Owner, Foreign};
        const TSharedRef<SWidget> HeldRoot = View->GetRegion(TEXT("main"));
        Scope.Window = SNew(SWindow).AutoCenter(EAutoCenter::None).ClientSize(FVector2D{480.0f, 240.0f}).CreateTitleBar(false).HasCloseButton(false)
            [SNew(SOverlay) + SOverlay::Slot()[HeldRoot] + SOverlay::Slot().HAlign(HAlign_Right).VAlign(VAlign_Bottom)[External]];
        Slate.AddWindow(Scope.Window.ToSharedRef(), true);
        if (!TestTrue(TEXT("Mounted redirect search view loads"), View->TryReload(Markup(true), TEXT(""), TEXT("OwnerReleaseFocusRedirect")).Succeeded)) { return false; }
        Tick(Slate);
        const TSharedPtr<SSearchBox> Search = FindSearch(HeldRoot);
        if (!TestTrue(TEXT("Redirect case resolves mounted authored search"), Search.IsValid())) { return false; }
        Slate.SetUserFocus(Owner, Search.ToSharedRef(), EFocusCause::SetDirectly);
        if (!TestTrue(TEXT("Owner focuses search before retained release callback"), Slate.GetUserFocusedWidget(Owner) == Search || Slate.HasUserFocusedDescendants(Search.ToSharedRef(), Owner))) { return false; }

        View.Reset();
        TestTrue(TEXT("Retained release callback receives the explicit owner"), RedirectStats->Owner == Owner && RedirectStats->ReleaseCalls == 1);
        TestTrue(TEXT("Retained release redirect preserves owner focus outside the released root"), Slate.GetUserFocusedWidget(Owner) == External);
    }
    return true;
}

#endif
