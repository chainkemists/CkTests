# AngelScript Handle Conversion Progress

Generated: 2026-01-17 17:44:01

## Summary

| Metric | Count |
|--------|-------|
| Total Files Scanned | 45 |
| Files Modified | 7 |
| Simple Renames (To_FCk_Handle_XYZ → As_XYZ) | 11 |
| Pattern Optimizations (convert-check → Is_/As_) | 3 |

## Files Processed

| File | Simple Renames | Pattern Optimizations |
|------|----------------|----------------------|
| CkAttribute\Byte\CkAttributeGym_Byte_Multiple.as | 2 | 0 |
| CkAttribute\CkAttributeGym_BasicAttributes.as | 0 | 1 |
| CkAttribute\CkAttributeGym_Integer.as | 5 | 2 |
| CkAudio\Advanced\CkAudioGym_Advanced_SpatialStation.as | 1 | 0 |
| CkGrid\CkGridSystem_GymActor.as | 1 | 0 |
| CkTween\CkTween_GymActor.as | 1 | 0 |
| Common\CkGym_Utils.as | 1 | 0 |

## Conversion Rules Applied

### Rule 1: Simple Rename
`ngelscript
// Before
Handle.To_FCk_Handle_Probe()

// After  
Handle.As_Probe()
`

### Rule 2: Convert-Check Optimization
`ngelscript
// Before
auto MaybeProbe = KilledEntity.To_FCk_Handle_Probe();
if (ck::IsValid(MaybeProbe))
{
    MaybeProbe.Request_EnableDisable(...);
}

// After
if (KilledEntity.Is_Probe())
{
    KilledEntity.As_Probe().Request_EnableDisable(...);
}
`

**Note:** Pattern optimization only applies when the converted handle is used exactly once inside the if-block.