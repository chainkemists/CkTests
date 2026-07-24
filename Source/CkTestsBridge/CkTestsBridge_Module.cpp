#include "CkTestsBridge_Module.h"

#include "CkTestsBridge_Log.h"

#define LOCTEXT_NAMESPACE "FCkTestsBridgeModule"

// --------------------------------------------------------------------------------------------------------------------

auto
    FCkTestsBridgeModule::
    StartupModule()
    -> void
{
    // The live-editor bridge is a UEditorSubsystem (UCkTestBridge_Subsystem) — it auto-registers with the
    // editor subsystem collection, so there is nothing to wire up here. The warm-server variant is the SAME
    // subsystem, kept serving by the -CkTestBridgeServe command-line flag (see CkTestBridge_Subsystem.h).
    ck::tests_bridge::Verbose(TEXT("[Module] CkTestsBridge started"));
}

auto
    FCkTestsBridgeModule::
    ShutdownModule()
    -> void
{
    ck::tests_bridge::Verbose(TEXT("[Module] CkTestsBridge shutting down"));
}

// --------------------------------------------------------------------------------------------------------------------

#undef LOCTEXT_NAMESPACE

IMPLEMENT_MODULE(FCkTestsBridgeModule, CkTestsBridge)
