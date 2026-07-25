using System.IO;
using UnrealBuildTool;

public class CkTestsBridge : CkModuleRules
{
    public CkTestsBridge(ReadOnlyTargetRules Target) : base(Target)
    {
        PrivateIncludePaths.AddRange(new string[] {
            ModuleDirectory,
        });

        PublicDependencyModuleNames.AddRange(new string[]
        {
            "Core",
            "CoreUObject",
            "Engine",
            "Json",
            "JsonUtilities",
            "UnrealEd",
            "EditorSubsystem",
            "Projects",
            "DeveloperSettings",

            // Editor-presence effects while serving an interactive session (CkTestBridge_EditorPresence):
            // MainFrame for the window-title override, Slate for pushing that title to the LIVE window.
            "MainFrame",
            "Slate",
            "SlateCore",
            "FunctionalTesting",
            "AutomationController",
            "AutomationWorker",
            "AutomationTest",

            "CkCore",
            "CkEcs",
            "CkLog",
            "CkTests",
        });
    }
}
