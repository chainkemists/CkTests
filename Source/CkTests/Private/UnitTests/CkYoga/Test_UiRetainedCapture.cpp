#include "CkSlateLayout/CkUiWidgetRegistry.h"
#include "CkSlateLayout/SCkUiSurface.h"
#include "CkSlateLayout/CkUiCollection.h"
#include "CkSlateLayout/SCkUiRepeat.h"

#include "Framework/Application/SlateApplication.h"
#include "Framework/Application/SlateUser.h"
#include "Input/Events.h"
#include "InputCoreTypes.h"
#include "Layout/WidgetPath.h"
#include "Misc/AutomationTest.h"
#include "Misc/ScopeExit.h"
#include "Widgets/Layout/SBox.h"
#include "Widgets/SCompoundWidget.h"
#include "Widgets/SNullWidget.h"
#include "Widgets/SOverlay.h"
#include "Widgets/SWindow.h"

#if WITH_DEV_AUTOMATION_TESTS

namespace ck_tests_ui_retained_capture
{
    struct FPointerKey
    {
        int32 UserIndex = INDEX_NONE;
        uint32 PointerIndex = 0;

        friend bool operator==(const FPointerKey& InLeft, const FPointerKey& InRight)
        { return InLeft.UserIndex == InRight.UserIndex && InLeft.PointerIndex == InRight.PointerIndex; }
    };

    struct FFixtureStats final
    {
        int32 SyntheticCaptureLosses = 0;
        int32 CancelledCaptures = 0;
        int32 ConsumerCallbacks = 0;
        int32 Draft = 0;
        bool bReportStalePointer = false;
        TArray<FCkUiPointerCapture> AdditionalReports;
        TFunction<void()> OnCaptureLost;
    };

    class SCaptureWidget final : public SCompoundWidget
    {
    public:
        SLATE_BEGIN_ARGS(SCaptureWidget) {}
            SLATE_ARGUMENT(TSharedPtr<FFixtureStats>, Stats)
            SLATE_ATTRIBUTE(bool, CanDispatchEvents)
        SLATE_END_ARGS()

        void Construct(const FArguments& InArgs)
        {
            _Stats = InArgs._Stats;
            _CanDispatchEvents = InArgs._CanDispatchEvents;
            ChildSlot[SNullWidget::NullWidget];
        }

        virtual FReply OnMouseButtonDown(const FGeometry&, const FPointerEvent& InEvent) override
        {
            Begin(InEvent);
            return FReply::Handled().CaptureMouse(SharedThis(this));
        }

        virtual FReply OnTouchStarted(const FGeometry&, const FPointerEvent& InEvent) override
        {
            Begin(InEvent);
            return FReply::Handled().CaptureMouse(SharedThis(this));
        }

        virtual void OnMouseCaptureLost(const FCaptureLostEvent& InEvent) override
        {
            if (_Stats->OnCaptureLost) { _Stats->OnCaptureLost(); }
            const FPointerKey Key{InEvent.UserIndex, static_cast<uint32>(InEvent.PointerIndex)};
            if (_TransferKeys.Remove(Key) > 0)
            {
                ++_Stats->SyntheticCaptureLosses;
                return;
            }
            if (_ActiveKeys.Remove(Key) > 0)
            {
                ++_Stats->CancelledCaptures;
                if (_CanDispatchEvents.Get(false)) { ++_Stats->ConsumerCallbacks; }
            }
        }

        auto GetCaptures() const -> TArray<FCkUiPointerCapture>
        {
            auto Result = TArray<FCkUiPointerCapture>{};
            for (const FPointerKey& Key : _ActiveKeys)
            { Result.Add({Key.UserIndex, Key.PointerIndex, ConstCastSharedRef<SWidget>(AsShared())}); }
            if (_Stats->bReportStalePointer)
            { Result.Add({0, 29, ConstCastSharedRef<SWidget>(AsShared())}); }
            Result.Append(_Stats->AdditionalReports);
            return Result;
        }

        void BeginTransfer(const FCkUiPointerCapture& InCapture) noexcept
        {
            _TransferKeys.Add({InCapture.UserIndex, InCapture.PointerIndex});
        }

        void EndTransfer(const FCkUiPointerCapture& InCapture, const bool bRestored) noexcept
        {
            const FPointerKey Key{InCapture.UserIndex, InCapture.PointerIndex};
            _TransferKeys.Remove(Key);
            if (!bRestored && _ActiveKeys.Remove(Key) > 0) { ++_Stats->CancelledCaptures; }
        }

    private:
        void Begin(const FPointerEvent& InEvent)
        {
            _ActiveKeys.Add({static_cast<int32>(InEvent.GetUserIndex()), InEvent.GetPointerIndex()});
            ++_Stats->Draft;
        }

        TSharedPtr<FFixtureStats> _Stats;
        TAttribute<bool> _CanDispatchEvents;
        TArray<FPointerKey> _ActiveKeys;
        TArray<FPointerKey> _TransferKeys;
    };

    class FPreparedUpdate final : public ICkUiPreparedWidgetUpdate
    {
    public:
        virtual void Commit() noexcept override {}
    };

    class FCaptureComponent final : public ICkUiRetainedWidget
    {
    public:
        FCaptureComponent(const TSharedRef<FFixtureStats>& InStats, TAttribute<bool> InCanDispatchEvents)
            : _Stats(InStats), _Widget(SNew(SCaptureWidget).Stats(InStats).CanDispatchEvents(MoveTemp(InCanDispatchEvents))) {}

        virtual auto GetWidget() const -> TSharedRef<SWidget> override { return _Widget.ToSharedRef(); }
        virtual auto GetPointerCaptures() const -> TArray<FCkUiPointerCapture> override { return _Widget->GetCaptures(); }
        virtual void BeginPointerCaptureTransfer(const FCkUiPointerCapture& InCapture) noexcept override { _Widget->BeginTransfer(InCapture); }
        virtual void EndPointerCaptureTransfer(const FCkUiPointerCapture& InCapture, bool bRestored) noexcept override { _Widget->EndTransfer(InCapture, bRestored); }
        virtual auto PrepareReload(const FCkUiCustomWidgetArguments&, FString&) const -> TUniquePtr<ICkUiPreparedWidgetUpdate> override
        { return MakeUnique<FPreparedUpdate>(); }

        auto GetCaptureWidget() const -> TSharedRef<SCaptureWidget> { return _Widget.ToSharedRef(); }

    private:
        TSharedRef<FFixtureStats> _Stats;
        TSharedPtr<SCaptureWidget> _Widget;
    };

    struct FWindowScope final
    {
        explicit FWindowScope(FSlateApplication& InSlate) : Slate(InSlate) {}
        ~FWindowScope() { if (Window.IsValid()) { Slate.DestroyWindowImmediately(Window.ToSharedRef()); } }
        FSlateApplication& Slate;
        TSharedPtr<SWindow> Window;
    };

    auto Markup(const FString& InChildren = TEXT("<capture id=\"capture\" state=\"stable\"/>")) -> FString
    {
        return FString::Printf(TEXT("<ui version=\"1\"><region name=\"main\"><column id=\"root\">%s</column></region></ui>"), *InChildren);
    }

    auto Tick(FSlateApplication& InSlate) -> void
    {
        InSlate.PumpMessages();
        InSlate.Tick();
        InSlate.Tick();
    }

    class FSlotContainer final : public ICkUiRetainedWidget
    {
    public:
        explicit FSlotContainer(const TSharedRef<SWidget>& InBody)
            : Body(InBody), Root(SNew(SBox)[InBody]) {}

        virtual auto GetWidget() const -> TSharedRef<SWidget> override { return Root; }
        virtual auto PrepareReload(const FCkUiCustomWidgetArguments& InArguments, FString& OutFailure) const -> TUniquePtr<ICkUiPreparedWidgetUpdate> override
        {
            if (InArguments.Slots.FindRef(TEXT("body")) != Body)
            { OutFailure = TEXT("Capture container lost its stable body mount."); return nullptr; }
            return MakeUnique<FPreparedUpdate>();
        }

    private:
        TSharedRef<SWidget> Body;
        TSharedRef<SWidget> Root;
    };

    auto RegisterCapture(const TSharedRef<FFixtureStats>& InStats, TSharedPtr<FCaptureComponent>& OutComponent, bool& OutRegistered) -> TSharedPtr<const FCkUiWidgetRegistrySnapshot>
    {
        auto Registry = FCkUiWidgetRegistry{};
        auto Registration = FCkUiCustomWidgetRegistration{};
        Registration.Schema.Tag = TEXT("capture");
        Registration.Schema.Properties = {{TEXT("state"), ECkUiCustomPropertyKind::Text, true}};
        Registration.Schema.StateKeyProperty = TEXT("state");
        Registration.RetainedFactory = [&OutComponent, InStats](const FCkUiCustomWidgetArguments& InArguments, FString&) -> TSharedPtr<ICkUiRetainedWidget>
        {
            OutComponent = MakeShared<FCaptureComponent>(InStats, InArguments.CanDispatchEvents);
            return OutComponent;
        };
        OutRegistered = Registry.Register(MoveTemp(Registration)).Succeeded;
        auto Container = FCkUiCustomWidgetRegistration{};
        Container.Schema.Tag = TEXT("capture-container");
        Container.Schema.Slots = {{TEXT("body"), false}};
        Container.RetainedFactory = [](const FCkUiCustomWidgetArguments& InArguments, FString& OutFailure) -> TSharedPtr<ICkUiRetainedWidget>
        {
            const auto Body = InArguments.Slots.FindRef(TEXT("body"));
            if (!Body.IsValid()) { OutFailure = TEXT("Capture container requires its declared mount."); return nullptr; }
            return MakeShared<FSlotContainer>(Body.ToSharedRef());
        };
        OutRegistered = Registry.Register(MoveTemp(Container)).Succeeded && OutRegistered;
        return Registry.CreateSnapshot();
    }

    auto HasCurrentCapturePath(FSlateApplication& InSlate, FSlateUser& InUser,
        const uint32 InPointerIndex, const TSharedRef<SWidget>& InWidget) -> bool
    {
        FWidgetPath Expected;
        if (!InSlate.GeneratePathToWidgetUnchecked(InWidget, Expected)) { return false; }
        const FWidgetPath Actual = InUser.GetCaptorPath(InPointerIndex, FWeakWidgetPath::EInterruptedPathHandling::ReturnInvalid);
        if (!Actual.IsValid() || Actual.Widgets.Num() != Expected.Widgets.Num()) { return false; }
        for (int32 Index = 0; Index < Expected.Widgets.Num(); ++Index)
        {
            if (Actual.Widgets[Index].Widget != Expected.Widgets[Index].Widget) { return false; }
        }
        return true;
    }

    auto CaptureMouse(FSlateApplication& InSlate, const TSharedRef<SWidget>& InWidget, int32 InUserIndex, uint32 InPointerIndex) -> bool
    {
        const FGeometry Geometry = InWidget->GetCachedGeometry();
        const FVector2D Position = Geometry.GetAbsolutePosition() + FVector2D(2.0f, 2.0f);
        const TSet<FKey> Buttons{EKeys::LeftMouseButton};
        const FPointerEvent Down(InUserIndex, InPointerIndex, Position, Position, Buttons, EKeys::LeftMouseButton, 0.0f, FModifierKeysState{});
        FWidgetPath Path;
        if (!InSlate.GeneratePathToWidgetUnchecked(InWidget, Path)) { return false; }
        const FReply Reply = InWidget->OnMouseButtonDown(Geometry, Down);
        InSlate.ProcessReply(Path, Reply, &Path, &Down, InUserIndex);
        const TSharedPtr<FSlateUser> User = InSlate.GetUser(InUserIndex);
        return Reply.IsEventHandled() && User.IsValid() && User->GetPointerCaptor(InPointerIndex) == InWidget;
    }

    auto CaptureTouch(FSlateApplication& InSlate, const TSharedRef<SWidget>& InWidget, int32 InUserIndex, uint32 InPointerIndex) -> bool
    {
        const FGeometry Geometry = InWidget->GetCachedGeometry();
        const FVector2D Position = Geometry.GetAbsolutePosition() + FVector2D(3.0f, 3.0f);
        const FPointerEvent Down(InUserIndex, InPointerIndex, Position, Position, 1.0f, true, false, true);
        FWidgetPath Path;
        if (!InSlate.GeneratePathToWidgetUnchecked(InWidget, Path)) { return false; }
        const FReply Reply = InWidget->OnTouchStarted(Geometry, Down);
        InSlate.ProcessReply(Path, Reply, &Path, &Down, InUserIndex);
        const TSharedPtr<FSlateUser> User = InSlate.GetUser(InUserIndex);
        return Reply.IsEventHandled() && User.IsValid() && User->GetPointerCaptor(InPointerIndex) == InWidget;
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiRetainedCapture_Runtime, "Ck.UiAuthoring.RetainedCapture.Runtime", EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiRetainedCapture_Runtime::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_retained_capture;
    if (!FSlateApplication::IsInitialized()) { AddError(TEXT("Retained capture test requires Slate.")); return false; }

    FSlateApplication& Slate = FSlateApplication::Get();
    const TSharedRef<FFixtureStats> Stats = MakeShared<FFixtureStats>();
    const TSharedRef<FFixtureStats> ForeignStats = MakeShared<FFixtureStats>();
    TSharedPtr<FCaptureComponent> Component;
    bool CaptureRegistrationSucceeded = false;
    const TSharedRef<FCkUiView> View = FCkUiView::Create({}, {}, {}, FSlateFontInfo{}, {}, RegisterCapture(Stats, Component, CaptureRegistrationSucceeded));
    if (!TestTrue(TEXT("Retained capture fixture registration succeeds"), CaptureRegistrationSucceeded)) { return false; }
    FWindowScope Scope(Slate);
    const TSharedRef<SCaptureWidget> ForeignCaptor = SNew(SCaptureWidget).Stats(ForeignStats);
    Scope.Window = SNew(SWindow).AutoCenter(EAutoCenter::None).ClientSize(FVector2D(360, 180)).CreateTitleBar(false)
    [SNew(SOverlay)
        + SOverlay::Slot()[View->GetRegion(TEXT("main"))]
        + SOverlay::Slot().HAlign(HAlign_Right).VAlign(VAlign_Bottom).Padding(8.0f)[ForeignCaptor]];
    Slate.AddWindow(Scope.Window.ToSharedRef(), true);
    if (!TestTrue(TEXT("Initial retained capture component loads"), View->TryReload(Markup(), TEXT(""), TEXT("RetainedCaptureInitial")).Succeeded)) { return false; }
    Tick(Slate);
    if (!TestTrue(TEXT("Capture component exists"), Component.IsValid())) { return false; }
    const TSharedRef<SCaptureWidget> Captor = Component->GetCaptureWidget();
    const int32 CursorUserIndex = Slate.GetCursorUser()->GetUserIndex();
    if (!TestTrue(TEXT("Mouse capture is established through Slate ProcessReply"), CaptureMouse(Slate, Captor, CursorUserIndex, FSlateApplication::CursorPointerIndex))) { return false; }

    const TSharedRef<FSlateVirtualUserHandle> VirtualUser = Slate.FindOrCreateVirtualUser(91);
    const int32 VirtualUserIndex = VirtualUser->GetUserIndex();
    if (!TestTrue(TEXT("Virtual-user touch capture is established through Slate ProcessReply"), CaptureTouch(Slate, Captor, VirtualUserIndex, 17))) { return false; }
    const int32 DraftBeforeReload = Stats->Draft;
    if (!TestTrue(TEXT("Foreign capture is established"), CaptureMouse(Slate, ForeignCaptor, CursorUserIndex, 29))) { return false; }
    Stats->bReportStalePointer = true;
    Stats->AdditionalReports.Add({INDEX_NONE, 0, Captor});
    Stats->AdditionalReports.Add({CursorUserIndex, 3, {}});
    Stats->AdditionalReports.Add({CursorUserIndex, 29, ForeignCaptor});
    Stats->AdditionalReports.Add({CursorUserIndex, FSlateApplication::CursorPointerIndex, Captor});

    if (!TestTrue(TEXT("Compatible reload succeeds during mouse and virtual touch capture"), View->TryReload(Markup(), TEXT(""), TEXT("RetainedCaptureCompatible")).Succeeded)) { return false; }
    const TSharedPtr<FSlateUser> CursorUser = Slate.GetUser(CursorUserIndex);
    const TSharedPtr<FSlateUser> VirtualSlateUser = Slate.GetUser(VirtualUserIndex);
    TestTrue(TEXT("Mouse captor survives compatible reload"), CursorUser.IsValid() && CursorUser->GetPointerCaptor(FSlateApplication::CursorPointerIndex) == Captor);
    TestTrue(TEXT("Virtual touch captor survives compatible reload"), VirtualSlateUser.IsValid() && VirtualSlateUser->GetPointerCaptor(17) == Captor);
    TestTrue(TEXT("Stale descriptor does not disturb a foreign captor"), CursorUser.IsValid() && CursorUser->GetPointerCaptor(29) == ForeignCaptor);
    TestTrue(TEXT("Mouse capture ancestry matches the newly published layout"), HasCurrentCapturePath(Slate, *CursorUser, FSlateApplication::CursorPointerIndex, Captor));
    TestTrue(TEXT("Virtual touch ancestry matches the newly published layout"), HasCurrentCapturePath(Slate, *VirtualSlateUser, 17, Captor));
    TestEqual(TEXT("Compatible transfer preserves the local draft"), Stats->Draft, DraftBeforeReload);
    TestEqual(TEXT("Compatible transfer suppresses both synthetic capture losses"), Stats->SyntheticCaptureLosses, 2);
    TestEqual(TEXT("Compatible transfer does not cancel either live interaction"), Stats->CancelledCaptures, 0);

    const int32 LossesBeforeRejectedReload = Stats->SyntheticCaptureLosses;
    TestFalse(TEXT("Invalid reload is rejected before capture transfer"), View->TryReload(Markup(TEXT("<unknown id=\"bad\"/>")), TEXT(""), TEXT("RetainedCaptureInvalid")).Succeeded);
    TestTrue(TEXT("Rejected reload retains mouse capture"), CursorUser->GetPointerCaptor(FSlateApplication::CursorPointerIndex) == Captor);
    TestTrue(TEXT("Rejected reload retains virtual touch capture"), VirtualSlateUser->GetPointerCaptor(17) == Captor);
    TestEqual(TEXT("Rejected reload emits no synthetic capture loss"), Stats->SyntheticCaptureLosses, LossesBeforeRejectedReload);

    CursorUser->ReleaseCapture(FSlateApplication::CursorPointerIndex);
    TestFalse(TEXT("Direct capture release clears the restored mouse capture"), CursorUser->GetPointerCaptor(FSlateApplication::CursorPointerIndex).IsValid());
    TestEqual(TEXT("Direct capture release reaches the retained control after reload"), Stats->CancelledCaptures, 1);
    TestEqual(TEXT("Direct capture release dispatches one consumer callback"), Stats->ConsumerCallbacks, 1);
    if (!TestTrue(TEXT("Mouse capture can restart after direct release"), CaptureMouse(Slate, Captor, CursorUserIndex, FSlateApplication::CursorPointerIndex))) { return false; }

    if (!TestTrue(TEXT("Removal reload succeeds"), View->TryReload(Markup(TEXT("<text id=\"replacement\">removed</text>")), TEXT(""), TEXT("RetainedCaptureRemoval")).Succeeded)) { return false; }
    TestFalse(TEXT("Removal releases mouse capture"), CursorUser->GetPointerCaptor(FSlateApplication::CursorPointerIndex).IsValid());
    TestFalse(TEXT("Removal releases virtual touch capture"), VirtualSlateUser->GetPointerCaptor(17).IsValid());
    TestTrue(TEXT("Removal leaves foreign capture untouched"), CursorUser->GetPointerCaptor(29) == ForeignCaptor);
    TestEqual(TEXT("Removal delivers local cancellation for each owned pointer"), Stats->CancelledCaptures, 3);
    TestEqual(TEXT("Removal does not dispatch additional consumer callbacks"), Stats->ConsumerCallbacks, 1);

    const TSharedRef<FFixtureStats> DestructorStats = MakeShared<FFixtureStats>();
    TSharedPtr<FCaptureComponent> DestructorComponent;
    bool DestructorRegistrationSucceeded = false;
    TSharedPtr<FCkUiView> DestructorView = FCkUiView::Create({}, {}, {}, FSlateFontInfo{}, {}, RegisterCapture(DestructorStats, DestructorComponent, DestructorRegistrationSucceeded));
    if (!TestTrue(TEXT("Destructor capture fixture registration succeeds"), DestructorRegistrationSucceeded)) { return false; }
    FWindowScope DestructorScope(Slate);
    DestructorScope.Window = SNew(SWindow).AutoCenter(EAutoCenter::None).ClientSize(FVector2D(240, 100)).CreateTitleBar(false)
    [DestructorView->GetRegion(TEXT("main"))];
    Slate.AddWindow(DestructorScope.Window.ToSharedRef(), true);
    if (!TestTrue(TEXT("Destructor capture component loads"), DestructorView->TryReload(Markup(), TEXT(""), TEXT("RetainedCaptureDestructor")).Succeeded)) { return false; }
    Tick(Slate);
    if (!TestTrue(TEXT("Destructor capture component exists"), DestructorComponent.IsValid())) { return false; }
    const TSharedRef<SCaptureWidget> DestructorCaptor = DestructorComponent->GetCaptureWidget();
    const TSharedPtr<SWidget> HeldMountedRegion = DestructorView->GetRegion(TEXT("main"));
    if (!TestTrue(TEXT("Destructor capture is established through Slate ProcessReply"), CaptureMouse(Slate, DestructorCaptor, CursorUserIndex, 47))) { return false; }
    DestructorComponent.Reset();
    DestructorView.Reset();
    TestTrue(TEXT("External mounted region keeps the capture leaf alive"), HeldMountedRegion.IsValid());
    TestFalse(TEXT("View destruction releases owned retained capture"), CursorUser->GetPointerCaptor(47).IsValid());
    TestEqual(TEXT("View destruction clears local capture state"), DestructorStats->CancelledCaptures, 1);
    TestEqual(TEXT("View destruction does not dispatch consumer callbacks"), DestructorStats->ConsumerCallbacks, 0);
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiRetainedCapture_Repeat,
    "Ck.UiAuthoring.RetainedCapture.RepeatedChildren",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiRetainedCapture_Repeat::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_retained_capture;
    if (!FSlateApplication::IsInitialized()) { AddError(TEXT("Repeat capture requires Slate.")); return false; }
    FSlateApplication& Slate = FSlateApplication::Get();
    FWindowScope Scope(Slate);
    TSharedPtr<FCkUiCollection> Collection;
    if (!TestTrue(TEXT("Repeat capture schema creates"), FCkUiCollection::TryCreate({{TEXT("label"), ECkUiFieldKind::Text}}, Collection).Succeeded)) { return false; }
    FCkUiRecordData Row;
    Row.Key = TEXT("a");
    Row.Fields.Add(TEXT("label"), FCkUiFieldValue{.Kind = ECkUiFieldKind::Text, .Text = FText::FromString(TEXT("Captured row"))});
    Collection->TrySetRecords({Row});
    FCkUiView::FDataBindings Data;
    Data.Collections.Add(TEXT("rows"), Collection);
    const auto Stats = MakeShared<FFixtureStats>();
    TSharedPtr<FCaptureComponent> Component;
    bool Registered = false;
    const auto Registry = RegisterCapture(Stats, Component, Registered);
    if (!TestTrue(TEXT("Repeat capture widget registers"), Registered)) { return false; }
    const auto View = FCkUiView::Create({}, {}, {}, FSlateFontInfo{}, MoveTemp(Data), Registry);
    const FString Initial = Markup(TEXT("<repeat id=\"rows\" bind=\"rows\"><capture id=\"capture\" state=\"stable\"/></repeat>"));
    const FString Wrapped = Markup(TEXT("<repeat id=\"rows\" bind=\"rows\"><column id=\"wrapper\"><capture id=\"capture\" state=\"stable\"/></column></repeat>"));
    const auto Region = View->GetRegion(TEXT("main"));
    const auto Loaded = View->TryReload(Initial, TEXT(""));
    if (!TestTrue(*FString::Join(Loaded.Errors, TEXT("\n")), Loaded.Succeeded)) { return false; }
    Scope.Window = SNew(SWindow).ClientSize(FVector2D(320, 180)).CreateTitleBar(false)[Region];
    Slate.AddWindow(Scope.Window.ToSharedRef(), true);
    Tick(Slate);
    const auto Captor = Component->GetCaptureWidget();
    const uint32 Pointer = FSlateApplication::CursorPointerIndex;
    const auto User = Slate.GetUser(0);
    if (!TestTrue(TEXT("Repeated component captures native mouse"), User.IsValid() && CaptureMouse(Slate, Captor, 0, Pointer))) { return false; }
    int32 Reentries = 0;
    bool RejectedAllReentries = true;
    int64 ObservedRevision = 0;
    const TWeakPtr<FCkUiView> WeakView = View;
    Stats->OnCaptureLost = [WeakView, &Reentries, &RejectedAllReentries, &ObservedRevision, Initial]()
    {
        if (const auto Owner = WeakView.Pin())
        {
            ++Reentries;
            ObservedRevision = Owner->GetRevision();
            RejectedAllReentries &= !Owner->TryReload(Initial, TEXT(""), TEXT("CaptureLossReentry")).Succeeded;
        }
    };
    const int64 BeforeReload = View->GetRevision();
    const auto Reloaded = View->TryReload(Wrapped, TEXT(""));
    if (!TestTrue(*FString::Join(Reloaded.Errors, TEXT("\n")), Reloaded.Succeeded)) { return false; }
    TestTrue(TEXT("Repeated retained capture gets the current parent/child ancestry"), User->GetPointerCaptor(Pointer) == Captor && HasCurrentCapturePath(Slate, *User, Pointer, Captor));
    TestTrue(TEXT("Capture reconciliation observes published parent and rejects reentry"), Reentries > 0 && RejectedAllReentries && ObservedRevision == BeforeReload + 1);
    TestEqual(TEXT("Capture transfer preserves active draft"), Stats->Draft, 1);
    TestEqual(TEXT("Capture transfer does not cancel the interaction"), Stats->CancelledCaptures, 0);
    TestEqual(TEXT("Transaction capture callbacks do not reach consumer"), Stats->ConsumerCallbacks, 0);
    Collection->TrySetRecords({});
    if (!TestTrue(TEXT("Removing captured repeat item refreshes"), View->GetRepeat(TEXT("rows"))->TryRefresh())) { return false; }
    TestFalse(TEXT("Collection removal releases the captured child"), User->GetPointerCaptor(Pointer).IsValid());
    TestEqual(TEXT("Collection removal cancels the child once"), Stats->CancelledCaptures, 1);
    Collection->TrySetRecords({Row});
    View->GetRepeat(TEXT("rows"))->TryRefresh();
    Tick(Slate);
    const auto Reinserted = Component->GetCaptureWidget();
    if (!TestTrue(TEXT("Reinserted item starts fresh capture"), Reinserted != Captor && CaptureMouse(Slate, Reinserted, 0, Pointer))) { return false; }
    const auto Removed = View->TryReload(Markup(TEXT("<text id=\"empty\">No cards</text>")), TEXT(""));
    if (!TestTrue(*FString::Join(Removed.Errors, TEXT("\n")), Removed.Succeeded)) { return false; }
    TestFalse(TEXT("Parent document removal releases externally held repeated captor"), User->GetPointerCaptor(Pointer).IsValid());
    TestTrue(TEXT("Removal reconciliation rejects every capture-loss reentry"), RejectedAllReentries);
    TestEqual(TEXT("Removed nested interactions never call consumer"), Stats->ConsumerCallbacks, 0);
    Stats->OnCaptureLost = {};
    User->ReleaseCapture(Pointer);
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiRetainedCapture_Slots,
    "Ck.UiAuthoring.RetainedCapture.CustomSlots",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiRetainedCapture_Slots::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_retained_capture;
    if (!FSlateApplication::IsInitialized()) { AddError(TEXT("Slot capture requires Slate.")); return false; }
    FSlateApplication& Slate = FSlateApplication::Get();
    FWindowScope Scope(Slate);
    const auto Stats = MakeShared<FFixtureStats>();
    TSharedPtr<FCaptureComponent> Component;
    bool Registered = false;
    const auto Registry = RegisterCapture(Stats, Component, Registered);
    if (!TestTrue(TEXT("Slot capture registry creates"), Registered)) { return false; }
    const auto View = FCkUiView::Create({}, {}, {}, FSlateFontInfo{}, {}, Registry);
    const FString Initial = Markup(TEXT("<capture-container id=\"panel\"><slot name=\"body\"><capture id=\"capture\" state=\"stable\"/></slot></capture-container>"));
    const FString Wrapped = Markup(TEXT("<capture-container id=\"panel\"><slot name=\"body\"><column id=\"wrapper\"><capture id=\"capture\" state=\"stable\"/></column></slot></capture-container>"));
    const auto Region = View->GetRegion(TEXT("main"));
    const auto Loaded = View->TryReload(Initial, TEXT(""));
    if (!TestTrue(*FString::Join(Loaded.Errors, TEXT("\n")), Loaded.Succeeded)) { return false; }
    Scope.Window = SNew(SWindow).ClientSize(FVector2D(320, 180)).CreateTitleBar(false)[Region];
    Slate.AddWindow(Scope.Window.ToSharedRef(), true);
    Tick(Slate);
    const auto Captor = Component->GetCaptureWidget();
    const uint32 Pointer = FSlateApplication::CursorPointerIndex;
    const auto User = Slate.GetUser(0);
    if (!TestTrue(TEXT("Slot child captures native mouse"), User.IsValid() && CaptureMouse(Slate, Captor, 0, Pointer))) { return false; }
    int32 Reentries = 0;
    bool RejectedAllReentries = true;
    const TWeakPtr<FCkUiView> WeakView = View;
    Stats->OnCaptureLost = [WeakView, &Reentries, &RejectedAllReentries, Initial]()
    {
        if (const auto Owner = WeakView.Pin())
        {
            ++Reentries;
            RejectedAllReentries &= !Owner->TryReload(Initial, TEXT(""), TEXT("SlotCaptureLossReentry")).Succeeded;
        }
    };
    ON_SCOPE_EXIT { Stats->OnCaptureLost = {}; };
    const auto Reloaded = View->TryReload(Wrapped, TEXT(""));
    if (!TestTrue(*FString::Join(Reloaded.Errors, TEXT("\n")), Reloaded.Succeeded)) { return false; }
    TestTrue(TEXT("Slot capture survives authored ancestry change"), Component->GetCaptureWidget() == Captor
        && User->GetPointerCaptor(Pointer) == Captor && HasCurrentCapturePath(Slate, *User, Pointer, Captor));
    TestTrue(TEXT("Slot capture transfer blocks parent reentry"), Reentries > 0 && RejectedAllReentries);
    TestEqual(TEXT("Slot capture transfer preserves draft"), Stats->Draft, 1);
    TestEqual(TEXT("Slot capture transfer does not cancel"), Stats->CancelledCaptures, 0);
    const auto RemovedSlot = View->TryReload(Markup(TEXT("<capture-container id=\"panel\"/>")), TEXT(""));
    if (!TestTrue(*FString::Join(RemovedSlot.Errors, TEXT("\n")), RemovedSlot.Succeeded)) { return false; }
    TestFalse(TEXT("Optional slot removal releases held native captor"), User->GetPointerCaptor(Pointer).IsValid());
    TestEqual(TEXT("Optional slot removal cancels once"), Stats->CancelledCaptures, 1);
    const auto Reinserted = View->TryReload(Initial, TEXT(""));
    if (!TestTrue(*FString::Join(Reinserted.Errors, TEXT("\n")), Reinserted.Succeeded)) { return false; }
    Tick(Slate);
    if (!TestTrue(TEXT("Reinserted slot child captures"), Component->GetCaptureWidget() != Captor && CaptureMouse(Slate, Component->GetCaptureWidget(), 0, Pointer))) { return false; }
    const auto RemovedParent = View->TryReload(Markup(TEXT("<text id=\"empty\">No panel</text>")), TEXT(""));
    if (!TestTrue(*FString::Join(RemovedParent.Errors, TEXT("\n")), RemovedParent.Succeeded)) { return false; }
    TestFalse(TEXT("Parent removal releases held slot captor"), User->GetPointerCaptor(Pointer).IsValid());
    TestEqual(TEXT("Both removals cancel exactly once"), Stats->CancelledCaptures, 2);
    TestTrue(TEXT("Removal callbacks reject parent reentry"), RejectedAllReentries);
    TestEqual(TEXT("Slot transaction callbacks never reach consumer"), Stats->ConsumerCallbacks, 0);
    Stats->OnCaptureLost = {};
    User->ReleaseCapture(Pointer);
    return true;
}

#endif
