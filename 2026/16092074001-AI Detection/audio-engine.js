// Shared audio engine used by both the free-play piano and Practice Mode, so
// keyboard input and mouse/touch input always go through the exact same
// note-playing code path (same instrument, same envelope, same sample).
(function (global) {
  const INSTRUMENTS = {
    piano: {
      partials: [
        { type: 'triangle', ratio: 1, gain: 1 },
        { type: 'sine', ratio: 2, gain: 0.35 },
        { type: 'sine', ratio: 4, gain: 0.1 },
      ],
      envelope: { attack: 0.005, decay: 0.35, sustain: 0.25, release: 0.3 },
    },
    organ: {
      partials: [
        { type: 'sine', ratio: 1, gain: 0.7 },
        { type: 'sine', ratio: 2, gain: 0.5 },
        { type: 'sine', ratio: 3, gain: 0.3 },
        { type: 'sine', ratio: 4, gain: 0.2 },
      ],
      envelope: { attack: 0.02, decay: 0.05, sustain: 1, release: 0.08 },
    },
    synth: {
      partials: [
        { type: 'sawtooth', ratio: 1, gain: 0.8 },
        { type: 'square', ratio: 1.005, gain: 0.3 },
      ],
      envelope: { attack: 0.01, decay: 0.15, sustain: 0.7, release: 0.2 },
      filter: { type: 'lowpass', frequency: 2500 },
    },
    bell: {
      partials: [
        { type: 'sine', ratio: 1, gain: 0.6 },
        { type: 'sine', ratio: 2.76, gain: 0.3 },
        { type: 'sine', ratio: 5.4, gain: 0.15 },
      ],
      envelope: { attack: 0.001, decay: 1.4, sustain: 0, release: 0.6 },
    },
    strings: {
      partials: [
        { type: 'sawtooth', ratio: 1, gain: 0.5 },
        { type: 'sawtooth', ratio: 1.003, gain: 0.5 },
        { type: 'sawtooth', ratio: 0.997, gain: 0.5 },
      ],
      envelope: { attack: 0.3, decay: 0.1, sustain: 0.8, release: 0.4 },
      filter: { type: 'lowpass', frequency: 1800 },
    },
    marimba: {
      partials: [
        { type: 'sine', ratio: 1, gain: 0.8 },
        { type: 'sine', ratio: 3.99, gain: 0.25 },
        { type: 'sine', ratio: 9.2, gain: 0.08 },
      ],
      envelope: { attack: 0.002, decay: 0.6, sustain: 0, release: 0.2 },
    },
    flute: {
      partials: [
        { type: 'sine', ratio: 1, gain: 0.85 },
        { type: 'triangle', ratio: 2, gain: 0.15 },
        { type: 'sine', ratio: 3, gain: 0.05 },
      ],
      envelope: { attack: 0.09, decay: 0.1, sustain: 0.85, release: 0.25 },
      filter: { type: 'lowpass', frequency: 3200 },
    },
    brass: {
      partials: [
        { type: 'sawtooth', ratio: 1, gain: 0.6 },
        { type: 'square', ratio: 1, gain: 0.3 },
        { type: 'sawtooth', ratio: 2, gain: 0.15 },
      ],
      envelope: { attack: 0.06, decay: 0.1, sustain: 0.75, release: 0.15 },
      filter: { type: 'lowpass', frequency: 2200 },
    },
    pad: {
      partials: [
        { type: 'sine', ratio: 1, gain: 0.5 },
        { type: 'triangle', ratio: 2.01, gain: 0.3 },
        { type: 'sine', ratio: 0.5, gain: 0.25 },
      ],
      envelope: { attack: 0.6, decay: 0.3, sustain: 0.7, release: 0.9 },
      filter: { type: 'lowpass', frequency: 1500 },
    },
    music_box: {
      partials: [
        { type: 'sine', ratio: 1, gain: 0.7 },
        { type: 'sine', ratio: 4, gain: 0.3 },
        { type: 'sine', ratio: 8.5, gain: 0.12 },
      ],
      envelope: { attack: 0.001, decay: 1.0, sustain: 0, release: 0.4 },
    },
  };

  class PianoAudioEngine {
    constructor({ samplesPath = 'samples/', onSamplesLoaded } = {}) {
      this.audioCtx = new (window.AudioContext || window.webkitAudioContext)();
      this.instrument = 'acoustic-piano';
      this.volume = 0.5;
      this.activeVoices = {};
      this.samplesLoaded = false;

      const pianoUrls = {};
      ['1', '2', '3', '4', '5', '6', '7'].forEach((o) => {
        pianoUrls[`C${o}`] = `C${o}.mp3`;
        pianoUrls[`D#${o}`] = `Ds${o}.mp3`;
        pianoUrls[`F#${o}`] = `Fs${o}.mp3`;
        pianoUrls[`A${o}`] = `A${o}.mp3`;
      });
      pianoUrls.A0 = 'A0.mp3';
      pianoUrls.C8 = 'C8.mp3';

      this.pianoSampler = new Tone.Sampler({
        urls: pianoUrls,
        baseUrl: samplesPath,
        onload: () => {
          this.samplesLoaded = true;
          if (onSamplesLoaded) onSamplesLoaded();
        },
      }).toDestination();
    }

    setInstrument(name) {
      this.instrument = name;
    }

    setVolume(volume) {
      this.volume = volume;
    }

    resume() {
      if (this.audioCtx.state === 'suspended') this.audioCtx.resume();
      Tone.start();
    }

    playNote(midi) {
      if (this.activeVoices[midi]) return;
      const noteData = NoteUtils.midiToNoteData(midi);
      if (!noteData) return;

      if (this.instrument === 'acoustic-piano' && !this.samplesLoaded) return;

      this.resume();

      if (this.instrument === 'acoustic-piano') {
        this.pianoSampler.volume.value = Tone.gainToDb(Math.max(this.volume, 0.001));
        this.pianoSampler.triggerAttack(noteData.note);
        this.activeVoices[midi] = { sampler: true };
        return;
      }

      const instrument = INSTRUMENTS[this.instrument];
      const now = this.audioCtx.currentTime;
      const { attack, decay, sustain } = instrument.envelope;

      const voiceGain = this.audioCtx.createGain();
      voiceGain.gain.setValueAtTime(0, now);
      voiceGain.gain.linearRampToValueAtTime(this.volume, now + attack);
      voiceGain.gain.linearRampToValueAtTime(this.volume * sustain, now + attack + decay);

      let outputNode = voiceGain;
      if (instrument.filter) {
        const filterNode = this.audioCtx.createBiquadFilter();
        filterNode.type = instrument.filter.type;
        filterNode.frequency.setValueAtTime(instrument.filter.frequency, now);
        voiceGain.connect(filterNode);
        outputNode = filterNode;
      }
      outputNode.connect(this.audioCtx.destination);

      const oscillators = instrument.partials.map((partial) => {
        const oscillator = this.audioCtx.createOscillator();
        oscillator.type = partial.type;
        oscillator.frequency.setValueAtTime(noteData.freq * partial.ratio, now);

        const partialGain = this.audioCtx.createGain();
        partialGain.gain.setValueAtTime(partial.gain, now);

        oscillator.connect(partialGain);
        partialGain.connect(voiceGain);
        oscillator.start();
        return oscillator;
      });

      this.activeVoices[midi] = { oscillators, voiceGain, instrument };
    }

    stopNote(midi) {
      const active = this.activeVoices[midi];
      if (!active) return;

      if (active.sampler) {
        const noteData = NoteUtils.midiToNoteData(midi);
        this.pianoSampler.triggerRelease(noteData.note);
        delete this.activeVoices[midi];
        return;
      }

      const { oscillators, voiceGain, instrument } = active;
      const now = this.audioCtx.currentTime;
      const releaseTime = instrument.envelope.release;

      voiceGain.gain.cancelScheduledValues(now);
      voiceGain.gain.setValueAtTime(voiceGain.gain.value, now);
      voiceGain.gain.linearRampToValueAtTime(0, now + releaseTime);

      oscillators.forEach((oscillator) => oscillator.stop(now + releaseTime));

      delete this.activeVoices[midi];
    }

    stopAll() {
      Object.keys(this.activeVoices).forEach((midi) => this.stopNote(Number(midi)));
    }

    // --- Celebration audio (Game Mode final results) ---------------------------
    // Deliberately bypasses `activeVoices`/the sampler entirely so it can never
    // silently no-op because a gameplay note's MIDI number happens to still be
    // "active" (e.g. the final note's key hasn't been released yet), and so it
    // never interferes with piano note state.
    playCelebrationSound() {
      this.resume();
      const now = this.audioCtx.currentTime;
      // Bright ascending "ta-da" arpeggio, independent oscillators/gains.
      const freqs = [523.25, 659.25, 783.99, 1046.5]; // C5 E5 G5 C6
      freqs.forEach((freq, i) => {
        const start = now + i * 0.09;
        const osc = this.audioCtx.createOscillator();
        const gain = this.audioCtx.createGain();
        osc.type = 'triangle';
        osc.frequency.setValueAtTime(freq, start);
        gain.gain.setValueAtTime(0, start);
        gain.gain.linearRampToValueAtTime(0.35, start + 0.02);
        gain.gain.exponentialRampToValueAtTime(0.001, start + 0.5);
        osc.connect(gain).connect(this.audioCtx.destination);
        osc.start(start);
        osc.stop(start + 0.55);
      });
    }

    playApplauseSound() {
      this.resume();
      const now = this.audioCtx.currentTime;
      // Synthesized clapping: several short filtered-noise bursts, staggered
      // and randomized slightly so it doesn't sound like a single mechanical beep.
      const burstCount = 14;
      for (let i = 0; i < burstCount; i++) {
        const start = now + i * 0.06 + Math.random() * 0.03;
        const duration = 0.08 + Math.random() * 0.05;
        const bufferSize = Math.ceil(this.audioCtx.sampleRate * duration);
        const buffer = this.audioCtx.createBuffer(1, bufferSize, this.audioCtx.sampleRate);
        const data = buffer.getChannelData(0);
        for (let s = 0; s < bufferSize; s++) data[s] = Math.random() * 2 - 1;

        const noise = this.audioCtx.createBufferSource();
        noise.buffer = buffer;

        const bandpass = this.audioCtx.createBiquadFilter();
        bandpass.type = 'bandpass';
        bandpass.frequency.value = 1500 + Math.random() * 800;
        bandpass.Q.value = 1.2;

        const gain = this.audioCtx.createGain();
        gain.gain.setValueAtTime(0.25, start);
        gain.gain.exponentialRampToValueAtTime(0.001, start + duration);

        noise.connect(bandpass).connect(gain).connect(this.audioCtx.destination);
        noise.start(start);
        noise.stop(start + duration);
      }
    }
  }

  global.PianoAudioEngine = PianoAudioEngine;
})(window);
