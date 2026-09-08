#include "CkSlateLayout/CkUiCollection.h"

#include "Misc/AutomationTest.h"

#include <limits>

#if WITH_DEV_AUTOMATION_TESTS

namespace ck_tests_ui_collection
{
    auto Schema() -> TArray<FCkUiFieldSchema>
    {
        return {{TEXT("label"), ECkUiFieldKind::Text}, {TEXT("rank"), ECkUiFieldKind::Number}, {TEXT("enabled"), ECkUiFieldKind::Bool}, {TEXT("tone"), ECkUiFieldKind::Color}, {TEXT("icon"), ECkUiFieldKind::Image, false}};
    }

    auto Record(const FString& InKey, const FString& InLabel, const float InRank = 1.0f) -> FCkUiRecordData
    {
        auto Result = FCkUiRecordData{};
        Result.Key = InKey;
        Result.Fields.Add(TEXT("label"), FCkUiFieldValue{.Kind = ECkUiFieldKind::Text, .Text = FText::FromString(InLabel)});
        Result.Fields.Add(TEXT("rank"), FCkUiFieldValue{.Kind = ECkUiFieldKind::Number, .Number = InRank});
        Result.Fields.Add(TEXT("enabled"), FCkUiFieldValue{.Kind = ECkUiFieldKind::Bool, .Bool = true});
        Result.Fields.Add(TEXT("tone"), FCkUiFieldValue{.Kind = ECkUiFieldKind::Color, .Color = FLinearColor::White});
        return Result;
    }

    auto Create(TSharedPtr<FCkUiCollection>& OutCollection) -> bool { return FCkUiCollection::TryCreate(Schema(), OutCollection).Succeeded && OutCollection.IsValid(); }
    auto HasError(const FCkUiLoadResult& InResult) -> bool { return !InResult.Errors.IsEmpty(); }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiCollection_Mutation,
    "Ck.UiAuthoring.Collection.StableRowsAndAtomicMutation",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiCollection_Mutation::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_collection;
    TSharedPtr<FCkUiCollection> Collection;
    if (!TestTrue(TEXT("Valid collection schema creates"), Create(Collection))) { return false; }
    int32 Notifications = 0;
    bool bCallbackSawPublishedState = false;
    bool bReentrantRejected = false;
    TSharedPtr<FCkUiCollection> CallbackOwner = Collection;
    Collection->OnChanged().AddLambda([&]
    {
        ++Notifications;
        bCallbackSawPublishedState = Collection->GetRevision() == 1 && Collection->GetRecords().Num() == 2 && Collection->FindRecord(TEXT("a")).IsValid();
        bReentrantRejected = !Collection->TrySetRecords({Record(TEXT("reentrant"), TEXT("no"))}).Succeeded;
        CallbackOwner.Reset();
    });
    if (!TestTrue(TEXT("Initial records commit"), Collection->TrySetRecords({Record(TEXT("a"), TEXT("A")), Record(TEXT("b"), TEXT("B"), 2.0f)}).Succeeded)) { return false; }
    TestEqual(TEXT("Initial commit emits once"), Notifications, 1);
    TestTrue(TEXT("Callback observes entire published collection and rejects reentry"), bCallbackSawPublishedState && bReentrantRejected);
    TestFalse(TEXT("Callback can release a non-owning client reference safely"), CallbackOwner.IsValid());
    const TSharedPtr<const FCkUiRecord> OriginalA = Collection->FindRecord(TEXT("a"));
    TSharedPtr<const FCkUiRecord> OriginalB = Collection->FindRecord(TEXT("b"));
    if (!TestTrue(TEXT("Stable records can be found"), OriginalA.IsValid() && OriginalB.IsValid())) { return false; }
    const int64 Revision = Collection->GetRevision();
    if (!TestTrue(TEXT("Reorder with changed stable key commits"), Collection->TrySetRecords({Record(TEXT("b"), TEXT("B2"), 3.0f), Record(TEXT("a"), TEXT("A"))}).Succeeded)) { return false; }
    TestTrue(TEXT("Unchanged record preserves shared row identity"), Collection->FindRecord(TEXT("a")) == OriginalA);
    TestTrue(TEXT("Changed values preserve shared row identity"), Collection->FindRecord(TEXT("b")) == OriginalB);
    const FCkUiFieldValue* UpdatedRank = OriginalB->FindField(TEXT("rank"));
    const FCkUiFieldValue* UpdatedLabel = OriginalB->FindField(TEXT("label"));
    TestTrue(TEXT("Existing row readers observe updated typed values"), UpdatedRank != nullptr && UpdatedRank->Number == 3.0f
        && UpdatedLabel != nullptr && UpdatedLabel->Text.ToString() == TEXT("B2"));
    if (!TestEqual(TEXT("Reordered records retain requested count"), Collection->GetRecords().Num(), 2)) { return false; }
    const TSharedPtr<const FCkUiRecord>& FirstRecord = Collection->GetRecords()[0];
    TestTrue(TEXT("Reordered first record is valid and has requested key"), FirstRecord.IsValid() && FirstRecord->GetKey() == TEXT("b"));
    TestEqual(TEXT("Changed record advances revision once"), Collection->GetRevision(), Revision + 1);
    const int32 NotificationsAfterChange = Notifications;
    if (!TestTrue(TEXT("Identical ordered data is a no-op"), Collection->TrySetRecords({Record(TEXT("b"), TEXT("B2"), 3.0f), Record(TEXT("a"), TEXT("A"))}).Succeeded)) { return false; }
    TestEqual(TEXT("No-op does not publish"), Notifications, NotificationsAfterChange);
    TestEqual(TEXT("No-op keeps revision"), Collection->GetRevision(), Revision + 1);

    const TSharedPtr<const FCkUiRecord> RootBeforeInvalid = Collection->FindRecord(TEXT("a"));
    auto Invalid = Record(TEXT("new"), TEXT("new"));
    auto Bad = Record(TEXT("bad"), TEXT("bad"));
    Bad.Fields.FindChecked(TEXT("rank")).Number = std::numeric_limits<float>::quiet_NaN();
    const FCkUiLoadResult Rejected = Collection->TrySetRecords({Record(TEXT("a"), TEXT("must-not-publish"), 99.0f), MoveTemp(Invalid), MoveTemp(Bad)});
    TestFalse(TEXT("Late invalid record rejects whole update"), Rejected.Succeeded);
    TestTrue(TEXT("Late invalid record reports error"), HasError(Rejected));
    TestTrue(TEXT("Rejected update retains earlier rows"), Collection->FindRecord(TEXT("a")) == RootBeforeInvalid && !Collection->FindRecord(TEXT("new")).IsValid());
    const FCkUiFieldValue* UnchangedLabel = OriginalA->FindField(TEXT("label"));
    TestTrue(TEXT("Late rejection does not change a surviving row in place"), UnchangedLabel != nullptr && UnchangedLabel->Text.ToString() == TEXT("A"));
    TestEqual(TEXT("Rejected update changes neither revision nor event count"), Collection->GetRevision(), Revision + 1);
    TestEqual(TEXT("Rejected update emits no event"), Notifications, NotificationsAfterChange);

    TWeakPtr<const FCkUiRecord> Removed = Collection->FindRecord(TEXT("b"));
    if (!TestTrue(TEXT("Removal update succeeds"), Collection->TrySetRecords({Record(TEXT("a"), TEXT("A"))}).Succeeded)) { return false; }
    OriginalB.Reset();
    TestFalse(TEXT("Removed row releases once external owner releases"), Removed.IsValid());

    TSharedPtr<FCkUiCollection> LastOwner;
    if (!TestTrue(TEXT("Lifetime fixture creates"), Create(LastOwner))) { return false; }
    TWeakPtr<FCkUiCollection> WeakModel = LastOwner;
    bool AliveDuringNotification = false;
    LastOwner->OnChanged().AddLambda([&]
    {
        LastOwner.Reset();
        AliveDuringNotification = WeakModel.IsValid();
        const TSharedPtr<FCkUiCollection> Pinned = WeakModel.Pin();
        if (Pinned.IsValid()) { AliveDuringNotification &= Pinned->GetRevision() == 1 && Pinned->FindRecord(TEXT("alive")).IsValid(); }
    });
    FCkUiCollection* ModelDuringCall = LastOwner.Get();
    TestTrue(TEXT("Publication survives its callback releasing the final client owner"), ModelDuringCall->TrySetRecords({Record(TEXT("alive"), TEXT("alive"))}).Succeeded);
    TestTrue(TEXT("Model remains alive through its notification"), AliveDuringNotification);
    TestFalse(TEXT("Model releases after publication returns"), WeakModel.IsValid());
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiCollection_ValidationAndScale,
    "Ck.UiAuthoring.Collection.ValidationAndDataScale",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiCollection_ValidationAndScale::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_collection;
    TSharedPtr<FCkUiCollection> Untouched;
    const FCkUiLoadResult BadSchema = FCkUiCollection::TryCreate({}, Untouched);
    TestFalse(TEXT("Empty schema rejects"), BadSchema.Succeeded);
    TestFalse(TEXT("Invalid schema leaves output null"), Untouched.IsValid());
    TArray<FCkUiFieldSchema> DuplicateSchema = Schema();
    DuplicateSchema.Add({TEXT("label"), ECkUiFieldKind::Text});
    TestFalse(TEXT("Duplicate schema field rejects"), FCkUiCollection::TryCreate(MoveTemp(DuplicateSchema), Untouched).Succeeded);
    auto InvalidKindSchema = Schema();
    InvalidKindSchema[0].Kind = static_cast<ECkUiFieldKind>(255);
    TestFalse(TEXT("Invalid schema field kind rejects"), FCkUiCollection::TryCreate(MoveTemp(InvalidKindSchema), Untouched).Succeeded);

    TSharedPtr<FCkUiCollection> Collection;
    if (!TestTrue(TEXT("Scale fixture schema creates"), Create(Collection))) { return false; }
    Untouched = Collection;
    TestFalse(TEXT("Invalid replacement schema rejects"), FCkUiCollection::TryCreate({}, Untouched).Succeeded);
    TestTrue(TEXT("Schema failure preserves an existing output"), Untouched == Collection);
    const auto Reject = [this, &Collection](const FString& InName, TArray<FCkUiRecordData> InRecords)
    {
        const int64 Revision = Collection->GetRevision();
        const FCkUiLoadResult Result = Collection->TrySetRecords(MoveTemp(InRecords));
        TestFalse(*InName, Result.Succeeded);
        TestTrue(*(InName + TEXT(" reports error")), HasError(Result));
        TestEqual(*(InName + TEXT(" preserves revision")), Collection->GetRevision(), Revision);
    };
    auto Missing = Record(TEXT("missing"), TEXT("x")); Missing.Fields.Remove(TEXT("rank"));
    Reject(TEXT("Missing required field rejects"), {MoveTemp(Missing)});
    auto Unknown = Record(TEXT("unknown"), TEXT("x")); Unknown.Fields.Add(TEXT("extra"), FCkUiFieldValue{});
    Reject(TEXT("Unknown field rejects"), {MoveTemp(Unknown)});
    auto WrongType = Record(TEXT("wrong"), TEXT("x")); WrongType.Fields.FindChecked(TEXT("rank")).Kind = ECkUiFieldKind::Text;
    Reject(TEXT("Wrong field kind rejects"), {MoveTemp(WrongType)});
    auto InvalidColor = Record(TEXT("color"), TEXT("x")); InvalidColor.Fields.FindChecked(TEXT("tone")).Color.R = std::numeric_limits<float>::infinity();
    Reject(TEXT("Non-finite color rejects"), {MoveTemp(InvalidColor)});
    Reject(TEXT("Duplicate record key rejects"), {Record(TEXT("same"), TEXT("a")), Record(TEXT("same"), TEXT("b"))});
    Reject(TEXT("Blank record key rejects"), {Record(TEXT(""), TEXT("blank"))});

    // Data-only scale coverage: no Slate rows or widget virtualization are created here.
    for (const int32 Count : {0, 1, 12, 1000, 10000})
    {
        auto Records = TArray<FCkUiRecordData>{};
        Records.Reserve(Count);
        for (int32 Index = 0; Index < Count; ++Index) { Records.Add(Record(FString::Printf(TEXT("row-%d"), Index), TEXT("row"), static_cast<float>(Index))); }
        const FCkUiLoadResult Result = Collection->TrySetRecords(MoveTemp(Records));
        TestTrue(*FString::Printf(TEXT("Data-only collection accepts %d records"), Count), Result.Succeeded);
        TestEqual(*FString::Printf(TEXT("Data-only collection stores %d records"), Count), Collection->GetRecords().Num(), Count);
    }
    return true;
}

#endif
