// Free Play: the full 88-key piano. Note/frequency math, song data, keyboard
// mappings and audio playback all live in shared modules (note-utils.js,
// songs.js, keyboard-mapping.js, audio-engine.js) so Practice Mode reuses the
// exact same logic instead of duplicating it.
const { ALL_NOTES, MAX_MIDI } = NoteUtils;
const KEY_MAP = KeyboardMapping.FREE_PLAY_KEY_ORDER.map((key, semitone) => ({ key, semitone }));

const MIN_BASE_MIDI = 24; // C1
const MAX_BASE_MIDI = MAX_MIDI - KEY_MAP.length + 1; // keep the whole mapped range on the piano
let baseMidi = 48; // C3

const piano = document.getElementById('piano');
const instrumentSelect = document.getElementById('instrument');
const volumeSlider = document.getElementById('volume');
const statusEl = document.getElementById('status');
const octaveLabel = document.getElementById('octave-label');
const octaveDownBtn = document.getElementById('octave-down');
const octaveUpBtn = document.getElementById('octave-up');
const songSelectEl = document.getElementById('song-select');
const practiceLinkEl = document.getElementById('practice-link');
const playSongBtn = document.getElementById('play-song');
const stopSongBtn = document.getElementById('stop-song');

const engine = new PianoAudioEngine({
  samplesPath: 'samples/',
  onSamplesLoaded: () => { statusEl.textContent = ''; },
});
instrumentSelect.addEventListener('change', () => engine.setInstrument(instrumentSelect.value));
volumeSlider.addEventListener('input', () => engine.setVolume(parseFloat(volumeSlider.value)));
engine.setInstrument(instrumentSelect.value);
engine.setVolume(parseFloat(volumeSlider.value));

// Populate the song dropdown from the shared SONGS data, grouped by category
// (adding a new song - Bollywood or otherwise - only requires editing songs.js).
// Songs without verified/licensed note data (SongUtils.isSongPlayable === false)
// are left out of the dropdown entirely, instead of silently letting them play
// invented notes.
let selectedSongId = Object.values(SONGS).find((s) => SongUtils.isSongPlayable(s))?.id || Object.keys(SONGS)[0];
const songOptGroups = {};
Object.values(SONGS).forEach((song) => {
  if (!SongUtils.isSongPlayable(song)) return;
  const groupName = song.category || 'Songs';
  if (!songOptGroups[groupName]) {
    const group = document.createElement('optgroup');
    group.label = groupName;
    songSelectEl.appendChild(group);
    songOptGroups[groupName] = group;
  }
  const option = document.createElement('option');
  option.value = song.id;
  option.textContent = song.title;
  option.selected = song.id === selectedSongId;
  songOptGroups[groupName].appendChild(option);
});

function updatePracticeLink() {
  const song = SONGS[selectedSongId];
  const playable = SongUtils.isSongPlayable(song);
  practiceLinkEl.href = playable ? `practice/?song=${encodeURIComponent(selectedSongId)}` : '#';
  practiceLinkEl.classList.toggle('is-disabled', !playable);
  playSongBtn.disabled = !playable;
}
updatePracticeLink();

songSelectEl.addEventListener('change', () => {
  selectedSongId = songSelectEl.value;
  updatePracticeLink();
});

// Build all 88 piano keys, positioning white keys in a row and black keys absolutely on top.
let whiteIndex = 0;
ALL_NOTES.forEach((n) => {
  const keyEl = document.createElement('div');
  keyEl.classList.add('key', n.type);
  keyEl.dataset.midi = n.midi;

  if (n.type === 'white') {
    if (n.pitchClass === 'C') keyEl.textContent = n.note;
    piano.appendChild(keyEl);
    whiteIndex++;
  } else {
    keyEl.style.left = `${whiteIndex * 60 - 20}px`;
    piano.appendChild(keyEl);
  }

  keyEl.addEventListener('mousedown', () => playNote(n.midi));
  keyEl.addEventListener('mouseup', () => stopNote(n.midi));
  keyEl.addEventListener('mouseleave', () => stopNote(n.midi));
  keyEl.addEventListener('touchstart', (e) => { e.preventDefault(); playNote(n.midi); });
  keyEl.addEventListener('touchend', (e) => { e.preventDefault(); stopNote(n.midi); });
});

function findNote(midi) {
  return ALL_NOTES.find((n) => n.midi === midi);
}

function getKeyMidi(key) {
  const entry = KEY_MAP.find((k) => k.key === key);
  return entry ? baseMidi + entry.semitone : null;
}

// Re-labels and highlights whichever keys are currently bound to the computer
// keyboard, and scrolls them into view, since the keyboard can't reach all 88 keys at once.
function updateKeyBindings() {
  document.querySelectorAll('.key.bound').forEach((el) => el.classList.remove('bound'));
  document.querySelectorAll('.key').forEach((el) => {
    const midi = Number(el.dataset.midi);
    const noteData = findNote(midi);
    el.textContent = noteData.pitchClass === 'C' ? noteData.note : '';
  });

  let firstBoundEl = null;
  KEY_MAP.forEach(({ key, semitone }) => {
    const midi = baseMidi + semitone;
    const keyEl = document.querySelector(`.key[data-midi="${midi}"]`);
    if (!keyEl) return;
    keyEl.classList.add('bound');
    keyEl.textContent = key.toUpperCase();
    if (!firstBoundEl) firstBoundEl = keyEl;
  });

  if (octaveLabel) {
    const rootNote = findNote(baseMidi);
    const topNote = findNote(baseMidi + KEY_MAP.length - 1);
    octaveLabel.textContent = `Keyboard plays ${rootNote.note} - ${topNote.note}`;
  }
  if (firstBoundEl) {
    firstBoundEl.scrollIntoView({ behavior: 'smooth', inline: 'center', block: 'nearest' });
  }
}

function shiftOctave(direction) {
  const nextBase = baseMidi + direction * 12;
  if (nextBase < MIN_BASE_MIDI || nextBase > MAX_BASE_MIDI) return;
  baseMidi = nextBase;
  updateKeyBindings();
}

octaveDownBtn.addEventListener('click', () => shiftOctave(-1));
octaveUpBtn.addEventListener('click', () => shiftOctave(1));

function setKeyActive(midi, isActive) {
  document.querySelectorAll(`[data-midi="${midi}"]`).forEach((el) => {
    el.classList.toggle('active', isActive);
  });
}

function playNote(midi) {
  engine.playNote(midi);
  setKeyActive(midi, true);
}

function stopNote(midi) {
  engine.stopNote(midi);
  setKeyActive(midi, false);
}

let songTimeouts = [];

function stopSong() {
  songTimeouts.forEach((id) => clearTimeout(id));
  songTimeouts = [];
  engine.stopAll();
  playSongBtn.disabled = false;
}

function playSong(songId) {
  const song = SONGS[songId];
  if (!song || !SongUtils.isSongPlayable(song)) return;

  stopSong();
  engine.resume();

  const secondsPerBeat = 60 / song.tempo;
  playSongBtn.disabled = true;

  let cursor = 0;
  song.notes.forEach((noteInfo) => {
    const midi = NoteUtils.noteToMidi(noteInfo.note, noteInfo.octave);
    const durationSeconds = noteInfo.beats * secondsPerBeat;
    songTimeouts.push(setTimeout(() => playNote(midi), cursor * 1000));
    songTimeouts.push(setTimeout(() => stopNote(midi), (cursor + durationSeconds * 0.9) * 1000));
    cursor += durationSeconds;
  });

  songTimeouts.push(setTimeout(() => { playSongBtn.disabled = false; }, cursor * 1000));
}

playSongBtn.addEventListener('click', () => playSong(selectedSongId));
stopSongBtn.addEventListener('click', stopSong);
practiceLinkEl.addEventListener('click', (e) => {
  if (practiceLinkEl.classList.contains('is-disabled')) e.preventDefault();
});

window.addEventListener('keydown', (e) => {
  if (e.repeat) return;
  // Mac users: left Option/Alt shifts down an octave, right Option/Alt shifts up.
  if (e.key === 'Alt') {
    e.preventDefault();
    return shiftOctave(e.location === 2 ? 1 : -1);
  }
  const key = e.key.toLowerCase();
  const midi = getKeyMidi(key);
  if (midi !== null) playNote(midi);
});

window.addEventListener('keyup', (e) => {
  const key = e.key.toLowerCase();
  const midi = getKeyMidi(key);
  if (midi !== null) stopNote(midi);
});

updateKeyBindings();
