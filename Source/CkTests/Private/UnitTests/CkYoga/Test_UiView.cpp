#include "CkSlateLayout/CkFlexBox.h"
#include "CkSlateLayout/CkFlexText.h"
#include "CkSlateLayout/CkUiWidgetRegistry.h"
#include "CkSlateLayout/SCkUiSurface.h"
#include "Framework/Application/SlateApplication.h"
#include "Layout/ArrangedChildren.h"
#include "HAL/FileManager.h"
#include "Misc/AutomationTest.h"
#include "Misc/FileHelper.h"
#include "Misc/Guid.h"
#include "Misc/Paths.h"
#include "Widgets/Input/SButton.h"
#include "Widgets/Input/SEditableText.h"
#include "Widgets/Input/SSearchBox.h"
#include "Widgets/Images/SImage.h"
#include "Widgets/Layout/SBox.h"
#include "Widgets/Layout/SScrollBox.h"
#include "Widgets/Layout/SSpacer.h"
#include "Widgets/SBoxPanel.h"
#include "Widgets/SWindow.h"
#include "Widgets/Text/STextBlock.h"

#if WITH_DEV_AUTOMATION_TESTS

namespace ck_tests_ui_view
{
    auto Arrange(const TSharedRef<SCkFlexBox>& InPanel, const FVector2D InSize) -> FArrangedChildren
    {
        InPanel->SlatePrepass(1.0f);
        auto Children = FArrangedChildren{EVisibility::Visible};
        InPanel->OnArrangeChildren(FGeometry::MakeRoot(InSize, FSlateLayoutTransform{}), Children);
        return Children;
    }

    auto FindTagged(const TSharedRef<SWidget>& InRoot, const FName InTag) -> TSharedPtr<SWidget>
    {
        if (InRoot->GetTag() == InTag) { return InRoot; }
        const FChildren* Children = InRoot->GetChildren();
        if (Children == nullptr) { return nullptr; }
        for (int32 Index = 0; Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<SWidget> Found = FindTagged(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InTag); Found.IsValid()) { return Found; }
        }
        return nullptr;
    }

    auto CountWidget(const TSharedRef<SWidget>& InRoot, const TSharedRef<SWidget>& InNeedle) -> int32
    {
        auto Result = InRoot == InNeedle ? 1 : 0;
        const FChildren* Children = InRoot->GetChildren();
        if (Children == nullptr) { return Result; }
        for (int32 Index = 0; Index < Children->Num(); ++Index) { Result += CountWidget(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InNeedle); }
        return Result;
    }

    auto FindFirstType(const TSharedRef<SWidget>& InRoot, const FString& InType) -> TSharedPtr<SWidget>
    {
        if (InRoot->GetTypeAsString() == InType) { return InRoot; }
        const FChildren* Children = InRoot->GetChildren();
        if (Children == nullptr) { return nullptr; }
        for (int32 Index = 0; Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<SWidget> Found = FindFirstType(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InType); Found.IsValid()) { return Found; }
        }
        return nullptr;
    }

    auto RegionContent(const TSharedRef<FCkUiView>& InView, const FString& InRegion) -> TSharedRef<SWidget>
    {
        return StaticCastSharedRef<SBox>(InView->GetRegion(InRegion))->GetChildren()->GetChildAt(0);
    }

    auto HasError(const FCkUiLoadResult& InResult, const FString& InNeedle) -> bool
    {
        for (const FString& Error : InResult.Errors) { if (Error.Contains(InNeedle)) { return true; } }
        return false;
    }

    auto Markup(const FString& InLeftBinding = TEXT("left"), const FString& InRightBinding = TEXT("right")) -> FString
    {
        return FString::Printf(TEXT("<ui version=\"1\"><region name=\"left\"><row id=\"left-root\" class=\"root\"><native id=\"left-native\" bind=\"%s\" class=\"native\"/><text id=\"left-label\" class=\"label\">Left label</text><button id=\"left-action\" action=\"apply\">Apply</button></row></region><region name=\"right\"><column id=\"right-root\"><native id=\"right-native\" bind=\"%s\"/></column></region></ui>"), *InLeftBinding, *InRightBinding);
    }

    auto Styles(const float InGap = 7.0f) -> FString
    {
        return FString::Printf(TEXT(".root { gap: %.1fpx; padding: 3px 5px; } .native { min-width: 40px; max-width: 40px; } .label { font-size: 14px; }"), InGap);
    }

    auto DataMarkup(const bool bIncludeAcceptedStructure = false, const bool bIncludeSearch = true) -> FString
    {
        const TCHAR* Search = bIncludeSearch ? TEXT("<search id=\"query\" bind=\"query\" placeholder=\"Filter\"/>") : TEXT("");
        const TCHAR* AcceptedStructure = bIncludeAcceptedStructure ? TEXT("<text id=\"accepted\">Reloaded</text>") : TEXT("");
        return FString::Printf(TEXT("<ui version=\"1\"><region name=\"only\"><column id=\"root\">%s<image id=\"thumbnail\" bind=\"thumbnail\"/><scroll id=\"results\" visible=\"has-results\"><text id=\"summary\" bind=\"summary\"/></scroll>%s</column></region></ui>"), Search, AcceptedStructure);
    }

    auto FocusMarkup(const bool bIncludeOrdinaryButton, const bool bIncludeCustomButton) -> FString
    {
        const TCHAR* OrdinaryButton = bIncludeOrdinaryButton ? TEXT("<button id=\"ordinary\" action=\"noop\">Ordinary</button>") : TEXT("");
        const TCHAR* CustomButton = bIncludeCustomButton ? TEXT("<redirect id=\"custom\"/>") : TEXT("");
        return FString::Printf(TEXT("<ui version=\"1\"><region name=\"only\"><column id=\"root\">%s%s</column></region></ui>"), OrdinaryButton, CustomButton);
    }

    struct FSlateWindowScope final
    {
        explicit FSlateWindowScope(FSlateApplication& InSlate)
            : Slate(InSlate)
            , PreviousFocus(Slate.GetUserFocusedWidget(0))
        {
        }

        ~FSlateWindowScope()
        {
            for (const TSharedRef<SWindow>& Window : Windows) { Slate.DestroyWindowImmediately(Window); }
            if (PreviousFocus.IsValid()) { Slate.SetKeyboardFocus(PreviousFocus, EFocusCause::SetDirectly); }
            else { Slate.ClearKeyboardFocus(EFocusCause::SetDirectly); }
        }

        void Add(const TSharedRef<SWindow>& InWindow)
        {
            Slate.AddWindow(InWindow, false);
            Windows.Add(InWindow);
        }

        FSlateApplication& Slate;
        TSharedPtr<SWidget> PreviousFocus;
        TArray<TSharedRef<SWindow>> Windows;
    };
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiAuthoringView_Runtime,
    "Ck.UiAuthoring.View.RuntimePortsIdentityAndLayout",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiAuthoringView_Runtime::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_view;
    auto Calls = 0;
    const auto LeftNative = SNew(SBox).WidthOverride(20.0f).HeightOverride(18.0f);
    const auto RightNative = SNew(SBox).WidthOverride(30.0f).HeightOverride(18.0f);
    auto Bindings = FCkUiView::FNativeBindings{{TEXT("left"), LeftNative}, {TEXT("right"), RightNative}};
    auto Actions = FCkUiView::FActions{{TEXT("apply"), FSimpleDelegate::CreateLambda([&Calls] { ++Calls; })}};
    const auto View = FCkUiView::Create(MoveTemp(Bindings), MoveTemp(Actions));
    View->GetRegion(TEXT("left"));
    View->GetRegion(TEXT("right"));

    const FCkUiLoadResult Loaded = View->TryReload(Markup(), Styles(), TEXT("UiViewRuntime"));
    TestTrue(TEXT("Two-region document loads"), Loaded.Succeeded);
    if (!Loaded.Succeeded) { return false; }
    TestEqual(TEXT("First accepted document has revision one"), View->GetRevision(), int64{1});
    const TSharedRef<SWidget> LeftRoot = RegionContent(View, TEXT("left"));
    const TSharedRef<SWidget> RightRoot = RegionContent(View, TEXT("right"));
    TestEqual(TEXT("Left native is mounted exactly once"), CountWidget(LeftRoot, LeftNative), 1);
    TestEqual(TEXT("Right native is mounted exactly once"), CountWidget(RightRoot, RightNative), 1);
    const TSharedPtr<SWidget> TextWidget = FindTagged(LeftRoot, TEXT("left-label"));
    if (!TestTrue(TEXT("Authored text retains its id"), TextWidget.IsValid())) { return false; }
    TestEqual(TEXT("Authored text uses Slate flex text type"), TextWidget->GetTypeAsString(), FString(TEXT("SCkFlexText")));
    if (TextWidget->GetTypeAsString() != TEXT("SCkFlexText")) { return false; }
    const TSharedPtr<SCkFlexText> TextLabel = StaticCastSharedPtr<SCkFlexText>(TextWidget);
    TestTrue(TEXT("Authored text label has a live widget"), TextLabel.IsValid());
    const TSharedPtr<SWidget> ActionWidget = FindTagged(LeftRoot, TEXT("left-action"));
    if (!TestTrue(TEXT("Authored button retains its id"), ActionWidget.IsValid())) { return false; }
    TestEqual(TEXT("Authored button uses Slate button type"), ActionWidget->GetTypeAsString(), FString(TEXT("SButton")));
    if (ActionWidget->GetTypeAsString() != TEXT("SButton")) { return false; }
    const TSharedPtr<SButton> ActionButton = StaticCastSharedPtr<SButton>(ActionWidget);
    ActionButton->SimulateClick();
    TestEqual(TEXT("Tagged authored button invokes bound action once"), Calls, 1);

    TestEqual(TEXT("Authored row uses native flex panel type"), LeftRoot->GetTypeAsString(), FString(TEXT("SCkFlexBox")));
    if (LeftRoot->GetTypeAsString() != TEXT("SCkFlexBox")) { return false; }
    const TSharedRef<SCkFlexBox> LeftPanel = StaticCastSharedRef<SCkFlexBox>(LeftRoot);
    const FArrangedChildren Geometry = Arrange(LeftPanel, {200.0f, 60.0f});
    TestEqual(TEXT("Row arranges native, text, and button"), Geometry.Num(), 3);
    if (Geometry.Num() != 3) { return false; }
    TestEqual(TEXT("Root padding sets first child x"), Geometry[0].Geometry.GetAbsolutePosition().X, 5.0f);
    TestEqual(TEXT("Native min and max dimensions are exact"), Geometry[0].Geometry.GetLocalSize().X, 40.0f);
    TestEqual(TEXT("Root gap affects authored text position"), Geometry[1].Geometry.GetAbsolutePosition().X,
        Geometry[0].Geometry.GetAbsolutePosition().X + Geometry[0].Geometry.GetLocalSize().X + 7.0f);
    TestTrue(TEXT("Authored text has measured width"), Geometry[1].Geometry.GetLocalSize().X > 0.0f);

    const FString RestructuredMarkup = Markup().Replace(TEXT("</button></row>"), TEXT("</button><text id=\"left-added\">Added</text></row>"));
    const FCkUiLoadResult Reloaded = View->TryReload(RestructuredMarkup, Styles(11.0f), TEXT("UiViewReload"));
    TestTrue(TEXT("Style and structure reload succeeds"), Reloaded.Succeeded);
    if (!Reloaded.Succeeded) { return false; }
    TestEqual(TEXT("Successful reload increments revision"), View->GetRevision(), int64{2});
    TestTrue(TEXT("Region mount content changes for authored structure reload"), RegionContent(View, TEXT("left")) != LeftRoot);
    const TSharedRef<SWidget> ReloadedLeft = RegionContent(View, TEXT("left"));
    TestEqual(TEXT("Left native preserves identity across reload"), CountWidget(ReloadedLeft, LeftNative), 1);
    TestEqual(TEXT("Right native preserves identity across reload"), CountWidget(RegionContent(View, TEXT("right")), RightNative), 1);
    TestEqual(TEXT("Reloaded row remains native flex panel type"), ReloadedLeft->GetTypeAsString(), FString(TEXT("SCkFlexBox")));
    if (ReloadedLeft->GetTypeAsString() != TEXT("SCkFlexBox")) { return false; }
    const TSharedRef<SCkFlexBox> ReloadedPanel = StaticCastSharedRef<SCkFlexBox>(ReloadedLeft);
    const FArrangedChildren ReloadedGeometry = Arrange(ReloadedPanel, {200.0f, 60.0f});
    TestEqual(TEXT("Changed stylesheet changes real arranged gap"), ReloadedGeometry[1].Geometry.GetAbsolutePosition().X,
        ReloadedGeometry[0].Geometry.GetAbsolutePosition().X + ReloadedGeometry[0].Geometry.GetLocalSize().X + 11.0f);
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiAuthoringView_Rejects,
    "Ck.UiAuthoring.View.RejectsInvalidAtomically",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiAuthoringView_Rejects::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_view;
    auto Calls = 0;
    const auto LeftNative = SNew(SSpacer);
    const auto RightNative = SNew(SSpacer);
    auto Bindings = FCkUiView::FNativeBindings{{TEXT("left"), LeftNative}, {TEXT("right"), RightNative}};
    auto Actions = FCkUiView::FActions{{TEXT("apply"), FSimpleDelegate::CreateLambda([&Calls] { ++Calls; })}};
    const auto View = FCkUiView::Create(MoveTemp(Bindings), MoveTemp(Actions));
    View->GetRegion(TEXT("left"));
    View->GetRegion(TEXT("right"));
    TestTrue(TEXT("Baseline loads"), View->TryReload(Markup(), Styles()).Succeeded);
    const TSharedRef<SWidget> OldLeft = RegionContent(View, TEXT("left"));
    const TSharedRef<SWidget> OldRight = RegionContent(View, TEXT("right"));
    const int64 Revision = View->GetRevision();
    const auto RootSizing = View->TryReload(Markup(), Styles() + TEXT(" .root { width: 100px; }"), TEXT("RootSizing"));
    TestFalse(TEXT("Root sizing cannot silently ignore actual native mount allocation"), RootSizing.Succeeded);
    TestTrue(TEXT("Root sizing rejection explains native mount ownership"), HasError(RootSizing, TEXT("native mount")));
    TestEqual(TEXT("Root sizing rejection retains revision"), View->GetRevision(), Revision);
    TestTrue(TEXT("Root sizing rejection retains mounted native tree"), RegionContent(View, TEXT("left")) == OldLeft);
    const auto ExpectReject = [this, &View, &OldLeft, &OldRight, Revision, &Calls](const FString& Name, const FString& BadMarkup, const FString& Needle)
    {
        const FCkUiLoadResult Result = View->TryReload(BadMarkup, Styles(), Name);
        TestFalse(*Name, Result.Succeeded);
        TestTrue(*(Name + TEXT(" reports expected error")), HasError(Result, Needle));
        TestEqual(*(Name + TEXT(" keeps revision")), View->GetRevision(), Revision);
        TestTrue(*(Name + TEXT(" keeps left child")), RegionContent(View, TEXT("left")) == OldLeft);
        TestTrue(*(Name + TEXT(" keeps right child")), RegionContent(View, TEXT("right")) == OldRight);
        TestEqual(*(Name + TEXT(" invokes no action")), Calls, 0);
    };
    ExpectReject(TEXT("Unknown action"), Markup().Replace(TEXT("action=\"apply\""), TEXT("action=\"missing\"")), TEXT("missing action"));
    ExpectReject(TEXT("Unknown binding"), Markup(TEXT("unknown")), TEXT("unknown binding"));
    ExpectReject(TEXT("Missing region"), TEXT("<ui version=\"1\"><region name=\"left\"><text id=\"x\">x</text></region></ui>"), TEXT("missing requested region"));
    ExpectReject(TEXT("Duplicate binding"), Markup(TEXT("left"), TEXT("left")), TEXT("binding"));
    ExpectReject(TEXT("Same id binding swap"), Markup(TEXT("right"), TEXT("left")), TEXT("cannot change binding"));
    const FString ReplacedNativeId = TEXT("<ui version=\"1\"><region name=\"left\"><row id=\"left-root\"><text id=\"left-native\">replacement</text><native id=\"moved-native\" bind=\"left\"/><text id=\"left-label\">Left label</text><button id=\"left-action\" action=\"apply\">Apply</button></row></region><region name=\"right\"><column id=\"right-root\"><native id=\"right-native\" bind=\"right\"/></column></region></ui>");
    ExpectReject(TEXT("Native id replaced and binding moved"), ReplacedNativeId, TEXT("native id"));

    const auto AliasedNative = SNew(SSpacer);
    const auto AliasedView = FCkUiView::Create({{TEXT("first"), AliasedNative}, {TEXT("second"), AliasedNative}});
    AliasedView->GetRegion(TEXT("only"));
    const FString AliasedMarkup = TEXT("<ui version=\"1\"><region name=\"only\"><row id=\"root\"><native id=\"first-id\" bind=\"first\"/><native id=\"second-id\" bind=\"second\"/></row></region></ui>");
    const FCkUiLoadResult AliasedResult = AliasedView->TryReload(AliasedMarkup, TEXT(""), TEXT("AliasedNative"));
    TestFalse(TEXT("One native widget cannot satisfy two binding keys"), AliasedResult.Succeeded);
    TestTrue(TEXT("Aliased binding rejection reports an error"), !AliasedResult.Errors.IsEmpty());
    TestEqual(TEXT("Aliased binding rejection publishes no revision"), AliasedView->GetRevision(), int64{0});

    const auto Parent = SNew(SBox)[SNew(SSpacer)];
    const TSharedRef<SWidget> ParentedNative = Parent->GetChildren()->GetChildAt(0);
    const auto ParentedView = FCkUiView::Create({{TEXT("native"), ParentedNative}});
    ParentedView->GetRegion(TEXT("only"));
    const FString ParentedMarkup = TEXT("<ui version=\"1\"><region name=\"only\"><column id=\"root\"><native id=\"native-id\" bind=\"native\"/></column></region></ui>");
    const FCkUiLoadResult ParentedResult = ParentedView->TryReload(ParentedMarkup, TEXT(""), TEXT("AlreadyParentedNative"));
    TestFalse(TEXT("Already parented native is rejected before commit"), ParentedResult.Succeeded);
    TestTrue(TEXT("Already parented rejection reports an error"), !ParentedResult.Errors.IsEmpty());
    TestEqual(TEXT("Already parented rejection publishes no revision"), ParentedView->GetRevision(), int64{0});
    TestTrue(TEXT("Already parented rejection preserves original parent child"), Parent->GetChildren()->GetChildAt(0) == ParentedNative);
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiAuthoringView_Lifetime,
    "Ck.UiAuthoring.View.StrongCallbacksReleaseWithView",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiAuthoringView_Lifetime::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_view;
    TWeakPtr<FCkUiView> WeakView;
    TWeakPtr<SWidget> WeakNative;
    {
        const auto Native = SNew(SSpacer);
        WeakNative = Native;
        const auto View = FCkUiView::Create({{TEXT("native"), Native}}, {{TEXT("apply"), FSimpleDelegate::CreateLambda([Native] {})}});
        WeakView = View;
        View->GetRegion(TEXT("only"));
        const FString Single = TEXT("<ui version=\"1\"><region name=\"only\"><column id=\"root\"><native id=\"native-id\" bind=\"native\"/><button id=\"apply-id\" action=\"apply\">Apply</button></column></region></ui>");
        TestTrue(TEXT("Lifetime fixture loads"), View->TryReload(Single, TEXT(""), TEXT("UiViewLifetime")).Succeeded);
    }
    TestFalse(TEXT("View is released after owning scope"), WeakView.IsValid());
    TestFalse(TEXT("Native widget is released with view and bindings"), WeakNative.IsValid());
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiAuthoringView_Focus,
    "Ck.UiAuthoring.View.PreservesNativeAndExternalFocus",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiAuthoringView_Focus::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_view;
    if (!FSlateApplication::IsInitialized())
    {
        AddError(TEXT("Focus retention requires an initialized Slate application."));
        return false;
    }

    FSlateApplication& Slate = FSlateApplication::Get();
    FSlateWindowScope Windows{Slate};
    const auto NativeInput = SNew(SEditableText).Text(FText::FromString(TEXT("native")));
    const auto View = FCkUiView::Create({{TEXT("input"), NativeInput}});
    const TSharedRef<SWidget> Region = View->GetRegion(TEXT("only"));
    const auto ExternalInput = SNew(SEditableText).Text(FText::FromString(TEXT("external")));
    const auto ViewWindow = SNew(SWindow).AutoCenter(EAutoCenter::None).ClientSize(FVector2D{320.0f, 120.0f})
        .CreateTitleBar(false).HasCloseButton(false).FocusWhenFirstShown(false)
        [SNew(SVerticalBox)
            + SVerticalBox::Slot()[Region]
            + SVerticalBox::Slot()[ExternalInput]];
    Windows.Add(ViewWindow);

    const FString Initial = TEXT("<ui version=\"1\"><region name=\"only\"><column id=\"root\"><native id=\"input-id\" bind=\"input\"/></column></region></ui>");
    const FString Reloaded = TEXT("<ui version=\"1\"><region name=\"only\"><column id=\"root\"><native id=\"input-id\" bind=\"input\"/><text id=\"added\">Reloaded</text></column></region></ui>");
    const FCkUiLoadResult Loaded = View->TryReload(Initial, TEXT(""), TEXT("UiViewFocusInitial"));
    if (!TestTrue(TEXT("Focus fixture document loads"), Loaded.Succeeded)) { return false; }
    if (!TestTrue(TEXT("Native editable text receives real Slate focus"), Slate.SetKeyboardFocus(NativeInput, EFocusCause::SetDirectly))) { return false; }
    TestTrue(TEXT("Native input is the exact focused widget before reload"), Slate.GetUserFocusedWidget(0) == NativeInput);
    const TSharedRef<SWidget> OldAuthoredRoot = RegionContent(View, TEXT("only"));
    TestTrue(TEXT("Old authored root contains focused native input before reload"), Slate.HasUserFocusedDescendants(OldAuthoredRoot, 0));
    const FString NativeTextBeforeReload = NativeInput->GetText().ToString();
    const FCkUiLoadResult NativeReload = View->TryReload(Reloaded, TEXT(""), TEXT("UiViewFocusNativeReload"));
    TestTrue(TEXT("Focused-native reload succeeds"), NativeReload.Succeeded);
    TestTrue(TEXT("Focused native input retains exact focus across reload"), Slate.GetUserFocusedWidget(0) == NativeInput);
    TestEqual(TEXT("Focused native input preserves text across normal focus cycle"), NativeInput->GetText().ToString(), NativeTextBeforeReload);
    const TSharedRef<SWidget> NewAuthoredRoot = RegionContent(View, TEXT("only"));
    TestTrue(TEXT("Focused reload replaces the authored root"), NewAuthoredRoot != OldAuthoredRoot);
    TestTrue(TEXT("Focused native input is descended from new authored root"), Slate.HasUserFocusedDescendants(NewAuthoredRoot, 0));
    TestFalse(TEXT("Focused native input is no longer descended from held old authored root"), Slate.HasUserFocusedDescendants(OldAuthoredRoot, 0));

    if (!TestTrue(TEXT("External editable text receives real Slate focus"), Slate.SetKeyboardFocus(ExternalInput, EFocusCause::SetDirectly))) { return false; }
    TestTrue(TEXT("External input is exact focused widget before reload"), Slate.GetUserFocusedWidget(0) == ExternalInput);
    const FCkUiLoadResult ExternalReload = View->TryReload(Initial, TEXT(""), TEXT("UiViewFocusExternalReload"));
    TestTrue(TEXT("External-focus reload succeeds"), ExternalReload.Succeeded);
    TestTrue(TEXT("Reload does not steal focus from unrelated window"), Slate.GetUserFocusedWidget(0) == ExternalInput);
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiAuthoringView_DataBindings,
    "Ck.UiAuthoring.View.DataBindingsAndSearchRetention",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiAuthoringView_DataBindings::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_view;
    if (!FSlateApplication::IsInitialized())
    {
        AddError(TEXT("Search focus retention requires an initialized Slate application."));
        return false;
    }

    FString Query = TEXT("initial query");
    FString AlternateQuery = TEXT("alternate query");
    FString Summary = TEXT("Initial summary");
    bool bHasResults = true;
    int32 TextChangedCalls = 0;
    auto FirstBrush = FSlateBrush{};
    FirstBrush.ImageSize = FVector2D{13.0f, 7.0f};
    auto SecondBrush = FSlateBrush{};
    SecondBrush.ImageSize = FVector2D{29.0f, 11.0f};
    const FSlateBrush* Thumbnail = &FirstBrush;
    auto Data = FCkUiView::FDataBindings{};
    Data.Text.Add(TEXT("query"), TAttribute<FText>::CreateLambda([&Query] { return FText::FromString(Query); }));
    Data.Text.Add(TEXT("alternate"), TAttribute<FText>::CreateLambda([&AlternateQuery] { return FText::FromString(AlternateQuery); }));
    Data.Text.Add(TEXT("summary"), TAttribute<FText>::CreateLambda([&Summary] { return FText::FromString(Summary); }));
    Data.TextChanged.Add(TEXT("query"), FOnTextChanged::CreateLambda([&Query, &TextChangedCalls](const FText& InText)
    {
        Query = InText.ToString();
        ++TextChangedCalls;
    }));
    Data.TextChanged.Add(TEXT("alternate"), FOnTextChanged::CreateLambda([&AlternateQuery](const FText& InText)
    {
        AlternateQuery = InText.ToString();
    }));
    Data.Images.Add(TEXT("thumbnail"), TAttribute<const FSlateBrush*>::CreateLambda([&Thumbnail] { return Thumbnail; }));
    Data.Visibility.Add(TEXT("has-results"), TAttribute<bool>::CreateLambda([&bHasResults] { return bHasResults; }));
    auto NativeBindings = FCkUiView::FNativeBindings{};
    auto Actions = FCkUiView::FActions{};
    auto Tokens = FCkUiView::FTokens{};
    const TSharedRef<FCkUiView> View = FCkUiView::Create(MoveTemp(NativeBindings), MoveTemp(Actions), MoveTemp(Tokens), FSlateFontInfo{}, MoveTemp(Data));
    const TSharedRef<SWidget> Region = View->GetRegion(TEXT("only"));

    FSlateApplication& Slate = FSlateApplication::Get();
    FSlateWindowScope Windows{Slate};
    const TSharedRef<SEditableText> ExternalInput = SNew(SEditableText).Text(FText::FromString(TEXT("external")));
    const TSharedRef<SWindow> Window = SNew(SWindow).AutoCenter(EAutoCenter::None).ClientSize(FVector2D{320.0f, 120.0f})
        .CreateTitleBar(false).HasCloseButton(false).FocusWhenFirstShown(false)
        [SNew(SVerticalBox)
            + SVerticalBox::Slot()[Region]
            + SVerticalBox::Slot()[ExternalInput]];
    Windows.Add(Window);

    const FCkUiLoadResult Loaded = View->TryReload(DataMarkup(), TEXT(""), TEXT("UiViewDataInitial"));
    if (!TestTrue(TEXT("Data-bound document loads"), Loaded.Succeeded)) { return false; }
    TestEqual(TEXT("Initial load does not invoke the search text-changed callback"), TextChangedCalls, 0);
    const TSharedRef<SWidget> InitialRoot = RegionContent(View, TEXT("only"));
    InitialRoot->SlatePrepass(1.0f);
    TSharedPtr<SWidget> SearchWidget = FindFirstType(InitialRoot, TEXT("SSearchBox"));
    const TSharedPtr<SWidget> ImageWidget = FindTagged(InitialRoot, TEXT("thumbnail"));
    const TSharedPtr<SScrollBox> ScrollWidget = View->GetScroll(TEXT("results"));
    const TSharedPtr<SWidget> ScrollMount = FindTagged(InitialRoot, TEXT("results"));
    const TSharedPtr<SWidget> SummaryWidget = FindTagged(InitialRoot, TEXT("summary"));
    if (!TestTrue(TEXT("Search uses real SSearchBox"), SearchWidget.IsValid())
        || !TestTrue(TEXT("Tagged image uses real SImage"), ImageWidget.IsValid())
        || !TestTrue(TEXT("Scroll uses real SScrollBox and an authored mount"), ScrollWidget.IsValid() && ScrollMount.IsValid())
        || !TestTrue(TEXT("Bound summary text is tagged"), SummaryWidget.IsValid())) { return false; }
    if (ImageWidget->GetTypeAsString() != TEXT("SImage") || SummaryWidget->GetTypeAsString() != TEXT("SCkFlexText"))
    {
        AddError(TEXT("Bound image and scroll text must expose their expected Slate widget types."));
        return false;
    }
    TSharedPtr<SSearchBox> Search = StaticCastSharedPtr<SSearchBox>(SearchWidget);
    const TSharedPtr<SImage> Image = StaticCastSharedPtr<SImage>(ImageWidget);
    const TSharedPtr<SCkFlexText> SummaryText = StaticCastSharedPtr<SCkFlexText>(SummaryWidget);
    TSharedPtr<SWidget> SearchAsWidget = Search;
    TestEqual(TEXT("Bound search getter supplies initial value"), Search->GetText().ToString(), Query);
    TestEqual(TEXT("Bound text getter supplies initial value"), SummaryText->GetText().ToString(), Summary);
    Image->SlatePrepass(1.0f);
    TestTrue(TEXT("Bound image getter supplies initial size"), Image->GetDesiredSize().Equals(FVector2D{FirstBrush.ImageSize}));
    TestTrue(TEXT("Bound visibility getter supplies initial visibility"), ScrollMount->GetVisibility() == EVisibility::Visible);

    Query = TEXT("external update");
    TestEqual(TEXT("Bound search getter updates without reload"), Search->GetText().ToString(), Query);

    Summary = TEXT("Updated summary");
    Thumbnail = &SecondBrush;
    bHasResults = false;
    InitialRoot->SlatePrepass(1.0f);
    TestEqual(TEXT("Bound text updates without reload"), SummaryText->GetText().ToString(), Summary);
    Image->Invalidate(EInvalidateWidgetReason::Layout);
    Image->SlatePrepass(1.0f);
    TestTrue(TEXT("Bound image updates without reload"), Image->GetDesiredSize().Equals(FVector2D{SecondBrush.ImageSize}));
    // Collapsing the authored mount intentionally stops Slate prepass from updating descendants.
    // Check the layout participant, rather than the cached visibility of its native child.
    TestTrue(TEXT("Bound visibility updates without reload"), ScrollMount->GetVisibility() == EVisibility::Collapsed);
    const auto RootPanel = StaticCastSharedRef<SCkFlexBox>(InitialRoot);
    const auto HasScrollMount = [&ScrollMount](const FArrangedChildren& InChildren)
    {
        for (int32 Index = 0; Index < InChildren.Num(); ++Index)
        { if (InChildren[Index].Widget == ScrollMount) { return true; } }
        return false;
    };
    TestFalse(TEXT("Collapsed scroll mount leaves actual arranged layout"), HasScrollMount(Arrange(RootPanel, FVector2D{320.0f, 120.0f})));
    bHasResults = true;
    TestTrue(TEXT("Restored scroll mount returns to actual arranged layout"), HasScrollMount(Arrange(RootPanel, FVector2D{320.0f, 120.0f})));

    Search->SetText(FText::FromString(TEXT("typed query")));
    TestEqual(TEXT("Search SetText invokes the authored text-changed callback exactly once"), TextChangedCalls, 1);
    TestEqual(TEXT("Search text-changed callback updates its backing value"), Query, FString(TEXT("typed query")));
    TestEqual(TEXT("Search retains the callback-updated text"), Search->GetText().ToString(), Query);
    if (!TestTrue(TEXT("Search receives real Slate focus"), Slate.SetKeyboardFocus(Search.ToSharedRef(), EFocusCause::SetDirectly))) { return false; }
    TSharedPtr<SWidget> SearchFocusedLeaf = Slate.GetUserFocusedWidget(0);
    if (!TestTrue(TEXT("Search focus resolves to a real focused leaf"), SearchFocusedLeaf.IsValid())) { return false; }
    TestTrue(TEXT("Search owns the focused leaf before reload"), SearchFocusedLeaf == SearchAsWidget || Slate.HasUserFocusedDescendants(Search.ToSharedRef(), 0));

    const int64 AcceptedRevision = View->GetRevision();
    const FCkUiLoadResult Accepted = View->TryReload(DataMarkup(true), TEXT(""), TEXT("UiViewDataAcceptedReload"));
    if (!TestTrue(TEXT("Accepted data document reload succeeds"), Accepted.Succeeded)) { return false; }
    const TSharedRef<SWidget> AcceptedRoot = RegionContent(View, TEXT("only"));
    TestTrue(TEXT("Accepted reload replaces authored root"), AcceptedRoot != InitialRoot);
    TestTrue(TEXT("Accepted reload retains exact search widget identity"), FindFirstType(AcceptedRoot, TEXT("SSearchBox")) == SearchAsWidget);
    TestEqual(TEXT("Accepted reload retains search text"), Search->GetText().ToString(), Query);
    TestTrue(TEXT("Accepted reload restores the exact search focused leaf"), Slate.GetUserFocusedWidget(0) == SearchFocusedLeaf);
    TestTrue(TEXT("Search focus descends from accepted root"), Slate.HasUserFocusedDescendants(AcceptedRoot, 0));

    TextChangedCalls = 0;
    const auto ExpectRejectedBinding = [this, &Slate, &View, &Search, &SearchAsWidget, &AcceptedRoot, &Query, &TextChangedCalls, &SearchFocusedLeaf, AcceptedRevision](const FString& InName, const FString& InMarkup, const FString& InNeedle)
    {
        const FCkUiLoadResult Rejected = View->TryReload(InMarkup, TEXT(""), InName);
        TestFalse(*InName, Rejected.Succeeded);
        TestTrue(*(InName + TEXT(" reports its binding error")), HasError(Rejected, InNeedle));
        TestEqual(*(InName + TEXT(" retains revision")), View->GetRevision(), AcceptedRevision + 1);
        TestTrue(*(InName + TEXT(" retains authored root")), RegionContent(View, TEXT("only")) == AcceptedRoot);
        TestTrue(*(InName + TEXT(" retains exact search identity")), FindFirstType(AcceptedRoot, TEXT("SSearchBox")) == SearchAsWidget);
        TestEqual(*(InName + TEXT(" retains search text")), Search->GetText().ToString(), Query);
        TestTrue(*(InName + TEXT(" retains search focus")), Slate.GetUserFocusedWidget(0) == SearchFocusedLeaf);
        TestEqual(*(InName + TEXT(" performs no text write")), TextChangedCalls, 0);
    };
    ExpectRejectedBinding(TEXT("Missing search callback binding"), DataMarkup(true).Replace(TEXT("bind=\"query\""), TEXT("bind=\"summary\"")), TEXT("requires both"));
    ExpectRejectedBinding(TEXT("Search id binding change"), DataMarkup(true).Replace(TEXT("bind=\"query\""), TEXT("bind=\"alternate\"")), TEXT("cannot change binding"));
    ExpectRejectedBinding(TEXT("Search id kind change"), DataMarkup(true).Replace(TEXT("<search id=\"query\" bind=\"query\" placeholder=\"Filter\"/>"), TEXT("<text id=\"query\">replacement</text>")), TEXT("cannot change kind"));
    ExpectRejectedBinding(TEXT("Wrong image binding type"), DataMarkup(true).Replace(TEXT("bind=\"thumbnail\""), TEXT("bind=\"summary\"")), TEXT("missing image binding"));
    ExpectRejectedBinding(TEXT("Missing visibility binding"), DataMarkup(true).Replace(TEXT("visible=\"has-results\""), TEXT("visible=\"missing-visible\"")), TEXT("missing visibility binding"));
    ExpectRejectedBinding(TEXT("Late invalid candidate search omission"), DataMarkup(true, false).Replace(TEXT("visible=\"has-results\""), TEXT("visible=\"missing-visible\"")), TEXT("missing visibility binding"));

    const TWeakPtr<SSearchBox> RemovedSearch = Search;
    const FCkUiLoadResult Removed = View->TryReload(DataMarkup(true, false), TEXT(""), TEXT("UiViewDataSearchRemoved"));
    if (!TestTrue(TEXT("Search omission accepts a valid retained-document update"), Removed.Succeeded)) { return false; }
    const TSharedRef<SWidget> RemovedRoot = RegionContent(View, TEXT("only"));
    TestTrue(TEXT("Search omission replaces the authored root"), RemovedRoot != AcceptedRoot);
    TestFalse(TEXT("Search omission leaves no search in the mounted tree"), FindFirstType(RemovedRoot, TEXT("SSearchBox")).IsValid());
    TestFalse(TEXT("Removing the focused search clears focus"), Slate.GetUserFocusedWidget(0).IsValid());
    TestFalse(TEXT("Held pre-removal root no longer owns focused search"), Slate.HasUserFocusedDescendants(AcceptedRoot, 0));
    SearchFocusedLeaf.Reset();
    SearchAsWidget.Reset();
    SearchWidget.Reset();
    Search.Reset();
    TestFalse(TEXT("View releases the omitted search once external references release"), RemovedSearch.IsValid());

    Query = TEXT("current model after removal");
    TextChangedCalls = 0;
    const FCkUiLoadResult Readded = View->TryReload(DataMarkup(true), TEXT(""), TEXT("UiViewDataSearchReadded"));
    if (!TestTrue(TEXT("Removed search can be re-added"), Readded.Succeeded)) { return false; }
    const TSharedRef<SWidget> ReaddedRoot = RegionContent(View, TEXT("only"));
    const TSharedPtr<SWidget> ReaddedSearchWidget = FindFirstType(ReaddedRoot, TEXT("SSearchBox"));
    if (!TestTrue(TEXT("Re-added document creates a new search widget"), ReaddedSearchWidget.IsValid())) { return false; }
    const TSharedPtr<SSearchBox> ReaddedSearch = StaticCastSharedPtr<SSearchBox>(ReaddedSearchWidget);
    TestEqual(TEXT("Re-added search reads the current model value"), ReaddedSearch->GetText().ToString(), Query);
    TestEqual(TEXT("Re-added search does not synthesize an initial text-changed callback"), TextChangedCalls, 0);

    if (!TestTrue(TEXT("External input receives focus before data reload"), Slate.SetKeyboardFocus(ExternalInput, EFocusCause::SetDirectly))) { return false; }
    TestTrue(TEXT("External input is exact focused widget"), Slate.GetUserFocusedWidget(0) == ExternalInput);
    const FCkUiLoadResult ExternalReload = View->TryReload(DataMarkup(), TEXT(""), TEXT("UiViewDataExternalFocus"));
    TestTrue(TEXT("External-focus data reload succeeds"), ExternalReload.Succeeded);
    TestTrue(TEXT("Data reload does not steal unrelated focus"), Slate.GetUserFocusedWidget(0) == ExternalInput);
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiAuthoringView_FocusRemoval,
    "Ck.UiAuthoring.View.ClearsRemovedStatelessFocus",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiAuthoringView_FocusRemoval::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_view;
    if (!FSlateApplication::IsInitialized())
    {
        AddError(TEXT("Authored focus removal requires an initialized Slate application."));
        return false;
    }

    FSlateApplication& Slate = FSlateApplication::Get();
    FSlateWindowScope Windows{Slate};
    const TSharedRef<SEditableText> ExternalInput = SNew(SEditableText).Text(FText::FromString(TEXT("external")));
    const TWeakPtr<SEditableText> WeakExternalInput = ExternalInput;
    const TSharedRef<int32> RedirectCalls = MakeShared<int32>(0);
    auto Registry = FCkUiWidgetRegistry{};
    auto Registration = FCkUiCustomWidgetRegistration{};
    Registration.Schema.Tag = TEXT("redirect");
    Registration.Factory = [WeakExternalInput, RedirectCalls](const FCkUiCustomWidgetArguments&, FString&) -> TSharedPtr<SWidget>
    {
        const TSharedRef<SButton> Button = SNew(SButton).Tag(FName(TEXT("custom-button")))[SNew(STextBlock).Text(FText::FromString(TEXT("Custom")))];
        Button->SetOnFocusLost(FSimpleDelegate::CreateLambda([WeakExternalInput, RedirectCalls]()
        {
            ++*RedirectCalls;
            const TSharedPtr<SEditableText> External = WeakExternalInput.Pin();
            if (External.IsValid() && FSlateApplication::IsInitialized())
            { FSlateApplication::Get().SetKeyboardFocus(External, EFocusCause::SetDirectly); }
        }));
        return Button;
    };
    if (!TestTrue(TEXT("Stateless focus fixture registration succeeds"), Registry.Register(MoveTemp(Registration)).Succeeded)) { return false; }
    const TSharedRef<FCkUiView> View = FCkUiView::Create({}, {{TEXT("noop"), FSimpleDelegate::CreateLambda([] {})}}, {}, FSlateFontInfo{}, {}, Registry.CreateSnapshot());
    const TSharedRef<SWidget> Region = View->GetRegion(TEXT("only"));
    const TSharedRef<SWindow> Window = SNew(SWindow).AutoCenter(EAutoCenter::None).ClientSize(FVector2D{320.0f, 120.0f})
        .CreateTitleBar(false).HasCloseButton(false).FocusWhenFirstShown(false)
        [SNew(SVerticalBox)
            + SVerticalBox::Slot()[Region]
            + SVerticalBox::Slot()[ExternalInput]];
    Windows.Add(Window);

    if (!TestTrue(TEXT("Ordinary and stateless custom focus fixture loads"), View->TryReload(FocusMarkup(true, true), TEXT(""), TEXT("UiViewFocusRemovalInitial")).Succeeded)) { return false; }
    const TSharedRef<SWidget> InitialRoot = RegionContent(View, TEXT("only"));
    const TSharedPtr<SWidget> Ordinary = FindTagged(InitialRoot, TEXT("ordinary"));
    if (!TestTrue(TEXT("Fixture contains ordinary authored button"), Ordinary.IsValid())
        || !TestTrue(TEXT("Ordinary authored button receives focus"), Slate.SetKeyboardFocus(Ordinary.ToSharedRef(), EFocusCause::SetDirectly))) { return false; }
    TestTrue(TEXT("Old authored root contains ordinary focused leaf"), Slate.HasUserFocusedDescendants(InitialRoot, 0));

    if (!TestTrue(TEXT("Removing focused ordinary authored button succeeds"), View->TryReload(FocusMarkup(false, true), TEXT(""), TEXT("UiViewFocusRemovalOrdinary")).Succeeded)) { return false; }
    const TSharedRef<SWidget> CustomRoot = RegionContent(View, TEXT("only"));
    TestTrue(TEXT("Removing ordinary button replaces authored root"), CustomRoot != InitialRoot);
    TestFalse(TEXT("Removing ordinary authored leaf clears focus despite held old root"), Slate.GetUserFocusedWidget(0).IsValid());
    TestFalse(TEXT("Held old root no longer claims a focused descendant"), Slate.HasUserFocusedDescendants(InitialRoot, 0));

    const TSharedPtr<SWidget> Custom = FindTagged(CustomRoot, TEXT("custom-button"));
    if (!TestTrue(TEXT("Fixture contains stateless custom output"), Custom.IsValid())
        || !TestTrue(TEXT("Stateless custom output receives focus"), Slate.SetKeyboardFocus(Custom.ToSharedRef(), EFocusCause::SetDirectly))) { return false; }
    if (!TestTrue(TEXT("Removing focused stateless custom output succeeds"), View->TryReload(FocusMarkup(false, false), TEXT(""), TEXT("UiViewFocusRemovalCustom")).Succeeded)) { return false; }
    const TSharedRef<SWidget> RemovedRoot = RegionContent(View, TEXT("only"));
    TestTrue(TEXT("Removing stateless custom output replaces authored root"), RemovedRoot != CustomRoot);
    TestEqual(TEXT("Custom focus-loss redirect runs once"), *RedirectCalls, 1);
    TestTrue(TEXT("Focus-loss redirect wins over stale focus restoration"), Slate.GetUserFocusedWidget(0) == ExternalInput);
    TestFalse(TEXT("Held custom root no longer claims focused descendants"), Slate.HasUserFocusedDescendants(CustomRoot, 0));

    if (!TestTrue(TEXT("Reload after external focus succeeds"), View->TryReload(FocusMarkup(true, false), TEXT(""), TEXT("UiViewFocusRemovalExternal")).Succeeded)) { return false; }
    TestTrue(TEXT("Reload does not steal unrelated external focus"), Slate.GetUserFocusedWidget(0) == ExternalInput);
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiAuthoringView_Files,
    "Ck.UiAuthoring.View.FilePollingRecovery",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiAuthoringView_Files::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_view;
    const FString Directory = FPaths::ProjectSavedDir() / TEXT("Automation/UiAuthoringView") / FGuid::NewGuid().ToString(EGuidFormats::Digits);
    const FString MarkupPath = Directory / TEXT("view.html");
    const FString StylesheetPath = Directory / TEXT("view.css");
    IFileManager::Get().MakeDirectory(*Directory, true);
    const auto Native = SNew(SSpacer);
    const auto View = FCkUiView::Create({{TEXT("native"), Native}});
    View->GetRegion(TEXT("only"));
    const FString Single = TEXT("<ui version=\"1\"><region name=\"only\"><column id=\"root\" class=\"root\"><native id=\"native-id\" bind=\"native\"/></column></region></ui>");
    TestTrue(TEXT("Writes initial markup"), FFileHelper::SaveStringToFile(Single, *MarkupPath));
    TestTrue(TEXT("Writes initial stylesheet"), FFileHelper::SaveStringToFile(TEXT(".root { }"), *StylesheetPath));
    TestTrue(TEXT("Initial file load succeeds"), View->ReloadFiles(MarkupPath, StylesheetPath).Succeeded);
    const int64 Revision = View->GetRevision();
    TestFalse(TEXT("Unchanged file pair does not reload"), View->PollFiles());
    TestEqual(TEXT("Unchanged file pair keeps revision"), View->GetRevision(), Revision);
    TestTrue(TEXT("Changed valid stylesheet is detected"), FFileHelper::SaveStringToFile(TEXT(".root { gap: 2px; }"), *StylesheetPath));
    TestTrue(TEXT("Poll reloads changed valid stylesheet"), View->PollFiles());
    TestTrue(TEXT("Changed valid stylesheet succeeds"), View->GetLastResult().Succeeded);
    TestEqual(TEXT("Changed valid stylesheet advances revision"), View->GetRevision(), Revision + 1);
    TestTrue(TEXT("Malformed edit is detected"), FFileHelper::SaveStringToFile(TEXT(".root { gap: nonsense; }"), *StylesheetPath));
    TestTrue(TEXT("Poll notices malformed edit"), View->PollFiles());
    TestFalse(TEXT("Malformed edit retains last valid view"), View->GetLastResult().Succeeded);
    TestEqual(TEXT("Malformed edit keeps revision"), View->GetRevision(), Revision + 1);
    TestTrue(TEXT("Corrected edit is detected"), FFileHelper::SaveStringToFile(TEXT(".root { gap: 9px; }"), *StylesheetPath));
    TestTrue(TEXT("Poll notices corrected edit"), View->PollFiles());
    TestTrue(TEXT("Corrected edit succeeds"), View->GetLastResult().Succeeded);
    TestEqual(TEXT("Corrected edit advances revision"), View->GetRevision(), Revision + 2);
    IFileManager::Get().Delete(*StylesheetPath, false, true);
    TestTrue(TEXT("Missing stylesheet changes observed pair"), View->PollFiles());
    TestFalse(TEXT("Missing stylesheet reports error while retaining view"), View->GetLastResult().Succeeded);
    TestTrue(TEXT("Restores last accepted stylesheet after missing-file failure"), FFileHelper::SaveStringToFile(TEXT(".root { gap: 9px; }"), *StylesheetPath));
    TestTrue(TEXT("Restored stylesheet is detected"), View->PollFiles());
    TestTrue(TEXT("Restored stylesheet succeeds"), View->GetLastResult().Succeeded);
    const int64 RecoveredRevision = View->GetRevision();
    TestFalse(TEXT("Recovered unchanged file pair does not reload"), View->PollFiles());
    TestEqual(TEXT("Recovered unchanged file pair keeps revision"), View->GetRevision(), RecoveredRevision);
    return true;
}

#endif
