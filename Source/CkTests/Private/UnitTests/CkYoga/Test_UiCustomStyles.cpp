#include "CkSlateLayout/CkUiWidgetRegistry.h"
#include "CkSlateLayout/SCkUiSurface.h"

#include "Layout/Children.h"
#include "Misc/AutomationTest.h"
#include "Widgets/Layout/SBox.h"
#include "Widgets/Text/STextBlock.h"

#if WITH_DEV_AUTOMATION_TESTS
namespace ck_tests_ui_custom_styles
{
    struct FCustomStyleStats final
    {
        int32 FactoryCalls = 0;
        int32 PrepareCalls = 0;
        FCkUiStyle FactoryStyle;
        FCkUiStyle PreparedStyle;
    };

    class FNoopUpdate final : public ICkUiPreparedWidgetUpdate
    {
    public:
        virtual void Commit() noexcept override {}
    };

    class FRetainedProbe final : public ICkUiRetainedWidget
    {
    public:
        explicit FRetainedProbe(const TSharedRef<FCustomStyleStats>& InStats)
            : Stats(InStats), Widget(SNew(STextBlock).Text(FText::FromString(TEXT("custom-style-probe")))) {}

        virtual auto GetWidget() const -> TSharedRef<SWidget> override { return Widget.ToSharedRef(); }
        virtual auto PrepareReload(const FCkUiCustomWidgetArguments& InArguments, FString&) const -> TUniquePtr<ICkUiPreparedWidgetUpdate> override
        {
            ++Stats->PrepareCalls;
            Stats->PreparedStyle = InArguments.Style;
            return MakeUnique<FNoopUpdate>();
        }

    private:
        TSharedRef<FCustomStyleStats> Stats;
        TSharedPtr<SWidget> Widget;
    };

    auto Styles() -> TMap<FString, ECkUiCustomStyleKind>
    {
        return {
            {TEXT("-ck-number"), ECkUiCustomStyleKind::Number},
            {TEXT("-ck-length"), ECkUiCustomStyleKind::Length},
            {TEXT("-ck-color"), ECkUiCustomStyleKind::Color},
        };
    }

    auto Registration(const FString& InTag, const TSharedRef<FCustomStyleStats>& InStats, TMap<FString, ECkUiCustomStyleKind> InStyles = {}) -> FCkUiCustomWidgetRegistration
    {
        FCkUiCustomWidgetRegistration Registration;
        Registration.Schema.Tag = InTag;
        Registration.Schema.StyleProperties = MoveTemp(InStyles);
        Registration.RetainedFactory = [InStats](const FCkUiCustomWidgetArguments& InArguments, FString&) -> TSharedPtr<ICkUiRetainedWidget>
        {
            ++InStats->FactoryCalls;
            InStats->FactoryStyle = InArguments.Style;
            return MakeShared<FRetainedProbe>(InStats);
        };
        return Registration;
    }

    auto Markup(const FString& InLeaf = TEXT("<style-probe id=\"probe\" class=\"base tuned\"/>")) -> FString
    {
        return FString::Printf(TEXT("<ui version=\"1\"><region name=\"only\"><column id=\"root\">%s</column></region></ui>"), *InLeaf);
    }

    auto Stylesheet() -> FString
    {
        return TEXT(".base { -ck-number: -2.5; -ck-length: 3; -ck-color: #112233; } .tuned { -ck-number: 4.5; -ck-length: var(--length); -ck-color: var(--tone); }");
    }

    auto Tokens() -> TMap<FString, FString>
    {
        return {{TEXT("--length"), TEXT("12px")}, {TEXT("--tone"), TEXT("#AABBCCDD")}};
    }

    auto RegionContent(const TSharedRef<FCkUiView>& InView) -> TSharedRef<SWidget>
    {
        return StaticCastSharedRef<SBox>(InView->GetRegion(TEXT("only")))->GetChildren()->GetChildAt(0);
    }

    auto Leaf(const FCkUiDocument& InDocument) -> const FCkUiNode*
    {
        const FCkUiNode* Root = InDocument.Regions.Find(TEXT("only"));
        return Root != nullptr && Root->Children.Num() == 1 ? &Root->Children[0] : nullptr;
    }

    auto Value(const FCkUiStyle& InStyle, const FString& InName) -> const FCkUiCustomStyleValue*
    {
        return InStyle.CustomProperties.Find(InName);
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiCustomStyles_Registry,
    "Ck.UiAuthoring.CustomStyles.Registry",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiCustomStyles_Registry::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_custom_styles;
    const TSharedRef<FCustomStyleStats> Stats = MakeShared<FCustomStyleStats>();
    FCkUiWidgetRegistry Registry;

    auto InvalidPrefix = Registration(TEXT("bad-prefix"), Stats, {{TEXT("ck-number"), ECkUiCustomStyleKind::Number}});
    TestFalse(TEXT("Custom style requires the -ck- prefix"), Registry.Register(MoveTemp(InvalidPrefix)).Succeeded);
    TestNull(TEXT("Rejected prefix style is not published"), Registry.CreateSnapshot()->FindStyleProperty(TEXT("ck-number")));
    auto InvalidCase = Registration(TEXT("bad-case"), Stats, {{TEXT("-ck-Upper"), ECkUiCustomStyleKind::Number}});
    TestFalse(TEXT("Custom style requires lowercase name"), Registry.Register(MoveTemp(InvalidCase)).Succeeded);
    auto InvalidKind = Registration(TEXT("bad-kind"), Stats, {{TEXT("-ck-invalid"), static_cast<ECkUiCustomStyleKind>(255)}});
    TestFalse(TEXT("Custom style rejects invalid kind"), Registry.Register(MoveTemp(InvalidKind)).Succeeded);
    TestNull(TEXT("Rejected invalid kind is not published"), Registry.CreateSnapshot()->FindStyleProperty(TEXT("-ck-invalid")));

    TestTrue(TEXT("First shared custom style registers"), Registry.Register(Registration(TEXT("style-one"), Stats, {{TEXT("-ck-shared"), ECkUiCustomStyleKind::Number}})).Succeeded);
    const TSharedRef<const FCkUiWidgetRegistrySnapshot> FirstSnapshot = Registry.CreateSnapshot();
    const ECkUiCustomStyleKind* Shared = FirstSnapshot->FindStyleProperty(TEXT("-ck-shared"));
    TestTrue(TEXT("Snapshot exposes shared custom style kind"), Shared != nullptr && *Shared == ECkUiCustomStyleKind::Number);
    TestTrue(TEXT("Second tag may share the same custom style kind"), Registry.Register(Registration(TEXT("style-two"), Stats, {{TEXT("-ck-shared"), ECkUiCustomStyleKind::Number}})).Succeeded);
    auto Conflict = Registration(TEXT("style-conflict"), Stats, {{TEXT("-ck-shared"), ECkUiCustomStyleKind::Color}, {TEXT("-ck-unpublished"), ECkUiCustomStyleKind::Length}});
    TestFalse(TEXT("Conflicting shared custom style kind rejects atomically"), Registry.Register(MoveTemp(Conflict)).Succeeded);
    const TSharedRef<const FCkUiWidgetRegistrySnapshot> ConflictSnapshot = Registry.CreateSnapshot();
    TestNull(TEXT("Conflicting registration is not published"), ConflictSnapshot->Find(TEXT("style-conflict")));
    TestNull(TEXT("Conflicting registration publishes no partial custom style schema"), ConflictSnapshot->FindStyleProperty(TEXT("-ck-unpublished")));
    Shared = ConflictSnapshot->FindStyleProperty(TEXT("-ck-shared"));
    TestTrue(TEXT("Conflict preserves published custom style kind"), Shared != nullptr && *Shared == ECkUiCustomStyleKind::Number);

    TestTrue(TEXT("Later custom style registers"), Registry.Register(Registration(TEXT("style-later"), Stats, {{TEXT("-ck-later"), ECkUiCustomStyleKind::Length}})).Succeeded);
    TestNull(TEXT("Old style snapshot remains immutable"), FirstSnapshot->FindStyleProperty(TEXT("-ck-later")));
    const TSharedRef<const FCkUiWidgetRegistrySnapshot> NewSnapshot = Registry.CreateSnapshot();
    const ECkUiCustomStyleKind* Later = NewSnapshot->FindStyleProperty(TEXT("-ck-later"));
    TestTrue(TEXT("New style snapshot includes later registration"), Later != nullptr && *Later == ECkUiCustomStyleKind::Length);
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiCustomStyles_ParserAndView,
    "Ck.UiAuthoring.CustomStyles.ParserAndRetainedView",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiCustomStyles_ParserAndView::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_custom_styles;
    const TSharedRef<FCustomStyleStats> Stats = MakeShared<FCustomStyleStats>();
    FCkUiWidgetRegistry Registry;
    if (!TestTrue(TEXT("Style probe registers"), Registry.Register(Registration(TEXT("style-probe"), Stats, Styles())).Succeeded)) { return false; }
    if (!TestTrue(TEXT("Non-opted probe registers"), Registry.Register(Registration(TEXT("plain-probe"), Stats)).Succeeded)) { return false; }
    const TSharedRef<const FCkUiWidgetRegistrySnapshot> Snapshot = Registry.CreateSnapshot();

    FCkUiDocument Document;
    const FCkUiLoadResult Parsed = FCkUiDocumentParser::TryParse(Markup(), Stylesheet(), Tokens(), Document, TEXT("UiCustomStylesTyped"), Snapshot);
    const FCkUiNode* ParsedLeaf = Leaf(Document);
    if (!TestTrue(TEXT("Typed custom style document parses"), Parsed.Succeeded) || !TestNotNull(TEXT("Typed custom style leaf exists"), ParsedLeaf)) { return false; }
    const FCkUiCustomStyleValue* Number = Value(ParsedLeaf->Style, TEXT("-ck-number"));
    const FCkUiCustomStyleValue* Length = Value(ParsedLeaf->Style, TEXT("-ck-length"));
    const FCkUiCustomStyleValue* Color = Value(ParsedLeaf->Style, TEXT("-ck-color"));
    TestTrue(TEXT("Class cascade resolves typed signed number"), Number != nullptr && Number->Kind == ECkUiCustomStyleKind::Number && FMath::IsNearlyEqual(Number->Number, 4.5f));
    TestTrue(TEXT("Class cascade resolves typed px length token"), Length != nullptr && Length->Kind == ECkUiCustomStyleKind::Length && FMath::IsNearlyEqual(Length->Number, 12.0f));
    TestTrue(TEXT("Class cascade resolves typed color token"), Color != nullptr && Color->Kind == ECkUiCustomStyleKind::Color
        && Color->Color.Equals(FLinearColor::FromSRGBColor(FColor(0xAA, 0xBB, 0xCC, 0xDD))));

    const TSharedRef<FCkUiView> View = FCkUiView::Create({}, {}, Tokens(), FSlateFontInfo{}, {}, Snapshot);
    View->GetRegion(TEXT("only"));
    if (!TestTrue(TEXT("Typed custom style view loads"), View->TryReload(Markup(), Stylesheet(), TEXT("UiCustomStylesView")).Succeeded)) { return false; }
    Number = Value(Stats->FactoryStyle, TEXT("-ck-number"));
    Length = Value(Stats->FactoryStyle, TEXT("-ck-length"));
    Color = Value(Stats->FactoryStyle, TEXT("-ck-color"));
    TestTrue(TEXT("Factory receives resolved typed custom styles"), Stats->FactoryCalls == 1 && Number != nullptr && Length != nullptr && Color != nullptr
        && Number->Kind == ECkUiCustomStyleKind::Number && FMath::IsNearlyEqual(Number->Number, 4.5f)
        && Length->Kind == ECkUiCustomStyleKind::Length && FMath::IsNearlyEqual(Length->Number, 12.0f)
        && Color->Kind == ECkUiCustomStyleKind::Color && Color->Color.Equals(FLinearColor::FromSRGBColor(FColor(0xAA, 0xBB, 0xCC, 0xDD))));

    if (!TestTrue(TEXT("Compatible typed custom style reload succeeds"), View->TryReload(Markup(), TEXT(".base {} .tuned { -ck-number: 7; -ck-length: 0px; -ck-color: #010203; }"), TEXT("UiCustomStylesReload")).Succeeded)) { return false; }
    Number = Value(Stats->PreparedStyle, TEXT("-ck-number"));
    Length = Value(Stats->PreparedStyle, TEXT("-ck-length"));
    Color = Value(Stats->PreparedStyle, TEXT("-ck-color"));
    TestTrue(TEXT("Prepared retained reload receives resolved typed styles"), Stats->PrepareCalls == 2 && Number != nullptr && Length != nullptr && Color != nullptr
        && FMath::IsNearlyEqual(Number->Number, 7.0f) && FMath::IsNearlyEqual(Length->Number, 0.0f)
        && Color->Color.Equals(FLinearColor::FromSRGBColor(FColor(1, 2, 3))));

    const TSharedRef<SWidget> AcceptedRoot = RegionContent(View);
    const auto AssertAtomicReject = [this, &View, &Stats, &AcceptedRoot](const FString& InName, const FString& InMarkup, const FString& InStyles)
    {
        const int64 Revision = View->GetRevision();
        const int32 Factories = Stats->FactoryCalls;
        const int32 Prepares = Stats->PrepareCalls;
        const FCkUiLoadResult Result = View->TryReload(InMarkup, InStyles, InName);
        TestFalse(*InName, Result.Succeeded);
        TestEqual(*(InName + TEXT(" preserves revision")), View->GetRevision(), Revision);
        TestTrue(*(InName + TEXT(" preserves output")), RegionContent(View) == AcceptedRoot);
        TestEqual(*(InName + TEXT(" invokes no factory")), Stats->FactoryCalls, Factories);
        TestEqual(*(InName + TEXT(" invokes no reload preparation")), Stats->PrepareCalls, Prepares);
    };

    AssertAtomicReject(TEXT("Unknown declaration rejects even when unmatched"), Markup(), TEXT(".unmatched { -ck-unknown: 1; }"));
    AssertAtomicReject(TEXT("Malformed registered declaration rejects even when unmatched"), Markup(), TEXT(".unmatched { -ck-length: -1; }"));
    AssertAtomicReject(TEXT("Declared property rejects on builtin"), Markup(TEXT("<text id=\"builtin\" class=\"bad\">Builtin</text>")), TEXT(".bad { -ck-number: 1; }"));
    AssertAtomicReject(TEXT("Declared property rejects on non-opted custom tag"), Markup(TEXT("<plain-probe id=\"plain\" class=\"bad\"/>")), TEXT(".bad { -ck-number: 1; }"));
    AssertAtomicReject(TEXT("Negative custom length rejects"), Markup(), TEXT(".base {} .tuned { -ck-length: -1; }"));
    AssertAtomicReject(TEXT("Nonfinite custom number rejects"), Markup(), TEXT(".base {} .tuned { -ck-number: NaN; }"));
    AssertAtomicReject(TEXT("Unit-bearing custom number rejects"), Markup(), TEXT(".base {} .tuned { -ck-number: 1px; }"));
    AssertAtomicReject(TEXT("Malformed custom color rejects"), Markup(), TEXT(".base {} .tuned { -ck-color: #12345; }"));
    const FCkUiLoadResult Cyclic = FCkUiDocumentParser::TryParse(Markup(), TEXT(".base {} .tuned { -ck-length: var(--a); }"),
        {{TEXT("--a"), TEXT("var(--b)")}, {TEXT("--b"), TEXT("var(--a)")}}, Document, TEXT("UiCustomStylesCyclic"), Snapshot);
    TestFalse(TEXT("Cyclic custom style token rejects"), Cyclic.Succeeded);
    ParsedLeaf = Leaf(Document);
    Number = ParsedLeaf != nullptr ? Value(ParsedLeaf->Style, TEXT("-ck-number")) : nullptr;
    TestTrue(TEXT("Cyclic custom style token preserves parser output"), ParsedLeaf != nullptr && ParsedLeaf->Id == TEXT("probe")
        && Number != nullptr && FMath::IsNearlyEqual(Number->Number, 4.5f));

    const TMap<FString, FString> CyclicTokens = {{TEXT("--a"), TEXT("var(--b)")}, {TEXT("--b"), TEXT("var(--a)")}};
    const TSharedRef<FCkUiView> CyclicView = FCkUiView::Create({}, {}, CyclicTokens, FSlateFontInfo{}, {}, Snapshot);
    CyclicView->GetRegion(TEXT("only"));
    const FCkUiLoadResult CyclicInitial = CyclicView->TryReload(Markup(), TEXT(".base {} .tuned { -ck-number: 1; -ck-length: 1; -ck-color: #010203; }"), TEXT("UiCustomStylesCyclicInitial"));
    if (!TestTrue(TEXT("Cyclic-token view accepts a valid initial style"), CyclicInitial.Succeeded)) { AddError(FString::Join(CyclicInitial.Errors, TEXT("; "))); return false; }
    const int64 CyclicRevision = CyclicView->GetRevision();
    const TSharedRef<SWidget> CyclicRoot = RegionContent(CyclicView);
    const int32 CyclicFactories = Stats->FactoryCalls;
    const int32 CyclicPrepares = Stats->PrepareCalls;
    const FCkUiLoadResult CyclicViewResult = CyclicView->TryReload(Markup(), TEXT(".base {} .tuned { -ck-length: var(--a); }"), TEXT("UiCustomStylesCyclicView"));
    TestFalse(TEXT("Cyclic custom token rejects retained view reload"), CyclicViewResult.Succeeded);
    TestEqual(TEXT("Cyclic custom token preserves view revision"), CyclicView->GetRevision(), CyclicRevision);
    TestTrue(TEXT("Cyclic custom token preserves mounted output"), RegionContent(CyclicView) == CyclicRoot);
    TestEqual(TEXT("Cyclic custom token invokes no factory"), Stats->FactoryCalls, CyclicFactories);
    TestEqual(TEXT("Cyclic custom token invokes no reload preparation"), Stats->PrepareCalls, CyclicPrepares);
    return true;
}
#endif
