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
            "Gauntlet",
            "EnhancedInput",

            "CkActorRelay",
            "CkAggro",
            "CkAttribute",
            "CkAudio",
            "CkCore",
            "CkCue",
            "CkCVar",
            "CkEcs",
            "CkEcsExt",
            "CkEntityCollection",
            "CkEntityExtension",
            "CkGraphics",
            "CkInventory",
            "CkIsmRenderer",
            "CkLabel",
            "CkLog",
            "CkPerception",
            "CkPhysics",
            "CkProvider",
            "CkRecord",
            "CkRelationship",
            "CkResolver",
            "CkResourceLoader",
            "CkSettings",
            "CkShapes",
            "CkStateMachine",
            "CkSubstep",
            "CkTagSet",
            "CkTargeting",
            "CkUI",
            "CkUnrealComponent",
            "CkVariables",
            "CkWatermark",
        });

        if (Target.bBuildEditor)
        {
            PrivateDependencyModuleNames.AddRange(new string[]
            {
                "UnrealEd",
                "EditorSubsystem",
            });
        }
    }
}
