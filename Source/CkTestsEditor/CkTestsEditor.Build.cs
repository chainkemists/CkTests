using System.IO;
using UnrealBuildTool;

public class CkTestsEditor : CkModuleRules
{
    public CkTestsEditor(ReadOnlyTargetRules Target) : base(Target)
    {
        PublicDependencyModuleNames.AddRange(new string[]
        {
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

            "CkCore",
            "CkEcs",
            "CkLog",
            "CkTests",
        });
    }
}
