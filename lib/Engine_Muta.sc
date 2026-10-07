// MUTA v1.0.1 - specialized source voices + surgical 4-point EQ
// Sources: sine / noise / sub / FM / sample
// Mutations: FM, phase distortion, wavefold, noise texture, pseudo-grain, drift
// FX: mutation delay, dark reverb, DAMAGE processor

Engine_Muta : CroneEngine {
  var voiceParams;
  var fxBus;
  var pfxBus;
  var group;
  var fxSynth;
  var pfxSynth;
  var sampleBuf;

  alloc {
    group = Group.new(Crone.server);
    fxBus = Bus.audio(Crone.server, 2);
    pfxBus = Bus.audio(Crone.server, 2);

    SynthDef("MutaSine", {
      arg out = 0, freq = 220, amp = 0.4, attack = 0.006, decay = 0.16, sustain = 0.75, release = 0.2,
      cutoff = 2500, pw = 0.5, pan = 0, source = 1, grain = 0.3, fold = 0.1, fm = 0.1, phase = 0, noise = 0.0,
      eq_low = 0.0, eq_lomid = 0.0, eq_himid = 0.0, eq_high = 0.0,
      eq_low_x = 0.10, eq_lomid_x = 0.36, eq_himid_x = 0.64, eq_high_x = 0.90,
      sample_start = 0.0, sample_end = 1.0, sample_mode = 1, bufnum = 0;

      var env, snapEnv, drift, mod, phaseWarp, sig, drive, filtFreq, presenceAmt;
      var lowFreq, loMidFreq, hiMidFreq, highFreq, lowGain, highGain, midQ1, midQ2, lowCut, highCut;
      var sine;
      drift = LFNoise1.kr(0.18 + (grain * 3.5)).range(1 - (phase * 0.018), 1 + (phase * 0.018));
      freq = (freq * drift).clip(20, 12000);
      env = Env([0, 1, sustain.clip(0, 1), sustain.clip(0, 1), 0],
        [attack.clip(0.001, 1.5), decay.clip(0.005, 1.8), 0.025, release.clip(0.02, 3.0)], [-4, -4, 0, -4]).kr(doneAction: 2) * amp.clip(0, 1.35);
      snapEnv = Env.perc(0.001, 0.018, 1.0, -5).kr(doneAction: 0);
      mod = SinOsc.ar(freq * (1.0 + (phase * 4.0)), phase * 6.28318) * (freq * fm.clip(0, 1) * 1.15);
      phaseWarp = SinOsc.ar(freq * (1 + (fm * 0.35)) + mod, phase * 6.28318);
      sine = ((phaseWarp * (1 + (phase * 2.5))).tanh * (1 - (phase * 0.22)))
        + (SinOsc.ar(freq + (mod * 0.20)) * 0.22) + (SinOsc.ar(freq * 2.0) * 0.055) + (SinOsc.ar(freq * 1.5) * 0.035);
      // Source-aware cleanup: removes sub-rumble without thinning the played fundamental.
      sig = HPF.ar(sine * 1.18, (freq * 0.18).clip(28, 70));
      presenceAmt = 2.2;
      sig = sig + (sig * snapEnv * 0.065);
      sig = sig + WhiteNoise.ar(noise.clip(0, 1) * 0.18);

      drive = 1 + (fold.clip(0, 1) * 14);
      sig = (sig * drive).fold2(1.0) * (1 / drive.sqrt);
      sig = (sig + (sig.squared * fold * 0.15)).softclip;
      filtFreq = cutoff.clip(90, 15500) * (0.82 + (env * 1.65));
      sig = RLPF.ar(sig, filtFreq.clip(80, 17000), 0.24 + ((1 - grain.clip(0, 1)) * 0.58));
      sig = BHiShelf.ar(sig, 4200, 0.75, presenceAmt);

      // V12.5 EQ V2: wider musical ranges, stronger cuts, adaptive-Q mids and true edge cuts.
      lowFreq = eq_low_x.clip(0.00, 0.30).linexp(0.00, 0.30, 30, 300);
      loMidFreq = eq_lomid_x.clip(0.18, 0.52).linexp(0.18, 0.52, 100, 2000);
      hiMidFreq = eq_himid_x.clip(0.48, 0.82).linexp(0.48, 0.82, 500, 8000);
      highFreq = eq_high_x.clip(0.70, 1.00).linexp(0.70, 1.00, 2000, 16000);
      lowGain = eq_low.clip(-1, 0).linlin(-1, 0, -24, 0) + eq_low.clip(0, 1).linlin(0, 1, 0, 12);
      highGain = eq_high.clip(-1, 0).linlin(-1, 0, -24, 0) + eq_high.clip(0, 1).linlin(0, 1, 0, 12);
      midQ1 = eq_lomid.abs.linlin(0, 1, 1.15, 0.42);
      midQ2 = eq_himid.abs.linlin(0, 1, 1.15, 0.42);
      sig = BLowShelf.ar(sig, lowFreq, 0.85, lowGain);
      sig = BPeakEQ.ar(sig, loMidFreq, midQ1, eq_lomid.clip(-1, 1) * 18);
      sig = BPeakEQ.ar(sig, hiMidFreq, midQ2, eq_himid.clip(-1, 1) * 18);
      sig = BHiShelf.ar(sig, highFreq, 0.85, highGain);
      // At the bottom of LOW / HIGH, shelves progressively become real HPF / LPF cuts.
      lowCut = eq_low.clip(-1, -0.72).linlin(-0.72, -1, 25, lowFreq);
      highCut = eq_high.clip(-1, -0.72).linlin(-0.72, -1, 19000, highFreq);
      sig = HPF.ar(sig, lowCut.clip(20, 1200));
      sig = LPF.ar(sig, highCut.clip(500, 20000));
      sig = LeakDC.ar(sig);
      sig = Pan2.ar(sig * env, pan.clip(-1, 1));
      Out.ar(out, sig);
    }).add;



    SynthDef("MutaNoise", {
      arg out = 0, freq = 220, amp = 0.4, attack = 0.006, decay = 0.16, sustain = 0.75, release = 0.2,
      cutoff = 2500, pw = 0.5, pan = 0, source = 1, grain = 0.3, fold = 0.1, fm = 0.1, phase = 0, noise = 0.0,
      eq_low = 0.0, eq_lomid = 0.0, eq_himid = 0.0, eq_high = 0.0,
      eq_low_x = 0.10, eq_lomid_x = 0.36, eq_himid_x = 0.64, eq_high_x = 0.90,
      sample_start = 0.0, sample_end = 1.0, sample_mode = 1, bufnum = 0;

      var env, snapEnv, drift, mod, phaseWarp, sig, drive, filtFreq, presenceAmt;
      var lowFreq, loMidFreq, hiMidFreq, highFreq, lowGain, highGain, midQ1, midQ2, lowCut, highCut;
      var noisy;
      drift = LFNoise1.kr(0.18 + (grain * 3.5)).range(1 - (phase * 0.018), 1 + (phase * 0.018));
      freq = (freq * drift).clip(20, 12000);
      env = Env([0, 1, sustain.clip(0, 1), sustain.clip(0, 1), 0],
        [attack.clip(0.001, 1.5), decay.clip(0.005, 1.8), 0.025, release.clip(0.02, 3.0)], [-4, -4, 0, -4]).kr(doneAction: 2) * amp.clip(0, 1.35);
      snapEnv = Env.perc(0.001, 0.018, 1.0, -5).kr(doneAction: 0);
      noisy = BPF.ar(WhiteNoise.ar(1.08), (freq * (1.8 + (phase * 12))).clip(120, 12500), 0.11 + (grain * 0.58));
      noisy = noisy + Decay2.ar(Dust.ar(3 + (noise.clip(0, 1) * 24)), 0.001, 0.025, noise.clip(0, 1) * 0.10);
      sig = HPF.ar(noisy * 1.08, 55);
      presenceAmt = 1.4;
      sig = sig + (sig * snapEnv * 0.065);
      sig = sig + WhiteNoise.ar(noise.clip(0, 1) * 0.18);

      drive = 1 + (fold.clip(0, 1) * 14);
      sig = (sig * drive).fold2(1.0) * (1 / drive.sqrt);
      sig = (sig + (sig.squared * fold * 0.15)).softclip;
      filtFreq = cutoff.clip(90, 15500) * (0.82 + (env * 1.65));
      sig = RLPF.ar(sig, filtFreq.clip(80, 17000), 0.24 + ((1 - grain.clip(0, 1)) * 0.58));
      sig = BHiShelf.ar(sig, 4200, 0.75, presenceAmt);

      // V12.5 EQ V2: wider musical ranges, stronger cuts, adaptive-Q mids and true edge cuts.
      lowFreq = eq_low_x.clip(0.00, 0.30).linexp(0.00, 0.30, 30, 300);
      loMidFreq = eq_lomid_x.clip(0.18, 0.52).linexp(0.18, 0.52, 100, 2000);
      hiMidFreq = eq_himid_x.clip(0.48, 0.82).linexp(0.48, 0.82, 500, 8000);
      highFreq = eq_high_x.clip(0.70, 1.00).linexp(0.70, 1.00, 2000, 16000);
      lowGain = eq_low.clip(-1, 0).linlin(-1, 0, -24, 0) + eq_low.clip(0, 1).linlin(0, 1, 0, 12);
      highGain = eq_high.clip(-1, 0).linlin(-1, 0, -24, 0) + eq_high.clip(0, 1).linlin(0, 1, 0, 12);
      midQ1 = eq_lomid.abs.linlin(0, 1, 1.15, 0.42);
      midQ2 = eq_himid.abs.linlin(0, 1, 1.15, 0.42);
      sig = BLowShelf.ar(sig, lowFreq, 0.85, lowGain);
      sig = BPeakEQ.ar(sig, loMidFreq, midQ1, eq_lomid.clip(-1, 1) * 18);
      sig = BPeakEQ.ar(sig, hiMidFreq, midQ2, eq_himid.clip(-1, 1) * 18);
      sig = BHiShelf.ar(sig, highFreq, 0.85, highGain);
      // At the bottom of LOW / HIGH, shelves progressively become real HPF / LPF cuts.
      lowCut = eq_low.clip(-1, -0.72).linlin(-0.72, -1, 25, lowFreq);
      highCut = eq_high.clip(-1, -0.72).linlin(-0.72, -1, 19000, highFreq);
      sig = HPF.ar(sig, lowCut.clip(20, 1200));
      sig = LPF.ar(sig, highCut.clip(500, 20000));
      sig = LeakDC.ar(sig);
      sig = Pan2.ar(sig * env, pan.clip(-1, 1));
      Out.ar(out, sig);
    }).add;



    SynthDef("MutaSub", {
      arg out = 0, freq = 220, amp = 0.4, attack = 0.006, decay = 0.16, sustain = 0.75, release = 0.2,
      cutoff = 2500, pw = 0.5, pan = 0, source = 1, grain = 0.3, fold = 0.1, fm = 0.1, phase = 0, noise = 0.0,
      eq_low = 0.0, eq_lomid = 0.0, eq_himid = 0.0, eq_high = 0.0,
      eq_low_x = 0.10, eq_lomid_x = 0.36, eq_himid_x = 0.64, eq_high_x = 0.90,
      sample_start = 0.0, sample_end = 1.0, sample_mode = 1, bufnum = 0;

      var env, snapEnv, drift, mod, phaseWarp, sig, drive, filtFreq, presenceAmt;
      var lowFreq, loMidFreq, hiMidFreq, highFreq, lowGain, highGain, midQ1, midQ2, lowCut, highCut;
      var sub;
      drift = LFNoise1.kr(0.18 + (grain * 3.5)).range(1 - (phase * 0.018), 1 + (phase * 0.018));
      freq = (freq * drift).clip(20, 12000);
      env = Env([0, 1, sustain.clip(0, 1), sustain.clip(0, 1), 0],
        [attack.clip(0.001, 1.5), decay.clip(0.005, 1.8), 0.025, release.clip(0.02, 3.0)], [-4, -4, 0, -4]).kr(doneAction: 2) * amp.clip(0, 1.35);
      snapEnv = Env.perc(0.001, 0.018, 1.0, -5).kr(doneAction: 0);
      mod = SinOsc.ar(freq * (1.0 + (phase * 4.0)), phase * 6.28318) * (freq * fm.clip(0, 1) * 1.15);
      sub = SinOsc.ar((freq * 0.5 + (mod * 0.10)).clip(20, 8000))
        + (SinOsc.ar(freq * 0.25).softclip * 0.22) + (SinOsc.ar(freq) * 0.10);
      // SUB deliberately keeps its weight; only inaudible/DC energy is removed.
      sig = HPF.ar(sub * 1.24, 22);
      presenceAmt = 1.7;
      sig = sig + (sig * snapEnv * 0.065);
      sig = sig + WhiteNoise.ar(noise.clip(0, 1) * 0.18);

      drive = 1 + (fold.clip(0, 1) * 14);
      sig = (sig * drive).fold2(1.0) * (1 / drive.sqrt);
      sig = (sig + (sig.squared * fold * 0.15)).softclip;
      filtFreq = cutoff.clip(90, 15500) * (0.82 + (env * 1.65));
      sig = RLPF.ar(sig, filtFreq.clip(80, 17000), 0.24 + ((1 - grain.clip(0, 1)) * 0.58));
      sig = BHiShelf.ar(sig, 4200, 0.75, presenceAmt);

      // V12.5 EQ V2: wider musical ranges, stronger cuts, adaptive-Q mids and true edge cuts.
      lowFreq = eq_low_x.clip(0.00, 0.30).linexp(0.00, 0.30, 30, 300);
      loMidFreq = eq_lomid_x.clip(0.18, 0.52).linexp(0.18, 0.52, 100, 2000);
      hiMidFreq = eq_himid_x.clip(0.48, 0.82).linexp(0.48, 0.82, 500, 8000);
      highFreq = eq_high_x.clip(0.70, 1.00).linexp(0.70, 1.00, 2000, 16000);
      lowGain = eq_low.clip(-1, 0).linlin(-1, 0, -24, 0) + eq_low.clip(0, 1).linlin(0, 1, 0, 12);
      highGain = eq_high.clip(-1, 0).linlin(-1, 0, -24, 0) + eq_high.clip(0, 1).linlin(0, 1, 0, 12);
      midQ1 = eq_lomid.abs.linlin(0, 1, 1.15, 0.42);
      midQ2 = eq_himid.abs.linlin(0, 1, 1.15, 0.42);
      sig = BLowShelf.ar(sig, lowFreq, 0.85, lowGain);
      sig = BPeakEQ.ar(sig, loMidFreq, midQ1, eq_lomid.clip(-1, 1) * 18);
      sig = BPeakEQ.ar(sig, hiMidFreq, midQ2, eq_himid.clip(-1, 1) * 18);
      sig = BHiShelf.ar(sig, highFreq, 0.85, highGain);
      // At the bottom of LOW / HIGH, shelves progressively become real HPF / LPF cuts.
      lowCut = eq_low.clip(-1, -0.72).linlin(-0.72, -1, 25, lowFreq);
      highCut = eq_high.clip(-1, -0.72).linlin(-0.72, -1, 19000, highFreq);
      sig = HPF.ar(sig, lowCut.clip(20, 1200));
      sig = LPF.ar(sig, highCut.clip(500, 20000));
      sig = LeakDC.ar(sig);
      sig = Pan2.ar(sig * env, pan.clip(-1, 1));
      Out.ar(out, sig);
    }).add;



    SynthDef("MutaFM", {
      arg out = 0, freq = 220, amp = 0.4, attack = 0.006, decay = 0.16, sustain = 0.75, release = 0.2,
      cutoff = 2500, pw = 0.5, pan = 0, source = 1, grain = 0.3, fold = 0.1, fm = 0.1, phase = 0, noise = 0.0,
      eq_low = 0.0, eq_lomid = 0.0, eq_himid = 0.0, eq_high = 0.0,
      eq_low_x = 0.10, eq_lomid_x = 0.36, eq_himid_x = 0.64, eq_high_x = 0.90,
      sample_start = 0.0, sample_end = 1.0, sample_mode = 1, bufnum = 0;

      var env, snapEnv, drift, mod, phaseWarp, sig, drive, filtFreq, presenceAmt;
      var lowFreq, loMidFreq, hiMidFreq, highFreq, lowGain, highGain, midQ1, midQ2, lowCut, highCut;
      var fmVoice, ratio, grainGate;
      drift = LFNoise1.kr(0.18 + (grain * 3.5)).range(1 - (phase * 0.018), 1 + (phase * 0.018));
      freq = (freq * drift).clip(20, 12000);
      env = Env([0, 1, sustain.clip(0, 1), sustain.clip(0, 1), 0],
        [attack.clip(0.001, 1.5), decay.clip(0.005, 1.8), 0.025, release.clip(0.02, 3.0)], [-4, -4, 0, -4]).kr(doneAction: 2) * amp.clip(0, 1.35);
      snapEnv = Env.perc(0.001, 0.018, 1.0, -5).kr(doneAction: 0);
      ratio = Select.kr((phase * 4).clip(0, 3), [1, 1.5, 2, 3]);
      fmVoice = SinOsc.ar((freq + (SinOsc.ar(freq * ratio, phase * 6.28318) * freq * fm.clip(0, 1) * 1.7)).clip(20, 12000));
      grainGate = Decay2.ar(Dust.ar(2 + (grain * 10)), 0.001, 0.010 + (grain * 0.030));
      // Less fixed half-frequency energy than V12.4.4: clearer stacking, same FM identity.
      fmVoice = (fmVoice + (SinOsc.ar(freq * 0.5) * 0.09) + (SinOsc.ar(freq * (ratio + 1)) * grainGate * 0.22)).softclip;
      sig = HPF.ar(fmVoice * 1.13, 38);
      presenceAmt = 2.0;
      sig = sig + (sig * snapEnv * 0.065);
      sig = sig + WhiteNoise.ar(noise.clip(0, 1) * 0.18);

      drive = 1 + (fold.clip(0, 1) * 14);
      sig = (sig * drive).fold2(1.0) * (1 / drive.sqrt);
      sig = (sig + (sig.squared * fold * 0.15)).softclip;
      filtFreq = cutoff.clip(90, 15500) * (0.82 + (env * 1.65));
      sig = RLPF.ar(sig, filtFreq.clip(80, 17000), 0.24 + ((1 - grain.clip(0, 1)) * 0.58));
      sig = BHiShelf.ar(sig, 4200, 0.75, presenceAmt);

      // V12.5 EQ V2: wider musical ranges, stronger cuts, adaptive-Q mids and true edge cuts.
      lowFreq = eq_low_x.clip(0.00, 0.30).linexp(0.00, 0.30, 30, 300);
      loMidFreq = eq_lomid_x.clip(0.18, 0.52).linexp(0.18, 0.52, 100, 2000);
      hiMidFreq = eq_himid_x.clip(0.48, 0.82).linexp(0.48, 0.82, 500, 8000);
      highFreq = eq_high_x.clip(0.70, 1.00).linexp(0.70, 1.00, 2000, 16000);
      lowGain = eq_low.clip(-1, 0).linlin(-1, 0, -24, 0) + eq_low.clip(0, 1).linlin(0, 1, 0, 12);
      highGain = eq_high.clip(-1, 0).linlin(-1, 0, -24, 0) + eq_high.clip(0, 1).linlin(0, 1, 0, 12);
      midQ1 = eq_lomid.abs.linlin(0, 1, 1.15, 0.42);
      midQ2 = eq_himid.abs.linlin(0, 1, 1.15, 0.42);
      sig = BLowShelf.ar(sig, lowFreq, 0.85, lowGain);
      sig = BPeakEQ.ar(sig, loMidFreq, midQ1, eq_lomid.clip(-1, 1) * 18);
      sig = BPeakEQ.ar(sig, hiMidFreq, midQ2, eq_himid.clip(-1, 1) * 18);
      sig = BHiShelf.ar(sig, highFreq, 0.85, highGain);
      // At the bottom of LOW / HIGH, shelves progressively become real HPF / LPF cuts.
      lowCut = eq_low.clip(-1, -0.72).linlin(-0.72, -1, 25, lowFreq);
      highCut = eq_high.clip(-1, -0.72).linlin(-0.72, -1, 19000, highFreq);
      sig = HPF.ar(sig, lowCut.clip(20, 1200));
      sig = LPF.ar(sig, highCut.clip(500, 20000));
      sig = LeakDC.ar(sig);
      sig = Pan2.ar(sig * env, pan.clip(-1, 1));
      Out.ar(out, sig);
    }).add;



    SynthDef("MutaSampleGate", {
      arg out = 0, freq = 220, amp = 0.4, attack = 0.006, decay = 0.16, sustain = 0.75, release = 0.2,
      cutoff = 2500, pw = 0.5, pan = 0, source = 1, grain = 0.3, fold = 0.1, fm = 0.1, phase = 0, noise = 0.0,
      eq_low = 0.0, eq_lomid = 0.0, eq_himid = 0.0, eq_high = 0.0,
      eq_low_x = 0.10, eq_lomid_x = 0.36, eq_himid_x = 0.64, eq_high_x = 0.90,
      sample_start = 0.0, sample_end = 1.0, sample_mode = 1, bufnum = 0;

      var env, snapEnv, drift, mod, phaseWarp, sig, drive, filtFreq, presenceAmt;
      var lowFreq, loMidFreq, hiMidFreq, highFreq, lowGain, highGain, midQ1, midQ2, lowCut, highCut;
      var sample, frames, startFrame, endFrame, regionDur, readPhase, sampleGate;
      drift = LFNoise1.kr(0.18 + (grain * 3.5)).range(1 - (phase * 0.018), 1 + (phase * 0.018));
      freq = (freq * drift).clip(20, 12000);
      env = Env([0, 1, sustain.clip(0, 1), sustain.clip(0, 1), 0],
        [attack.clip(0.001, 1.5), decay.clip(0.005, 1.8), 0.025, release.clip(0.02, 3.0)], [-4, -4, 0, -4]).kr(doneAction: 2) * amp.clip(0, 1.35);
      snapEnv = Env.perc(0.001, 0.018, 1.0, -5).kr(doneAction: 0);
      frames = BufFrames.kr(bufnum).max(1);
      startFrame = (sample_start.clip(0, 0.999) * frames).clip(0, frames - 1);
      endFrame = (sample_end.clip(0.001, 1.0) * frames).clip(startFrame + 1, frames);
      regionDur = ((endFrame - startFrame) / (BufSampleRate.kr(bufnum).max(1) * (freq / 261.625).clip(0.125, 4))).clip(0.001, 30);
      readPhase = Line.ar(startFrame, endFrame - 1, regionDur, doneAction: 0);
      sampleGate = EnvGen.kr(Env([1, 1, 0], [regionDur, 0.001]), doneAction: 0);
      sample = BufRd.ar(1, bufnum, readPhase, interpolation: 2) * sampleGate * (BufFrames.kr(bufnum) > 1);
      sample = sample + (SinOsc.ar(freq) * 0.001);
      sig = HPF.ar(sample, 28);
      presenceAmt = 0.0;
      sig = sig + (sig * snapEnv * 0.065);
      sig = sig + WhiteNoise.ar(noise.clip(0, 1) * 0.18);

      drive = 1 + (fold.clip(0, 1) * 14);
      sig = (sig * drive).fold2(1.0) * (1 / drive.sqrt);
      sig = (sig + (sig.squared * fold * 0.15)).softclip;
      filtFreq = cutoff.clip(90, 15500) * (0.82 + (env * 1.65));
      sig = RLPF.ar(sig, filtFreq.clip(80, 17000), 0.24 + ((1 - grain.clip(0, 1)) * 0.58));
      sig = BHiShelf.ar(sig, 4200, 0.75, presenceAmt);

      // V12.5 EQ V2: wider musical ranges, stronger cuts, adaptive-Q mids and true edge cuts.
      lowFreq = eq_low_x.clip(0.00, 0.30).linexp(0.00, 0.30, 30, 300);
      loMidFreq = eq_lomid_x.clip(0.18, 0.52).linexp(0.18, 0.52, 100, 2000);
      hiMidFreq = eq_himid_x.clip(0.48, 0.82).linexp(0.48, 0.82, 500, 8000);
      highFreq = eq_high_x.clip(0.70, 1.00).linexp(0.70, 1.00, 2000, 16000);
      lowGain = eq_low.clip(-1, 0).linlin(-1, 0, -24, 0) + eq_low.clip(0, 1).linlin(0, 1, 0, 12);
      highGain = eq_high.clip(-1, 0).linlin(-1, 0, -24, 0) + eq_high.clip(0, 1).linlin(0, 1, 0, 12);
      midQ1 = eq_lomid.abs.linlin(0, 1, 1.15, 0.42);
      midQ2 = eq_himid.abs.linlin(0, 1, 1.15, 0.42);
      sig = BLowShelf.ar(sig, lowFreq, 0.85, lowGain);
      sig = BPeakEQ.ar(sig, loMidFreq, midQ1, eq_lomid.clip(-1, 1) * 18);
      sig = BPeakEQ.ar(sig, hiMidFreq, midQ2, eq_himid.clip(-1, 1) * 18);
      sig = BHiShelf.ar(sig, highFreq, 0.85, highGain);
      // At the bottom of LOW / HIGH, shelves progressively become real HPF / LPF cuts.
      lowCut = eq_low.clip(-1, -0.72).linlin(-0.72, -1, 25, lowFreq);
      highCut = eq_high.clip(-1, -0.72).linlin(-0.72, -1, 19000, highFreq);
      sig = HPF.ar(sig, lowCut.clip(20, 1200));
      sig = LPF.ar(sig, highCut.clip(500, 20000));
      sig = LeakDC.ar(sig);
      sig = Pan2.ar(sig * env, pan.clip(-1, 1));
      Out.ar(out, sig);
    }).add;




    SynthDef("MutaSampleOneShot", {
      arg out = 0,
      freq = 220,
      amp = 0.4,
      cutoff = 2500,
      pw = 0.5,
      pan = 0,
      grain = 0.3,
      fold = 0.1,
      fm = 0.1,
      phase = 0,
      noise = 0.0,
      eq_low = 0.0,
      eq_lomid = 0.0,
      eq_himid = 0.0,
      eq_high = 0.0,
      eq_low_x = 0.10,
      eq_lomid_x = 0.36,
      eq_himid_x = 0.64,
      eq_high_x = 0.90,
      sample_start = 0.0,
      sample_end = 1.0,
      bufnum = 0;

      var sampleRate, frames, startFrame, endFrame, regionDur, readPhase, sample, drive, filtFreq, gate, sig;
      var lowFreq, loMidFreq, hiMidFreq, highFreq, lowGain, highGain, midQ1, midQ2, lowCut, highCut;

      // V9.1 ONE SHOT: sample lifetime is driven by the selected region duration,
      // not by the per-step ADSR envelope. A full 5s file with START=0 / END=100%
      // will therefore play the full region.
      sampleRate = BufRateScale.kr(bufnum) * (freq / 261.625).clip(0.125, 4);
      frames = BufFrames.kr(bufnum).max(1);
      startFrame = (sample_start.clip(0, 0.999) * frames).clip(0, frames - 1);
      endFrame = (sample_end.clip(0.001, 1.0) * frames).clip(startFrame + 1, frames);
      regionDur = ((endFrame - startFrame) / (BufSampleRate.kr(bufnum).max(1) * (freq / 261.625).clip(0.125, 4))).clip(0.001, 30);
      readPhase = Line.ar(startFrame, endFrame - 1, regionDur, doneAction: 2);
      gate = EnvGen.kr(Env([0, 1], [0.003]), doneAction: 0);
      sample = BufRd.ar(1, bufnum, readPhase, interpolation: 2) * gate;
      sample = sample * (BufFrames.kr(bufnum) > 1);
      sample = sample + (SinOsc.ar(freq) * 0.001); // safety fallback when no sample is loaded

      sig = sample + WhiteNoise.ar(noise.clip(0, 1) * 0.12);
      drive = 1 + (fold.clip(0, 1) * 14);
      sig = (sig * drive).fold2(1.0) * (1 / drive.sqrt);
      sig = (sig + (sig.squared * fold * 0.15)).softclip;
      filtFreq = cutoff.clip(70, 13000);
      sig = RLPF.ar(sig, filtFreq.clip(60, 15000), 0.18 + ((1 - grain.clip(0, 1)) * 0.55));
      // V12.5 EQ V2 for sample voices: same response as synth voices.
      lowFreq = eq_low_x.clip(0.00, 0.30).linexp(0.00, 0.30, 30, 300);
      loMidFreq = eq_lomid_x.clip(0.18, 0.52).linexp(0.18, 0.52, 100, 2000);
      hiMidFreq = eq_himid_x.clip(0.48, 0.82).linexp(0.48, 0.82, 500, 8000);
      highFreq = eq_high_x.clip(0.70, 1.00).linexp(0.70, 1.00, 2000, 16000);
      lowGain = eq_low.clip(-1, 0).linlin(-1, 0, -24, 0) + eq_low.clip(0, 1).linlin(0, 1, 0, 12);
      highGain = eq_high.clip(-1, 0).linlin(-1, 0, -24, 0) + eq_high.clip(0, 1).linlin(0, 1, 0, 12);
      midQ1 = eq_lomid.abs.linlin(0, 1, 1.15, 0.42);
      midQ2 = eq_himid.abs.linlin(0, 1, 1.15, 0.42);
      sig = BLowShelf.ar(sig, lowFreq, 0.85, lowGain);
      sig = BPeakEQ.ar(sig, loMidFreq, midQ1, eq_lomid.clip(-1, 1) * 18);
      sig = BPeakEQ.ar(sig, hiMidFreq, midQ2, eq_himid.clip(-1, 1) * 18);
      sig = BHiShelf.ar(sig, highFreq, 0.85, highGain);
      lowCut = eq_low.clip(-1, -0.72).linlin(-0.72, -1, 25, lowFreq);
      highCut = eq_high.clip(-1, -0.72).linlin(-0.72, -1, 19000, highFreq);
      sig = HPF.ar(sig, lowCut.clip(20, 1200));
      sig = LPF.ar(sig, highCut.clip(500, 20000));
      sig = LeakDC.ar(sig);
      sig = Pan2.ar(sig * amp.clip(0, 1.2) * 0.95, pan.clip(-1, 1));
      Out.ar(out, sig);
    }).add;


    SynthDef("MutaSampleLoop", {
      arg out = 0,
      freq = 220,
      amp = 0.4,
      attack = 0.006,
      decay = 0.16,
      sustain = 0.75,
      release = 0.2,
      cutoff = 2500,
      pw = 0.5,
      pan = 0,
      grain = 0.3,
      fold = 0.1,
      fm = 0.1,
      phase = 0,
      noise = 0.0,
      eq_low = 0.0,
      eq_lomid = 0.0,
      eq_himid = 0.0,
      eq_high = 0.0,
      eq_low_x = 0.10,
      eq_lomid_x = 0.36,
      eq_himid_x = 0.64,
      eq_high_x = 0.90,
      sample_start = 0.0,
      sample_end = 1.0,
      bufnum = 0;

      var env, sampleRate, frames, startFrame, endFrame, loopFrames, readPhase, sample, drive, filtFreq, sig;
      var lowFreq, loMidFreq, hiMidFreq, highFreq, lowGain, highGain, midQ1, midQ2, lowCut, highCut;

      // V9.1.1 LOOP: the selected START/END region loops while the step envelope is alive.
      // This keeps looped sample voices finite and avoids building up infinite voices.
      env = Env([0, 1, sustain.clip(0, 1), sustain.clip(0, 1), 0],
        [attack.clip(0.001, 1.5), decay.clip(0.005, 1.8), 0.025, release.clip(0.02, 3.0)],
        [-4, -4, 0, -4]
      ).kr(doneAction: 2) * amp.clip(0, 1.2);

      sampleRate = BufRateScale.kr(bufnum) * (freq / 261.625).clip(0.125, 4);
      frames = BufFrames.kr(bufnum).max(1);
      startFrame = (sample_start.clip(0, 0.999) * frames).clip(0, frames - 1);
      endFrame = (sample_end.clip(0.001, 1.0) * frames).clip(startFrame + 1, frames);
      loopFrames = (endFrame - startFrame).max(2);
      readPhase = Phasor.ar(0, sampleRate, startFrame, endFrame - 1, startFrame);
      sample = BufRd.ar(1, bufnum, readPhase, interpolation: 2);
      sample = sample * (BufFrames.kr(bufnum) > 1);
      sample = sample + (SinOsc.ar(freq) * 0.001);

      sig = sample + WhiteNoise.ar(noise.clip(0, 1) * 0.12);
      drive = 1 + (fold.clip(0, 1) * 14);
      sig = (sig * drive).fold2(1.0) * (1 / drive.sqrt);
      sig = (sig + (sig.squared * fold * 0.15)).softclip;
      filtFreq = cutoff.clip(70, 13000);
      sig = RLPF.ar(sig, filtFreq.clip(60, 15000), 0.18 + ((1 - grain.clip(0, 1)) * 0.55));
      // V12.5 EQ V2 for sample voices: same response as synth voices.
      lowFreq = eq_low_x.clip(0.00, 0.30).linexp(0.00, 0.30, 30, 300);
      loMidFreq = eq_lomid_x.clip(0.18, 0.52).linexp(0.18, 0.52, 100, 2000);
      hiMidFreq = eq_himid_x.clip(0.48, 0.82).linexp(0.48, 0.82, 500, 8000);
      highFreq = eq_high_x.clip(0.70, 1.00).linexp(0.70, 1.00, 2000, 16000);
      lowGain = eq_low.clip(-1, 0).linlin(-1, 0, -24, 0) + eq_low.clip(0, 1).linlin(0, 1, 0, 12);
      highGain = eq_high.clip(-1, 0).linlin(-1, 0, -24, 0) + eq_high.clip(0, 1).linlin(0, 1, 0, 12);
      midQ1 = eq_lomid.abs.linlin(0, 1, 1.15, 0.42);
      midQ2 = eq_himid.abs.linlin(0, 1, 1.15, 0.42);
      sig = BLowShelf.ar(sig, lowFreq, 0.85, lowGain);
      sig = BPeakEQ.ar(sig, loMidFreq, midQ1, eq_lomid.clip(-1, 1) * 18);
      sig = BPeakEQ.ar(sig, hiMidFreq, midQ2, eq_himid.clip(-1, 1) * 18);
      sig = BHiShelf.ar(sig, highFreq, 0.85, highGain);
      lowCut = eq_low.clip(-1, -0.72).linlin(-0.72, -1, 25, lowFreq);
      highCut = eq_high.clip(-1, -0.72).linlin(-0.72, -1, 19000, highFreq);
      sig = HPF.ar(sig, lowCut.clip(20, 1200));
      sig = LPF.ar(sig, highCut.clip(500, 20000));
      sig = LeakDC.ar(sig);
      sig = Pan2.ar(sig * env * 0.95, pan.clip(-1, 1));
      Out.ar(out, sig);
    }).add;


    SynthDef("MutaFX", {
      arg in = 0, out = 0,
      delay_time = 0.375,
      delay_feedback = 0.42,
      delay_tone = 0.63,
      delay_mix = 0.31,
      delay_diffusion = 0.18,
      delay_smear = 0.15,
      reverb_size = 0.78,
      reverb_decay = 4.2,
      reverb_damp = 0.62,
      reverb_mix = 0.45,
      damage_crush = 0.12,
      damage_fold = 0.18,
      damage_instability = 0.10,
      damage_dropout = 0.0,
      main_l = 0.85,
      main_r = 0.85,
      phone_l = 0.85,
      phone_r = 0.85,
      comp_amount = 0.78,
      comp_threshold = 0.36,
      comp_ratio = 0.62,
      limiter_ceiling = 0.88;

      var dry, del, del2, toneFreq, smearRate, rev, sig, damaged, sampleRate, bits, dropoutGate, wobble, compSig, th, slope, ceil, protected;
      dry = In.ar(in, 2);

      wobble = LFNoise1.kr(0.35).range(1 - (damage_instability * 0.025), 1 + (damage_instability * 0.025));
      toneFreq = delay_tone.linexp(0, 1, 250, 9500);
      // Delay audibility fix: a 0.0 UI time previously became a 20 ms comb, which
      // felt like "no delay" when only MIX was P-locked. Keep a musical minimum
      // while preserving the 0..1.5 s range.
      del = CombC.ar(dry, 1.5, (delay_time.clip(0.08, 1.5) * wobble), (delay_feedback.clip(0, 0.82) * 4.2) + 0.18);
      del2 = AllpassC.ar(del, 0.25, (0.018 + (delay_diffusion * 0.19)).clip(0.001, 0.25), 0.4 + (delay_diffusion * 2.2));
      smearRate = delay_smear.linexp(0, 1, 12000, 1200);
      del2 = LPF.ar(del2, toneFreq.min(smearRate));
      // Delay behaves as a send/return rather than a pure crossfade. This makes
      // short P-lock bursts audible while keeping the dry step present.
      sig = (dry + (del2 * (delay_mix.clip(0, 1) * 1.35))).clip2(1.25);

      rev = FreeVerb2.ar(sig[0], sig[1], reverb_mix.clip(0, 1), reverb_size.clip(0, 1), reverb_damp.clip(0, 1));
      rev = LPF.ar(rev, reverb_damp.linexp(0, 1, 9000, 1400));
      sig = XFade2.ar(sig, rev, (reverb_mix.clip(0, 1) * 2) - 1);

      // DAMAGE: bit depth, sample-rate reduction, extra folding, random dropouts.
      bits = damage_crush.linlin(0, 1, 32768, 12);
      sampleRate = damage_crush.linexp(0, 1, 22050, 1800);
      damaged = Latch.ar(sig, Impulse.ar(sampleRate));
      damaged = ((damaged * bits).round / bits).clip2(1.0);
      damaged = (damaged * (1 + (damage_fold * 10))).fold2(1.0) * (1 / (1 + (damage_fold * 4)));
      dropoutGate = Lag.kr(LFNoise0.kr(8 + (damage_dropout * 35)).range(0, 1) > damage_dropout, 0.01);
      damaged = damaged * dropoutGate;
      sig = XFade2.ar(sig, damaged, ((damage_crush + damage_fold + damage_instability + damage_dropout).clip(0, 1) * 2) - 1);
      sig = sig + (BrownNoise.ar(damage_instability * 0.008) ! 2);

      // MIX dynamics v8.9.6: more protective compressor + true final ceiling.
      // The UI remains 0..100%, but the mapping is now musically useful:
      // lower threshold range, stronger ratio range, fast attack, slower release.
      sig = LeakDC.ar(sig);
      th = comp_threshold.linexp(0, 1, 0.035, 0.75).clip(0.03, 0.9);
      slope = comp_ratio.linlin(0, 1, 0.85, 0.07).clip(0.07, 0.85);
      compSig = Compander.ar(sig, sig, th, 1, slope, 0.0025, 0.18);
      sig = XFade2.ar(sig, compSig, (comp_amount.clip(0, 1) * 2) - 1);

      // A gentle safety soft-clip catches extreme mutation / feedback bursts before the limiter.
      protected = tanh(sig * (1 + (comp_amount.clip(0, 1) * 0.35))) / (1 + (comp_amount.clip(0, 1) * 0.18));
      sig = XFade2.ar(sig, protected, (comp_amount.clip(0, 1) * 1.4) - 1);

      // Limiter knob now maps to a conservative ceiling range; final clip is a last-resort guard.
      ceil = limiter_ceiling.linlin(0, 1, 0.50, 0.98).clip(0.50, 0.98);
      sig = Limiter.ar(sig, ceil, 0.01).clip2(ceil);

      // v8.10: MASTER is the real output trim. CUE is a Lua-side performance
      // value and no longer multiplies the final signal here.
      sig = [sig[0] * main_l.clip(0, 1), sig[1] * main_r.clip(0, 1)];
      Out.ar(out, sig);
    }).add;

    Server.default.sync;

    voiceParams = Dictionary.newFrom([
      \amp, 0.45,
      \release, 0.22,
      \cutoff, 2400,
      \pw, 0.5,
      \pan, 0,
      \source, 1,
      \bufnum, 0,
      \grain, 0.3,
      \fold, 0.1,
      \fm, 0.1,
      \phase, 0,
      \noise, 0.0,
      \eq_low, 0.0,
      \eq_lomid, 0.0,
      \eq_himid, 0.0,
      \eq_high, 0.0,
      \eq_low_x, 0.10,
      \eq_lomid_x, 0.36,
      \eq_himid_x, 0.64,
      \eq_high_x, 0.90
    ]);

    sampleBuf = Buffer.alloc(Crone.server, 1, 1);
    fxSynth = Synth.tail(group, "MutaFX", [\in, fxBus, \out, 0]);
    // Dedicated P-lock return: only voices from locked steps enter this bus.
    // Its delay/reverb state can decay naturally while later dry voices use fxBus.
    pfxSynth = Synth.tail(group, "MutaFX", [
      \in, pfxBus, \out, 0,
      \delay_mix, 0, \reverb_mix, 0,
      \damage_crush, 0, \damage_fold, 0,
      \damage_instability, 0, \damage_dropout, 0
    ]);

    voiceParams.keysDo({ arg key;
      this.addCommand(key, "f", { arg msg;
        voiceParams[key] = msg[1].asFloat;
      });
    });

    this.addCommand(\hz, "f", { arg msg;
      voiceParams[\bufnum] = sampleBuf.bufnum;
      Synth.head(group, "MutaSine", [\out, fxBus, \freq, msg[1].asFloat] ++ voiceParams.getPairs);
    });

    // Compact trigger command used by Lua to avoid sending 10+ OSC messages per voice.
    // args (27): freq amp attack decay sustain release cutoff pw pan source grain fold fm phase noise sample_start sample_end sample_mode eq_low eq_lomid eq_himid eq_high eq_low_x eq_lomid_x eq_himid_x eq_high_x pfx_route
    this.addCommand(\trig, "fffffffffffffffffffffffffff", { arg msg;
      var src, smode, synthName, routeBus;
      src = msg[10].asFloat;
      smode = msg[18].asFloat;
      synthName = if(src == 1, { "MutaSine" }, { if(src == 2, { "MutaNoise" }, { if(src == 3, { "MutaSub" }, { if(src == 4, { "MutaFM" }, { if(smode >= 3, { "MutaSampleLoop" }, { if(smode >= 2, { "MutaSampleOneShot" }, { "MutaSampleGate" }) }) }) }) }) });
      routeBus = if(msg[27].asFloat >= 0.5, { pfxBus }, { fxBus });
      Synth.head(group, synthName, [
        \out, routeBus,
        \freq, msg[1].asFloat,
        \amp, msg[2].asFloat,
        \attack, msg[3].asFloat,
        \decay, msg[4].asFloat,
        \sustain, msg[5].asFloat,
        \release, msg[6].asFloat,
        \cutoff, msg[7].asFloat,
        \pw, msg[8].asFloat,
        \pan, msg[9].asFloat,
        \source, msg[10].asFloat,
        \grain, msg[11].asFloat,
        \fold, msg[12].asFloat,
        \fm, msg[13].asFloat,
        \phase, msg[14].asFloat,
        \noise, msg[15].asFloat,
        \sample_start, msg[16].asFloat.clip(0, 1),
        \sample_end, msg[17].asFloat.clip(0, 1),
        \sample_mode, smode.clip(1, 3),
        \eq_low, msg[19].asFloat.clip(-1, 1),
        \eq_lomid, msg[20].asFloat.clip(-1, 1),
        \eq_himid, msg[21].asFloat.clip(-1, 1),
        \eq_high, msg[22].asFloat.clip(-1, 1),
        \eq_low_x, msg[23].asFloat.clip(0, 1),
        \eq_lomid_x, msg[24].asFloat.clip(0, 1),
        \eq_himid_x, msg[25].asFloat.clip(0, 1),
        \eq_high_x, msg[26].asFloat.clip(0, 1),
        \bufnum, sampleBuf.bufnum
      ]);
    });

    this.addCommand(\delay_time, "f", { arg msg; fxSynth.set(\delay_time, msg[1].asFloat.clip(0.08, 1.5)); });
    this.addCommand(\delay_feedback, "f", { arg msg; fxSynth.set(\delay_feedback, msg[1].asFloat.clip(0, 0.82)); });
    this.addCommand(\delay_tone, "f", { arg msg; fxSynth.set(\delay_tone, msg[1].asFloat.clip(0, 1)); });
    this.addCommand(\delay_diffusion, "f", { arg msg; fxSynth.set(\delay_diffusion, msg[1].asFloat.clip(0, 1)); });
    this.addCommand(\delay_smear, "f", { arg msg; fxSynth.set(\delay_smear, msg[1].asFloat.clip(0, 1)); });
    this.addCommand(\delay_mix, "f", { arg msg; fxSynth.set(\delay_mix, msg[1].asFloat.clip(0, 1)); });
    this.addCommand(\reverb_size, "f", { arg msg; fxSynth.set(\reverb_size, msg[1].asFloat.clip(0, 1)); });
    this.addCommand(\reverb_decay, "f", { arg msg; fxSynth.set(\reverb_decay, msg[1].asFloat.clip(0.1, 10)); });
    this.addCommand(\reverb_damp, "f", { arg msg; fxSynth.set(\reverb_damp, msg[1].asFloat.clip(0, 1)); });
    this.addCommand(\reverb_mix, "f", { arg msg; fxSynth.set(\reverb_mix, msg[1].asFloat.clip(0, 1)); });
    this.addCommand(\damage_crush, "f", { arg msg; fxSynth.set(\damage_crush, msg[1].asFloat.clip(0, 1)); });
    this.addCommand(\damage_fold, "f", { arg msg; fxSynth.set(\damage_fold, msg[1].asFloat.clip(0, 1)); });
    this.addCommand(\damage_instability, "f", { arg msg; fxSynth.set(\damage_instability, msg[1].asFloat.clip(0, 1)); });
    this.addCommand(\damage_dropout, "f", { arg msg; fxSynth.set(\damage_dropout, msg[1].asFloat.clip(0, 1)); });

    this.addCommand(\plock_delay_time, "f", { arg msg; pfxSynth.set(\delay_time, msg[1].asFloat.clip(0.08, 1.5)); });
    this.addCommand(\plock_delay_feedback, "f", { arg msg; pfxSynth.set(\delay_feedback, msg[1].asFloat.clip(0, 0.82)); });
    this.addCommand(\plock_delay_tone, "f", { arg msg; pfxSynth.set(\delay_tone, msg[1].asFloat.clip(0, 1)); });
    this.addCommand(\plock_delay_diffusion, "f", { arg msg; pfxSynth.set(\delay_diffusion, msg[1].asFloat.clip(0, 1)); });
    this.addCommand(\plock_delay_smear, "f", { arg msg; pfxSynth.set(\delay_smear, msg[1].asFloat.clip(0, 1)); });
    this.addCommand(\plock_delay_mix, "f", { arg msg; pfxSynth.set(\delay_mix, msg[1].asFloat.clip(0, 1)); });
    this.addCommand(\plock_reverb_size, "f", { arg msg; pfxSynth.set(\reverb_size, msg[1].asFloat.clip(0, 1)); });
    this.addCommand(\plock_reverb_decay, "f", { arg msg; pfxSynth.set(\reverb_decay, msg[1].asFloat.clip(0.1, 10)); });
    this.addCommand(\plock_reverb_damp, "f", { arg msg; pfxSynth.set(\reverb_damp, msg[1].asFloat.clip(0, 1)); });
    this.addCommand(\plock_reverb_mix, "f", { arg msg; pfxSynth.set(\reverb_mix, msg[1].asFloat.clip(0, 1)); });
    this.addCommand(\plock_damage_crush, "f", { arg msg; pfxSynth.set(\damage_crush, msg[1].asFloat.clip(0, 1)); });
    this.addCommand(\plock_damage_fold, "f", { arg msg; pfxSynth.set(\damage_fold, msg[1].asFloat.clip(0, 1)); });
    this.addCommand(\plock_damage_instability, "f", { arg msg; pfxSynth.set(\damage_instability, msg[1].asFloat.clip(0, 1)); });
    this.addCommand(\plock_damage_dropout, "f", { arg msg; pfxSynth.set(\damage_dropout, msg[1].asFloat.clip(0, 1)); });

    // Compact full P-lock FX snapshot. Keeps zero-reset semantics while avoiding
    // bursts of individual OSC messages on dense multi-track patterns.
    this.addCommand(\plock_fx, "ffffffffffffff", { arg msg;
      pfxSynth.set(
        \delay_time, msg[1].asFloat.clip(0.08, 1.5),
        \delay_feedback, msg[2].asFloat.clip(0, 0.82),
        \delay_tone, msg[3].asFloat.clip(0, 1),
        \delay_diffusion, msg[4].asFloat.clip(0, 1),
        \delay_smear, msg[5].asFloat.clip(0, 1),
        \delay_mix, msg[6].asFloat.clip(0, 1),
        \reverb_size, msg[7].asFloat.clip(0, 1),
        \reverb_decay, msg[8].asFloat.clip(0.1, 10),
        \reverb_damp, msg[9].asFloat.clip(0, 1),
        \reverb_mix, msg[10].asFloat.clip(0, 1),
        \damage_crush, msg[11].asFloat.clip(0, 1),
        \damage_fold, msg[12].asFloat.clip(0, 1),
        \damage_instability, msg[13].asFloat.clip(0, 1),
        \damage_dropout, msg[14].asFloat.clip(0, 1)
      );
    });
    this.addCommand(\main_l, "f", { arg msg; var v=msg[1].asFloat.clip(0,1); fxSynth.set(\main_l,v); pfxSynth.set(\main_l,v); });
    this.addCommand(\main_r, "f", { arg msg; var v=msg[1].asFloat.clip(0,1); fxSynth.set(\main_r,v); pfxSynth.set(\main_r,v); });
    this.addCommand(\phone_l, "f", { arg msg; fxSynth.set(\phone_l, msg[1].asFloat.clip(0, 1)); });
    this.addCommand(\phone_r, "f", { arg msg; fxSynth.set(\phone_r, msg[1].asFloat.clip(0, 1)); });
    this.addCommand(\comp_amount, "f", { arg msg; var v=msg[1].asFloat.clip(0,1); fxSynth.set(\comp_amount,v); pfxSynth.set(\comp_amount,v); });
    this.addCommand(\comp_threshold, "f", { arg msg; var v=msg[1].asFloat.clip(0,1); fxSynth.set(\comp_threshold,v); pfxSynth.set(\comp_threshold,v); });
    this.addCommand(\comp_ratio, "f", { arg msg; var v=msg[1].asFloat.clip(0,1); fxSynth.set(\comp_ratio,v); pfxSynth.set(\comp_ratio,v); });
    this.addCommand(\limiter_ceiling, "f", { arg msg; var v=msg[1].asFloat.clip(0,1); fxSynth.set(\limiter_ceiling,v); pfxSynth.set(\limiter_ceiling,v); });

    this.addCommand(\load_sample, "s", { arg msg;
      var path;
      path = msg[1].asString;
      if(sampleBuf.notNil, { sampleBuf.free; });
      sampleBuf = Buffer.readChannel(Crone.server, path, channels: [0]);
    });

    this.addCommand(\panic, "", {
      group.freeAll;
      fxSynth = Synth.tail(group, "MutaFX", [\in, fxBus, \out, 0]);
      pfxSynth = Synth.tail(group, "MutaFX", [\in, pfxBus, \out, 0, \delay_mix, 0, \reverb_mix, 0]);
    });
  }

  free {
    if(group.notNil, { group.free; });
    if(fxBus.notNil, { fxBus.free; });
    if(pfxBus.notNil, { pfxBus.free; });
    if(sampleBuf.notNil, { sampleBuf.free; });
  }
}
