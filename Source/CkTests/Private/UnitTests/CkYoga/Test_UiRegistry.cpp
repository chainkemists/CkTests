#include "CkSlateLayout/CkUiWidgetRegistry.h"
#include "CkSlateLayout/SCkUiSurface.h"
#include "Misc/AutomationTest.h"
#include "Widgets/Input/SButton.h"
#include "Widgets/Layout/SBox.h"
#include "Widgets/Text/STextBlock.h"
#include "Styling/SlateBrush.h"

#if WITH_DEV_AUTOMATION_TESTS

namespace ck_tests_ui_registry
{
    struct FFactoryStats final
    {
        int32 NoticeCalls = 0;
        int32 FailCalls = 0;
        int32 NullCalls = 0;
        int32 DiagnosticCalls = 0;
        int32 ParentedCalls = 0;
        int32 SameCalls = 0;
        bool bSawExpectedArguments = false;
        TAttribute<FText> Label;
        TAttribute<const FSlateBrush*> Thumbnail;
        TAttribute<float> Number;
        TAttribute<bool> Enabled;
    };

    auto RegionContent(const TSharedRef<FCkUiView>& InView) -> TSharedRef<SWidget>
    {
        return StaticCastSharedRef<SBox>(InView->GetRegion(TEXT("only")))->GetChildren()->GetChildAt(0);
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

    auto HasError(const FCkUiLoadResult& InResult, const FString& InNeedle) -> bool
    {
        for (const FString& Error : InResult.Errors) { if (Error.Contains(InNeedle)) { return true; } }
        return false;
    }

    auto NoticeRegistration(const TSharedRef<FFactoryStats>& InStats) -> FCkUiCustomWidgetRegistration
    {
        auto Registration = FCkUiCustomWidgetRegistration{};
        Registration.Schema.Tag = TEXT("notice");
        Registration.Schema.Properties = {
            {TEXT("message"), ECkUiCustomPropertyKind::Text, true},
            {TEXT("rank"), ECkUiCustomPropertyKind::Number, true},
            {TEXT("enabled"), ECkUiCustomPropertyKind::Bool, true},
            {TEXT("tone"), ECkUiCustomPropertyKind::Color, true},
            {TEXT("label"), ECkUiCustomPropertyKind::TextBinding, true},
            {TEXT("thumb"), ECkUiCustomPropertyKind::ImageBinding, true},
            {TEXT("value"), ECkUiCustomPropertyKind::NumberBinding, true},
            {TEXT("flag"), ECkUiCustomPropertyKind::BoolBinding, true},
            {TEXT("action"), ECkUiCustomPropertyKind::Action, true},
            {TEXT("bind"), ECkUiCustomPropertyKind::Text, false},
        };
        Registration.Factory = [InStats](const FCkUiCustomWidgetArguments& InArguments, FString& OutFailure) -> TSharedPtr<SWidget>
        {
            ++InStats->NoticeCalls;
            const FText* Message = InArguments.TextProperties.Find(TEXT("message"));
            const float* Rank = InArguments.NumberProperties.Find(TEXT("rank"));
            const bool* Enabled = InArguments.BoolProperties.Find(TEXT("enabled"));
            const FLinearColor* Tone = InArguments.ColorProperties.Find(TEXT("tone"));
            const TAttribute<FText>* Label = InArguments.TextBindings.Find(TEXT("label"));
            const TAttribute<const FSlateBrush*>* Thumbnail = InArguments.ImageBindings.Find(TEXT("thumb"));
            const TAttribute<float>* Value = InArguments.NumberBindings.Find(TEXT("value"));
            const TAttribute<bool>* Flag = InArguments.BoolBindings.Find(TEXT("flag"));
            const FSimpleDelegate* Activate = InArguments.Actions.Find(TEXT("action"));
            const FText* EmptyBind = InArguments.TextProperties.Find(TEXT("bind"));
            if (Message == nullptr || Rank == nullptr || Enabled == nullptr || Tone == nullptr || Label == nullptr || Thumbnail == nullptr || Value == nullptr || Flag == nullptr || Activate == nullptr || EmptyBind == nullptr)
            {
                OutFailure = TEXT("Notice factory did not receive typed arguments.");
                return nullptr;
            }
            InStats->bSawExpectedArguments = Message->ToString() == TEXT("Ready") && EmptyBind->IsEmpty() && Thumbnail->Get() != nullptr && *Rank == 2.5f && *Enabled
                && Tone->Equals(FLinearColor::FromSRGBColor(FColor{0x11, 0x22, 0x33, 0xff}));
            InStats->Label = *Label;
            InStats->Thumbnail = *Thumbnail;
            InStats->Number = *Value;
            InStats->Enabled = *Flag;
            const FSimpleDelegate Action = *Activate;
            const TSharedRef<SButton> Button = SNew(SButton).Tag(FName(*InArguments.Id))
                .OnClicked_Lambda([Action]() mutable { Action.ExecuteIfBound(); return FReply::Handled(); })
                [SNew(STextBlock).Text(*Label)];
            return Button;
        };
        return Registration;
    }

    auto NoticeMarkup() -> FString
    {
        return TEXT("<ui version=\"1\"><region name=\"only\"><column id=\"root\"><notice id=\"notice\" message=\"Ready\" rank=\"2.5\" enabled=\"true\" tone=\"#112233\" label-bind=\"label\" thumb-bind=\"thumb\" value-bind=\"value\" flag-bind=\"flag\" action=\"activate\" bind=\"\"/></column></region></ui>");
    }

    auto RootMarkup(const FString& InLeaf) -> FString
    {
        return FString::Printf(TEXT("<ui version=\"1\"><region name=\"only\"><column id=\"root\">%s</column></region></ui>"), *InLeaf);
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiAuthoringRegistry_Schema,
    "Ck.UiAuthoring.Registry.SchemaValidation",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiAuthoringRegistry_Schema::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_registry;
    const auto Stats = MakeShared<FFactoryStats>();
    auto Registry = FCkUiWidgetRegistry{};

    auto Empty = NoticeRegistration(Stats);
    Empty.Schema.Tag.Reset();
    TestFalse(TEXT("Empty custom tag rejects"), Registry.Register(MoveTemp(Empty)).Succeeded);

    auto Builtin = NoticeRegistration(Stats);
    Builtin.Schema.Tag = TEXT("row");
    TestFalse(TEXT("Built-in tag rejects"), Registry.Register(MoveTemp(Builtin)).Succeeded);

    for (const FString Tag : {TEXT("template"), TEXT("param"), TEXT("use")})
    {
        auto Reserved = NoticeRegistration(Stats);
        Reserved.Schema.Tag = Tag;
        TestFalse(*(Tag + TEXT(" tag is reserved for authored templates")), Registry.Register(MoveTemp(Reserved)).Succeeded);
        TestNull(*(Tag + TEXT(" rejected registration is not published")), Registry.CreateSnapshot()->Find(Tag));
    }
    auto ReferenceCollision = NoticeRegistration(Stats);
    ReferenceCollision.Schema.Tag = TEXT("reference-collision");
    ReferenceCollision.Schema.Properties = {{TEXT("message-param"), ECkUiCustomPropertyKind::Text, true}};
    TestFalse(TEXT("Parameter-reference property spelling rejects"), Registry.Register(MoveTemp(ReferenceCollision)).Succeeded);
    TestNull(TEXT("Rejected parameter-reference schema is not published"), Registry.CreateSnapshot()->Find(TEXT("reference-collision")));

    auto DuplicateProperty = NoticeRegistration(Stats);
    DuplicateProperty.Schema.Properties.Add({TEXT("message"), ECkUiCustomPropertyKind::Text, false});
    TestFalse(TEXT("Duplicate property rejects"), Registry.Register(MoveTemp(DuplicateProperty)).Succeeded);

    auto InvalidPropertyKind = NoticeRegistration(Stats);
    InvalidPropertyKind.Schema.Properties[0].Kind = static_cast<ECkUiCustomPropertyKind>(255);
    TestFalse(TEXT("Invalid property enum rejects"), Registry.Register(MoveTemp(InvalidPropertyKind)).Succeeded);

    auto GeneratedAttributeCollision = NoticeRegistration(Stats);
    GeneratedAttributeCollision.Schema.Tag = TEXT("attribute-collision");
    GeneratedAttributeCollision.Schema.Properties = {
        {TEXT("label"), ECkUiCustomPropertyKind::TextBinding, true},
        {TEXT("label-bind"), ECkUiCustomPropertyKind::Text, true},
    };
    TestFalse(TEXT("Generated binding attribute collision rejects"), Registry.Register(MoveTemp(GeneratedAttributeCollision)).Succeeded);

    TestTrue(TEXT("Lowercase notice registration succeeds"), Registry.Register(NoticeRegistration(Stats)).Succeeded);
    TestFalse(TEXT("Exact duplicate tag rejects"), Registry.Register(NoticeRegistration(Stats)).Succeeded);
    auto CaseVariant = NoticeRegistration(Stats);
    CaseVariant.Schema.Tag = TEXT("NOTICE");
    TestFalse(TEXT("Case-variant duplicate tag rejects"), Registry.Register(MoveTemp(CaseVariant)).Succeeded);
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiAuthoringRegistry_Runtime,
    "Ck.UiAuthoring.Registry.ImmutableBindingsAndAtomicFactories",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiAuthoringRegistry_Runtime::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_registry;
    const auto Stats = MakeShared<FFactoryStats>();
    auto Label = FText::FromString(TEXT("Initial label"));
    auto FirstBrush = FSlateBrush{};
    FirstBrush.ImageSize = FVector2D{16.0f, 16.0f};
    auto SecondBrush = FSlateBrush{};
    SecondBrush.ImageSize = FVector2D{32.0f, 32.0f};
    const FSlateBrush* Thumbnail = &FirstBrush;
    auto Value = 3.0f;
    auto Flag = true;
    auto ActionCalls = 0;

    auto Registry = FCkUiWidgetRegistry{};
    TestTrue(TEXT("Notice registers"), Registry.Register(NoticeRegistration(Stats)).Succeeded);
    const TSharedRef<const FCkUiWidgetRegistrySnapshot> OldSnapshot = Registry.CreateSnapshot();
    auto Data = FCkUiView::FDataBindings{};
    Data.Text.Add(TEXT("label"), TAttribute<FText>::CreateLambda([&Label]() { return Label; }));
    Data.Images.Add(TEXT("thumb"), TAttribute<const FSlateBrush*>::CreateLambda([&Thumbnail]() { return Thumbnail; }));
    Data.Number.Add(TEXT("value"), TAttribute<float>::CreateLambda([&Value]() { return Value; }));
    Data.Visibility.Add(TEXT("flag"), TAttribute<bool>::CreateLambda([&Flag]() { return Flag; }));
    auto Actions = FCkUiView::FActions{};
    Actions.Add(TEXT("activate"), FSimpleDelegate::CreateLambda([&ActionCalls]() { ++ActionCalls; }));
    const TSharedRef<FCkUiView> View = FCkUiView::Create({}, MoveTemp(Actions), {}, FSlateFontInfo{}, MoveTemp(Data), OldSnapshot);
    View->GetRegion(TEXT("only"));

    const FCkUiLoadResult Loaded = View->TryReload(NoticeMarkup(), TEXT(""), TEXT("UiRegistryNotice"));
    if (!TestTrue(TEXT("Typed custom leaf loads"), Loaded.Succeeded)) { return false; }
    const TSharedRef<SWidget> AcceptedRoot = RegionContent(View);
    TestEqual(TEXT("Accepted document increments revision"), View->GetRevision(), int64{1});
    TestEqual(TEXT("Factory receives one typed invocation"), Stats->NoticeCalls, 1);
    TestTrue(TEXT("Factory receives typed literal arguments"), Stats->bSawExpectedArguments);
    TestEqual(TEXT("Factory receives live text binding"), Stats->Label.Get().ToString(), Label.ToString());
    TestTrue(TEXT("Factory receives live image binding"), Stats->Thumbnail.Get() == Thumbnail);
    TestEqual(TEXT("Factory receives live number binding"), Stats->Number.Get(), Value);
    TestEqual(TEXT("Factory receives live bool binding"), Stats->Enabled.Get(), Flag);
    Label = FText::FromString(TEXT("Updated label"));
    Thumbnail = &SecondBrush;
    Value = 9.0f;
    Flag = false;
    TestEqual(TEXT("Text binding remains live after mount"), Stats->Label.Get().ToString(), Label.ToString());
    TestTrue(TEXT("Image binding remains live after mount"), Stats->Thumbnail.Get() == Thumbnail);
    TestEqual(TEXT("Number binding remains live after mount"), Stats->Number.Get(), Value);
    TestEqual(TEXT("Bool binding remains live after mount"), Stats->Enabled.Get(), Flag);
    const TSharedPtr<SWidget> NoticeMount = FindTagged(AcceptedRoot, TEXT("notice"));
    if (!TestTrue(TEXT("Custom factory mount retains its id"), NoticeMount.IsValid()) || !TestEqual(TEXT("Custom factory mount is an adapter wrapper"), NoticeMount->GetTypeAsString(), FString(TEXT("SBox")))) { return false; }
    const TSharedPtr<SWidget> NoticeWidget = FindFirstType(AcceptedRoot, TEXT("SButton"));
    if (!TestTrue(TEXT("Custom factory result is mounted"), NoticeWidget.IsValid())) { return false; }
    const TSharedPtr<SWidget> LabelWidget = FindFirstType(AcceptedRoot, TEXT("STextBlock"));
    if (!TestTrue(TEXT("Custom factory binds its returned text widget"), LabelWidget.IsValid())) { return false; }
    TestEqual(TEXT("Mounted custom text tracks its live binding"), StaticCastSharedPtr<STextBlock>(LabelWidget)->GetText().ToString(), Label.ToString());
    StaticCastSharedPtr<SButton>(NoticeWidget)->SimulateClick();
    TestEqual(TEXT("Custom action invokes only on click"), ActionCalls, 1);

    const auto AssertAtomicReject = [this, &View, &AcceptedRoot](const FString& InName, const FString& InMarkup)
    {
        const int64 RevisionBefore = View->GetRevision();
        const FCkUiLoadResult Result = View->TryReload(InMarkup, TEXT(""), InName);
        TestFalse(*InName, Result.Succeeded);
        TestEqual(*(InName + TEXT(" preserves revision")), View->GetRevision(), RevisionBefore);
        TestTrue(*(InName + TEXT(" preserves mounted root")), RegionContent(View) == AcceptedRoot);
    };

    const int32 CallsBeforeMalformed = Stats->NoticeCalls;
    AssertAtomicReject(TEXT("Late malformed custom property"), RootMarkup(TEXT("<notice id=\"first\" message=\"Ready\" rank=\"2.5\" enabled=\"true\" tone=\"#112233\" label-bind=\"label\" thumb-bind=\"thumb\" value-bind=\"value\" flag-bind=\"flag\" action=\"activate\"/><notice id=\"late\" invalid=\"value\"/>")));
    TestEqual(TEXT("Malformed late property invokes no factory"), Stats->NoticeCalls, CallsBeforeMalformed);
    const int32 CallsBeforeBinding = Stats->NoticeCalls;
    AssertAtomicReject(TEXT("Late missing custom binding"), RootMarkup(TEXT("<notice id=\"first\" message=\"Ready\" rank=\"2.5\" enabled=\"true\" tone=\"#112233\" label-bind=\"label\" thumb-bind=\"thumb\" value-bind=\"value\" flag-bind=\"flag\" action=\"activate\"/><notice id=\"late\" message=\"Ready\" rank=\"2.5\" enabled=\"true\" tone=\"#112233\" label-bind=\"missing\" thumb-bind=\"missing-thumb\" value-bind=\"value\" flag-bind=\"flag\" action=\"activate\"/>")));
    TestEqual(TEXT("Missing late binding invokes no factory"), Stats->NoticeCalls, CallsBeforeBinding);

    auto Later = FCkUiCustomWidgetRegistration{};
    Later.Schema.Tag = TEXT("later");
    Later.Factory = [](const FCkUiCustomWidgetArguments&, FString&) -> TSharedPtr<SWidget> { return SNew(STextBlock).Text(FText::FromString(TEXT("Later"))); };
    TestTrue(TEXT("Later type registers after old snapshot"), Registry.Register(MoveTemp(Later)).Succeeded);
    AssertAtomicReject(TEXT("Old snapshot rejects later type"), RootMarkup(TEXT("<later id=\"later\"/>")));
    const TSharedRef<const FCkUiWidgetRegistrySnapshot> NewSnapshot = Registry.CreateSnapshot();
    const TSharedRef<FCkUiView> NewView = FCkUiView::Create({}, {}, {}, FSlateFontInfo{}, {}, NewSnapshot);
    NewView->GetRegion(TEXT("only"));
    TestTrue(TEXT("New snapshot accepts later type"), NewView->TryReload(RootMarkup(TEXT("<later id=\"later\"/>")), TEXT(""), TEXT("UiRegistryNewSnapshot")).Succeeded);

    const TSharedRef<SBox> ParentedRoot = SNew(SBox);
    const TSharedRef<STextBlock> ParentedChild = SNew(STextBlock).Text(FText::FromString(TEXT("Parented")));
    ParentedRoot->SetContent(ParentedChild);
    TestTrue(TEXT("Parented factory fixture has an existing parent"), ParentedChild->GetParentWidget().Get() == &ParentedRoot.Get());
    const TSharedPtr<SWidget> SharedWidget = SNew(STextBlock).Text(FText::FromString(TEXT("Shared")));
    auto Fail = FCkUiCustomWidgetRegistration{};
    Fail.Schema.Tag = TEXT("fail");
    Fail.Factory = [Stats](const FCkUiCustomWidgetArguments&, FString& OutFailure) -> TSharedPtr<SWidget> { ++Stats->FailCalls; OutFailure = TEXT("Expected factory failure."); return nullptr; };
    auto Null = FCkUiCustomWidgetRegistration{};
    Null.Schema.Tag = TEXT("nuller");
    Null.Factory = [Stats](const FCkUiCustomWidgetArguments&, FString&) -> TSharedPtr<SWidget> { ++Stats->NullCalls; return nullptr; };
    auto Diagnostic = FCkUiCustomWidgetRegistration{};
    Diagnostic.Schema.Tag = TEXT("diagnostic");
    Diagnostic.Factory = [Stats](const FCkUiCustomWidgetArguments&, FString& OutFailure) -> TSharedPtr<SWidget>
    {
        ++Stats->DiagnosticCalls;
        OutFailure = TEXT("Expected non-empty diagnostic.");
        return SNew(STextBlock).Text(FText::FromString(TEXT("Must not mount")));
    };
    auto Parented = FCkUiCustomWidgetRegistration{};
    Parented.Schema.Tag = TEXT("parented");
    Parented.Factory = [Stats, ParentedChild](const FCkUiCustomWidgetArguments&, FString&) -> TSharedPtr<SWidget> { ++Stats->ParentedCalls; return ParentedChild; };
    auto Same = FCkUiCustomWidgetRegistration{};
    Same.Schema.Tag = TEXT("same");
    Same.Factory = [Stats, SharedWidget](const FCkUiCustomWidgetArguments&, FString&) -> TSharedPtr<SWidget> { ++Stats->SameCalls; return SharedWidget; };
    TestTrue(TEXT("Failure type registers"), Registry.Register(MoveTemp(Fail)).Succeeded);
    TestTrue(TEXT("Null type registers"), Registry.Register(MoveTemp(Null)).Succeeded);
    TestTrue(TEXT("Diagnostic type registers"), Registry.Register(MoveTemp(Diagnostic)).Succeeded);
    TestTrue(TEXT("Parented type registers"), Registry.Register(MoveTemp(Parented)).Succeeded);
    TestTrue(TEXT("Same-widget type registers"), Registry.Register(MoveTemp(Same)).Succeeded);
    const TSharedRef<const FCkUiWidgetRegistrySnapshot> FailureSnapshot = Registry.CreateSnapshot();
    const TSharedRef<FCkUiView> FailureView = FCkUiView::Create({}, {}, {}, FSlateFontInfo{}, {}, FailureSnapshot);
    FailureView->GetRegion(TEXT("only"));
    TestTrue(TEXT("Failure fixture accepts initial root"), FailureView->TryReload(RootMarkup(TEXT("<later id=\"accepted\"/>")), TEXT(""), TEXT("UiRegistryFailureInitial")).Succeeded);
    const TSharedRef<SWidget> FailureRoot = RegionContent(FailureView);
    const int64 FailureRevision = FailureView->GetRevision();
    const auto AssertFailureViewReject = [this, &FailureView, &FailureRoot, FailureRevision](const FString& InName, const FString& InMarkup)
    {
        const FCkUiLoadResult Result = FailureView->TryReload(InMarkup, TEXT(""), InName);
        TestFalse(*InName, Result.Succeeded);
        TestEqual(*(InName + TEXT(" preserves revision")), FailureView->GetRevision(), FailureRevision);
        TestTrue(*(InName + TEXT(" preserves root")), RegionContent(FailureView) == FailureRoot);
    };
    AssertFailureViewReject(TEXT("Late factory failure"), RootMarkup(TEXT("<later id=\"first\"/><fail id=\"late\"/>")));
    TestEqual(TEXT("Failing factory invoked once"), Stats->FailCalls, 1);
    AssertFailureViewReject(TEXT("Null factory output"), RootMarkup(TEXT("<nuller id=\"null\"/>")));
    TestEqual(TEXT("Null factory invoked once"), Stats->NullCalls, 1);
    AssertFailureViewReject(TEXT("Nonempty factory diagnostic rejects output"), RootMarkup(TEXT("<diagnostic id=\"diagnostic\"/>")));
    TestEqual(TEXT("Diagnostic factory invoked once"), Stats->DiagnosticCalls, 1);
    AssertFailureViewReject(TEXT("Parented factory output"), RootMarkup(TEXT("<parented id=\"parented\"/>")));
    TestEqual(TEXT("Parented factory invoked once"), Stats->ParentedCalls, 1);
    AssertFailureViewReject(TEXT("Same factory widget aliases siblings"), RootMarkup(TEXT("<column id=\"nested\"><same id=\"first\"/><same id=\"second\"/></column>")));
    TestEqual(TEXT("Same factory invoked for both siblings"), Stats->SameCalls, 2);
    TestTrue(TEXT("Fresh shared factory widget first mounts successfully"), FailureView->TryReload(RootMarkup(TEXT("<same id=\"single\"/>")), TEXT(""), TEXT("UiRegistrySameFirst")).Succeeded);
    const TSharedRef<SWidget> SameRoot = RegionContent(FailureView);
    const int64 SameRevision = FailureView->GetRevision();
    const FCkUiLoadResult Reused = FailureView->TryReload(RootMarkup(TEXT("<same id=\"single\"/>")), TEXT(""), TEXT("UiRegistrySameReuse"));
    TestFalse(TEXT("Previously mounted custom widget cannot be returned again"), Reused.Succeeded);
    TestEqual(TEXT("Previously mounted widget rejection preserves revision"), FailureView->GetRevision(), SameRevision);
    TestTrue(TEXT("Previously mounted widget rejection preserves root"), RegionContent(FailureView) == SameRoot);
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiAuthoringRegistry_Lifetime,
    "Ck.UiAuthoring.Registry.WeakFactoryOwner",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiAuthoringRegistry_Lifetime::RunTest(const FString&) -> bool
{
    struct FOwner final {};
    TSharedPtr<FOwner> Owner = MakeShared<FOwner>();
    const TWeakPtr<FOwner> WeakOwner = Owner;
    auto Registry = FCkUiWidgetRegistry{};
    auto Registration = FCkUiCustomWidgetRegistration{};
    Registration.Schema.Tag = TEXT("weak-owner");
    Registration.Factory = [WeakOwner](const FCkUiCustomWidgetArguments&, FString& OutFailure) -> TSharedPtr<SWidget>
    {
        if (!WeakOwner.IsValid()) { OutFailure = TEXT("Owner expired."); return nullptr; }
        return SNew(STextBlock).Text(FText::FromString(TEXT("Owned")));
    };
    TestTrue(TEXT("Weak-owner factory registers"), Registry.Register(MoveTemp(Registration)).Succeeded);
    const TSharedRef<const FCkUiWidgetRegistrySnapshot> Snapshot = Registry.CreateSnapshot();
    const TSharedRef<FCkUiView> View = FCkUiView::Create({}, {}, {}, FSlateFontInfo{}, {}, Snapshot);
    View->GetRegion(TEXT("only"));
    Owner.Reset();
    TestFalse(TEXT("Registry snapshot and view do not retain weak factory owner"), WeakOwner.IsValid());
    const FCkUiLoadResult Result = View->TryReload(ck_tests_ui_registry::RootMarkup(TEXT("<weak-owner id=\"weak\"/>")), TEXT(""), TEXT("UiRegistryWeakOwner"));
    TestFalse(TEXT("Expired weak factory owner rejects cleanly"), Result.Succeeded);
    TestTrue(TEXT("Expired weak factory owner reports its detached failure"), ck_tests_ui_registry::HasError(Result, TEXT("Owner expired")));
    return true;
}

#endif
