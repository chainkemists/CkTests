using System.IO;
using UnrealBuildTool;

public class CkTests : CkModuleRules
{
    public CkTests(ReadOnlyTargetRules Target) : base(Target)
    {
        PrivateIncludePaths.AddRange(new string[] {
            // ... add other private include paths required here ...
        });

        PublicDependencyModuleNames.AddRange(new string[]
        {
            "Core",
            "CoreUObject",
            "DeveloperSettings",
            "Engine",
            "GameplayTags",
            "FunctionalTesting",

            "CkCore",
            "CkCVar",
            "CkEcs",
            "CkLabel",
            "CkLog",
            "CkPerception",
            "CkProvider",
            "CkRecord",
            "CkSettings",
            "CkShapes",
            "CkUI",
            "CkWatermark",
        });
    }
}
