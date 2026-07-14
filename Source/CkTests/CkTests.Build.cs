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
            "Projects",
            "GameplayTags",
            "FunctionalTesting",
            "Gauntlet",
            "EnhancedInput",
            "RenderCore",

            "CkActorRelay",
            "CkAggro",
            "CkAnimation",
            "CkAttribute",
            "CkAudio",
            "CkCamera",
            "CkCore",
            "CkCue",
            "CkCVar",
            "CkDynamic",
            "CkEcs",
            "CkEcsExt",
            "CkEntityCollection",
            "CkEntityExtension",
            "CkEqs",
            "CkGraphics",
            "CkGrid",
            "CkInteraction",
            "CkInventory",
            "CkIsmRenderer",
            "CkLabel",
            "CkLagCompensation",
            "CkLog",
            "CkPathNetwork",
            "CkPerception",
            "CkPmg",
            "CkPhysics",
            "CkProfile",
            "CkProjectile",
            "CkProvider",
            "CkRecord",
            "CkRelationship",
            "CkRenderTarget",
            "CkResolver",
            "CkResourceLoader",
            "CkSettings",
            "CkShapes",
            "CkSnapshot",
            "CkStateMachine",
            "CkSubstep",
            "CkTagSet",
            "CkTargeting",
            "CkTimer",
            "CkUI",
            "CkUnrealComponent",
            "CkUsf",
            "CkVariables",
            "CkWatermark",
        });

        if (Target.bBuildEditor)
        {
            PrivateDependencyModuleNames.AddRange(new string[]
            {
                "UnrealEd",
                "EditorSubsystem",
                "CkUsfEditor",
            });
        }
    }
}
