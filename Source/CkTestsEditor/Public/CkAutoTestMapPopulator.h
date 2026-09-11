#pragma once

#include <CoreMinimal.h>
#include <EditorSubsystem.h>

#include "CkAutoTestMapPopulator.generated.h"

// --------------------------------------------------------------------------------------------------------------------

struct FAssetData;

class UCkAutoTestMapConfig;
class UWorld;
class UPackage;
class AActor;

// --------------------------------------------------------------------------------------------------------------------

USTRUCT(BlueprintType)
struct CKTESTSEDITOR_API FCkAutoTestSyncResult
{
    GENERATED_BODY()

    UPROPERTY(BlueprintReadOnly, Category = "Ck|AutoTest")
    int32 Spawned = 0;

    UPROPERTY(BlueprintReadOnly, Category = "Ck|AutoTest")
    int32 Removed = 0;

    UPROPERTY(BlueprintReadOnly, Category = "Ck|AutoTest")
    int32 AlreadyPresent = 0;

    // Wrapper actors whose Outliner label was stale (e.g. placed manually
    // before the populator existed and still carrying the unstripped class
    // name) and got rewritten this pass. Counts toward Has_Delta() so the
    // auto-save path persists the fix.
    UPROPERTY(BlueprintReadOnly, Category = "Ck|AutoTest")
    int32 Relabeled = 0;

    UPROPERTY(BlueprintReadOnly, Category = "Ck|AutoTest")
    bool bSkipped = false;

    UPROPERTY(BlueprintReadOnly, Category = "Ck|AutoTest")
    bool bSaved = false;

    UPROPERTY(BlueprintReadOnly, Category = "Ck|AutoTest")
    FString SkipReason;

    // A THIRD outcome, distinct from both "synced" and "skipped": the pass recognised
    // none of the AutoTest wrappers belonging to its map and REFUSED to act, because
    // acting would have destroyed every one of them.
    //
    // It is its own field rather than a flavour of bSkipped because the two mean
    // opposite things to a caller. bSkipped is "nothing to do here" (map not open, no
    // package) and is unremarkable; bRefused is "there WAS something to do and doing it
    // looked like data loss". Folding them together would let the summary line report a
    // refused wipe as a routine skip, and reporting a refusal as "already in sync" is
    // the same class of untruth -- which is why the refusal is NOT implemented by
    // returning early from the pre-check.
    UPROPERTY(BlueprintReadOnly, Category = "Ck|AutoTest")
    bool bRefused = false;

    UPROPERTY(BlueprintReadOnly, Category = "Ck|AutoTest")
    FString RefusalReason;

    auto
    Has_Delta() const -> bool { return Spawned > 0 || Removed > 0 || Relabeled > 0; }
};

// --------------------------------------------------------------------------------------------------------------------

// What an external-actor package under an AutoTests map's __ExternalActors__ root is.
//
// Three values, not a bool, because "we could not read this package's class metadata" is a
// third thing and both callers need it: the pre-check must not silently skip such a package
// (it treats it as a reason to run the full pass), and the wipe floor counts it as evidence
// that wrappers exist, which biases the floor toward refusing rather than destroying.
enum class ECk_AutoTestWrapperPackageKind : uint8
{
    // Class metadata read, and it is not an ACk_AutoTestRunner -- the level's floor, its
    // lights, whatever else it holds. Not the populator's business.
    NotAWrapper,

    // Class metadata read, and its nearest native parent is (or derives from)
    // ACk_AutoTestRunner.
    Wrapper,

    // No readable ActorMetaDataClass. Never silently skipped by either caller.
    UnreadableMetadata,
};

// --------------------------------------------------------------------------------------------------------------------

enum class ECk_AutoTestWipeFloorDecision : uint8
{
    // No floor has run. The DEFAULT, deliberately, and it is the whole reason this value
    // exists: with `Proceed` as the default, a default-constructed verdict declared above
    // the destructive sites both compiles and satisfies a `!= Refuse` check -- so the
    // natural response to the compile error those sites raise (hoist the declaration, assign
    // later) silently defeats the guard it was raised by. Sites therefore check for a
    // POSITIVE decision, never for "not Refuse".
    NotEvaluated = 0,

    // Nothing about this pass looks like a wipe. Carry on.
    Proceed,

    // This pass would destroy every wrapper belonging to the map. Do nothing.
    Refuse,

    // It would, and a human explicitly authorised it (opt-in CVar AND a forced pass).
    // Distinct from Proceed so the authorisation is ANNOUNCED at the moment of use --
    // otherwise a CVar left behind in an .ini makes the next wipe silent.
    ProceedAuthorised,
};

// --------------------------------------------------------------------------------------------------------------------

// --------------------------------------------------------------------------------------------------------------------

// Everything the destructive half needs that the half above it computed. A struct rather than
// seven more parameters, and passed const because none of it is the destructive half's to change --
// the one thing that IS mutable travels separately as FCkAutoTestSyncResult&.
struct CKTESTSEDITOR_API FCk_AutoTestSyncContext
{
    UWorld*   World   = nullptr;
    UPackage* Package = nullptr;

    // The set the floor was asked about. Recomputed after the world resolved, never reused
    // from the pre-check -- a pre-load snapshot must not drive a deletion.
    TArray<UClass*> WantedClasses;
    TSet<UClass*>   WantedSet;

    // Placed wrapper actors, by class. Read-only here: the destructive half decides what to
    // remove from it, never what is in it.
    TMap<UClass*, TArray<AActor*>> CurrentByClass;

    bool bWasLoadedFresh  = false;
    bool bWasDirtyOnEntry = false;
};

// --------------------------------------------------------------------------------------------------------------------

struct CKTESTSEDITOR_API FCk_AutoTestWipeFloorVerdict
{
    // Defaults to NotEvaluated, NOT Proceed. Adding the enum value without changing THIS line
    // left the fail-open default fully in place while looking fixed -- caught only because the
    // property is asserted rather than assumed.
    ECk_AutoTestWipeFloorDecision Decision = ECk_AutoTestWipeFloorDecision::NotEvaluated;

    // Short, for FCkAutoTestSyncResult::RefusalReason. Empty when Proceed.
    FString Reason;

    // The SHORT line, for the Slate toast. Set ONLY on Refuse -- that is the only decision
    // that raises a toast. ProceedAuthorised reports through a Warning carrying Explanation,
    // and Proceed reports nothing, so a Headline on either would be a field nothing reads.
    //
    // Separate from Explanation because a Slate notification silently clips a long
    // message, mid-token: the first version of this refusal rendered as
    // "...set Ck.AutoTest.Populator.AllowUnrecogn AND run..." and truncated the exact
    // console variable the reader has to type. The toast is a fading overlay and gets a
    // summary; the Message Log and Output Log hold and get everything.
    //
    // It deliberately does NOT carry the CVar name or the recovery recipe. Half a CVar
    // name is worse than none -- it looks copyable and is not -- so the toast points at
    // the Output Log and the log carries the instruction in full.
    FString Headline;

    // The full user-facing text, for the Message Log row and the Output Log. Empty when
    // Proceed.
    //
    // Built HERE rather than at the call sites because it makes a claim about
    // consequences that is only true in one of the two states this floor catches, and a
    // claim like that must be derived from the numbers rather than restated by hand.
    FString Explanation;
};

// --------------------------------------------------------------------------------------------------------------------

// Editor subsystem that keeps each registered AutoTests map in sync with the set of
// discoverable ACk_AutoTestRunner subclasses. Triggered automatically on AngelScript
// post-compile and on subsystem Initialize. Can also be triggered manually via the
// BlueprintCallable functions or the Ck.SyncAutoTestMaps console command.
//
// Layer 2A scope: the populator only operates on a config whose TargetMap is the
// currently-loaded editor world. Configs whose map is not currently open are
// reported as skipped (with a clear reason). The "edit the map even when unloaded"
// path is Layer 2B.
UCLASS(BlueprintType)
class CKTESTSEDITOR_API UCkAutoTestMapPopulator : public UEditorSubsystem
{
    GENERATED_BODY()

public:
    virtual auto
    Initialize(
        FSubsystemCollectionBase& Collection) -> void override;

    virtual auto
    Deinitialize() -> void override;

public:
    // Discovers every UCkAutoTestMapConfig in the asset registry and runs SyncConfig
    // against each. Fires automatically after every AS recompile; can also be invoked
    // manually from BP/console.
    UFUNCTION(BlueprintCallable, Category = "Ck|AutoTest")
    void
    Sync_AllConfigs();

    UFUNCTION(BlueprintCallable, Category = "Ck|AutoTest")
    FCkAutoTestSyncResult
    Sync_Config(
        UCkAutoTestMapConfig* InConfig);

public:
    // THE WIPE FLOOR. Pure, static and public so it can be tested without a world.
    //
    // Answers: "is this pass about to destroy every AutoTest wrapper belonging to this
    // map because discovery handed it an empty set?"
    //
    // Why the predicate is `wanted == 0`, and not a ratio or a threshold:
    //
    //   A ratio would be an invented constant, and the failure this floors is not a
    //   matter of degree. Discovery for one config is a single scope test -- every
    //   candidate class is kept or dropped by whether ClassScanRoot appears in the
    //   class's source path -- so when it breaks it breaks for ALL of them at once.
    //   "Wanted is empty while the map is full of wrappers" is therefore the exact
    //   signature of broken discovery, and nothing weaker is needed to catch it.
    //
    //   The converse case -- a non-empty wanted set that happens to intersect nothing
    //   placed -- is deliberately NOT refused. That is a genuinely stale map (a map
    //   copied from another project, a config repointed at a new target) and syncing it
    //   is the correct, intended thing to do. Refusing there would break the feature to
    //   guard a failure that cannot occur.
    //
    // How discovery actually breaks, so this is not a hypothetical: Discover_TestClasses
    // scopes by testing whether ClassScanRoot (e.g. "/BusterBlockTests/") is a substring
    // of the class's ABSOLUTE SOURCE FILE PATH, taken from UASClass::GetSourceFilePath().
    // A renamed or moved plugin folder, a config whose ClassScanRoot is edited to a value
    // that no longer matches, or an AS source path that comes back empty collapses the
    // wanted set to zero while every wrapper class is still resident and every wrapper
    // actor still loads -- and the orphan sweep then destroys all of them and
    // SCC-deletes their packages, on the AUTOMATIC boot path, with no console command
    // and no CVar.
    //
    // An AngelScript compile failure is NOT a trigger, and an earlier version of this
    // comment claiming it reached the on-disk cleanup passes was WRONG in both halves --
    // corrected in review, and worth stating plainly because the wrong version reads
    // perfectly plausibly:
    //   * a failed compile cannot even get here. The initial compile blocks engine init
    //     in a modal retry prompt (AngelscriptManager.cpp:1106-1120) or exits outright
    //     under a commandlet / -as-exit-on-error (:1015-1021); a failed HOT reload keeps
    //     all old script code and does NOT broadcast PostCompile (:2636-2639, :2881-2885),
    //     so the populator is never even called.
    //   * and had it got here, it would reach nothing. ULevel::PostLoad only adds objects
    //     that actually loaded as actors and then strips nulls (Level.cpp:1435-1452, :1460),
    //     so a wrapper whose class is absent leaves NO placeholder for the orphan sweep --
    //     and UPackage::GetExternalPackages finds no object either, so the stranded pass
    //     cannot see it.
    // The on-disk count below is still right; see Count_WrapperPackagesOnDisk for the
    // reasons that actually hold.
    static auto
    Get_WouldWipeUnrecognizedWrappers(
        int32 InNumWantedClasses,
        int32 InNumAssociatedWrappers) -> bool;

    // The wipe authorisation, in ONE place.
    //
    // Requires BOTH the opt-in CVar and a forced pass. The CVar alone is not enough: it
    // can sit in an .ini and outlive the intent that set it, and an automatic boot sync
    // must never be the thing that acts on a leftover. Forcing alone is not enough
    // either -- "force" says which PATH to take (do the real load-and-sync rather than
    // trust the cheap pre-check), which every console invocation says, and which is not
    // consent to destruction.
    //
    // Requiring both is exactly the recovery the refusal message already prints ("set the
    // CVar and run Ck.SyncAutoTestMaps"), so it costs the user nothing, and it means the
    // automatic path can never be the one that wipes.
    static auto
    Get_WipeAuthorisation(
        bool bInIsForcedPass) -> bool;

    // The authorisation RULE, split out from the CVar read so it can be tested for the
    // thing that matters.
    //
    // Asserting on Get_WipeAuthorisation directly is vacuous: with the CVar at its default
    // 0 the whole conjunction is false whether or not the forced clause exists, so a test
    // of it stays green with the fix reverted. Passing bInCVarSet explicitly is what makes
    // "CVar set, pass not forced -> NOT authorised" an assertion that can actually fail.
    static auto
    Get_IsWipeAuthorised(
        bool bInCVarSet,
        bool bInIsForcedPass) -> bool;

    // The whole floor DECISION, in one place: predicate, authorisation, and the wording
    // of what is reported.
    //
    // It exists because the floor is asked at TWO sites -- pre-load in the unforced
    // branch, and above the destructive sites in the full pass -- and while the rule was
    // single-sourced from the start, the HANDLING of it was not, and drifted immediately:
    // the two sites conjoined the CVar differently, only one of them announced an
    // authorised wipe, and the authorised pre-load fell through into the pre-check with
    // an empty wanted set and printed "Already in sync -- 0 wrapper(s) verified", the
    // exact untruth the refusal exists to prevent. Two sites are correct (they see
    // different evidence: disk-only before a load, disk plus loaded actors after), one
    // decision is correct, and this is that decision.
    static auto
    Evaluate_WipeFloor(
        const FString& InConfigDisplayName,
        const FString& InMapPackageName,
        int32          InNumWantedClasses,
        int32          InNumAssociatedWrappers,
        int32          InNumResidentWrapperActors,
        bool           bInWipeAuthorised) -> FCk_AutoTestWipeFloorVerdict;

    // The single rule for classifying an external-actor package, used by the pre-check and
    // by the wipe floor's count. One rule in one place on purpose: this classification
    // previously existed only inside the pre-check, where it string-compared
    // ActorMetaDataClass to ACk_AutoTestRunner's exact path -- a native subclass would have
    // made every wrapper invisible -- and a second hand-written copy elsewhere is exactly
    // how such a fix drifts back out.
    //
    // Public and static so it can be tested without a world; a regression here does not fail
    // loudly, it makes the wipe floor count zero and silently stop flooring.
    static auto
    Get_WrapperPackageKind(
        const FAssetData& InAsset) -> ECk_AutoTestWrapperPackageKind;

    // Does this decision authorise the destructive half to run?
    //
    // Pure and public so it can be tested in BOTH directions. That matters more than it looks:
    // the failure this protects against is the check being weakened -- inverted, widened to
    // include NotEvaluated -- and a test that only ever feeds it positive values stays green
    // through exactly that. This session shipped one fix that was inert while its comments read
    // correctly; a predicate asserted in one direction is the same trap.
    static auto
    Get_IsPositiveDecision(
        ECk_AutoTestWipeFloorDecision InDecision) -> bool;


private:
    // Both public entry points above are EXPLICIT requests (a user at the console, a
    // designer's Blueprint), so they force the full load-and-sync pass. The automatic
    // triggers -- subsystem Initialize and AngelScript post-compile -- call this with
    // bInForceFullSync = false, which lets Is_AlreadyInSync_FromAssetRegistry answer
    // "nothing to do" without loading any map.
    //
    // Keeping the forcing decision at the ENTRY POINT rather than inside the sync is
    // deliberate: it means "I asked for it, so do the real thing" is always available,
    // which is the bounded escape hatch for any case the cheap check gets wrong.
    auto
    Sync_AllConfigs_Internal(
        bool bInForceFullSync) -> void;

    auto
    Discover_AllConfigs() -> TArray<UCkAutoTestMapConfig*>;

    // Emits a refusal to the user, once per config per editor session. Not static: the
    // latch is session state.
    auto
    DoReport_Refusal(
        UCkAutoTestMapConfig*               InConfig,
        const FCk_AutoTestWipeFloorVerdict& InVerdict) -> void;

    // Counts the AutoTest wrapper external-actor packages that belong to InMapPackageName,
    // read from the asset registry rather than from the loaded level.
    //
    // On disk, not in memory, on purpose: the two destructive passes that survive an
    // empty Level->Actors -- the unloadable-wrapper cleanup and the stranded-external
    // cleanup -- both act on packages, so a floor that counted only loaded actors would
    // read zero exactly when those passes are the ones about to delete 1,400 files.
    static auto
    Count_WrapperPackagesOnDisk(
        const FString& InMapPackageName) -> int32;



    auto
    Sync_Config_Internal(
        UCkAutoTestMapConfig* InConfig,
        bool                  bInForceFullSync) -> FCkAutoTestSyncResult;

    // EVERY destructive line in this subsystem lives here, and nothing else does.
    //
    // That containment is the guarantee, and it is the one thing a per-site guard could not
    // buy: a destructive line added anywhere inside this function inherits the entry check with
    // nothing to remember, and the floor cannot be moved below a site because it is in another
    // function entirely.
    //
    // The verdict is a PARAMETER rather than a bare bool so the signature names what authorises
    // the call. It is not a capability: the decision field is public and this function's only
    // possible callers are members of this class, so nothing stops a member passing a
    // hand-built verdict. An earlier version wrapped it in a move-only token with a private
    // constructor and claimed that closed the gap -- review established it did not (a public
    // minting function plus a public field is a public constructor with extra steps), and the
    // claim was deleted rather than weakened. The entry ensure is the guard; the type is
    // documentation.
    auto
    DoApply_Sync(
        const FCk_AutoTestWipeFloorVerdict& InVerdict,
        UCkAutoTestMapConfig*          InConfig,
        const FCk_AutoTestSyncContext& InContext,
        FCkAutoTestSyncResult&         InOutResult) -> void;

    // Cheap pre-check: can we conclude "this config's map is already correct" WITHOUT
    // loading it?
    //
    // Why this exists: loading the target map is the entire cost of a populator pass.
    // BusterBlock's two configs pull in 1,439 external-actor packages between them and
    // take 4.89 s of blocked game-thread time in editor frame 1, on every editor boot
    // (including every automation-test boot), only to report "0 spawned, 0 removed".
    //
    // Why it is not a staleness heuristic: for an OFPA level the set of placed actors IS
    // the set of external-actor packages on disk -- the level discovers them by asset
    // registry scan of __ExternalActors__/<MapName>/, not from a manifest in the .umap
    // (which is why the OFPA save path below never writes the .umap). The asset registry
    // already carries each package's actor class (AssetClassPath), its native base
    // (ActorMetaDataClass) and its Outliner label (ActorLabel) from disk. So the same
    // question the full pass answers by loading 1,439 packages is answerable from
    // registry metadata, exactly, and the answer is not an approximation of the full
    // pass -- it is the full pass's inputs, read from the cheaper source.
    //
    // Every uncertainty resolves toward doing the work: a non-OFPA map, an
    // as-yet-unpopulated map, a package the registry has no class metadata for, a count
    // mismatch, a label mismatch, an in-memory copy of the map that might differ from
    // disk -- all return false and the full load-and-sync runs.
    auto
    Is_AlreadyInSync_FromAssetRegistry(
        UCkAutoTestMapConfig* InConfig,
        const TArray<UClass*>& InWantedClasses,
        FString&               OutReasonToLoad) -> bool;

    // Builds the set of ACk_AutoTestRunner subclasses whose source matches
    // the config's ClassScanRoot filter.
    auto
    Discover_TestClasses(
        UCkAutoTestMapConfig* InConfig) const -> TArray<UClass*>;

    static auto
    Get_AssertedSourcePathForClass(
        UClass* InClass) -> FString;

    // The Outliner label the populator assigns a wrapper: the class name with the
    // conventional "_Actor" suffix stripped. Single source of truth -- the live-actor
    // relabel pass, the on-disk stale-wrapper detection and the asset-registry
    // pre-check all derive the expected label from here. A second copy of this rule
    // would let the pre-check skip a map the full pass would have relabeled.
    static auto
    Compute_ExpectedLabelForClassName(
        const FString& InClassName) -> FString;

    static auto
    Compute_ExpectedLabelForClass(
        const UClass* InClass) -> FString;

    static auto
    Is_LiveTestRunnerSubclass(
        UClass* InClass,
        UClass* InAutoTestRunnerBase) -> bool;

    // Returns the implicit "owner scope" of a config: a path fragment used to filter
    // test classes when the config's ClassScanRoot field is left empty. Resolves
    // automatically from where the config was authored:
    //   - AS-defined assets — uses the ScriptAssetFilename metadata (set by AS-UE)
    //     to find the plugin whose Source dir contains the .as file.
    //   - On-disk .uasset configs — uses the package mount point (e.g., /CkTests/).
    // Returns an empty string if no owner can be determined; the caller treats that
    // as "scan everything".
    static auto
    Get_OwnerScopeForConfig(
        UCkAutoTestMapConfig* InConfig) -> FString;

    // Resolves the UWorld to sync against for the given config. Two paths:
    //   1. If the config's TargetMap IS the currently-active editor world, returns
    //      that live world (OutWasLoadedFresh = false). Edits become user-visible
    //      immediately and the existing dirty-state guard applies.
    //   2. Otherwise, loads the target package via LoadPackage, locates the world
    //      inside (OutWasLoadedFresh = true). The package was clean before our load,
    //      so post-edit auto-save is unconditionally safe.
    // Returns nullptr (and a populated SkipReason via OutSkipReason) on any failure.
    auto
    Find_OrLoad_TargetWorld(
        UCkAutoTestMapConfig* InConfig,
        bool& OutWasLoadedFresh,
        FString& OutSkipReason) const -> UWorld*;

    auto
    OnAngelscriptPostCompile() -> void;

    auto
    OnAssetRegistryFilesLoaded() -> void;

    auto
    Defer_SyncToNextTick(
        bool bInForceFullSync) -> void;

private:
    FDelegateHandle _PostAngelscriptCompileHandle;
    FDelegateHandle _AssetRegistryFilesLoadedHandle;

    // Config display names whose unloadable-stale-wrapper preview has already been
    // emitted this editor session. The pre-check can run several times per boot (asset
    // registry files-loaded, then every AngelScript post-compile), and the condition it
    // reports is a property of what is on disk, not of this pass -- so repeating it per
    // pass is noise, not information.
    TSet<FString> _StaleWrapperPreviewReported;

    // Same idea, for the wipe refusal's toast. Only the NOTIFICATION is latched --
    // Result.bRefused and the summary's "N REFUSED" count are recorded on every pass, so
    // the log record stays complete while the alarm fires once.
    TSet<FString> _WipeRefusalReported;
};

// --------------------------------------------------------------------------------------------------------------------
