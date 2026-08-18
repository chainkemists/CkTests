// T-C1-1 — the fence that makes a declared snapshot posture mandatory instead of advisory.
//
// It enumerates every SCRIPT-DECLARED reflected struct (ck::Is_AngelScriptDeclaredStruct — the reflected class
// path of UASStruct, with NO size clause), narrows to the project's fragment-name prefixes, and requires each one
// to resolve Durable or Session — declared, or derived-pure. Anything still Undeclared must appear on the
// project's allow-list, which is capped and may only shrink. A fragment authored today is therefore red today.
//
// The enumerator is itself a tested property, and that is deliberate. The obvious predicate to reach for here is
// ck_untraced_struct_safety::IsAngelScriptStruct, which adds GetPropertiesSize() == 0 because the GC walk reaches
// it only from its field-less branch: a fence built on that would see ~90 tag structs out of ~640 fragments and be
// green on day one with an empty allow-list — enforcement that never fires, which is worse than none. So this test
// asserts COUNT BANDS over both the unnarrowed and the narrowed population. Re-introduce a size clause anywhere in
// the enumeration and both bands go red instead of the suite going quietly green.
//
// Coverage limit, stated rather than papered over: no reflected marker distinguishes a script-declared dynamic
// fragment from any other script struct, so the narrowing is a NAME convention supplied by the project. A fragment
// named outside those prefixes is invisible here. The bands are a floor, not a completeness proof, which is why
// the prefix list is committed config and is ratcheted exactly like the allow-list.
//
// The registered C++ payload types are the other half of the population, and their posture is the REGISTRAR: a
// handler with Produce + HydrationApply is Durable, a wire-only handler is Session. Here that inference only has to
// be WELL-FORMED; whether a registration's DECLARED posture agrees with its lambda set is T-C1-7's assertion.

#include "CkCore/Format/CkFormat.h"
#include "CkCore/Macros/CkMacros.h"
#include "CkCore/Validation/CkUntracedStructSafety.h"

#include "CkEcs/Persistence/CkPersistenceHandlerRegistry.h"
#include "CkEcs/Snapshot/CkSnapshot_Posture.h"

#include "CkSnapshot/Settings/CkSnapshot_PostureRatchet_Settings.h"

#include "CkTests/CkTests_Log.h"

#include "Misc/AutomationTest.h"
#include "Misc/FileHelper.h"
#include "Misc/Paths.h"

#include "UObject/UObjectIterator.h"

#if WITH_DEV_AUTOMATION_TESTS

namespace ck_fragment_posture_coverage
{
    // Commissioned against the BusterBlock corpus, 2026-08-17. The ceiling is the MAXIMUM a project may declare,
    // and exists so a migration cannot hand back the ground it took: lower it as the debt drains, never raise it.
    constexpr auto AllowListHardCeiling = 324;

    // Band over the narrowed population. Its purpose is not to pin a number but to red when the enumeration
    // silently collapses — a size clause, a wrong class path, an AngelScript module that never compiled.
    constexpr auto NarrowedCountMin = 574;
    constexpr auto NarrowedCountMax = 701;

    // Band over the UNNARROWED population: every script-declared struct, params and generated bindings included.
    // It is an order of magnitude larger than the narrowed set, which is what makes it an independent check — a
    // prefix list that still matches cannot hide a broken enumerator from this one.
    constexpr auto ScriptDeclaredCountMin = 3500;

    // ----------------------------------------------------------------------------------------------------------------

    struct FRow
    {
        FString                            Name;
        ck::FCk_Snapshot_PostureResolution Resolution;
    };

    struct FEnumeration
    {
        int32        ScriptDeclaredCount = 0;
        TArray<FRow> Narrowed;
        TArray<FRow> Undeclared;
        int32        DurableCount = 0;
        int32        SessionCount = 0;
        int32        SplitCount   = 0;
    };

    auto Get_Settings() -> const UCk_Snapshot_PostureRatchet_Settings*
    { return GetDefault<UCk_Snapshot_PostureRatchet_Settings>(); }

    auto Enumerate(
        const TArray<FString>& InPrefixes) -> FEnumeration
    {
        auto Out = FEnumeration{};

        for (TObjectIterator<UScriptStruct> It; It; ++It)
        {
            const auto* Type = *It;
            if (NOT ck::Is_AngelScriptDeclaredStruct(Type))
            { continue; }

            const auto Name = Type->GetName();

            // A script recompile RENAMES the previous generation to "<Name>_REPLACED_<N>" and leaves it root-set,
            // so the iterator yields every stale generation beside the live one. Counting them would inflate both
            // bands and could re-admit an already-fixed type as debt.
            if (Name.Contains(TEXT("_REPLACED_"), ESearchCase::CaseSensitive))
            { continue; }

            ++Out.ScriptDeclaredCount;

            const auto MatchesPrefix = InPrefixes.ContainsByPredicate([&Name](const FString& InPrefix) -> bool
            { return NOT InPrefix.IsEmpty() && Name.StartsWith(InPrefix, ESearchCase::CaseSensitive); });

            if (NOT MatchesPrefix)
            { continue; }

            auto Row = FRow{Name, ck::Resolve_FragmentPosture(Type)};

            switch (Row.Resolution.Posture)
            {
                case ECk_Snapshot_Posture::Durable:
                {
                    ++Out.DurableCount;
                    break;
                }
                case ECk_Snapshot_Posture::Session:
                {
                    ++Out.SessionCount;
                    break;
                }
                default:
                {
                    if (Row.Resolution.RequiresSplit)
                    { ++Out.SplitCount; }

                    Out.Undeclared.Add(Row);
                    break;
                }
            }

            Out.Narrowed.Add(MoveTemp(Row));
        }

        const auto ByName = [](const FRow& InA, const FRow& InB) -> bool { return InA.Name < InB.Name; };
        Out.Narrowed.Sort(ByName);
        Out.Undeclared.Sort(ByName);

        return Out;
    }

    // ----------------------------------------------------------------------------------------------------------------

    // The commissioning generator, emitted from the SAME enumeration the fence runs on, so the committed list and
    // the fence cannot disagree about what "discovered" means. Reachable two ways: the fence writes it whenever it
    // is red (the case where a human needs it), and the console command below writes it on demand.
    auto Build_IniBlock(
        const FEnumeration&    InEnumeration,
        const TArray<FString>& InPrefixes) -> FString
    {
        auto Block = FString{};
        Block += TEXT("[/Script/CkSnapshot.Ck_Snapshot_PostureRatchet_Settings]\r\n");
        Block += FString::Printf(TEXT("_AllowListCeiling=%d\r\n"), InEnumeration.Undeclared.Num());

        for (const auto& Prefix : InPrefixes)
        { Block += FString::Printf(TEXT("+_FragmentNamePrefixes=%s\r\n"), *Prefix); }

        // Grouped by disposition rather than annotated per line: the config parser only honours ';' at the start of
        // a line, so a trailing comment would become part of the value.
        const auto EmitGroup = [&Block, &InEnumeration](bool InRequiresSplit, const TCHAR* InHeading) -> void
        {
            auto Names = TArray<FString>{};
            for (const auto& Row : InEnumeration.Undeclared)
            {
                if (Row.Resolution.RequiresSplit == InRequiresSplit)
                { Names.Add(Row.Name); }
            }

            Block += FString::Printf(TEXT("; --- %d %s ---\r\n"), Names.Num(), InHeading);

            for (const auto& Name : Names)
            { Block += FString::Printf(TEXT("+_UndeclaredFragmentAllowList=%s\r\n"), *Name); }
        };

        EmitGroup(false, TEXT("need an explicit posture declaration"));
        EmitGroup(true,  TEXT("need the fragment SPLIT (a derived-Session shape carrying durable value fields)"));

        return Block;
    }

    auto Get_GeneratedBlockPath() -> FString
    { return FPaths::ProjectSavedDir() / TEXT("CkSnapshot") / TEXT("PostureAllowList.ini"); }

    auto Get_ClassificationPath() -> FString
    { return FPaths::ProjectSavedDir() / TEXT("CkSnapshot") / TEXT("PostureClassification.csv"); }

    // Every enumerated type with its resolved posture AND the reason it resolved that way, so no classification is
    // silent. Written on every run, because the artifact that makes a change to the capture set falsifiable is a
    // diff of this file across the change — not a count in a summary line.
    auto Build_Classification(
        const FEnumeration& InEnumeration) -> FString
    {
        auto Csv = FString{TEXT("Type,Posture,RequiresSplit,Reason\r\n")};

        for (const auto& Row : InEnumeration.Narrowed)
        {
            Csv += FString::Printf(TEXT("%s,%s,%s,\"%s\"\r\n"),
                *Row.Name,
                *ck::Format_UE(TEXT("{}"), Row.Resolution.Posture),
                Row.Resolution.RequiresSplit ? TEXT("split-me") : TEXT("-"),
                *Row.Resolution.Reason.Replace(TEXT("\""), TEXT("'")));
        }

        return Csv;
    }

    auto Write_Artifacts(
        const FEnumeration&    InEnumeration,
        const TArray<FString>& InPrefixes) -> void
    {
        // ForceUTF8, not the default AutoDetect: a reason string with one non-ASCII character would flip the whole
        // file to UTF-16 and the artifact's whole point is that it diffs cleanly across a change to the capture set.
        FFileHelper::SaveStringToFile(Build_IniBlock(InEnumeration, InPrefixes), *Get_GeneratedBlockPath(),
            FFileHelper::EEncodingOptions::ForceUTF8);
        FFileHelper::SaveStringToFile(Build_Classification(InEnumeration), *Get_ClassificationPath(),
            FFileHelper::EEncodingOptions::ForceUTF8);
    }

    static FAutoConsoleCommand GCmd_PrintPostureAllowList(
        TEXT("Ck.Snapshot.PrintPostureAllowList"),
        TEXT("Writes this project's fragment-posture allow-list ini block and full classification to ")
        TEXT("Saved/CkSnapshot/, from the same enumeration Ck.Snapshot.Meta.FragmentPostureCoverage runs on."),
        FConsoleCommandDelegate::CreateLambda([]() -> void
        {
            const auto& Prefixes = Get_Settings()->Get_FragmentNamePrefixes();
            Write_Artifacts(Enumerate(Prefixes), Prefixes);

            ck::tests::Display(TEXT("Fragment-posture artifacts written to [{}] and [{}]"),
                Get_GeneratedBlockPath(), Get_ClassificationPath());
        }));
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_FragmentPostureCoverage_MetaTest,
    "Ck.Snapshot.Meta.FragmentPostureCoverage",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_FragmentPostureCoverage_MetaTest::
    RunTest(
        const FString& /*InParameters*/)
{
    using namespace ck_fragment_posture_coverage;

    const auto* Settings = Get_Settings();
    if (Settings == nullptr)
    {
        AddError(TEXT("UCk_Snapshot_PostureRatchet_Settings has no CDO, so this fence cannot run — and a fence that "
            "cannot run must fail rather than pass."));
        return false;
    }

    const auto& Prefixes  = Settings->Get_FragmentNamePrefixes();
    const auto& AllowList = Settings->Get_UndeclaredFragmentAllowList();
    const auto  Ceiling   = Settings->Get_AllowListCeiling();

    if (Prefixes.IsEmpty())
    {
        AddError(TEXT("_FragmentNamePrefixes is empty, so this fence would enumerate nothing. Set it in the "
            "project's [/Script/CkSnapshot.Ck_Snapshot_PostureRatchet_Settings] config section to the "
            "reflected-name prefixes of its script-declared fragments (e.g. Bb_Fragment_, Bb_Tag_)."));
        return false;
    }

    const auto Enumeration = Enumerate(Prefixes);
    Write_Artifacts(Enumeration, Prefixes);

    AddInfo(FString::Printf(
        TEXT("Fragment posture: script-declared=[%d] narrowed=[%d] durable=[%d] session=[%d] undeclared=[%d] ")
        TEXT("(of which split-me=[%d]); allow-list=[%d] ceiling=[%d] hard-ceiling=[%d]"),
        Enumeration.ScriptDeclaredCount, Enumeration.Narrowed.Num(), Enumeration.DurableCount,
        Enumeration.SessionCount, Enumeration.Undeclared.Num(), Enumeration.SplitCount,
        AllowList.Num(), Ceiling, AllowListHardCeiling));

    // ---- The enumerator is a tested property, not a hope ------------------------------------------------------------

    TestTrue(
        FString::Printf(TEXT("script-declared struct count [%d] is at least the commissioned floor [%d] — below it, "
            "either the enumeration predicate narrowed (a size clause, a wrong class path) or AngelScript never "
            "compiled in this boot"), Enumeration.ScriptDeclaredCount, ScriptDeclaredCountMin),
        Enumeration.ScriptDeclaredCount >= ScriptDeclaredCountMin);

    TestTrue(
        FString::Printf(TEXT("narrowed fragment count [%d] is inside the commissioned band [%d..%d] — outside it, "
            "either the enumeration broke or the corpus moved far enough that the band must be re-commissioned"),
            Enumeration.Narrowed.Num(), NarrowedCountMin, NarrowedCountMax),
        Enumeration.Narrowed.Num() >= NarrowedCountMin && Enumeration.Narrowed.Num() <= NarrowedCountMax);

    // ---- The allow-list only ever shrinks ---------------------------------------------------------------------------

    TestTrue(
        FString::Printf(TEXT("declared allow-list ceiling [%d] does not exceed the commissioned hard ceiling [%d]"),
            Ceiling, AllowListHardCeiling),
        Ceiling <= AllowListHardCeiling);

    TestTrue(
        FString::Printf(TEXT("allow-list size [%d] does not exceed its declared ceiling [%d]"),
            AllowList.Num(), Ceiling),
        AllowList.Num() <= Ceiling);

    // ---- Every Undeclared type is listed, and its disposition is stated ---------------------------------------------

    const auto AllowSet = TSet<FName>{AllowList};

    for (const auto& Row : Enumeration.Undeclared)
    {
        if (AllowSet.Contains(FName{*Row.Name}))
        { continue; }

        AddError(FString::Printf(
            TEXT("Fragment [%s] has NO snapshot posture: %s. %s Until then it is captured and hydrated field-wise, ")
            TEXT("which is the behaviour the posture contract exists to remove. Either fix it, or add it to ")
            TEXT("_UndeclaredFragmentAllowList and keep the ceiling — the generated block at [%s] has both."),
            *Row.Name,
            *Row.Resolution.Reason,
            Row.Resolution.RequiresSplit
                ? TEXT("Its content cannot round-trip as one unit, so SPLIT it: the durable fields into a Durable "
                       "fragment, the session content into a Session one.")
                : TEXT("DECLARE one: carry an FCk_Snapshot_Durable or FCk_Snapshot_Session marker field."),
            *Get_GeneratedBlockPath()));
    }

    // Drift guard, mirroring the RepData ratchet's: an entry that no longer resolves Undeclared makes the count
    // meaningless and hides the fact that the debt was already paid — or that the type was renamed out from under
    // the list, which would silently drop it out of coverage.
    auto DiscoveredUndeclared = TSet<FName>{};
    for (const auto& Row : Enumeration.Undeclared)
    { DiscoveredUndeclared.Add(FName{*Row.Name}); }

    for (const auto& Allowed : AllowList)
    {
        TestTrue(
            FString::Printf(TEXT("allow-listed fragment [%s] still exists AND still resolves Undeclared — remove it "
                "from the list, and lower the ceiling, once it is fixed or renamed"), *Allowed.ToString()),
            DiscoveredUndeclared.Contains(Allowed));
    }

    // ---- The registered C++ payload half ----------------------------------------------------------------------------

    const auto RegisteredTypes = FCk_PersistenceHandlerRegistry::Get_RegisteredTypes();
    auto RegisteredDurable = 0;
    auto RegisteredSession = 0;

    for (const auto* Registered : RegisteredTypes)
    {
        const auto* Handler = FCk_PersistenceHandlerRegistry::Find(Registered);
        if (Handler == nullptr)
        { continue; }

        const auto HasProduce   = static_cast<bool>(Handler->Produce);
        const auto HasHydration = static_cast<bool>(Handler->HydrationApply);
        const auto HasNetApply  = static_cast<bool>(Handler->NetApply);

        if (HasProduce && HasHydration)
        {
            ++RegisteredDurable;
            continue;
        }

        if (HasNetApply && NOT HasProduce)
        {
            ++RegisteredSession;
            continue;
        }

        AddError(FString::Printf(
            TEXT("Registered payload type [%s] has no inferable snapshot posture: Produce=[%d] HydrationApply=[%d] ")
            TEXT("NetApply=[%d]. A save participant needs BOTH Produce and HydrationApply (Durable); a wire-only ")
            TEXT("type needs NetApply and no Produce (Session). Anything else is a registration nobody can read a ")
            TEXT("posture from."),
            *Registered->GetName(), HasProduce ? 1 : 0, HasHydration ? 1 : 0, HasNetApply ? 1 : 0));
    }

    AddInfo(FString::Printf(TEXT("Registered payload postures: durable=[%d] session=[%d] of [%d] registrations"),
        RegisteredDurable, RegisteredSession, RegisteredTypes.Num()));

    TestTrue(TEXT("the persistence registry resolved a non-trivial number of registrations (0 would mean this "
        "enumeration is broken, not that the registry is empty)"), RegisteredTypes.Num() >= 3);

    AddInfo(FString::Printf(TEXT("Commissioning artifacts: allow-list block [%s], full classification [%s]"),
        *Get_GeneratedBlockPath(), *Get_ClassificationPath()));

    return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS
