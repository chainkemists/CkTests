# GroundNav streaming acceptance fixture

Open the host project and choose **Tools > Execute Python Script**, then select:

`D:\Repos\CkPlugins_3\Plugins\CkTests\Content\Python\groundnav_streaming_acceptance_setup.py`

The project's editor-only `PythonScriptPlugin` entry is already enabled. The script creates, saves,
and opens the fixture without requiring manual level authoring.

The generator owns only `/CkTests/GroundNavAcceptance`. It is rerunnable: it removes actors tagged
`CkTests.GroundNavAcceptance` from each current fixture level and rebuilds the visible floor, ramp, upper
floor, labels, optional Ck PathNetwork actor, and the host's GroundNav streaming harness actor.

The script creates a fully configured manifest-driven GroundNav volume, a PathNetwork with four
candidate points, a runtime acceptance harness, and West/East manifest bindings with stable,
complete, disjoint volume/partition/tile identities.

`CkTestsEditor` supplies the ordinary streaming-level bridge used by the script. Rebuild the editor
after pulling the C++ change. The bridge refuses map packages outside the fixture root and saves only
dirty fixture maps, preserving unrelated dirty levels.

After generation, press PIE. The in-memory harness automatically runs the production lifecycle
Reset, Load, Deactivate, Reactivate, and Unload operations and shows a PASS/FAIL row for each. This
immediate lane deliberately does not claim manifest, level-streaming, World Partition, or data-layer
coverage.

The West/East authored streaming lane is ready for BusterBlock's dry cook and real cook to generate
its manifests. After those assets exist, the same map can validate actual level add/remove behavior.
That cooked lane also supplies the editor GroundNav field needed for the PathNetwork snap and
Undo/Redo check; it is intentionally deferred with the BusterBlock cook.
