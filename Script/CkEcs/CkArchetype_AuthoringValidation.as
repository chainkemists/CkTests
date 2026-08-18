// Authoring-ergonomics validation for UCk_ArchetypeDefinition (ECS debugger redesign,
// CkGameplayDebugger docs/specs/2026-07-10 §3.3): proves the AS asset-definition path —
// scalar defaults + imperative TArray population — compiles and loads. Mirrors the
// UCkDynamic_HandleDefinition authoring shape.
//
// Registration into ck::archetype_registry is consumer-driven (the ECS debugger scans
// definitions when it opens — redesign Phase 1); this asset only validates authoring.

asset TestArchetype_Crate of UCk_ArchetypeDefinition
{
    Name        = n"CkTests.Crate";
    DisplayName = FText::FromString("Crate (authoring validation)");
    FeatureIds.Add(n"Transform");
    FeatureIds.Add(n"Label");
    // Resolved through FCkIconStyle's dynamic lane: the basename matches a generated
    // ECk_Icon semantic ("Entity"), or a game registers its own SVG via Register_DynamicIcon.
    IconSvgPath = "Icons/Entity.svg";
    Color       = FLinearColor(0.85f, 0.65f, 0.28f);
    Priority    = 1;
}
