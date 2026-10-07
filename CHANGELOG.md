# Changelog

## 1.0.1

- newly loaded samples now default to **ONE SHOT** mode after a successful load
- GATED and LOOP remain available as manual playback-mode choices
- failed or missing sample loads preserve the current playback mode

## 1.0.0

First public GitHub release of MUTA.

- six tracks × sixteen steps
- SINE / NOISE / SUB / FM / SAMPLE sources
- mutation and propagation system
- trigger and mutation probability
- per-step P-locks for supported parameters, including FX, EQ and relative PITCH behavior
- dual-bus FX P-lock architecture with delay / reverb / damage continuity
- ARP MUTA
- deterministic EUCLID morph system
- sample browser and WAV waveform analysis
- Grid / Arc / Crow / MIDI / Link integration
- CPU-oriented source-specific SuperCollider SynthDefs
- user data stored separately under `dust/data/MUTA/`
