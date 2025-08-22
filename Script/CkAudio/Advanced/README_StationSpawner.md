# AudioGym Advanced - Station Spawner System

## Overview
Instead of automatic station spawning, you now have full manual control over station placement using the `ACkAudioGym_Advanced_StationSpawner` actor.

## How to Use

### 1. Place StationSpawner Actors in Your Level
- Drag `ACkAudioGym_Advanced_StationSpawner` from the Content Browser into your level
- Position them exactly where you want each station
- **3D Text Label**: Each spawner displays "AUDIO STATION" above it to help identify placement

### 2. Configure Each StationSpawner
In the Details panel for each StationSpawner:

#### **Station EntityScript Class** (Required)
- **Spatial Station**: `UCkAudioGym_Advanced_SpatialStation`
- **Attenuation Station**: `UCkAudioGym_Advanced_AttenuationStation`
- **Concurrency Station**: `UCkAudioGym_Advanced_ConcurrencyStation`

#### **Transform Override** (Optional)
- **bOverrideStationTransform**: Check to use custom transform
- **StationTransform**: Set custom position/rotation/scale

### 3. Available Stations

#### **Spatial Station** (Orange)
- **Size**: 400x400x300 units
- **Purpose**: Test 3D positioning and thunder effects
- **Audio**: Single thunder sound with spatial positioning

#### **Attenuation Station** (Green)
- **Size**: 800x800x400 units
- **Purpose**: Test volume/frequency changes based on distance
- **Audio**: Background music with advanced attenuation settings

#### **Concurrency Station** (Purple)
- **Size**: 200x1200x300 units (narrow corridor)
- **Purpose**: Test multiple sounds playing simultaneously
- **Audio**: Up to 5 thunder sounds playing at once

## Benefits of Manual Placement

✅ **Precise Positioning**: Place stations exactly where you want them
✅ **No Overlap Issues**: You control the spacing and layout
✅ **Flexible Testing**: Test different arrangements easily
✅ **Level Design Control**: Integrate stations into your level design
✅ **Debugging**: Easier to isolate issues with individual stations
✅ **Visual Identification**: 3D text labels help identify spawner locations in the editor

## Example Setup

```
Player Start (0,0,0)
    ↓
Spatial Station (0,200,0) - Orange, 400x400
    ↓
Attenuation Station (0,800,0) - Green, 800x800
    ↓
Concurrency Station (0,1400,0) - Purple, 200x1200 corridor
```

## Troubleshooting

- **Stations not appearing**: Check that `StationEntityScriptClass` is set
- **Wrong position**: Verify actor transform or enable transform override
- **Audio not working**: Ensure player probe is overlapping with station probe
- **Audio at wrong position**: All stations now properly pass their transform to audio cues
- **Console errors**: Check that all required assets are loaded

## Next Steps

Once you have the basic stations working, you can:
1. Add more station types (fade-in/fade-out, cross-fade, multiple sounds)
2. Customize station sizes and shapes
3. Add visual effects and UI elements
4. Create complex audio testing scenarios
