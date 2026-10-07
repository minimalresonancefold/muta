# MUTA

**MUTA** is a generative mutation sequencer for **monome norns** by **MRF — Minimal Resonance Fold**.

It is built around six tracks and sixteen steps, with controlled mutation, propagation, probability, per-step parameter locks, arpeggiation, Euclidean transformation, sample playback and flexible output routing. The aim is not to behave like a conventional groovebox, but to let patterns evolve while remaining playable and controllable.

## Version

**v1.0.1** — current public release.

This release keeps the stabilized MUTA architecture and adds the corrected sample-loading behavior: every newly loaded sample starts in **ONE SHOT** mode, while the user can still switch to GATED or LOOP afterwards.

## Requirements

- monome norns or norns shield
- current norns software recommended
- optional monome grid 128
- optional monome arc
- optional crow
- optional MIDI / Ableton Link

MUTA includes its own SuperCollider engine: `lib/Engine_Muta.sc`.

## Install with Maiden

In the Maiden REPL, run:

```text
;install https://github.com/minimalresonancefold/muta
```

Because MUTA contains a custom SuperCollider engine, restart norns after the first installation or after an engine update.

Then load:

```text
muta/muta.lua
```

Once MUTA is registered in the norns community catalog, installation and future updates can be handled directly from Maiden's Project Manager.

## Core navigation

- **E1** — change page
- **K2** — transport on most pages; contextual action on SOURCE / PITCH
- **K3** — contextual action or subpage
- **K1** — shift / modifier
- **K1 + K3** — toggle P-lock mode
- **K1 + K2** — clear P-locks on the selected step

On **SEQ**:

- **E2** — select step
- **E3** — select track
- short **K3** — toggle selected step
- long **K3** — copy / paste complete step

## Pages

`SEQ · SRC · ENV · EQ · PITCH · FX · MTX · ARP · EUCLID · MIX · OUT · CLOCK`

## Grid

The bottom row provides direct page navigation and performance controls.

- key 14 — P-lock mode
- key 15 — hold for track mute controls
- key 16 — play / stop

ARP and EUCLID page keys cycle their internal pages when pressed repeatedly.

## Samples and user data

Samples are read from:

```text
/home/we/dust/audio/MUTA/
```

MUTA stores presets and session data outside the code repository under:

```text
/home/we/dust/data/MUTA/
```

This separation means updating the script through Maiden/Git does not overwrite user presets or session data.

## Sound engine

Sources:

- SINE
- NOISE
- SUB
- FM
- SAMPLE

The engine includes a four-point EQ, delay, reverb, damage processing, global FX and per-step FX P-lock routing.

## Author

**MRF — Minimal Resonance Fold**  
GitHub: `@minimalresonancefold`

## Project status

MUTA v1.0.1 is the current GitHub/Maiden-oriented public release. Development continues through versioned Git commits and releases rather than development ZIP filenames.
