// Practice Mode engine: reusable for any song in songs.js - reads the song id
// from the URL, then drives a guided note-by-note lesson using the exact same
// AudioEngine, NoteUtils and SONGS data as Free Play (script.js).
//
// State (single source of truth - nothing here is derived from another page):
//   currentIndex     - index into `sequence` of the note the user must play next
//   loopCount        - how many full passes through the song have been completed + 1
//   correctAttempts  - total correct key presses (across all loops)
//   wrongAttempts    - total incorrect key presses
//   isPaused         - practice input is ignored while true
//   hasStarted       - becomes true after the first correct press (controls the
//                      lightweight "Press X to begin" hint vs. the normal stats bar)
const KEY_TO_PITCH = Object.fromEntries(
  Object.entries(KeyboardMapping.PRACTICE_KEY_MAP).map(([pitch, key]) => [key, pitch])
);

const songId = new URLSearchParams(window.location.search).get('song') || Object.keys(SONGS)[0];
const song = SONGS[songId];

const titleEl = document.getElementById('song-title');
const instructionEl = document.getElementById('song-instruction');
const startHintEl = document.getElementById('start-hint');
const statsBarEl = document.getElementById('stats-bar');
const loopLabelEl = document.getElementById('loop-label');
const accuracyLabelEl = document.getElementById('accuracy-label');
const mistakesLabelEl = document.getElementById('mistakes-label');
const statusEl = document.getElementById('status');
const currentLabelEl = document.getElementById('current-note-label');
const nextLabelEl = document.getElementById('next-note-label');
const progressFillEl = document.getElementById('progress-bar-fill');
const progressCountEl = document.getElementById('progress-count');
const progressStatusEl = document.getElementById('progress-status');
const sequenceWrapperEl = document.getElementById('practice-sequence-wrapper');
const sequenceEl = document.getElementById('practice-sequence');
const pianoEl = document.getElementById('practice-piano');
const instrumentSelect = document.getElementById('practice-instrument');
const volumeSlider = document.getElementById('practice-volume');
const restartBtn = document.getElementById('restart-btn');
const pauseBtn = document.getElementById('pause-btn');

if (!song) {
  titleEl.textContent = 'Song not found';
  instructionEl.textContent = 'That song does not exist. Go back and pick one from the list.';
  throw new Error(`Unknown song id: ${songId}`);
}

if (!SongUtils.isSongPlayable(song)) {
  titleEl.textContent = `🎯 ${song.title}`;
  instructionEl.textContent = 'This song is Coming Soon - verified note data hasn\'t been added yet, so practice is disabled rather than teaching a wrong melody.';
  statusEl.hidden = true;
  throw new Error(`Song "${songId}" is not playable yet (incomplete note data)`);
}

titleEl.textContent = song.title;

const engine = new PianoAudioEngine({
  samplesPath: 'samples/',
  onSamplesLoaded: () => { statusEl.textContent = ''; },
});

const savedInstrument = localStorage.getItem('practice-instrument');
if (savedInstrument && Array.from(instrumentSelect.options).some((option) => option.value === savedInstrument)) {
  instrumentSelect.value = savedInstrument;
}
let selectedInstrument = instrumentSelect.value;
engine.setInstrument(selectedInstrument);
engine.setVolume(parseFloat(volumeSlider.value));
instrumentSelect.addEventListener('change', () => {
  selectedInstrument = instrumentSelect.value;
  engine.setInstrument(selectedInstrument);
  localStorage.setItem('practice-instrument', selectedInstrument);
});
volumeSlider.addEventListener('input', () => engine.setVolume(parseFloat(volumeSlider.value)));

function playPracticeNote(midi) {
  engine.setInstrument(selectedInstrument);
  engine.playNote(midi);
}

const prefersReducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

// The song's notes, pre-resolved to MIDI + display data so nothing is recomputed later.
// This is the ONLY note sequence in Practice Mode - the sequence strip, the piano
// highlight, and the audio all read from these same objects.
const sequence = song.notes.map((n) => ({
  pitchClass: n.note,
  octave: n.octave,
  midi: NoteUtils.noteToMidi(n.note, n.octave),
  name: `${n.note}${n.octave}`,
  keyChar: KeyboardMapping.PRACTICE_KEY_MAP[n.note] || '?',
}));

let currentIndex = 0;
let loopCount = 1;
let correctAttempts = 0;
let wrongAttempts = 0;
let isPaused = false;
let hasStarted = false;
const sequenceChips = [];
const activeAttemptMidi = {}; // key char -> midi currently sounding, so keyup can stop it

// --- Build the practice sequence strip -------------------------------------------------
sequence.forEach((noteInfo) => {
  const chip = document.createElement('div');
  chip.className = 'seq-note';
  // Practice cards show only the keyboard key to press - never the piano note name,
  // so the learner never has to translate note -> key while playing.
  chip.innerHTML = `<span class="seq-note-key">${noteInfo.keyChar.toUpperCase()}</span>`;
  sequenceEl.appendChild(chip);
  sequenceChips.push(chip);
});

// --- Build the one-octave practice piano (note name + key always visible) --------------
// Sized well above the old fixed 60px keys so the piano is the visual focus; the
// black-key left offset is computed from these same numbers so positioning never drifts.
const PITCH_ORDER = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];

function getPianoDimensions() {
  const width = window.innerWidth;
  if (width < 480) return { whiteW: 64, whiteH: 190, blackW: 40, blackH: 120 };
  if (width < 900) return { whiteW: 96, whiteH: 260, blackW: 60, blackH: 160 };
  return { whiteW: 125, whiteH: 340, blackW: 78, blackH: 210 };
}

const dims = getPianoDimensions();
pianoEl.style.setProperty('--white-w', `${dims.whiteW}px`);
pianoEl.style.setProperty('--white-h', `${dims.whiteH}px`);
pianoEl.style.setProperty('--black-w', `${dims.blackW}px`);
pianoEl.style.setProperty('--black-h', `${dims.blackH}px`);

let whiteIndex = 0;
PITCH_ORDER.forEach((pitchClass) => {
  const isBlack = pitchClass.includes('#');
  const keyEl = document.createElement('div');
  keyEl.classList.add('key', isBlack ? 'black' : 'white');
  keyEl.dataset.pitch = pitchClass;
  keyEl.setAttribute('role', 'button');
  keyEl.setAttribute('tabindex', '0');
  keyEl.setAttribute('aria-label', `Piano key ${pitchClass}, keyboard shortcut ${(KeyboardMapping.PRACTICE_KEY_MAP[pitchClass] || '').toUpperCase()}`);

  const label = isBlack ? NoteUtils.ENHARMONIC_LABELS[pitchClass] : pitchClass;
  keyEl.innerHTML = `
    <span class="key-note-label">${label}</span>
    <span class="key-letter-label">${(KeyboardMapping.PRACTICE_KEY_MAP[pitchClass] || '').toUpperCase()}</span>
  `;

  if (!isBlack) {
    pianoEl.appendChild(keyEl);
    whiteIndex++;
  } else {
    keyEl.style.left = `${whiteIndex * dims.whiteW - dims.blackW / 2}px`;
    pianoEl.appendChild(keyEl);
  }

  keyEl.addEventListener('mousedown', () => handleAttempt(pitchClass));
  keyEl.addEventListener('mouseup', () => handleRelease(pitchClass));
  keyEl.addEventListener('mouseleave', () => handleRelease(pitchClass));
  keyEl.addEventListener('touchstart', (e) => { e.preventDefault(); handleAttempt(pitchClass); });
  keyEl.addEventListener('touchend', (e) => { e.preventDefault(); handleRelease(pitchClass); });
  keyEl.addEventListener('keydown', (e) => {
    if ((e.key === 'Enter' || e.key === ' ') && !e.repeat) { e.preventDefault(); handleAttempt(pitchClass); }
  });
  keyEl.addEventListener('keyup', (e) => {
    if (e.key === 'Enter' || e.key === ' ') handleRelease(pitchClass);
  });
});

function setPianoKeyActive(pitchClass, isActive) {
  document.querySelectorAll(`.practice-piano [data-pitch="${pitchClass}"]`).forEach((el) => {
    el.classList.toggle('active', isActive);
  });
}

// Keeps the piano key for the current target visually in sync with the practice
// sequence's "current" card - both read from the same `sequence[currentIndex]`.
function updatePianoTarget() {
  document.querySelectorAll('.practice-piano .key.target').forEach((el) => el.classList.remove('target'));
  const target = sequence[currentIndex];
  if (!target) return;
  document.querySelectorAll(`.practice-piano [data-pitch="${target.pitchClass}"]`).forEach((el) => {
    el.classList.add('target');
  });
}

// --- Core interaction: keyboard, piano clicks, and piano keyboard-focus all call this
// single function, so there is exactly one path from user input to progress/audio. -----
function handleAttempt(pitchClass) {
  if (isPaused || currentIndex >= sequence.length) return;
  const target = sequence[currentIndex];
  setPianoKeyActive(pitchClass, true);

  if (pitchClass === target.pitchClass) {
    correctAttempts++;
    playPracticeNote(target.midi);
    activeAttemptMidi[pitchClass] = target.midi;
    hasStarted = true;
    advance();
  } else {
    wrongAttempts++;
    // Audible feedback in the same octave as the target, without marking progress.
    const feedbackMidi = NoteUtils.noteToMidi(pitchClass, target.octave);
    playPracticeNote(feedbackMidi);
    activeAttemptMidi[pitchClass] = feedbackMidi;
    flashWrong(pitchClass);
    renderStats();
  }
}

function handleRelease(pitchClass) {
  setPianoKeyActive(pitchClass, false);
  const midi = activeAttemptMidi[pitchClass];
  if (midi !== undefined) {
    engine.stopNote(midi);
    delete activeAttemptMidi[pitchClass];
  }
}

// Brief, subtle feedback on both the pressed piano key and the (unchanged) target
// card - never blocking, never advancing, never resetting progress.
function flashWrong(pitchClass) {
  const chip = sequenceChips[currentIndex];
  chip.classList.add('wrong');
  setTimeout(() => chip.classList.remove('wrong'), 300);

  document.querySelectorAll(`.practice-piano [data-pitch="${pitchClass}"]`).forEach((el) => {
    el.classList.add('wrong');
    setTimeout(() => el.classList.remove('wrong'), 300);
  });
}

// Practice mode never "finishes" - reaching the last note loops back to the start
// so the user can keep practicing without any interruption or modal. The loop can
// only be triggered by an actual successful final-note press, never by initialization.
function advance() {
  const songLoaded = Array.isArray(sequence) && sequence.length > 0;
  const isFinalNote = songLoaded && currentIndex === sequence.length - 1;
  let didLoop = false;

  if (isFinalNote) {
    currentIndex = 0;
    loopCount++;
    didLoop = true;
  } else {
    currentIndex++;
  }
  renderProgress(didLoop);
  renderStats();
  if (didLoop) pulseLoopTransition();
}

// A very short, subtle pulse on the loop counter - the only feedback for the
// automatic loop restart, never a modal and never a pause in the music.
function pulseLoopTransition() {
  loopLabelEl.classList.add('loop-pulse');
  setTimeout(() => loopLabelEl.classList.remove('loop-pulse'), 260);
}

function renderProgress(resetScroll) {
  sequenceChips.forEach((chip, i) => {
    chip.classList.remove('completed', 'current', 'upcoming');
    chip.classList.add(i < currentIndex ? 'completed' : i === currentIndex ? 'current' : 'upcoming');
  });

  const target = sequence[currentIndex];
  const next = sequence[currentIndex + 1];
  currentLabelEl.textContent = target ? target.keyChar.toUpperCase() : '—';
  nextLabelEl.textContent = next ? next.keyChar.toUpperCase() : '—';

  const percent = (currentIndex / sequence.length) * 100;
  progressFillEl.style.width = `${percent}%`;
  progressCountEl.textContent = `${currentIndex} / ${sequence.length} notes`;

  updatePianoTarget();
  updateStartHint();

  if (resetScroll) {
    sequenceWrapperEl.scrollTo({ left: 0, behavior: 'auto' });
  } else if (target) {
    sequenceChips[currentIndex].scrollIntoView({
      behavior: prefersReducedMotion ? 'auto' : 'smooth',
      inline: 'center',
      block: 'nearest',
    });
  }
}

// A lightweight, non-blocking instruction shown only before the very first correct
// press of this visit - never a modal, and it never re-appears once the user starts.
// Shown instead of (not alongside) the Press/Next row, to avoid saying "press G" twice.
function updateStartHint() {
  if (hasStarted) {
    startHintEl.hidden = true;
    statsBarEl.hidden = false;
    progressStatusEl.hidden = false;
    return;
  }
  const target = sequence[currentIndex];
  startHintEl.hidden = !target;
  statsBarEl.hidden = true;
  progressStatusEl.hidden = true;
  if (target) startHintEl.innerHTML = `Press <strong>${target.keyChar.toUpperCase()}</strong> to begin`;
}

function renderStats() {
  loopLabelEl.textContent = loopCount;
  mistakesLabelEl.textContent = wrongAttempts;
  const totalAttempts = correctAttempts + wrongAttempts;
  accuracyLabelEl.textContent = totalAttempts > 0 ? `${Math.round((correctAttempts / totalAttempts) * 100)}%` : '—';
}

function restart() {
  currentIndex = 0;
  loopCount = 1;
  correctAttempts = 0;
  wrongAttempts = 0;
  hasStarted = false;
  renderProgress(true);
  renderStats();
}

function togglePause() {
  isPaused = !isPaused;
  pauseBtn.textContent = isPaused ? '▶ Resume' : '⏸ Pause';
  pauseBtn.setAttribute('aria-label', isPaused ? 'Resume practice' : 'Pause practice');
}

restartBtn.addEventListener('click', restart);
pauseBtn.addEventListener('click', togglePause);

function handleKeyDown(e) {
  if (e.repeat) return;
  const pitchClass = KEY_TO_PITCH[e.key.toLowerCase()];
  if (pitchClass) handleAttempt(pitchClass);
}

function handleKeyUp(e) {
  const pitchClass = KEY_TO_PITCH[e.key.toLowerCase()];
  if (pitchClass) handleRelease(pitchClass);
}

window.addEventListener('keydown', handleKeyDown);
window.addEventListener('keyup', handleKeyUp);

// Leaving the page (Back to Songs, closing the tab, etc.) tears down audio and
// listeners - Practice Mode has no background state once this page is gone, and
// Free Play (a separate page/script) is completely unaffected.
function cleanup() {
  window.removeEventListener('keydown', handleKeyDown);
  window.removeEventListener('keyup', handleKeyUp);
  engine.stopAll();
}
window.addEventListener('pagehide', cleanup);

renderProgress(false);
renderStats();
