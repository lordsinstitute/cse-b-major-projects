// Shared note/frequency math used by both the free-play piano and Practice Mode,
// so the two never disagree about what a given note actually sounds like.
(function (global) {
  const NOTE_NAMES = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
  const MIN_MIDI = 21; // A0
  const MAX_MIDI = 108; // C8

  function midiToNoteData(midi) {
    const name = NOTE_NAMES[midi % 12];
    const octave = Math.floor(midi / 12) - 1;
    const freq = 440 * Math.pow(2, (midi - 69) / 12);
    return {
      midi,
      note: `${name}${octave}`,
      pitchClass: name,
      octave,
      freq,
      type: name.includes('#') ? 'black' : 'white',
    };
  }

  // Accepts either a note name string ("C#4") or a { note, octave } object.
  function noteToMidi(note, octave) {
    let pitchClass = note;
    let oct = octave;
    if (typeof note === 'object') {
      pitchClass = note.note;
      oct = note.octave;
    } else if (oct === undefined) {
      const match = note.match(/^([A-G]#?)(-?\d+)$/);
      pitchClass = match[1];
      oct = parseInt(match[2], 10);
    }
    return (oct + 1) * 12 + NOTE_NAMES.indexOf(pitchClass);
  }

  const ALL_NOTES = [];
  for (let midi = MIN_MIDI; midi <= MAX_MIDI; midi++) {
    ALL_NOTES.push(midiToNoteData(midi));
  }

  // A black key's enharmonic pair, e.g. "C#" -> "C# / Db".
  const ENHARMONIC_LABELS = {
    'C#': 'C# / Db',
    'D#': 'D# / Eb',
    'F#': 'F# / Gb',
    'G#': 'G# / Ab',
    'A#': 'A# / Bb',
  };

  global.NoteUtils = {
    NOTE_NAMES,
    MIN_MIDI,
    MAX_MIDI,
    ALL_NOTES,
    midiToNoteData,
    noteToMidi,
    ENHARMONIC_LABELS,
  };
})(window);
