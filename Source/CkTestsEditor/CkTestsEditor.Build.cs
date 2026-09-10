using System.IO;
using UnrealBuildTool;

public class CkTestsEditor : CkModuleRules
{
    public CkTestsEditor(ReadOnlyTargetRules Target) : base(Target)
    {
        PublicDependencyModuleNames.AddRange(new string[]
        {
            "CoreUObject",
            "Engine",
            "Slate",
            "SlateCore",
            "EditorStyle",
            "EditorFramework",
            "UnrealEd",
            "EditorSubsystem",
            "ToolMenus",
            "AssetTools",
            "AssetRegistry",
            "Projects",
            "DeveloperSettings",
            "FunctionalTesting",
            "MessageLog",
            "SourceControl",
            "Landscape",
            "NavigationSystem",

            "CkCore",
            "CkEcs",
            "CkEntitySpawner",
            "CkGroundNav",
            "CkLog",
            "CkPathNetwork",
            "CkShapes",
            "CkTests",
        });
    }
}
