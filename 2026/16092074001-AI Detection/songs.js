// Centralized song data: every practice-able / auto-playable song lives here so
// the piano/audio engine and the reusable Practice page never duplicate melody logic.
(function (global) {
  // Converts a compact "C6 C#6 D5 ..." token string into the canonical
  // { note, octave, beats } shape used everywhere else - used for melodies
  // transcribed as plain note-letter sequences (no per-note rhythm supplied),
  // so every note gets a uniform duration instead of invented timing.
  function parseMelody(tokenString, beatsPerNote) {
    return tokenString
      .trim()
      .split(/\s+/)
      .map((token) => {
        const match = token.match(/^([A-G]#?)(\d)$/);
        if (!match) throw new Error(`parseMelody: invalid note token "${token}"`);
        return { note: match[1], octave: Number(match[2]), beats: beatsPerNote };
      });
  }

  global.SONGS = {
    'happy-birthday': {
      id: 'happy-birthday',
      title: 'Happy Birthday',
      category: 'Classics',
      tempo: 108, // beats per minute
      // Standard "Happy Birthday to You" melody in the key of C, verified against
      // the well-known public-domain transcription (3/4 time; beats are in quarter notes).
      notes: [
        { note: 'G', octave: 4, beats: 0.5 },
        { note: 'G', octave: 4, beats: 0.5 },
        { note: 'A', octave: 4, beats: 1 },
        { note: 'G', octave: 4, beats: 1 },
        { note: 'C', octave: 5, beats: 1 },
        { note: 'B', octave: 4, beats: 2 },

        { note: 'G', octave: 4, beats: 0.5 },
        { note: 'G', octave: 4, beats: 0.5 },
        { note: 'A', octave: 4, beats: 1 },
        { note: 'G', octave: 4, beats: 1 },
        { note: 'D', octave: 5, beats: 1 },
        { note: 'C', octave: 5, beats: 2 },

        { note: 'G', octave: 4, beats: 0.5 },
        { note: 'G', octave: 4, beats: 0.5 },
        { note: 'G', octave: 5, beats: 1 },
        { note: 'E', octave: 5, beats: 1 },
        { note: 'C', octave: 5, beats: 1 },
        { note: 'B', octave: 4, beats: 1 },
        { note: 'A', octave: 4, beats: 2 },

        { note: 'F', octave: 5, beats: 0.5 },
        { note: 'F', octave: 5, beats: 0.5 },
        { note: 'E', octave: 5, beats: 1 },
        { note: 'C', octave: 5, beats: 1 },
        { note: 'D', octave: 5, beats: 1 },
        { note: 'C', octave: 5, beats: 2 },
      ],
    },

    'twinkle-twinkle': {
      id: 'twinkle-twinkle',
      title: 'Twinkle Twinkle Little Star',
      category: 'Classics',
      tempo: 100,
      // Standard public-domain melody in C major (4/4 time; beats are quarter notes).
      notes: [
        { note: 'C', octave: 4, beats: 1 }, { note: 'C', octave: 4, beats: 1 },
        { note: 'G', octave: 4, beats: 1 }, { note: 'G', octave: 4, beats: 1 },
        { note: 'A', octave: 4, beats: 1 }, { note: 'A', octave: 4, beats: 1 },
        { note: 'G', octave: 4, beats: 2 },
        { note: 'F', octave: 4, beats: 1 }, { note: 'F', octave: 4, beats: 1 },
        { note: 'E', octave: 4, beats: 1 }, { note: 'E', octave: 4, beats: 1 },
        { note: 'D', octave: 4, beats: 1 }, { note: 'D', octave: 4, beats: 1 },
        { note: 'C', octave: 4, beats: 2 },
        { note: 'G', octave: 4, beats: 1 }, { note: 'G', octave: 4, beats: 1 },
        { note: 'F', octave: 4, beats: 1 }, { note: 'F', octave: 4, beats: 1 },
        { note: 'E', octave: 4, beats: 1 }, { note: 'E', octave: 4, beats: 1 },
        { note: 'D', octave: 4, beats: 2 },
        { note: 'G', octave: 4, beats: 1 }, { note: 'G', octave: 4, beats: 1 },
        { note: 'F', octave: 4, beats: 1 }, { note: 'F', octave: 4, beats: 1 },
        { note: 'E', octave: 4, beats: 1 }, { note: 'E', octave: 4, beats: 1 },
        { note: 'D', octave: 4, beats: 2 },
        { note: 'C', octave: 4, beats: 1 }, { note: 'C', octave: 4, beats: 1 },
        { note: 'G', octave: 4, beats: 1 }, { note: 'G', octave: 4, beats: 1 },
        { note: 'A', octave: 4, beats: 1 }, { note: 'A', octave: 4, beats: 1 },
        { note: 'G', octave: 4, beats: 2 },
        { note: 'F', octave: 4, beats: 1 }, { note: 'F', octave: 4, beats: 1 },
        { note: 'E', octave: 4, beats: 1 }, { note: 'E', octave: 4, beats: 1 },
        { note: 'D', octave: 4, beats: 1 }, { note: 'D', octave: 4, beats: 1 },
        { note: 'C', octave: 4, beats: 2 },
      ],
    },

    'mary-had-a-little-lamb': {
      id: 'mary-had-a-little-lamb',
      title: 'Mary Had a Little Lamb',
      category: 'Classics',
      tempo: 110,
      notes: [
        { note: 'E', octave: 4, beats: 1 }, { note: 'D', octave: 4, beats: 1 },
        { note: 'C', octave: 4, beats: 1 }, { note: 'D', octave: 4, beats: 1 },
        { note: 'E', octave: 4, beats: 1 }, { note: 'E', octave: 4, beats: 1 },
        { note: 'E', octave: 4, beats: 2 },
        { note: 'D', octave: 4, beats: 1 }, { note: 'D', octave: 4, beats: 1 },
        { note: 'D', octave: 4, beats: 2 },
        { note: 'E', octave: 4, beats: 1 }, { note: 'G', octave: 4, beats: 1 },
        { note: 'G', octave: 4, beats: 2 },
        { note: 'E', octave: 4, beats: 1 }, { note: 'D', octave: 4, beats: 1 },
        { note: 'C', octave: 4, beats: 1 }, { note: 'D', octave: 4, beats: 1 },
        { note: 'E', octave: 4, beats: 1 }, { note: 'E', octave: 4, beats: 1 },
        { note: 'E', octave: 4, beats: 1 }, { note: 'E', octave: 4, beats: 1 },
        { note: 'D', octave: 4, beats: 1 }, { note: 'D', octave: 4, beats: 1 },
        { note: 'E', octave: 4, beats: 1 }, { note: 'D', octave: 4, beats: 1 },
        { note: 'C', octave: 4, beats: 2 },
      ],
    },

    'ode-to-joy': {
      id: 'ode-to-joy',
      title: 'Ode to Joy',
      category: 'Classics',
      tempo: 112,
      // Beethoven's Symphony No. 9 theme (public domain), simplified in C major.
      notes: [
        { note: 'E', octave: 4, beats: 1 }, { note: 'E', octave: 4, beats: 1 },
        { note: 'F', octave: 4, beats: 1 }, { note: 'G', octave: 4, beats: 1 },
        { note: 'G', octave: 4, beats: 1 }, { note: 'F', octave: 4, beats: 1 },
        { note: 'E', octave: 4, beats: 1 }, { note: 'D', octave: 4, beats: 1 },
        { note: 'C', octave: 4, beats: 1 }, { note: 'C', octave: 4, beats: 1 },
        { note: 'D', octave: 4, beats: 1 }, { note: 'E', octave: 4, beats: 1 },
        { note: 'E', octave: 4, beats: 1.5 }, { note: 'D', octave: 4, beats: 0.5 },
        { note: 'D', octave: 4, beats: 2 },

        { note: 'E', octave: 4, beats: 1 }, { note: 'E', octave: 4, beats: 1 },
        { note: 'F', octave: 4, beats: 1 }, { note: 'G', octave: 4, beats: 1 },
        { note: 'G', octave: 4, beats: 1 }, { note: 'F', octave: 4, beats: 1 },
        { note: 'E', octave: 4, beats: 1 }, { note: 'D', octave: 4, beats: 1 },
        { note: 'C', octave: 4, beats: 1 }, { note: 'C', octave: 4, beats: 1 },
        { note: 'D', octave: 4, beats: 1 }, { note: 'E', octave: 4, beats: 1 },
        { note: 'D', octave: 4, beats: 1.5 }, { note: 'C', octave: 4, beats: 0.5 },
        { note: 'C', octave: 4, beats: 2 },
      ],
    },

    'jingle-bells': {
      id: 'jingle-bells',
      title: 'Jingle Bells',
      category: 'Classics',
      tempo: 120,
      notes: [
        { note: 'E', octave: 4, beats: 1 }, { note: 'E', octave: 4, beats: 1 },
        { note: 'E', octave: 4, beats: 2 },
        { note: 'E', octave: 4, beats: 1 }, { note: 'E', octave: 4, beats: 1 },
        { note: 'E', octave: 4, beats: 2 },
        { note: 'E', octave: 4, beats: 1 }, { note: 'G', octave: 4, beats: 1 },
        { note: 'C', octave: 4, beats: 1 }, { note: 'D', octave: 4, beats: 1 },
        { note: 'E', octave: 4, beats: 4 },

        { note: 'F', octave: 4, beats: 1 }, { note: 'F', octave: 4, beats: 1 },
        { note: 'F', octave: 4, beats: 1 }, { note: 'F', octave: 4, beats: 1 },
        { note: 'F', octave: 4, beats: 1 }, { note: 'E', octave: 4, beats: 1 },
        { note: 'E', octave: 4, beats: 1 }, { note: 'E', octave: 4, beats: 0.5 }, { note: 'E', octave: 4, beats: 0.5 },
        { note: 'E', octave: 4, beats: 1 }, { note: 'D', octave: 4, beats: 1 },
        { note: 'D', octave: 4, beats: 1 }, { note: 'E', octave: 4, beats: 1 },
        { note: 'D', octave: 4, beats: 2 }, { note: 'G', octave: 4, beats: 2 },
      ],
    },

    'om-shanti-om-theme': {
      id: 'om-shanti-om-theme',
      title: 'Om Shanti Om Theme',
      category: 'Bollywood',
      composer: 'Vishal & Shekhar',
      sourceType: 'user-provided-transcription',
      // Source: fan piano-note transcription of "Main Agar Kahoon" supplied by the
      // user (https://jarzee.in/piano-notes/Om%20Shanti%20Om/Main%20Agar%20Kahoon).
      // Trimmed to just the recognizable hook (opening line + main chorus) instead
      // of the full ~7-minute transcription, matching the length of the other songs.
      // This is a note-letter transcription with no per-note rhythm markings, so
      // every note is played as a uniform quarter note (beats: 1 via parseMelody) -
      // that's a timing approximation, not the real recording's rhythm; refine the
      // `beats` values later if a fully rhythm-accurate arrangement becomes available.
      tempo: 100,
      notes: parseMelody(`
        G#4 F4 G#4 F4 G#4 F4 F4 F4 E4 E4 F4
        G#4 F4 G#4 F4 G#4 F4 F4 A#4 G4 F4 D#4 G4
        F4 F4 C#5 C#5 C#5 C5 A#4 G4 G4 A#4 G4 C#5 C5 C5
        F4 F4 C#5 C#5 C#5 C5 A#4 G4 G4 A#4 G4 C#5 C5 C5
        C5 C#5 C5 A#4 G#4 G4 G4 F4 E4 G4 F4 F4
        G#4 F4 G#4 F4 G#4 F4 F4 F4 E4 E4 F4
      `, 1),
    },

    'kal-ho-na-ho': {
      id: 'kal-ho-na-ho',
      title: 'Kal Ho Na Ho Theme',
      category: 'Bollywood',
      composer: 'Shankar-Ehsaan-Loy',
      sourceType: 'user-provided-midi',
      // Source: user-supplied MIDI file ("Kal Ho Na Ho - Jarzee.mid", Piano 1 track).
      // Parsed directly from the file's actual note-on/note-off events and tempo
      // meta-event (88 BPM, 960 ticks/beat) - beats below are the real timing
      // between notes as performed in the MIDI, not invented/uniform durations.
      // Trimmed to the first full statement of the theme (44 notes); the MIDI
      // repeats this same phrase from note 45 onward.
      tempo: 88,
      notes: [
        { note: 'C', octave: 5, beats: 0.87 },
        { note: 'B', octave: 4, beats: 0.31 },
        { note: 'C', octave: 5, beats: 0.87 },
        { note: 'B', octave: 4, beats: 0.31 },
        { note: 'C', octave: 5, beats: 0.88 },
        { note: 'B', octave: 4, beats: 0.28 },
        { note: 'C', octave: 5, beats: 0.34 },
        { note: 'E', octave: 5, beats: 0.28 },
        { note: 'D', octave: 5, beats: 0.33 },
        { note: 'C', octave: 5, beats: 0.29 },
        { note: 'B', octave: 4, beats: 0.86 },
        { note: 'A', octave: 4, beats: 0.33 },
        { note: 'B', octave: 4, beats: 0.88 },
        { note: 'A', octave: 4, beats: 0.34 },
        { note: 'B', octave: 4, beats: 2.57 },
        { note: 'C', octave: 5, beats: 0.87 },
        { note: 'B', octave: 4, beats: 0.32 },
        { note: 'C', octave: 5, beats: 0.93 },
        { note: 'B', octave: 4, beats: 0.32 },
        { note: 'C', octave: 5, beats: 0.9 },
        { note: 'B', octave: 4, beats: 0.3 },
        { note: 'C', octave: 5, beats: 0.3 },
        { note: 'E', octave: 5, beats: 0.29 },
        { note: 'D', octave: 5, beats: 0.32 },
        { note: 'C', octave: 5, beats: 0.32 },
        { note: 'B', octave: 4, beats: 0.9 },
        { note: 'A', octave: 4, beats: 0.34 },
        { note: 'B', octave: 4, beats: 0.87 },
        { note: 'A', octave: 4, beats: 0.36 },
        { note: 'B', octave: 4, beats: 0.98 },
        { note: 'G', octave: 4, beats: 0.57 },
        { note: 'A', octave: 4, beats: 0.58 },
        { note: 'C', octave: 5, beats: 0.34 },
        { note: 'A', octave: 4, beats: 3.48 },
        { note: 'F', octave: 4, beats: 0.57 },
        { note: 'G', octave: 4, beats: 0.55 },
        { note: 'A', octave: 4, beats: 0.34 },
        { note: 'G', octave: 4, beats: 3.31 },
        { note: 'G', octave: 4, beats: 0.57 },
        { note: 'A', octave: 4, beats: 0.57 },
        { note: 'C', octave: 5, beats: 0.34 },
        { note: 'A', octave: 4, beats: 1.94 },
        { note: 'G', octave: 4, beats: 0.56 },
        { note: 'F', octave: 4, beats: 2 },
      ],
    },
  };

  // Centralized validation: every song must go through this before it's treated as
  // playable anywhere in the app, so no page can silently play invalid/garbage notes.
  function validateSong(song) {
    const errors = [];
    if (!song || typeof song !== 'object') return { valid: false, errors: ['Song is missing or not an object'] };
    if (song.incomplete) errors.push('Song is marked incomplete (no verified note data yet)');
    if (!Array.isArray(song.notes) || song.notes.length === 0) errors.push('Song has no notes');
    if (!(typeof song.tempo === 'number' && song.tempo > 0)) errors.push('Song has an invalid tempo');

    (song.notes || []).forEach((n, i) => {
      if (!n || !NoteUtils.NOTE_NAMES.includes(n.note)) errors.push(`Note ${i}: invalid pitch "${n && n.note}"`);
      if (!(typeof n.octave === 'number' && Number.isFinite(n.octave))) errors.push(`Note ${i}: invalid octave`);
      if (!(typeof n.beats === 'number' && n.beats > 0)) errors.push(`Note ${i}: invalid duration`);
      if (n && n.note && !KeyboardMapping.PRACTICE_KEY_MAP[n.note]) errors.push(`Note ${i}: no keyboard mapping for "${n.note}"`);
      if (n) {
        const midi = NoteUtils.noteToMidi(n.note, n.octave);
        if (!Number.isFinite(midi) || !Number.isFinite(NoteUtils.midiToNoteData(midi).freq)) {
          errors.push(`Note ${i}: produces an invalid frequency`);
        }
      }
    });

    return { valid: errors.length === 0, errors };
  }

  global.SongUtils = {
    validateSong,
    // Single gate used by Free Play, Preview, Practice, and Game Mode - a song is
    // only ever playable if it passes validation, never based on rounded/guessed data.
    isSongPlayable(song) {
      const result = validateSong(song);
      if (!result.valid && !song.incomplete) {
        // Only warn for songs NOT already flagged incomplete - an incomplete song
        // failing validation is expected, not a bug worth logging every load.
        console.warn(`Invalid song data: ${song.id}`, result.errors);
      }
      return result.valid;
    },
    getExpectedTimings(song) {
      const secondsPerBeat = 60 / song.tempo;
      let cursor = 0;
      return song.notes.map((n) => {
        const expectedTime = cursor;
        cursor += n.beats * secondsPerBeat;
        return expectedTime;
      });
    },
    getTotalDuration(song) {
      const secondsPerBeat = 60 / song.tempo;
      return song.notes.reduce((total, n) => total + n.beats * secondsPerBeat, 0);
    },
  };
})(window);
