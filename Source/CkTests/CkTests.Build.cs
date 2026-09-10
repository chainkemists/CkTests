using System.IO;
using UnrealBuildTool;

public class CkTests : CkModuleRules
{
    public CkTests(ReadOnlyTargetRules Target) : base(Target)
    {
        // The matched navigation harness emits raw, provider-labelled evidence records.
        PrivateDependencyModuleNames.Add("Json");

        PrivateIncludePaths.AddRange(new string[] {
            // ... add other private include paths required here ...
        });

        PrivateDependencyModuleNames.AddRange(new string[]
        {
            // The layout lifecycle fixture creates and activates CommonUI widgets directly.
            "UMG",
            "CommonUI",
            "Text3D",
            "PhysicsCore",
        });

        // Direct C API integration coverage lives in this module's private unit-test source.
        PrivateDependencyModuleNames.Add("CkYoga");
        PrivateDependencyModuleNames.Add("CkSlateLayout");
        PrivateDependencyModuleNames.Add("AppFramework"); // Exercise native color-picker behavior through authored controls.
        PrivateDependencyModuleNames.Add("ImageCore");

        RuntimeDependencies.Add(Path.Combine(PluginDirectory, "Resources", "ResourceInspector", "ResourceInspector.ui.html"), StagedFileType.NonUFS);
        RuntimeDependencies.Add(Path.Combine(PluginDirectory, "Resources", "ResourceInspector", "ResourceInspector.ui.css"), StagedFileType.NonUFS);
        RuntimeDependencies.Add(Path.Combine(PluginDirectory, "Resources", "CapabilityGallery", "CapabilityGallery.ui.html"), StagedFileType.NonUFS);
        RuntimeDependencies.Add(Path.Combine(PluginDirectory, "Resources", "CapabilityGallery", "CapabilityGallery.ui.css"), StagedFileType.NonUFS);
        RuntimeDependencies.Add(Path.Combine(PluginDirectory, "Resources", "CapabilityGallery", "Templates", "GalleryStarter.ui.html"), StagedFileType.NonUFS);
        RuntimeDependencies.Add(Path.Combine(PluginDirectory, "Resources", "CapabilityGallery", "Templates", "GalleryStarter.ui.css"), StagedFileType.NonUFS);

        PublicDependencyModuleNames.AddRange(new string[]
        {
            "Core",
            "CoreUObject",
            "DeveloperSettings",
            "Engine",
            // Public fixture config derives from UNavigationSystemModuleConfig.
            "NavigationSystem",
            "Projects",
            "GameplayTags",
            "FunctionalTesting",
            "Gauntlet",
            "EnhancedInput",
            "RenderCore",
            "RHI",
            // The CkJolt dynamic-mesh bake tests author a runtime FDynamicMesh3 (GeometryCore) on an
            // ADynamicMeshActor (GeometryFramework) — the exact runtime-generated geometry that bake serves.
            "GeometryCore",
            "GeometryFramework",
            // Direct, not inherited through CkParticles: the CkParticles authoring gate loads a UNiagaraSystem
            // itself, and the transitive public dependency did not put Niagara's import lib on this link
            // (LNK2019 on Z_Construct_UClass_UNiagaraSystem_NoRegister).
            "Niagara",
            "Voice",
            // The gym switchboard (Slate viewport widget styled with the shared CkStyle tokens).
            // Slate/SlateCore are reachable transitively via CkWidgets/CkUICore, but transitive
            // links are luck, not policy.
            "Slate",
            "SlateCore",
            "InputCore",
            "CkEditorTools",

            "CkActorRelay",
            "CkAggro",
            "CkAnimation",
            "CkAttribute",
            "CkAudio",
            "CkCamera",
            "CkCore",
            "CkCrowd",
            "CkCue",
            "CkCVar",
            "CkDebugScene",
            "CkDynamic",
            "CkEcs",
            "CkEcsExt",
            "CkEntityVisualizer",
            "CkEntityCollection",
            // Level-root persistence contracts exercise authored/runtime CkEntitySpawner identity stamping.
            "CkEntitySpawner",
            "CkEntityExtension",
            "CkEntityTag",
            "CkEqs",
            "CkFx",
            "CkGoap",
            "CkGraphics",
            "CkGrid",
            "CkInput",
            "CkInteraction",
            "CkIntent",
            "CkInventory",
            "CkIskmRenderer",
            "CkIsmRenderer",
            "CkGroundNav",
            "CkJolt",
            "CkThirdParty",
            "CkLabel",
            "CkLagCompensation",
            "CkLog",
            "CkNavigation",
            "CkObjective",
            // Public dependency on purpose: it carries the CK_WITH_PARTICLES definition that the CkParticles
            // authoring gate keys on. A private dependency would leave that define undetectable here and the
            // gate would silently skip forever.
            "CkParticles",
            "CkPathNetwork",
            "CkMinimap",
            "CkPerception",
            "CkPixelArtRenderer",
            "CkPmg",
            "CkPhysics",
            "CkProfile",
            "TraceLog", // CPU-work trace writer lifecycle fixture.
            "CkProjectile",
            "CkProvider",
            "CkQueue",
            "CkRecord",
            "CkRelationship",
            "CkRenderTarget",
            "CkResolver",
            "CkResourceLoader",
            "CkSettings",
            "CkShapes",
            "CkSnapshot",
            // CkNetAutomation_Common exposes probe payload types in its public latent-test surface.
            // Adaptive non-unity compilation requires the defining module's import library directly.
            "CkSpatialQuery",
            "CkStateMachine",
            "CkSubstep",
            "CkTagSet",
            "CkTargeting",
            "CkTimer",
            "CkWidgets",
            "CkUI",
            "CkUICore",
            "CkUnrealComponent",
            "CkUsf",
            "CkVariables",
            "CkVoiceChat",
            // The VisualLod arbiter-tuner PIE fixture creates real domain-tagged arbiters and members
            // through the public runtime utilities; do not rely on the debugger's transitive link.
            "CkVisualLod",
            "CkVoxelNav",
            "CkWatermark",
        });

        if (Target.bBuildEditor)
        {
            PrivateDependencyModuleNames.AddRange(new string[]
            {
                "UnrealEd",
                "EditorSubsystem",
                "CkUsfEditor",
                // The Jolt incremental-cook planner and index remap are pure functions living in the
                // editor cooker; their tests link against it directly.
                "CkJoltEditor",
                // The Intent Input HUD PIE fixture includes the authored debugger control and
                // waits for its real runtime LocalPlayer subsystem. Keep both Editor-only so
                // CkTests does not pull developer diagnostics into game/package targets.
                "CkIntentDebugger",
                "CkInputHudOverlay",
                "CkDebuggerCommon",
                // The PIE fixture mounts the real authored arbiter-tuners surface from its debugger host.
                "CkVisualLodDebugger",
                // The Dialog PIE fixture mounts the real four-region debugger window and routes its commands
                // through the active PIE player controller.
                "CkDialogDebugger",
                "CkDialog",
                // The Aggro PIE fixture mounts the real retained authored debugger surface over authority-world data.
                "CkAggroDebugger",
                // The AI roster PIE fixture mounts the real authored roster over public Crowd-agent state.
                "CkAiDebugger",
                // The GOAP Squad PIE fixture mounts the production authored table over a real planner roster.
                "CkGoapDebugger",
                // The Save debugger authored-navigation fixture opens an actual snapshot file through the
                // editor debugger window; keep the diagnostic host editor-only.
                "CkSaveDebugger",
                // The UI-debugger History PIE fixture mounts the real Slate debugger and drives
                // its events through the public per-player UI layout subsystem.
                "CommonUI",
                "CkUI",
                "CkUIDebugger",
                "CkGroundNavEditor",
            });
        }
    }
}
