"""Creates the isolated GroundNav streaming acceptance fixture.

Run from Unreal's Python console after enabling PythonScriptPlugin:

    exec(open(r".../groundnav_streaming_acceptance_setup.py", encoding="utf-8").read())

The script deliberately has no import-time side effects.  Call ``run()`` after reviewing the
constants below.  It only creates or edits assets beneath /CkTests/GroundNavAcceptance.
"""

import unreal


ROOT = "/CkTests/GroundNavAcceptance"
MAP_PATH = ROOT + "/Maps/GroundNavStreamingAcceptance"
WEST_LEVEL_PATH = ROOT + "/Maps/GroundNavStreamingAcceptance_West"
EAST_LEVEL_PATH = ROOT + "/Maps/GroundNavStreamingAcceptance_East"
OWNERSHIP_TAG = "CkTests.GroundNavAcceptance"

# A host can supply either class.  Keep this list explicit so a fixture never silently picks an
# unrelated actor merely because its display name happens to contain "GroundNav".
HARNESS_CLASS_PATHS = (
    "/Script/CkTests.Ck_GroundNav_StreamingAcceptanceActor",
    "/Script/CkTests.Ck_GroundNavStreamingAcceptanceHarness",
    "/Script/BusterBlock.Ck_GroundNavStreamingAcceptanceHarness",
)
BINDING_CLASS_PATH = "/Script/CkGroundNav.Ck_GroundNav_StreamManifestBinding_UE"
EDITOR_UTILS_CLASS_NAMES = (
    "Ck_GroundNavStreamingAcceptance_EditorUtils",
    "CkGroundNavStreamingAcceptanceEditorUtils",
)


class FixtureError(RuntimeError):
    pass


def _log(message):
    unreal.log("[GroundNavAcceptance] " + message)


def _fail(message):
    unreal.log_error("[GroundNavAcceptance] " + message)
    raise FixtureError(message)


def _has_callable(owner, name):
    return owner is not None and callable(getattr(owner, name, None))


def _load_first_class(paths, required_label):
    for path in paths:
        try:
            loaded = unreal.load_class(None, path)
        except Exception:
            loaded = None
        if loaded is not None:
            return loaded
    _fail("Could not resolve {}. Tried: {}".format(required_label, ", ".join(paths)))


def _find_python_type(candidate_names):
    for name in candidate_names:
        reflected_type = getattr(unreal, name, None)
        if reflected_type is not None:
            return reflected_type

    normalized_candidates = {name.replace("_", "").lower() for name in candidate_names}
    for name in dir(unreal):
        if name.replace("_", "").lower() in normalized_candidates:
            return getattr(unreal, name)
    return None


def _preflight():
    """Reject before creating/saving anything when this editor cannot create streamed levels."""
    required = (
        (unreal.EditorLevelLibrary, "new_level"),
        (unreal.EditorLevelLibrary, "load_level"),
        (unreal.EditorLevelLibrary, "save_current_level"),
        (unreal.EditorLevelLibrary, "spawn_actor_from_class"),
    )
    missing = [name for owner, name in required if not _has_callable(owner, name)]
    if missing:
        _fail("Editor scripting support is incomplete; missing {}.".format(", ".join(missing)))

    harness_class = _load_first_class(HARNESS_CLASS_PATHS, "GroundNav streaming acceptance harness class")

    editor_utils = _find_python_type(EDITOR_UTILS_CLASS_NAMES)
    required_utils = ("create_or_add_streaming_level", "make_named_level_current",
                      "restore_persistent_current_level", "save_dirty_fixture_levels",
                      "create_volume_spawner", "create_path_network_actor",
                      "delete_owned_actors_in_current_level")
    if editor_utils is None or any(not _has_callable(editor_utils, name) for name in required_utils):
        visible_matches = [name for name in dir(unreal) if "groundnavstreamingacceptance" in name.replace("_", "").lower()]
        _fail("CkTestsEditor GroundNav acceptance editor bridge is unavailable (visible matches: {}). "
              "Restart the editor on the freshly built binary; no assets were saved."
              .format(visible_matches))

    return harness_class, editor_utils


def _asset_exists(asset_path):
    return unreal.EditorAssetLibrary.does_asset_exist(asset_path)


def _delete_owned_actors(editor_utils):
    editor_utils.delete_owned_actors_in_current_level(unreal.Name(OWNERSHIP_TAG))


def _tag_and_label(actor, label):
    actor.tags = list(actor.tags) + [unreal.Name(OWNERSHIP_TAG)]
    actor.set_actor_label(label)
    return actor


def _spawn(actor_class, location, label, rotation=None):
    rotation = rotation or unreal.Rotator()
    actor = unreal.EditorLevelLibrary.spawn_actor_from_class(actor_class, location, rotation)
    if actor is None:
        _fail("Failed to spawn {}.".format(label))
    return _tag_and_label(actor, label)


def _set_if_present(target, property_name, value):
    try:
        target.set_editor_property(property_name, value)
        return True
    except Exception:
        _log("{} has no writable '{}' property; leaving its default.".format(target.get_name(), property_name))
        return False


def _make_floor(label, location, scale, material=None):
    actor = _spawn(unreal.StaticMeshActor, location, label)
    component = actor.static_mesh_component
    mesh = unreal.load_asset("/Engine/BasicShapes/Cube.Cube")
    if mesh is None:
        _fail("Engine cube mesh is unavailable.")
    component.set_static_mesh(mesh)
    actor.set_actor_scale3d(scale)
    if material is not None:
        component.set_material(0, material)
    return actor


def _make_label(text, location):
    actor = _spawn(unreal.TextRenderActor, location, "Label_" + text.replace(" ", "_"))
    component = actor.text_render
    _set_if_present(component, "text", unreal.Text(text))
    _set_if_present(component, "world_size", 90.0)
    actor.set_actor_rotation(unreal.Rotator(0.0, 0.0, 0.0), False)
    return actor


def _create_or_replace_plain_level(level_path, editor_utils):
    if _asset_exists(level_path):
        if not unreal.EditorLevelLibrary.load_level(level_path):
            _fail("Could not load existing level {}.".format(level_path))
        _delete_owned_actors(editor_utils)
        return
    if not unreal.EditorLevelLibrary.new_level(level_path):
        _fail("Could not create level {}.".format(level_path))


def _create_streamed_level(level_path, editor_utils):
    if not editor_utils.create_or_add_streaming_level(level_path):
        _fail("CkTestsEditor could not create or add streamed level {}.".format(level_path))


def _create_geometry():
    floor_material = unreal.load_asset("/Engine/BasicShapes/BasicShapeMaterial.BasicShapeMaterial")
    _make_floor("Ramp", unreal.Vector(0.0, -400.0, 125.0), unreal.Vector(4.0, 2.5, 0.35), floor_material).set_actor_rotation(
        unreal.Rotator(0.0, -18.0, 0.0), False)
    _make_floor("UpperFloor", unreal.Vector(0.0, 500.0, 350.0), unreal.Vector(3.5, 2.5, 0.25), floor_material)
    _make_label("WEST: load this level", unreal.Vector(-900.0, -650.0, 120.0))
    _make_label("EAST: load this level", unreal.Vector(900.0, -650.0, 120.0))
    _make_label("UPPER FLOOR", unreal.Vector(0.0, 500.0, 480.0))


def _spawn_binding(partition_id, tile_coords, location, label):
    try:
        binding_class = unreal.load_class(None, BINDING_CLASS_PATH)
    except Exception:
        binding_class = None
    if binding_class is None:
        _fail("GroundNav manifest binding class is unavailable: {}".format(BINDING_CLASS_PATH))
    binding = _spawn(binding_class, location, label)
    required = (
        _set_if_present(binding, "streaming_volume_id", 71001),
        _set_if_present(binding, "partition_id", partition_id),
        _set_if_present(binding, "data_layer_names", []),
        _set_if_present(binding, "tile_coords", [unreal.IntPoint(x, y) for x, y in tile_coords]),
    )
    if not all(required):
        _fail("Could not configure every reflected property on {}.".format(label))


def run():
    """Create/update the complete fixture. Safe to rerun after a successful first run."""
    harness_class, editor_utils = _preflight()
    _create_or_replace_plain_level(MAP_PATH, editor_utils)
    _create_streamed_level(WEST_LEVEL_PATH, editor_utils)
    _create_streamed_level(EAST_LEVEL_PATH, editor_utils)
    if not editor_utils.restore_persistent_current_level():
        _fail("CkTestsEditor could not restore the persistent acceptance level.")
    _create_geometry()
    volume = editor_utils.create_volume_spawner()
    if volume is None:
        _fail("CkTestsEditor could not create the manifest-driven GroundNav volume.")
    _tag_and_label(volume, "GroundNavAcceptance_Volume")
    path_network = editor_utils.create_path_network_actor()
    if path_network is None:
        _fail("CkTestsEditor could not create the PathNetwork acceptance actor.")
    _tag_and_label(path_network, "GroundNavAcceptance_PathNetwork")
    _spawn(harness_class, unreal.Vector(0.0, 0.0, 150.0), "GroundNavStreamingAcceptanceHarness")

    partitions = (
        (WEST_LEVEL_PATH, 1, ((0, 0), (0, 1)), unreal.Vector(-400.0, 0.0, 100.0), "West"),
        (EAST_LEVEL_PATH, 2, ((1, 0), (1, 1)), unreal.Vector(400.0, 0.0, 100.0), "East"),
    )
    for level_path, partition_id, tile_coords, location, side in partitions:
        if not editor_utils.make_named_level_current(level_path):
            _fail("CkTestsEditor could not make {} current.".format(level_path))
        _delete_owned_actors(editor_utils)
        _make_floor("{}StreamingFloor".format(side),
                    unreal.Vector(location.x, 0.0, -50.0), unreal.Vector(4.0, 8.0, 0.5))
        _spawn_binding(partition_id, tile_coords, location, "GroundNavAcceptance_Binding_" + side)

    if not editor_utils.restore_persistent_current_level() or not editor_utils.save_dirty_fixture_levels():
        _fail("CkTestsEditor could not save the GroundNav acceptance fixture levels.")

    _log("Fixture saved: {}".format(MAP_PATH))
    _log("Immediate test: press PIE; the on-screen harness automatically runs Reset/Load/Deactivate/Reactivate/Unload.")
    _log("Authored level-streaming lane: BusterBlock's cook must generate the source manifests before it can pass.")
    _log("Editor test: use GroundNavAcceptance_PathNetwork with the GroundNav snap utility, then Undo/Redo.")


if __name__ == "__main__":
    run()
