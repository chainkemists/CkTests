#include "CkTestsEditor_Module.h"

#include "CkTestsEditor_Log.h"

// --------------------------------------------------------------------------------------------------------------------

#define LOCTEXT_NAMESPACE "FCkTestsEditorModule"

void FCkTestsEditorModule::StartupModule()
{
    ck::tests_editor::Log(TEXT("[CkTestsEditor] Module started."));
}

void FCkTestsEditorModule::ShutdownModule()
{
    ck::tests_editor::Log(TEXT("[CkTestsEditor] Module stopped."));
}

#undef LOCTEXT_NAMESPACE

IMPLEMENT_MODULE(FCkTestsEditorModule, CkTestsEditor)

// --------------------------------------------------------------------------------------------------------------------
