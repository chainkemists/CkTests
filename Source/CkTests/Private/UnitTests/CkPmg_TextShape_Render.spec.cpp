// CkPmg text shape render test — end-to-end smoke: spawns a DrawText entity on the server
// world, ticks ~5 frames, then asserts the returned handle has a non-empty
// FFragment_Pmg_DebugShape_Lines (the wireframe tier — the most accessible end-to-end signal).
//
// Uses the PIE latent-command harness from CkNetAutomation_Common.h (same pattern as
// Test_Snapshot_FloatAttribute_Gate.spec.cpp). NumClients=1 == 1 server window, no extra clients.
//
// Surface in Session Frontend: Ck.Pmg.TextShape.RendersWireframe

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "CkPmg/CkPmg_Fragment.h"
#include "CkPmg/CkPmg_Utils_TextShapes.h"

#include "CkTests/Net/CkNetAutomation_Common.h"

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkPmg_TextShape_RendersWireframe,
    "Ck.Pmg.TextShape.RendersWireframe",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkPmg_TextShape_RendersWireframe::RunTest(const FString& Parameters)
{
    auto Handle = MakeShared<FCk_Handle_Pmg_DebugShape>();

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(1, TEXT("/Engine/Maps/Entry")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(1, 30.0f));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this, Handle](UWorld* InWorld) -> void
        {
            *Handle = UCk_Utils_Pmg_TextShapes::DrawText(
                InWorld,
                FVector::ZeroVector,
                TEXT("Ag"),
                100.0f,
                FLinearColor::White,
                /*InDrawLines=*/true,
                /*InDrawFilled=*/true,
                2.0f,
                ECk_Pmg_TextAlign::Left,
                ECk_Plane_Axis::XZ,
                /*InFontOverride=*/nullptr,
                /*InDuration=*/-1.0f);

            if (ck::Is_NOT_Valid(*Handle))
            {
                AddError(TEXT("DrawText returned invalid handle"));
            }
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(5));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this, Handle]() -> bool
        {
            auto& H = *Handle;
            if (ck::Is_NOT_Valid(H))
            {
                AddError(TEXT("text entity handle is invalid at assertion time"));
                return true;
            }

            const bool bHasLines = H.Has<ck::FFragment_Pmg_DebugShape_Lines>();
            TestTrue(TEXT("text entity has Lines fragment"), bHasLines);
            if (bHasLines)
            {
                TestTrue(TEXT("wireframe produced segments"),
                    H.Get<ck::FFragment_Pmg_DebugShape_Lines>().Get_Lines().Num() > 0);
            }
            return true;
        }),
        TEXT("text renders wireframe segments")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
