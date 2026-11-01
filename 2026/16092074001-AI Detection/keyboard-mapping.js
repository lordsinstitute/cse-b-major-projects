// Centralized keyboard-to-note mappings, kept separate from audio/rendering so
// both Free Play and Practice Mode reference the same source of truth.
(function (global) {
  // Free Play: chromatic mapping across three QWERTY rows (~2.75 octaves at once),
  // shiftable up/down since a real 88-key piano can't fit on one keyboard.
  const FREE_PLAY_KEY_ORDER = [
    'z', 'x', 'c', 'v', 'b', 'n', 'm', ',', '.', '/',
    'a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l', ';', '\'',
    'q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p', '[', ']',
  ];

  // Practice Mode: one octave, diatonic-friendly layout (white keys on the home
  // row, sharps on the row above), so "press A to play C" always holds true.
  const PRACTICE_KEY_MAP = {
    C: 'a',
    'C#': 'w',
    D: 's',
    'D#': 'e',
    E: 'd',
    F: 'f',
    'F#': 't',
    G: 'g',
    'G#': 'y',
    A: 'h',
    'A#': 'u',
    B: 'j',
  };

  global.KeyboardMapping = { FREE_PLAY_KEY_ORDER, PRACTICE_KEY_MAP };
})(window);
