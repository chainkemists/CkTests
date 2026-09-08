#include "CkSlateLayout/CkUiWidgetRegistry.h"
#include "CkSlateLayout/SCkUiSurface.h"

#include "Framework/Application/SlateApplication.h"
#include "Framework/Application/SlateUser.h"
#include "Layout/Children.h"
#include "Layout/WidgetPath.h"
#include "Misc/AutomationTest.h"
#include "Widgets/Input/SButton.h"
#include "Widgets/Layout/SBox.h"
#include "Widgets/SOverlay.h"
#include "Widgets/SWindow.h"

#if WITH_DEV_AUTOMATION_TESTS
namespace ck_tests_ui_multi_user_focus
{
    class FPreparedUpdate final : public ICkUiPreparedWidgetUpdate
    {
    public:
        virtual void Commit() noexcept override {}
    };

    class FFocusComponent final : public ICkUiRetainedWidget
    {
    public:
        FFocusComponent() : _Widget(SNew(SButton).IsFocusable(true)) {}
        virtual auto GetWidget() const -> TSharedRef<SWidget> override { return _Widget.ToSharedRef(); }
        virtual auto PrepareReload(const FCkUiCustomWidgetArguments&, FString&) const -> TUniquePtr<ICkUiPreparedWidgetUpdate> override
        { return MakeUnique<FPreparedUpdate>(); }
        auto GetButton() const -> TSharedRef<SButton> { return _Widget.ToSharedRef(); }

    private:
        TSharedPtr<SButton> _Widget;
    };

    struct FWindowScope final
    {
        explicit FWindowScope(FSlateApplication& InSlate) : Slate(InSlate) {}
        ~FWindowScope() { if (Window.IsValid()) { Slate.DestroyWindowImmediately(Window.ToSharedRef()); } }
        FSlateApplication& Slate;
        TSharedPtr<SWindow> Window;
    };

    auto Tick(FSlateApplication& InSlate) -> void { InSlate.PumpMessages(); InSlate.Tick(); InSlate.Tick(); }

    auto RetainedMarkup() -> FString
    { return TEXT("<ui version=\"1\"><region name=\"main\"><column id=\"root\"><focus id=\"retained\" state=\"stable\"/></column></region></ui>"); }

    auto StatelessMarkup() -> FString
    { return TEXT("<ui version=\"1\"><region name=\"main\"><column id=\"root\"><button id=\"stateless\" action=\"noop\">Stateless</button></column></region></ui>"); }

    auto FindTaggedWidget(const TSharedRef<SWidget>& InRoot, const FName InTag) -> TSharedPtr<SWidget>
    {
        if (InRoot->GetTag() == InTag) { return InRoot; }
        const FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<SWidget> Found = FindTaggedWidget(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InTag)) { return Found; }
        }
        return {};
    }

    auto RegisterFocus(TSharedPtr<FFocusComponent>& OutComponent, bool& OutRegistered) -> TSharedPtr<const FCkUiWidgetRegistrySnapshot>
    {
        auto Registry = FCkUiWidgetRegistry{};
        auto Registration = FCkUiCustomWidgetRegistration{};
        Registration.Schema.Tag = TEXT("focus");
        Registration.Schema.Properties = {{TEXT("state"), ECkUiCustomPropertyKind::Text, true}};
        Registration.Schema.StateKeyProperty = TEXT("state");
        Registration.RetainedFactory = [&OutComponent](const FCkUiCustomWidgetArguments&, FString&) -> TSharedPtr<ICkUiRetainedWidget>
        {
            OutComponent = MakeShared<FFocusComponent>();
            return OutComponent;
        };
        OutRegistered = Registry.Register(MoveTemp(Registration)).Succeeded;
        return Registry.CreateSnapshot();
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiMultiUserFocus, "Ck.UiAuthoring.MultiUserFocus", EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiMultiUserFocus::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_multi_user_focus;
    if (!FSlateApplication::IsInitialized()) { AddError(TEXT("Multi-user focus test requires Slate.")); return false; }

    FSlateApplication& Slate = FSlateApplication::Get();
    TSharedPtr<FFocusComponent> Component;
    bool Registered = false;
    FCkUiView::FActions Actions;
    Actions.Add(TEXT("noop"), FSimpleDelegate::CreateLambda([] {}));
    const TSharedRef<FCkUiView> View = FCkUiView::Create({}, MoveTemp(Actions), {}, {}, {}, RegisterFocus(Component, Registered));
    if (!TestTrue(TEXT("Focus component registration succeeds"), Registered)) { return false; }
    FWindowScope Scope(Slate);
    const TSharedRef<SButton> External = SNew(SButton).IsFocusable(true);
    Scope.Window = SNew(SWindow).AutoCenter(EAutoCenter::None).ClientSize(FVector2D(360.0f, 180.0f)).CreateTitleBar(false)
    [SNew(SOverlay) + SOverlay::Slot()[View->GetRegion(TEXT("main"))] + SOverlay::Slot().HAlign(HAlign_Right).VAlign(VAlign_Bottom)[External]];
    Slate.AddWindow(Scope.Window.ToSharedRef(), true);
    if (!TestTrue(TEXT("Initial retained focus document loads"), View->TryReload(RetainedMarkup(), TEXT(""), TEXT("MultiUserFocusInitial")).Succeeded)) { return false; }
    Tick(Slate);
    if (!TestTrue(TEXT("Retained focus component exists"), Component.IsValid())) { return false; }

    const TSharedRef<SButton> Retained = Component->GetButton();
    const TSharedRef<FSlateVirtualUserHandle> VirtualUser = Slate.FindOrCreateVirtualUser(127);
    const int32 VirtualUserIndex = VirtualUser->GetUserIndex();
    TestTrue(TEXT("User zero focuses retained descendant"), Slate.SetUserFocus(0, Retained, EFocusCause::SetDirectly));
    TestTrue(TEXT("Virtual user focuses retained descendant"), Slate.SetUserFocus(VirtualUserIndex, Retained, EFocusCause::SetDirectly));
    FWidgetPath PreviousMountedPath;
    if (!TestTrue(TEXT("Retained focus has a mounted pre-reload path"), Slate.GeneratePathToWidgetUnchecked(Retained, PreviousMountedPath))) { return false; }
    if (!TestTrue(TEXT("Compatible retained reload succeeds"), View->TryReload(RetainedMarkup(), TEXT(""), TEXT("MultiUserFocusCompatible")).Succeeded)) { return false; }
    FWidgetPath CurrentMountedPath;
    if (!TestTrue(TEXT("Retained focus has a current mounted path"), Slate.GeneratePathToWidgetUnchecked(Retained, CurrentMountedPath))) { return false; }
    const TArray<int32> FocusedUsers = {0, VirtualUserIndex};
    for (const int32 UserIndex : FocusedUsers)
    {
        const TSharedPtr<FSlateUser> User = Slate.GetUser(UserIndex);
        if (!TestTrue(TEXT("Focused Slate user remains available after reload"), User.IsValid())) { return false; }
        TestTrue(TEXT("Compatible reload restores the retained focus leaf"), Slate.GetUserFocusedWidget(UserIndex) == Retained);
        for (int32 CurrentIndex = 0; CurrentIndex < CurrentMountedPath.Widgets.Num(); ++CurrentIndex)
        {
            TestTrue(TEXT("Every current mounted ancestor belongs to each user's focus path"), User->IsWidgetInFocusPath(CurrentMountedPath.Widgets[CurrentIndex].Widget));
        }
        for (int32 PreviousIndex = 0; PreviousIndex < PreviousMountedPath.Widgets.Num(); ++PreviousIndex)
        {
            const TSharedRef<SWidget> Previous = PreviousMountedPath.Widgets[PreviousIndex].Widget;
            bool StillMounted = false;
            for (int32 CurrentIndex = 0; CurrentIndex < CurrentMountedPath.Widgets.Num(); ++CurrentIndex)
            {
                StillMounted |= CurrentMountedPath.Widgets[CurrentIndex].Widget == Previous;
            }
            if (!StillMounted)
            {
                TestFalse(TEXT("Detached pre-reload ancestor is absent from each user's focus path"), User->IsWidgetInFocusPath(Previous));
            }
        }
    }

    if (!TestTrue(TEXT("Stateless replacement reload succeeds"), View->TryReload(StatelessMarkup(), TEXT(""), TEXT("MultiUserFocusStateless")).Succeeded)) { return false; }
    TestFalse(TEXT("Removed retained focus clears virtual user"), Slate.GetUserFocusedWidget(VirtualUserIndex).IsValid());
    const TSharedPtr<SWidget> Stateless = FindTaggedWidget(View->GetRegion(TEXT("main")), TEXT("stateless"));
    if (!TestTrue(TEXT("Stateless authored button is mounted"), Stateless.IsValid())) { return false; }
    TestTrue(TEXT("Virtual user focuses stateless authored button"), Slate.SetUserFocus(VirtualUserIndex, Stateless, EFocusCause::SetDirectly));
    if (!TestTrue(TEXT("Stateless reload succeeds"), View->TryReload(StatelessMarkup(), TEXT(""), TEXT("MultiUserFocusStatelessReload")).Succeeded)) { return false; }
    TestFalse(TEXT("Stateless authored focus clears on reload"), Slate.GetUserFocusedWidget(VirtualUserIndex).IsValid());

    TestTrue(TEXT("User zero focuses an external sibling"), Slate.SetUserFocus(0, External, EFocusCause::SetDirectly));
    if (!TestTrue(TEXT("Reload with external focus succeeds"), View->TryReload(StatelessMarkup(), TEXT(""), TEXT("MultiUserFocusExternal")).Succeeded)) { return false; }
    TestTrue(TEXT("External user-zero focus remains untouched"), Slate.GetUserFocusedWidget(0) == External);
    Slate.ClearUserFocus(0, EFocusCause::SetDirectly);
    Slate.ClearUserFocus(VirtualUserIndex, EFocusCause::SetDirectly);
    return true;
}
#endif
