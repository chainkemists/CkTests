#pragma once

#include "CkCore/Log/CkLog.h"
#include "CkCore/Format/CkFormat.h"

#if WITH_EDITOR
#include <Styling/AppStyle.h>
#endif

// --------------------------------------------------------------------------------------------------------------------

CKTESTSEDITOR_API DECLARE_LOG_CATEGORY_EXTERN(CkTestsEditor, Log, All);

// --------------------------------------------------------------------------------------------------------------------

namespace ck::tests_editor
{
    CK_DEFINE_LOG_FUNCTIONS(CkTestsEditor);

    // Surfaces an error simultaneously on three editor channels so it cannot be missed:
    //   1. Slate toast (bottom-right, red error icon, ~20s) — gets the user's attention.
    //   2. Message Log row under the "CkTestsEditor" listing — auto-pops on Error so the
    //      diagnostic stays visible after the toast fades.
    //   3. Output Log Error line via ck::tests_editor::Error — for CI and headless capture.
    // Returns true when the notification fired so callers can keep the predicate shape of
    // CK_LOG_ERROR_NOTIFY_IF_NOT (e.g. `if (Notify_Error(...)) { return; }`).
    //
    // Styling note: we set Info.Image directly to the brush we want rather than calling
    // Notification->SetCompletionState(CS_Fail) afterwards. SetCompletionState triggers an
    // internal "task complete" fade timer in SNotificationItem that overrides ExpireDuration,
    // collapsing a 20s toast to ~1-2s. Setting Info.Image up front gives us the red icon AND
    // lets ExpireDuration run uninterrupted.
#if WITH_EDITOR
    template <typename... TArgs>
    auto Notify_Error(const TCHAR* InFmt, TArgs&&... InArgs) -> bool
    {
        const auto& FormattedString = ck::Format_UE(InFmt, Forward<TArgs>(InArgs)...);
        const auto& FormattedText   = FText::FromString(FormattedString);

        if (auto& MessageLogModule = FModuleManager::LoadModuleChecked<FMessageLogModule>(TEXT("MessageLog"));
            MessageLogModule.IsRegisteredLogListing(LogCategory) == false)
        {
            auto InitOptions = FMessageLogInitializationOptions{};
            InitOptions.bShowFilters = true;

            MessageLogModule.RegisterLogListing(LogCategory, FText::FromName(LogCategory), InitOptions);
        }

        auto EditorInfo = FMessageLog{LogCategory};
        EditorInfo.Error(FormattedText);

        auto Info = FNotificationInfo{FormattedText};
        Info.bFireAndForget  = true;
        Info.bUseThrobber    = false;
        Info.FadeOutDuration = 0.5f;
        // Long enough to read a multi-sentence message that includes a file path
        // and a recovery action without sprinting. The Message Log row persists
        // indefinitely under the "CkTestsEditor" listing as a backstop.
        Info.ExpireDuration  = 20.0f;
        Info.Image           = FAppStyle::Get().GetBrush(TEXT("Icons.Error"));

        FSlateNotificationManager::Get().AddNotification(Info);

        Error(TEXT("{}"), FormattedString);
        return true;
    }
#else
    template <typename... TArgs>
    auto Notify_Error(const TCHAR* InFmt, TArgs&&... InArgs) -> bool
    {
        Error(InFmt, Forward<TArgs>(InArgs)...);
        return true;
    }
#endif

    // Lighter-weight cousin of Notify_Error: surfaces "we did a thing you should
    // probably know about" — not "something broke." Differentiated styling so it
    // can't be mistaken for an error at a glance:
    //   - Toast uses the blue info icon, ~12s expire.
    //   - Message Log row is added at Info severity; the listing does NOT auto-pop
    //     on Info (only on Error), so it's available if the user looks but never
    //     steals focus.
    //   - Output Log line routes through Display (user-facing screen log level)
    //     rather than Error.
    // Used for the auto-checkout success path in the AutoTest populator — the
    // populator silently modifies the user's working tree when it auto-checks-out
    // a locked .umap, and the user has no other indication that happened. This
    // helper makes the implicit modification visible without crying wolf.
    //
    // Styling note: same rationale as Notify_Error — Info.Image is set directly so
    // ExpireDuration runs uninterrupted. See Notify_Error's comment for the full
    // SetCompletionState shortcut-fade explanation.
#if WITH_EDITOR
    template <typename... TArgs>
    auto Notify_Info(const TCHAR* InFmt, TArgs&&... InArgs) -> bool
    {
        const auto& FormattedString = ck::Format_UE(InFmt, Forward<TArgs>(InArgs)...);
        const auto& FormattedText   = FText::FromString(FormattedString);

        if (auto& MessageLogModule = FModuleManager::LoadModuleChecked<FMessageLogModule>(TEXT("MessageLog"));
            MessageLogModule.IsRegisteredLogListing(LogCategory) == false)
        {
            auto InitOptions = FMessageLogInitializationOptions{};
            InitOptions.bShowFilters = true;

            MessageLogModule.RegisterLogListing(LogCategory, FText::FromName(LogCategory), InitOptions);
        }

        auto EditorInfo = FMessageLog{LogCategory};
        EditorInfo.Info(FormattedText);

        auto Info = FNotificationInfo{FormattedText};
        Info.bFireAndForget  = true;
        Info.bUseThrobber    = false;
        Info.FadeOutDuration = 0.5f;
        // Less urgent than Notify_Error but still includes a file path and an
        // action ("remember to commit/submit"). Long enough to read at a normal
        // pace; the Message Log Info row persists as a backstop.
        Info.ExpireDuration  = 12.0f;
        Info.Image           = FAppStyle::Get().GetBrush(TEXT("Icons.Info"));

        FSlateNotificationManager::Get().AddNotification(Info);

        Display(TEXT("{}"), FormattedString);
        return true;
    }
#else
    template <typename... TArgs>
    auto Notify_Info(const TCHAR* InFmt, TArgs&&... InArgs) -> bool
    {
        Display(InFmt, Forward<TArgs>(InArgs)...);
        return true;
    }
#endif
}

// --------------------------------------------------------------------------------------------------------------------
