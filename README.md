<p align="center"><img src="docs/icon-preview.png" width="120" alt="Field Lab icon"></p>

# KolaCare Field Lab — spatial crop-disease training (visionOS)

**SE4041 Mobile Application Design and Development · Assignment 2 · Part B**
G M H Himal · IT23152632 · SLIIT Faculty of Computing

Agricultural extension officers in Sri Lanka teach farmers to recognise diseases that
are seasonal, fast and hard to show on demand. **Field Lab** puts a life-size diseased
plant on the trainer's table and a whole outbreak on the classroom floor:

* **3D specimen (volume)** — a procedurally built tomato plant whose symptoms advance from
  first specks to collapse. Drag to turn it, pinch to zoom, look at any leaf and pinch to
  read what that stage means. "Watch it spread" animates progression; "Apply treatment"
  shows recovery — or why late treatment fails.
* **Outbreak field (immersive space, mixed)** — 49 plants on the real floor. A seeded
  epidemiological model spreads the disease plant-to-plant according to temperature,
  humidity and rain (rain actually falls). Trainees look at a plant and pinch to spray it
  with a limited budget of 8 sprays and watch expected yield change.
* **Lab window** — disease guide, Sri Lankan season presets (Maha monsoon, Yala dry spell,
  Up-country mist), live weather sliders and an outbreak curve chart.

## Requirements
* Xcode 16 or later with the visionOS 2 SDK and Simulator
* visionOS 2.0+

## Run
1. Open `KolaFieldLab.xcodeproj`, choose the **KolaFieldLab** scheme and *Apple Vision Pro* simulator.
2. ⌘R. Choose a disease → **Open 3D specimen** → move the stage slider.
3. **Enter outbreak field** → choose a weather preset → **Run**. In the Simulator, click a plant to treat it.
4. ⌘U runs the simulation and symptom-model tests.

## Architecture
* SwiftUI scenes (`WindowGroup`, volumetric `WindowGroup`, `ImmersiveSpace`) share one `@Observable` `AppModel`.
* RealityKit **Entity-Component-System**: `SwayComponent`/`SwaySystem` animate wind, `RainDropComponent`/`RainSystem`
  animate rain; `LeafComponent`/`FieldPlantComponent` make entities identifiable for gestures.
* `OutbreakSimulation` (pure Swift, deterministic SplitMix64 RNG) and `SymptomModel` hold all logic and are unit tested.
* `MaterialPalette` caches quantised materials; meshes are shared — ~300 entities in the field.
* No 3D assets: every model is generated from primitives so any disease and stage can be shown.
