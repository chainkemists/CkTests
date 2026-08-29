#pragma once

#include "CoreMinimal.h"

#include <Widgets/SCompoundWidget.h>

struct FCkGym_Switchboard_Model;

// --------------------------------------------------------------------------------------------------------------------
//
// The gym switchboard's Slate root — the Group Rail layout. Visual-only by contract: the whole
// tree is HitTestInvisible and never takes keyboard focus (CkInput's Slate writer records only
// under direct viewport focus). Every keystroke arrives via the switchboard subsystem's
// input-layer captures, never via Slate events, and the subsystem calls Refresh() on every state
// change — there is no per-frame rebuild and no attribute binding, so sorts must be deterministic.
//
// --------------------------------------------------------------------------------------------------------------------

class SCkGym_Switchboard : public SCompoundWidget
{
public:
    SLATE_BEGIN_ARGS(SCkGym_Switchboard) {}
    SLATE_END_ARGS()

    void Construct(const FArguments& InArgs);

    void Refresh(const FCkGym_Switchboard_Model& InModel);

private:
    auto
    DoBuild_Rail(
        const FCkGym_Switchboard_Model& InModel) -> TSharedRef<SWidget>;

    auto
    DoBuild_RowList(
        const FCkGym_Switchboard_Model& InModel) -> TSharedRef<SWidget>;

    auto
    DoBuild_Header(
        const FCkGym_Switchboard_Model& InModel) -> TSharedRef<SWidget>;

    auto
    DoBuild_SettingsLine(
        const FCkGym_Switchboard_Model& InModel) -> TSharedRef<SWidget>;

    auto
    DoBuild_Footer(
        const FCkGym_Switchboard_Model& InModel) -> TSharedRef<SWidget>;
};
