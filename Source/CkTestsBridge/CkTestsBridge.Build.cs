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
