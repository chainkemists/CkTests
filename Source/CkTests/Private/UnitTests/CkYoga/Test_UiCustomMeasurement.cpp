#include "CkSlateLayout/CkFlexBox.h"
#include "CkSlateLayout/CkFlexLayoutTypes.h"
#include "CkSlateLayout/CkFlexText.h"
#include "CkSlateLayout/CkUiWidgetRegistry.h"
#include "CkSlateLayout/SCkUiSurface.h"

#include "Layout/ArrangedChildren.h"
#include "Misc/AutomationTest.h"
#include "Widgets/Layout/SBox.h"

#if WITH_DEV_AUTOMATION_TESTS

namespace ck_tests_ui_custom_measurement
{
    const FString LongText = TEXT("A deliberately long line of shaped Slate text must wrap consistently through every authored port.");

    auto Markup(const bool bExtra = false) -> FString
    {
        return FString::Printf(TEXT("<ui version=\"1\"><region name=\"only\"><column id=\"root\"><text id=\"direct\">%s</text><plain id=\"custom\"/><retained id=\"retained\"/><native id=\"native\" bind=\"native\"/>%s</column></region></ui>"), *LongText, bExtra ? TEXT("<text id=\"extra\">extra</text>") : TEXT(""));
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

    auto RegionPanel(const TSharedRef<FCkUiView>& InView) -> TSharedRef<SCkFlexBox>
    {
        return StaticCastSharedRef<SCkFlexBox>(StaticCastSharedRef<SBox>(InView->GetRegion(TEXT("only")))->GetChildren()->GetChildAt(0));
    }

    auto Arrange(const TSharedRef<SCkFlexBox>& InPanel, const float InWidth) -> FArrangedChildren
    {
        InPanel->SlatePrepass(1.0f);
        auto Result = FArrangedChildren{EVisibility::Visible};
        InPanel->OnArrangeChildren(FGeometry::MakeRoot(FVector2D{InWidth, 2000.0f}, FSlateLayoutTransform{}), Result);
        return Result;
    }

    auto FindSize(const FArrangedChildren& InChildren, const FName InTag, FVector2D& OutSize) -> bool
    {
        for (int32 Index = 0; Index < InChildren.Num(); ++Index)
        {
            if (InChildren[Index].Widget->GetTag() == InTag)
            {
                OutSize = InChildren[Index].Geometry.GetLocalSize();
                return true;
            }
        }
        return false;
    }

    class FNoopUpdate final : public ICkUiPreparedWidgetUpdate
    {
    public:
        virtual void Commit() noexcept override {}
    };

    class FRetainedText final : public ICkUiRetainedWidget
    {
    public:
        explicit FRetainedText(const FSlateFontInfo& InFont)
            : _Widget(SNew(SCkFlexText).Tag(FName(TEXT("retained-leaf"))).Text(FText::FromString(LongText)).Font(InFont)) {}

        virtual auto GetWidget() const -> TSharedRef<SWidget> override { return _Widget; }
        virtual auto PrepareReload(const FCkUiCustomWidgetArguments&, FString&) const -> TUniquePtr<ICkUiPreparedWidgetUpdate> override { return MakeUnique<FNoopUpdate>(); }

    private:
        TSharedRef<SCkFlexText> _Widget;
    };
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiCustomMeasurement_Ports,
    "Ck.UiAuthoring.Measurement.CustomPortsGeometry",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiCustomMeasurement_Ports::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_custom_measurement;
    const FSlateFontInfo Font = FCoreStyle::Get().GetWidgetStyle<FTextBlockStyle>("NormalText").Font;
    const TSharedRef<SCkFlexText> Native = SNew(SCkFlexText).Tag(FName(TEXT("native-leaf"))).Text(FText::FromString(LongText)).Font(Font);
    auto Registry = FCkUiWidgetRegistry{};
    auto Plain = FCkUiCustomWidgetRegistration{};
    Plain.Schema.Tag = TEXT("plain");
    Plain.Factory = [Font](const FCkUiCustomWidgetArguments&, FString&) -> TSharedPtr<SWidget>
    { return SNew(SCkFlexText).Tag(FName(TEXT("custom-leaf"))).Text(FText::FromString(LongText)).Font(Font); };
    if (!TestTrue(TEXT("Stateless measurement factory registers"), Registry.Register(MoveTemp(Plain)).Succeeded)) { return false; }
    TSharedPtr<FRetainedText> Retained;
    auto RetainedRegistration = FCkUiCustomWidgetRegistration{};
    RetainedRegistration.Schema.Tag = TEXT("retained");
    RetainedRegistration.RetainedFactory = [&Retained, Font](const FCkUiCustomWidgetArguments&, FString&) -> TSharedPtr<ICkUiRetainedWidget>
    {
        Retained = MakeShared<FRetainedText>(Font);
        return Retained;
    };
    if (!TestTrue(TEXT("Retained measurement factory registers"), Registry.Register(MoveTemp(RetainedRegistration)).Succeeded)) { return false; }

    const TSharedRef<FCkUiView> View = FCkUiView::Create({{TEXT("native"), Native}}, {}, {}, Font, {}, Registry.CreateSnapshot());
    View->GetRegion(TEXT("only"));
    if (!TestTrue(TEXT("Measurement fixture loads"), View->TryReload(Markup(), TEXT(""), TEXT("CustomMeasurementInitial")).Succeeded)) { return false; }
    const TSharedRef<SCkFlexBox> WidePanel = RegionPanel(View);
    const FArrangedChildren Wide = Arrange(WidePanel, 420.0f);
    const FArrangedChildren Narrow = Arrange(WidePanel, 90.0f);
    auto DirectWide = FVector2D{};
    auto CustomWide = FVector2D{};
    auto RetainedWide = FVector2D{};
    auto NativeWide = FVector2D{};
    auto DirectNarrow = FVector2D{};
    auto CustomNarrow = FVector2D{};
    auto RetainedNarrow = FVector2D{};
    auto NativeNarrow = FVector2D{};
    const bool FoundWide = FindSize(Wide, TEXT("direct"), DirectWide) && FindSize(Wide, TEXT("custom"), CustomWide)
        && FindSize(Wide, TEXT("retained"), RetainedWide) && FindSize(Wide, TEXT("native"), NativeWide);
    const bool FoundNarrow = FindSize(Narrow, TEXT("direct"), DirectNarrow) && FindSize(Narrow, TEXT("custom"), CustomNarrow)
        && FindSize(Narrow, TEXT("retained"), RetainedNarrow) && FindSize(Narrow, TEXT("native"), NativeNarrow);
    if (!TestTrue(TEXT("Wide layout arranges every measurement port"), FoundWide) || !TestTrue(TEXT("Narrow layout arranges every measurement port"), FoundNarrow)) { return false; }
    TestTrue(TEXT("Reference direct text grows taller at narrow width"), DirectNarrow.Y > DirectWide.Y);
    TestTrue(TEXT("Stateless custom text grows taller at narrow width"), CustomNarrow.Y > CustomWide.Y);
    TestTrue(TEXT("Retained custom text grows taller at narrow width"), RetainedNarrow.Y > RetainedWide.Y);
    TestTrue(TEXT("Native text grows taller at narrow width"), NativeNarrow.Y > NativeWide.Y);
    TestTrue(TEXT("Stateless custom multiline height agrees with direct authored text"), FMath::IsNearlyEqual(CustomNarrow.Y, DirectNarrow.Y, 1.0f));
    TestTrue(TEXT("Retained custom multiline height agrees with direct authored text"), FMath::IsNearlyEqual(RetainedNarrow.Y, DirectNarrow.Y, 1.0f));
    TestTrue(TEXT("Native multiline height agrees with direct authored text"), FMath::IsNearlyEqual(NativeNarrow.Y, DirectNarrow.Y, 1.0f));
    const TSharedPtr<SWidget> CustomPort = FindTagged(StaticCastSharedRef<SBox>(View->GetRegion(TEXT("only")))->GetChildren()->GetChildAt(0), TEXT("custom"));
    const TSharedPtr<SWidget> RetainedPort = FindTagged(StaticCastSharedRef<SBox>(View->GetRegion(TEXT("only")))->GetChildren()->GetChildAt(0), TEXT("retained"));
    TestTrue(TEXT("Stateless custom port forwards flex measurement metadata"), CustomPort.IsValid() && CustomPort->GetMetaData<FCkFlexMeasureMetaData>().IsValid());
    TestTrue(TEXT("Retained custom port forwards flex measurement metadata"), RetainedPort.IsValid() && RetainedPort->GetMetaData<FCkFlexMeasureMetaData>().IsValid());
    if (!TestTrue(TEXT("Retained factory produced a component"), Retained.IsValid())) { return false; }
    const TSharedPtr<SWidget> RetainedLeaf = FindTagged(RegionPanel(View), TEXT("retained-leaf"));
    if (!TestTrue(TEXT("Retained component leaf is mounted"), RetainedLeaf.IsValid())) { return false; }

    const TSharedRef<SWidget> AcceptedRoot = StaticCastSharedRef<SBox>(View->GetRegion(TEXT("only")))->GetChildren()->GetChildAt(0);
    const int64 AcceptedRevision = View->GetRevision();
    const FCkUiLoadResult Rejected = View->TryReload(Markup().Replace(TEXT("<plain id=\"custom\"/>"), TEXT("<plain id=\"custom\" visible=\"missing\"/>")), TEXT(""), TEXT("CustomMeasurementRejected"));
    TestFalse(TEXT("Rejected custom measurement reload fails"), Rejected.Succeeded);
    TestEqual(TEXT("Rejected custom measurement reload preserves revision"), View->GetRevision(), AcceptedRevision);
    TestTrue(TEXT("Rejected custom measurement reload preserves root"), StaticCastSharedRef<SBox>(View->GetRegion(TEXT("only")))->GetChildren()->GetChildAt(0) == AcceptedRoot);
    if (!TestTrue(TEXT("Valid retained measurement reload succeeds"), View->TryReload(Markup(true), TEXT(""), TEXT("CustomMeasurementRetainedReload")).Succeeded)) { return false; }
    TestTrue(TEXT("Valid retained measurement reload preserves leaf identity"), FindTagged(RegionPanel(View), TEXT("retained-leaf")) == RetainedLeaf);
    return true;
}

#endif
