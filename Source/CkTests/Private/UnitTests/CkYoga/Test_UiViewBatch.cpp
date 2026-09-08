#include "CkSlateLayout/CkUiWidgetRegistry.h"
#include "CkSlateLayout/SCkUiSurface.h"

#include "Framework/Application/SlateApplication.h"
#include "Layout/Children.h"
#include "Misc/AutomationTest.h"
#include "Widgets/Input/SButton.h"
#include "Widgets/Input/SSearchBox.h"
#include "Widgets/Layout/SBox.h"
#include "Widgets/SBoxPanel.h"
#include "Widgets/SWindow.h"
#include "Widgets/Text/STextBlock.h"

#if WITH_DEV_AUTOMATION_TESTS

namespace ck_tests_ui_view_batch
{
    struct FFactoryProbe final
    {
        int32 Calls = 0;
        FString RejectId;
        TArray<FCkUiView::FReloadRequest>* RequestsToMutate = nullptr;
        bool MutatedRequests = false;
    };

    auto RegisterFactoryProbe(const TSharedRef<FFactoryProbe>& InProbe, FCkUiWidgetRegistry& InRegistry) -> bool
    {
        auto Registration = FCkUiCustomWidgetRegistration{};
        Registration.Schema.Tag = TEXT("batch-probe");
        Registration.Factory = [InProbe](const FCkUiCustomWidgetArguments& InArguments, FString& OutFailure) -> TSharedPtr<SWidget>
        {
            ++InProbe->Calls;
            if (InArguments.Id == InProbe->RejectId)
            {
                OutFailure = TEXT("Requested batch factory rejection.");
                return nullptr;
            }
            if (InArguments.Id == TEXT("first-mutate") && InProbe->RequestsToMutate != nullptr && InProbe->RequestsToMutate->Num() == 2)
            {
                (*InProbe->RequestsToMutate)[1].Markup = TEXT("<ui version=\"1\"><region name=\"main\"/></ui>");
                InProbe->MutatedRequests = true;
            }
            return SNew(STextBlock).Text(FText::FromString(InArguments.Id));
        };
        return InRegistry.Register(MoveTemp(Registration)).Succeeded;
    }

    auto Markup(const FString& InProbeId) -> FString
    {
        return FString::Printf(TEXT("<ui version=\"1\"><region name=\"main\"><column id=\"root\"><search id=\"search\" bind=\"query\"/><batch-probe id=\"%s\"/></column></region></ui>"), *InProbeId);
    }

    auto InvalidMarkup() -> FString
    {
        return TEXT("<ui version=\"1\"><region name=\"main\"><column id=\"root\"><search id=\"search\" bind=\"missing\"/></column></region></ui>");
    }

    auto NativeMarkup() -> FString
    {
        return TEXT("<ui version=\"1\"><region name=\"main\"><native id=\"shared\" bind=\"shared\"/></region></ui>");
    }

    auto MakeData(FText& InOutQuery) -> FCkUiView::FDataBindings
    {
        auto Result = FCkUiView::FDataBindings{};
        Result.Text.Add(TEXT("query"), TAttribute<FText>::CreateLambda([&InOutQuery]() { return InOutQuery; }));
        Result.TextChanged.Add(TEXT("query"), FOnTextChanged::CreateLambda([&InOutQuery](const FText& InText) { InOutQuery = InText; }));
        return Result;
    }

    auto RegionRoot(const TSharedRef<SWidget>& InRegion) -> TSharedRef<SWidget>
    {
        return StaticCastSharedRef<SBox>(InRegion)->GetChildren()->GetChildAt(0);
    }

    auto FindSearch(const TSharedRef<SWidget>& InRoot) -> TSharedPtr<SSearchBox>
    {
        if (InRoot->GetTypeAsString() == TEXT("SSearchBox"))
        {
            return StaticCastSharedRef<SSearchBox>(InRoot);
        }
        const FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<SSearchBox> Found = FindSearch(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index))); Found.IsValid())
            {
                return Found;
            }
        }
        return {};
    }

    auto Request(const TSharedPtr<FCkUiView>& InView, const FString& InMarkup, const FString& InSource) -> FCkUiView::FReloadRequest
    {
        return FCkUiView::FReloadRequest{.View = InView, .Markup = InMarkup, .Source = InSource};
    }

    struct FFocusState final
    {
        TWeakPtr<FCkUiView> First;
        TWeakPtr<FCkUiView> Second;
        int64 ExpectedFirstRevision = 0;
        int64 ExpectedSecondRevision = 0;
        int32 FocusLostCalls = 0;
        bool bBothRevisionsPublished = false;
        FCkUiLoadResult FirstReentry;
        FCkUiLoadResult SecondReentry;
    };

    auto RegisterFocusProbe(const TSharedRef<FFocusState>& InState, FCkUiWidgetRegistry& InRegistry) -> bool
    {
        auto Registration = FCkUiCustomWidgetRegistration{};
        Registration.Schema.Tag = TEXT("batch-focus");
        Registration.Factory = [InState](const FCkUiCustomWidgetArguments&, FString&) -> TSharedPtr<SWidget>
        {
            const TSharedRef<SButton> Button = SNew(SButton).Tag(FName(TEXT("batch-focus-button")))[SNew(STextBlock).Text(FText::FromString(TEXT("Focus")))];
            Button->SetOnFocusLost(FSimpleDelegate::CreateLambda([InState]()
            {
                ++InState->FocusLostCalls;
                const TSharedPtr<FCkUiView> First = InState->First.Pin();
                const TSharedPtr<FCkUiView> Second = InState->Second.Pin();
                if (!First.IsValid() || !Second.IsValid()) { return; }
                InState->bBothRevisionsPublished = First->GetRevision() == InState->ExpectedFirstRevision
                    && Second->GetRevision() == InState->ExpectedSecondRevision;
                InState->FirstReentry = First->TryReload(Markup(TEXT("reentrant-first")), TEXT(""), TEXT("UiViewBatchFocusReentrantFirst"));
                InState->SecondReentry = Second->TryReload(Markup(TEXT("reentrant-second")), TEXT(""), TEXT("UiViewBatchFocusReentrantSecond"));
            }));
            return Button;
        };
        return InRegistry.Register(MoveTemp(Registration)).Succeeded;
    }

    auto FocusMarkup(const bool bIncludeFocus, const FString& InProbeId) -> FString
    {
        const TCHAR* Focus = bIncludeFocus ? TEXT("<batch-focus id=\"focus\"/>") : TEXT("");
        return FString::Printf(TEXT("<ui version=\"1\"><region name=\"main\"><column id=\"root\"><search id=\"search\" bind=\"query\"/>%s<batch-probe id=\"%s\"/></column></region></ui>"), Focus, *InProbeId);
    }

    auto FindTagged(const TSharedRef<SWidget>& InRoot, const FName InTag) -> TSharedPtr<SWidget>
    {
        if (InRoot->GetTag() == InTag)
        {
            return InRoot;
        }
        const FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<SWidget> Found = FindTagged(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InTag); Found.IsValid())
            {
                return Found;
            }
        }
        return {};
    }

    struct FWindowScope final
    {
        explicit FWindowScope(FSlateApplication& InSlate) : Slate(InSlate) {}
        ~FWindowScope() { if (Window.IsValid()) { Slate.DestroyWindowImmediately(Window.ToSharedRef()); } }
        FSlateApplication& Slate;
        TSharedPtr<SWindow> Window;
    };
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkUiViewBatch_PreflightAndFactoryAtomicity,
    "Ck.UiAuthoring.View.Batch.PreflightAndFactoryAtomicity",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiViewBatch_PreflightAndFactoryAtomicity::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_view_batch;

    const TSharedRef<FFactoryProbe> Probe = MakeShared<FFactoryProbe>();
    auto Registry = FCkUiWidgetRegistry{};
    if (NOT TestTrue(TEXT("Batch factory probe registration succeeds"), RegisterFactoryProbe(Probe, Registry)))
    {
        return false;
    }

    auto FirstQuery = FText::FromString(TEXT("first initial"));
    auto SecondQuery = FText::FromString(TEXT("second initial"));
    const TSharedPtr<FCkUiView> First = FCkUiView::Create({}, {}, {}, FSlateFontInfo{}, MakeData(FirstQuery), Registry.CreateSnapshot());
    const TSharedPtr<FCkUiView> Second = FCkUiView::Create({}, {}, {}, FSlateFontInfo{}, MakeData(SecondQuery), Registry.CreateSnapshot());
    const TSharedRef<SWidget> FirstRegion = First->GetRegion(TEXT("main"));
    const TSharedRef<SWidget> SecondRegion = Second->GetRegion(TEXT("main"));
    if (NOT TestTrue(TEXT("First mounted batch participant loads"), First->TryReload(Markup(TEXT("first-initial")), TEXT(""), TEXT("UiViewBatchFirstInitial")).Succeeded)
        || NOT TestTrue(TEXT("Second mounted batch participant loads"), Second->TryReload(Markup(TEXT("second-initial")), TEXT(""), TEXT("UiViewBatchSecondInitial")).Succeeded))
    {
        return false;
    }

    const TSharedRef<SWidget> FirstRoot = RegionRoot(FirstRegion);
    const TSharedPtr<SSearchBox> FirstSearch = FindSearch(FirstRoot);
    if (NOT TestTrue(TEXT("First participant mounts its native retained search"), FirstSearch.IsValid()))
    {
        return false;
    }
    FirstSearch->SetText(FText::FromString(TEXT("first retained query")));
    const int64 FirstRevision = First->GetRevision();
    const int64 SecondRevision = Second->GetRevision();

    const int32 FactoriesBeforePreflight = Probe->Calls;
    const FCkUiLoadResult InvalidLast = FCkUiView::TryReloadBatch({
        Request(First, Markup(TEXT("first-preflight")), TEXT("UiViewBatchFirstPreflight")),
        Request(Second, InvalidMarkup(), TEXT("UiViewBatchInvalidLast")),
    });
    TestFalse(TEXT("Invalid last batch request rejects"), InvalidLast.Succeeded);
    TestEqual(TEXT("Invalid last request stages no first custom factory"), Probe->Calls, FactoriesBeforePreflight);
    TestTrue(TEXT("Invalid last request preserves first mounted root and search"), RegionRoot(FirstRegion) == FirstRoot && FindSearch(FirstRoot) == FirstSearch);
    TestEqual(TEXT("Invalid last request preserves first revision"), First->GetRevision(), FirstRevision);
    TestEqual(TEXT("Invalid last request preserves second revision"), Second->GetRevision(), SecondRevision);

    Probe->RejectId = TEXT("second-reject");
    const FCkUiLoadResult LateFactoryFailure = FCkUiView::TryReloadBatch({
        Request(First, Markup(TEXT("first-stage")), TEXT("UiViewBatchFirstStage")),
        Request(Second, Markup(TEXT("second-reject")), TEXT("UiViewBatchSecondReject")),
    });
    TestFalse(TEXT("Later batch factory rejection fails the transaction"), LateFactoryFailure.Succeeded);
    TestTrue(TEXT("Later factory rejection preserves first root, search identity, and query"), RegionRoot(FirstRegion) == FirstRoot
        && FindSearch(FirstRoot) == FirstSearch && FirstSearch->GetText().ToString() == TEXT("first retained query"));
    TestEqual(TEXT("Later factory rejection preserves first revision"), First->GetRevision(), FirstRevision);
    TestEqual(TEXT("Later factory rejection preserves second revision"), Second->GetRevision(), SecondRevision);

    const FCkUiLoadResult EmptyRequest = FCkUiView::TryReloadBatch({});
    TestFalse(TEXT("Empty batch rejects safely"), EmptyRequest.Succeeded);
    const FCkUiLoadResult NullRequest = FCkUiView::TryReloadBatch({Request(nullptr, Markup(TEXT("null")), TEXT("UiViewBatchNull"))});
    TestFalse(TEXT("Null batch participant rejects safely"), NullRequest.Succeeded);
    const FCkUiLoadResult DuplicateRequest = FCkUiView::TryReloadBatch({
        Request(First, Markup(TEXT("first-duplicate")), TEXT("UiViewBatchDuplicateOne")),
        Request(First, Markup(TEXT("first-duplicate-two")), TEXT("UiViewBatchDuplicateTwo")),
    });
    TestFalse(TEXT("Duplicate batch participant rejects safely"), DuplicateRequest.Succeeded);
    TestTrue(TEXT("Rejected null and duplicate requests preserve mounted first state"), RegionRoot(FirstRegion) == FirstRoot && FindSearch(FirstRoot) == FirstSearch);

    auto MutableRequests = TArray<FCkUiView::FReloadRequest>{
        Request(First, Markup(TEXT("first-mutate")), TEXT("UiViewBatchFirstMutate")),
        Request(Second, Markup(TEXT("second-mutate")), TEXT("UiViewBatchSecondMutate")),
    };
    Probe->RequestsToMutate = &MutableRequests;
    const FCkUiLoadResult MutatedCaller = FCkUiView::TryReloadBatch(MutableRequests);
    Probe->RequestsToMutate = nullptr;
    TestTrue(TEXT("Batch snapshots caller requests before custom factory mutation"), MutatedCaller.Succeeded && Probe->MutatedRequests);
    TestEqual(TEXT("Mutated caller batch advances first revision once"), First->GetRevision(), FirstRevision + 1);
    TestEqual(TEXT("Mutated caller batch advances second revision once"), Second->GetRevision(), SecondRevision + 1);

    const TSharedRef<SButton> SharedNative = SNew(SButton);
    const TSharedPtr<FCkUiView> NativeFirst = FCkUiView::Create({{TEXT("shared"), SharedNative}}, {}, {}, FSlateFontInfo{});
    const TSharedPtr<FCkUiView> NativeSecond = FCkUiView::Create({{TEXT("shared"), SharedNative}}, {}, {}, FSlateFontInfo{});
    NativeFirst->GetRegion(TEXT("main"));
    NativeSecond->GetRegion(TEXT("main"));
    const FCkUiLoadResult SharedNativeResult = FCkUiView::TryReloadBatch({
        Request(NativeFirst, NativeMarkup(), TEXT("UiViewBatchSharedNativeFirst")),
        Request(NativeSecond, NativeMarkup(), TEXT("UiViewBatchSharedNativeSecond")),
    });
    TestFalse(TEXT("Shared native widget across batch participants rejects before publication"), SharedNativeResult.Succeeded);
    TestEqual(TEXT("Shared native rejection leaves first revision unchanged"), NativeFirst->GetRevision(), int64{0});
    TestEqual(TEXT("Shared native rejection leaves second revision unchanged"), NativeSecond->GetRevision(), int64{0});
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkUiViewBatch_PublicationFocusAndReentry,
    "Ck.UiAuthoring.View.Batch.PublicationFocusAndReentry",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiViewBatch_PublicationFocusAndReentry::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_view_batch;
    if (!FSlateApplication::IsInitialized())
    {
        AddError(TEXT("Batch focus test requires Slate."));
        return false;
    }

    const TSharedRef<FFactoryProbe> FactoryProbe = MakeShared<FFactoryProbe>();
    const TSharedRef<FFocusState> FocusState = MakeShared<FFocusState>();
    auto Registry = FCkUiWidgetRegistry{};
    if (NOT TestTrue(TEXT("Batch publication factory probe registration succeeds"), RegisterFactoryProbe(FactoryProbe, Registry))
        || NOT TestTrue(TEXT("Batch focus probe registration succeeds"), RegisterFocusProbe(FocusState, Registry)))
    {
        return false;
    }

    auto FirstQuery = FText::FromString(TEXT("first focus query"));
    auto SecondQuery = FText::FromString(TEXT("second focus query"));
    const TSharedPtr<FCkUiView> First = FCkUiView::Create({}, {}, {}, FSlateFontInfo{}, MakeData(FirstQuery), Registry.CreateSnapshot());
    const TSharedPtr<FCkUiView> Second = FCkUiView::Create({}, {}, {}, FSlateFontInfo{}, MakeData(SecondQuery), Registry.CreateSnapshot());
    FocusState->First = First;
    FocusState->Second = Second;
    const TSharedRef<SWidget> FirstRegion = First->GetRegion(TEXT("main"));
    const TSharedRef<SWidget> SecondRegion = Second->GetRegion(TEXT("main"));

    FSlateApplication& Slate = FSlateApplication::Get();
    FWindowScope Scope{Slate};
    Scope.Window = SNew(SWindow).AutoCenter(EAutoCenter::None).ClientSize(FVector2D{420.0f, 180.0f}).CreateTitleBar(false).HasCloseButton(false)
        [SNew(SVerticalBox) + SVerticalBox::Slot()[FirstRegion] + SVerticalBox::Slot()[SecondRegion]];
    Slate.AddWindow(Scope.Window.ToSharedRef(), true);
    if (NOT TestTrue(TEXT("First focus participant loads"), First->TryReload(FocusMarkup(true, TEXT("first-focus")), TEXT(""), TEXT("UiViewBatchFocusFirstInitial")).Succeeded)
        || NOT TestTrue(TEXT("Second focus participant loads"), Second->TryReload(FocusMarkup(false, TEXT("second-focus")), TEXT(""), TEXT("UiViewBatchFocusSecondInitial")).Succeeded))
    {
        return false;
    }

    const TSharedRef<SWidget> FirstRoot = RegionRoot(FirstRegion);
    const TSharedRef<SWidget> SecondRoot = RegionRoot(SecondRegion);
    const TSharedPtr<SSearchBox> FirstSearch = FindSearch(FirstRoot);
    const TSharedPtr<SSearchBox> SecondSearch = FindSearch(SecondRoot);
    const TSharedPtr<SWidget> FocusButton = FindTagged(FirstRoot, TEXT("batch-focus-button"));
    if (NOT TestTrue(TEXT("Focus batch mounts both retained searches and the native focus button"), FirstSearch.IsValid() && SecondSearch.IsValid() && FocusButton.IsValid())
        || NOT TestTrue(TEXT("Native focus button receives Slate focus"), Slate.SetKeyboardFocus(FocusButton.ToSharedRef(), EFocusCause::SetDirectly)))
    {
        return false;
    }
    FirstSearch->SetText(FText::FromString(TEXT("first retained focus query")));
    SecondSearch->SetText(FText::FromString(TEXT("second retained focus query")));
    FocusState->ExpectedFirstRevision = First->GetRevision() + 1;
    FocusState->ExpectedSecondRevision = Second->GetRevision() + 1;

    const FCkUiLoadResult Accepted = FCkUiView::TryReloadBatch({
        Request(First, FocusMarkup(false, TEXT("first-published")), TEXT("UiViewBatchFocusFirstAccepted")),
        Request(Second, FocusMarkup(false, TEXT("second-published")), TEXT("UiViewBatchFocusSecondAccepted")),
    });
    TestTrue(TEXT("Accepted focus batch publishes both participants"), Accepted.Succeeded);
    TestEqual(TEXT("Accepted focus batch advances first revision once"), First->GetRevision(), FocusState->ExpectedFirstRevision);
    TestEqual(TEXT("Accepted focus batch advances second revision once"), Second->GetRevision(), FocusState->ExpectedSecondRevision);
    TestEqual(TEXT("Native focus loss runs once during batch reconciliation"), FocusState->FocusLostCalls, 1);
    TestTrue(TEXT("Focus loss observes both new participant revisions"), FocusState->bBothRevisionsPublished);
    TestFalse(TEXT("Focus-loss reentrant reload rejects first participant during batch"), FocusState->FirstReentry.Succeeded);
    TestFalse(TEXT("Focus-loss reentrant reload rejects second participant during batch"), FocusState->SecondReentry.Succeeded);
    TestTrue(TEXT("Accepted batch retains both search identities and values"), FindSearch(RegionRoot(FirstRegion)) == FirstSearch
        && FindSearch(RegionRoot(SecondRegion)) == SecondSearch
        && FirstSearch->GetText().ToString() == TEXT("first retained focus query")
        && SecondSearch->GetText().ToString() == TEXT("second retained focus query"));
    return true;
}

#endif
