# AI-assisted development log

The assignment brief requires documenting AI tool use, including prompts and responses.
This file records how an AI assistant was used for KolaCare and must be kept up to date
by the student for every further AI interaction.

## Tool
Claude (Anthropic), used through the Claude app in October 2026.

## Interaction 1 — project generation
**Prompt (student):** "My name is G M H Himal and IT23152632. Create Final Application and Final
Report. Read the marking rubric carefully before creating the App." (with the SE4041 Assignment 2
brief attached). Follow-up choices made by the student: build Part A + Part B; concept *plant
disease scanner*; report as a Word file.

**What the AI produced:**
* App concept, architecture and the full SwiftUI/SwiftData source for Part A (KolaCare) and Part B (Field Lab, visionOS).
* The disease catalogue JSON, Sinhala/Tamil string catalogue, app icon and synthetic sample leaf images.
* Unit and UI test suites, Create ML training script, README and user guide.
* The draft final report.

**How it was verified / what the student must still do:**
* The AI environment had no macOS/Xcode, so the code was syntax-checked but **not compiled or run**.
  The student must build in Xcode, fix any compiler errors, run all tests, and record real results.
* Colour-analysis thresholds were validated by the AI against the bundled sample images using an
  equivalent Python implementation.
* Sinhala and Tamil translations need review by a native speaker.
* Agronomic content was written as general guidance and should be checked against DOA material.
* The CoreML model must be trained by the student with Create ML (ModelTraining/README.md); accuracy
  figures in the report must come from that run.

## Interaction log template (add one per session)

| Date | Prompt (summary or verbatim) | Response used for | What I changed / verified |
|---|---|---|---|
| | | | |
