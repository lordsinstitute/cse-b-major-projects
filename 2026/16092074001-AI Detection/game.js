// Game Mode: local pass-and-play scoring game built entirely on the existing
// Free Play / Practice infrastructure (NoteUtils, SONGS, KeyboardMapping,
// PianoAudioEngine, GameScoring) - no networking, no storage, nothing persists
// across a refresh because everything below lives only in normal JS variables.

// ---------------------------------------------------------------------------
// DOM references
// ---------------------------------------------------------------------------
const phaseEls = {
  'mode-select': document.getElementById('phase-mode-select'),
  'player-setup': document.getElementById('phase-player-setup'),
  'song-select': document.getElementById('phase-song-select'),
  'turn-ready': document.getElementById('phase-turn-ready'),
  countdown: document.getElementById('phase-countdown'),
  playing: document.getElementById('phase-playing'),
  'turn-results': document.getElementById('phase-turn-results'),
  'final-results': document.getElementById('phase-final-results'),
};

const soloBtn = document.getElementById('solo-btn');
const friendsBtn = document.getElementById('friends-btn');

const playerListEl = document.getElementById('player-list');
const playerAddForm = document.getElementById('player-add-form');
const playerNameInput = document.getElementById('player-name-input');
const playerErrorEl = document.getElementById('player-error');
const confirmPlayersBtn = document.getElementById('confirm-players-btn');

const songSelectEl = document.getElementById('song-select');
const startGameBtn = document.getElementById('start-game-btn');
const scoringRulesBodyEl = document.getElementById('scoring-rules-body');

const readyPlayerNameEl = document.getElementById('ready-player-name');
const readyPlayerNameEl2 = document.getElementById('ready-player-name-2');
const readyBtn = document.getElementById('ready-btn');

const countdownNumberEl = document.getElementById('countdown-number');

const playingSongTitleEl = document.getElementById('playing-song-title');
const playingPlayerNameEl = document.getElementById('playing-player-name');
const gameStartHintEl = document.getElementById('game-start-hint');
const gameStatsBarEl = document.getElementById('game-stats-bar');
const gameAccuracyLabelEl = document.getElementById('game-accuracy-label');
const gameMistakesLabelEl = document.getElementById('game-mistakes-label');
const gameProgressStatusEl = document.getElementById('game-progress-status');
const gameCurrentLabelEl = document.getElementById('game-current-label');
const gameNextLabelEl = document.getElementById('game-next-label');
const gameProgressFillEl = document.getElementById('game-progress-fill');
const gameProgressCountEl = document.getElementById('game-progress-count');
const gameSequenceWrapperEl = document.getElementById('game-sequence-wrapper');
const gameSequenceEl = document.getElementById('game-sequence');
const gamePianoEl = document.getElementById('game-piano');
const gamePauseBtn = document.getElementById('game-pause-btn');
const gameRestartBtn = document.getElementById('game-restart-btn');
const liveLeaderboardEl = document.getElementById('live-leaderboard');
const liveLeaderboardListEl = document.getElementById('live-leaderboard-list');
const statusEl = document.getElementById('status');

const resultsHeadingEl = document.getElementById('results-heading');
const resultStatsEl = document.getElementById('result-stats');
const currentLeaderEl = document.getElementById('current-leader');
const nextPlayerBoxEl = document.getElementById('next-player-box');
const nextPlayerNameEl = document.getElementById('next-player-name');
const nextPlayerNameEl2 = document.getElementById('next-player-name-2');
const nextReadyBtn = document.getElementById('next-ready-btn');

const winnerBoxEl = document.getElementById('winner-box');
const finalLeaderboardListEl = document.getElementById('final-leaderboard-list');
const samePlayersBtn = document.getElementById('same-players-btn');
const newGameBtn = document.getElementById('new-game-btn');
const exitGameLink = document.getElementById('exit-game');

const confettiCanvas = document.getElementById('confetti-canvas');

const prefersReducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

// ---------------------------------------------------------------------------
// Shared engine + keyboard mapping (same source of truth as Free Play/Practice)
// ---------------------------------------------------------------------------
const KEY_TO_PITCH = Object.fromEntries(
  Object.entries(KeyboardMapping.PRACTICE_KEY_MAP).map(([pitch, key]) => [key, pitch])
);

const engine = new PianoAudioEngine({
  samplesPath: 'samples/',
  onSamplesLoaded: () => { statusEl.textContent = ''; },
});
engine.setInstrument('acoustic-piano');
engine.setVolume(0.6);

// ---------------------------------------------------------------------------
// Game state - explicit phases, no persistence, everything in memory only.
// ---------------------------------------------------------------------------
let currentPhase = 'mode-select';
let players = [];
let selectedSongId = null;
let currentPlayerIndex = 0;
let celebrationPlayed = false;
const pendingTimeouts = [];

// Per-turn working state (reset every turn via resetTurnState()).
let sequence = [];
let expectedTimings = [];
let totalDuration = 0;
let sequenceChips = [];
let currentIndex = 0;
let correctNotes = 0;
let wrongAttempts = 0;
let timingSamples = [];
let fluencySamples = [];
let lastCorrectElapsedMs = null;
let turnStartPerf = 0;
let pausedTotalMs = 0;
let pauseStartPerf = 0;
let isPaused = false;
let hasStarted = false;
const activeAttemptMidi = {};

function showPhase(name) {
  const previousPhase = currentPhase;
  currentPhase = name;
  Object.entries(phaseEls).forEach(([key, el]) => { el.hidden = key !== name; });
  // Guarded transition (not "every render") so the celebration can never fire
  // more than once for the same game, no matter how often this screen re-renders.
  if (name === 'final-results' && previousPhase !== 'final-results') {
    triggerCelebration();
  }
}

function setTimeoutTracked(fn, delay) {
  const id = setTimeout(fn, delay);
  pendingTimeouts.push(id);
  return id;
}

function clearPendingTimeouts() {
  pendingTimeouts.forEach((id) => clearTimeout(id));
  pendingTimeouts.length = 0;
}

// ---------------------------------------------------------------------------
// Player management
// ---------------------------------------------------------------------------
let nextPlayerId = 1;
function makePlayer(name) {
  return {
    id: nextPlayerId++,
    name,
    correctNotes: 0,
    wrongAttempts: 0,
    totalAttempts: 0,
    accuracy: 0,
    timingScore: 0,
    fluencyScore: 0,
    speedScore: 0,
    completionTime: 0,
    score: 0,
    hasPlayed: false,
  };
}

function resetAllPlayerStats() {
  players.forEach((p) => {
    p.correctNotes = 0;
    p.wrongAttempts = 0;
    p.totalAttempts = 0;
    p.accuracy = 0;
    p.timingScore = 0;
    p.fluencyScore = 0;
    p.speedScore = 0;
    p.completionTime = 0;
    p.score = 0;
    p.hasPlayed = false;
  });
}

// --- Mode select -------------------------------------------------------------
soloBtn.addEventListener('click', () => {
  players = [makePlayer('You')];
  showSongSelect();
});

friendsBtn.addEventListener('click', () => {
  players = [];
  renderPlayerList();
  showPhase('player-setup');
});

// --- Player setup --------------------------------------------------------------
function renderPlayerList() {
  playerListEl.innerHTML = '';
  players.forEach((player, index) => {
    const row = document.createElement('div');
    row.className = 'player-row';

    const numberEl = document.createElement('span');
    numberEl.className = 'player-number';
    numberEl.textContent = `${index + 1}.`;

    const nameInput = document.createElement('input');
    nameInput.type = 'text';
    nameInput.value = player.name;
    nameInput.maxLength = 20;
    nameInput.setAttribute('aria-label', `Player ${index + 1} name`);
    nameInput.addEventListener('change', () => {
      const trimmed = nameInput.value.trim();
      player.name = trimmed || player.name;
      nameInput.value = player.name;
    });

    const removeBtn = document.createElement('button');
    removeBtn.type = 'button';
    removeBtn.className = 'remove-player-btn';
    removeBtn.setAttribute('aria-label', `Remove ${player.name}`);
    removeBtn.textContent = '✕';
    removeBtn.addEventListener('click', () => {
      players.splice(index, 1);
      renderPlayerList();
    });

    row.append(numberEl, nameInput, removeBtn);
    playerListEl.appendChild(row);
  });
}

function showPlayerError(message) {
  playerErrorEl.textContent = message;
  playerErrorEl.hidden = false;
  setTimeoutTracked(() => { playerErrorEl.hidden = true; }, 2500);
}

playerAddForm.addEventListener('submit', (e) => {
  e.preventDefault();
  const name = playerNameInput.value.trim();
  if (!name) { showPlayerError('Enter a name first.'); return; }
  if (players.length >= 6) { showPlayerError('Maximum of 6 players.'); return; }
  if (players.some((p) => p.name.toLowerCase() === name.toLowerCase())) {
    showPlayerError('That name is already taken.');
    return;
  }
  players.push(makePlayer(name));
  playerNameInput.value = '';
  renderPlayerList();
});

confirmPlayersBtn.addEventListener('click', () => {
  if (players.length < 2) { showPlayerError('Add at least 2 players for multiplayer.'); return; }
  showSongSelect();
});

// --- Song select --------------------------------------------------------------
function showSongSelect() {
  songSelectEl.innerHTML = '';
  const groups = {};
  Object.values(SONGS).forEach((song) => {
    if (!SongUtils.isSongPlayable(song)) return;
    const groupName = song.category || 'Songs';
    if (!groups[groupName]) {
      const group = document.createElement('optgroup');
      group.label = groupName;
      songSelectEl.appendChild(group);
      groups[groupName] = group;
    }
    const option = document.createElement('option');
    option.value = song.id;
    option.textContent = song.title;
    groups[groupName].appendChild(option);
  });

  const w = GameScoring.SCORE_WEIGHTS;
  scoringRulesBodyEl.innerHTML = `
    <ul>
      <li>Accuracy — ${Math.round(w.accuracy * 100)}%</li>
      <li>Timing — ${Math.round(w.timing * 100)}%</li>
      <li>Fluency — ${Math.round(w.fluency * 100)}%</li>
      <li>Speed — ${Math.round(w.speed * 100)}%</li>
    </ul>
    <p>Play accurately and keep the rhythm flowing - waiting between notes on purpose lowers your timing and fluency score.</p>
  `;

  currentPlayerIndex = 0;
  showPhase('song-select');
}

startGameBtn.addEventListener('click', () => {
  const song = SONGS[songSelectEl.value];
  if (!song || !SongUtils.isSongPlayable(song)) return;
  selectSong(songSelectEl.value);
});

function selectSong(songId) {
  selectedSongId = songId;
  const song = SONGS[songId];
  playingSongTitleEl.textContent = song.title;

  sequence = song.notes.map((n) => ({
    pitchClass: n.note,
    octave: n.octave,
    midi: NoteUtils.noteToMidi(n.note, n.octave),
    keyChar: KeyboardMapping.PRACTICE_KEY_MAP[n.note] || '?',
  }));
  expectedTimings = SongUtils.getExpectedTimings(song);
  totalDuration = SongUtils.getTotalDuration(song);
  buildSequenceChips();

  startTurnReady(0);
}

// --- Piano (built once - the one-octave layout never changes between turns) ---
const PITCH_ORDER = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];

function getPianoDimensions() {
  const width = window.innerWidth;
  if (width < 480) return { whiteW: 64, whiteH: 190, blackW: 40, blackH: 120 };
  if (width < 900) return { whiteW: 96, whiteH: 260, blackW: 60, blackH: 160 };
  return { whiteW: 125, whiteH: 340, blackW: 78, blackH: 210 };
}

(function buildPiano() {
  const dims = getPianoDimensions();
  gamePianoEl.style.setProperty('--white-w', `${dims.whiteW}px`);
  gamePianoEl.style.setProperty('--white-h', `${dims.whiteH}px`);
  gamePianoEl.style.setProperty('--black-w', `${dims.blackW}px`);
  gamePianoEl.style.setProperty('--black-h', `${dims.blackH}px`);

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
      gamePianoEl.appendChild(keyEl);
      whiteIndex++;
    } else {
      keyEl.style.left = `${whiteIndex * dims.whiteW - dims.blackW / 2}px`;
      gamePianoEl.appendChild(keyEl);
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
})();

function buildSequenceChips() {
  gameSequenceEl.innerHTML = '';
  sequenceChips = sequence.map((noteInfo) => {
    const chip = document.createElement('div');
    chip.className = 'seq-note';
    chip.innerHTML = `<span class="seq-note-key">${noteInfo.keyChar.toUpperCase()}</span>`;
    gameSequenceEl.appendChild(chip);
    return chip;
  });
}

function setPianoKeyActive(pitchClass, isActive) {
  document.querySelectorAll(`#game-piano [data-pitch="${pitchClass}"]`).forEach((el) => {
    el.classList.toggle('active', isActive);
  });
}

function updatePianoTarget() {
  document.querySelectorAll('#game-piano .key.target').forEach((el) => el.classList.remove('target'));
  const target = sequence[currentIndex];
  if (!target) return;
  document.querySelectorAll(`#game-piano [data-pitch="${target.pitchClass}"]`).forEach((el) => el.classList.add('target'));
}

// --- Turn lifecycle ------------------------------------------------------------
function startTurnReady(playerIndex) {
  currentPlayerIndex = playerIndex;
  const player = players[playerIndex];
  readyPlayerNameEl.textContent = player.name;
  readyPlayerNameEl2.textContent = player.name;
  readyBtn.textContent = `${player.name} is Ready`;
  showPhase('turn-ready');
}

readyBtn.addEventListener('click', runCountdown);
nextReadyBtn.addEventListener('click', () => {
  const nextIndex = players.findIndex((p) => !p.hasPlayed);
  if (nextIndex !== -1) startTurnReady(nextIndex);
});

function runCountdown() {
  showPhase('countdown');
  const steps = ['3', '2', '1', 'GO!'];
  steps.forEach((label, i) => {
    setTimeoutTracked(() => { countdownNumberEl.textContent = label; }, i * 650);
  });
  setTimeoutTracked(beginTurn, steps.length * 650);
}

function resetTurnState() {
  currentIndex = 0;
  correctNotes = 0;
  wrongAttempts = 0;
  timingSamples = [];
  fluencySamples = [];
  lastCorrectElapsedMs = null;
  pausedTotalMs = 0;
  isPaused = false;
  hasStarted = false;
  turnStartPerf = performance.now();
  gamePauseBtn.textContent = '⏸ Pause';
  gamePauseBtn.setAttribute('aria-label', 'Pause turn');
}

function beginTurn() {
  resetTurnState();
  const player = players[currentPlayerIndex];
  playingPlayerNameEl.textContent = player.name;
  // Show the phase BEFORE touching scroll/layout: the sequence container is
  // `display: none` (via the `hidden` attribute) until this runs, and scrolling
  // a hidden element is a no-op - that silently left the previous player's
  // scroll position in place, which was the root cause of bug #2 below.
  showPhase('playing');
  renderProgress(true);
  renderLiveStats();
  renderLiveLeaderboard();
}

// --- Core interaction: keyboard and piano clicks call this single function -----
function handleAttempt(pitchClass) {
  if (currentPhase !== 'playing' || isPaused || currentIndex >= sequence.length) return;
  const target = sequence[currentIndex];
  setPianoKeyActive(pitchClass, true);

  if (pitchClass === target.pitchClass) {
    const nowElapsedMs = performance.now() - turnStartPerf - pausedTotalMs;
    correctNotes++;
    engine.playNote(target.midi);
    activeAttemptMidi[pitchClass] = target.midi;
    hasStarted = true;

    // Timing/fluency scoring starts from the SECOND note - the first note is a
    // reaction to "GO!" and shouldn't be penalized (see game-scoring.js).
    if (currentIndex > 0) {
      const diffMs = nowElapsedMs - expectedTimings[currentIndex] * 1000;
      timingSamples.push(GameScoring.timingQualityFromDiff(diffMs));
      if (lastCorrectElapsedMs !== null) {
        const actualGapMs = nowElapsedMs - lastCorrectElapsedMs;
        const expectedGapMs = (expectedTimings[currentIndex] - expectedTimings[currentIndex - 1]) * 1000;
        fluencySamples.push(GameScoring.fluencyForGap(actualGapMs, expectedGapMs));
      }
    }
    lastCorrectElapsedMs = nowElapsedMs;

    advanceTurn(nowElapsedMs);
  } else {
    wrongAttempts++;
    const feedbackMidi = NoteUtils.noteToMidi(pitchClass, target.octave);
    engine.playNote(feedbackMidi);
    activeAttemptMidi[pitchClass] = feedbackMidi;
    flashWrong(pitchClass);
    renderLiveStats();
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

function flashWrong(pitchClass) {
  const chip = sequenceChips[currentIndex];
  chip.classList.add('wrong');
  setTimeoutTracked(() => chip.classList.remove('wrong'), 300);
  document.querySelectorAll(`#game-piano [data-pitch="${pitchClass}"]`).forEach((el) => {
    el.classList.add('wrong');
    setTimeoutTracked(() => el.classList.remove('wrong'), 300);
  });
}

// Defensive cleanup so no visual state (wrong-key flash, stale highlights) can
// ever leak from one player's turn into the next.
function clearTransientVisualState() {
  document.querySelectorAll('#game-sequence .wrong, #game-piano .wrong').forEach((el) => el.classList.remove('wrong'));
}

// Game Mode plays the song exactly once per turn - it never loops like Practice Mode.
function advanceTurn(nowElapsedMs) {
  if (currentIndex === sequence.length - 1) {
    finishTurn(nowElapsedMs / 1000);
  } else {
    currentIndex++;
    renderProgress(false);
    renderLiveStats();
  }
}

function finishTurn(completionSeconds) {
  const totalAttempts = correctNotes + wrongAttempts;
  const result = GameScoring.computeScore({
    correctNotes,
    wrongAttempts,
    timingSamples,
    fluencySamples,
    completionSeconds,
    expectedTotalSeconds: totalDuration,
  });

  const player = players[currentPlayerIndex];
  player.correctNotes = correctNotes;
  player.wrongAttempts = wrongAttempts;
  player.totalAttempts = totalAttempts;
  player.accuracy = result.accuracy;
  player.timingScore = result.timing;
  player.fluencyScore = result.fluency;
  player.speedScore = result.speed;
  player.completionTime = completionSeconds;
  player.score = result.score;
  player.hasPlayed = true;

  showTurnResults(player);
}

function renderProgress(resetScroll) {
  sequenceChips.forEach((chip, i) => {
    chip.classList.remove('completed', 'current', 'upcoming');
    chip.classList.add(i < currentIndex ? 'completed' : i === currentIndex ? 'current' : 'upcoming');
  });

  const target = sequence[currentIndex];
  const next = sequence[currentIndex + 1];
  gameCurrentLabelEl.textContent = target ? target.keyChar.toUpperCase() : '—';
  gameNextLabelEl.textContent = next ? next.keyChar.toUpperCase() : '—';

  const percent = (currentIndex / sequence.length) * 100;
  gameProgressFillEl.style.width = `${percent}%`;
  gameProgressCountEl.textContent = `${currentIndex} / ${sequence.length} notes`;

  updatePianoTarget();
  updateStartHint();

  if (resetScroll) {
    clearTransientVisualState();
    // Deferred one frame so this runs AFTER the phase/layout change above has
    // actually painted - scrolling in the same synchronous tick as unhiding an
    // element is unreliable (the browser may not have computed layout yet).
    requestAnimationFrame(() => {
      if (target) {
        sequenceChips[currentIndex].scrollIntoView({ behavior: 'auto', inline: 'center', block: 'nearest' });
      } else {
        gameSequenceWrapperEl.scrollTo({ left: 0, behavior: 'auto' });
      }
    });
  } else if (target) {
    sequenceChips[currentIndex].scrollIntoView({
      behavior: prefersReducedMotion ? 'auto' : 'smooth',
      inline: 'center',
      block: 'nearest',
    });
  }
}

function updateStartHint() {
  if (hasStarted) {
    gameStartHintEl.hidden = true;
    gameStatsBarEl.hidden = false;
    gameProgressStatusEl.hidden = false;
    return;
  }
  const target = sequence[currentIndex];
  gameStartHintEl.hidden = !target;
  gameStatsBarEl.hidden = true;
  gameProgressStatusEl.hidden = true;
  if (target) gameStartHintEl.innerHTML = `Press <strong>${target.keyChar.toUpperCase()}</strong> to begin`;
}

function renderLiveStats() {
  const totalAttempts = correctNotes + wrongAttempts;
  gameAccuracyLabelEl.textContent = totalAttempts > 0 ? `${Math.round((correctNotes / totalAttempts) * 100)}%` : '—';
  gameMistakesLabelEl.textContent = wrongAttempts;
}

function renderLiveLeaderboard() {
  const played = players.filter((p) => p.hasPlayed).sort(GameScoring.comparePlayers);
  if (played.length === 0) { liveLeaderboardEl.hidden = true; return; }
  liveLeaderboardEl.hidden = false;
  liveLeaderboardListEl.innerHTML = played
    .map((p) => `<li>${escapeHtml(p.name)} — ${p.score} pts (${p.accuracy}%)</li>`)
    .join('');
}

function escapeHtml(str) {
  const div = document.createElement('div');
  div.textContent = str;
  return div.innerHTML;
}

// --- Pause / restart -------------------------------------------------------------
gamePauseBtn.addEventListener('click', () => {
  if (currentPhase !== 'playing') return;
  isPaused = !isPaused;
  if (isPaused) {
    pauseStartPerf = performance.now();
    gamePauseBtn.textContent = '▶ Resume';
    gamePauseBtn.setAttribute('aria-label', 'Resume turn');
  } else {
    pausedTotalMs += performance.now() - pauseStartPerf;
    gamePauseBtn.textContent = '⏸ Pause';
    gamePauseBtn.setAttribute('aria-label', 'Pause turn');
  }
});

// Restarting resets only the CURRENT player's in-progress turn - other players'
// recorded scores and the turn order are untouched.
gameRestartBtn.addEventListener('click', () => {
  if (currentPhase !== 'playing') return;
  resetTurnState();
  renderProgress(true);
  renderLiveStats();
});

// --- Turn results / next player ---------------------------------------------------
function showTurnResults(player) {
  resultsHeadingEl.textContent = `🎉 ${player.name} finished!`;
  resultStatsEl.innerHTML = `
    <div><span>Accuracy</span><strong>${player.accuracy}%</strong></div>
    <div><span>Timing</span><strong>${player.timingScore}%</strong></div>
    <div><span>Fluency</span><strong>${player.fluencyScore}%</strong></div>
    <div><span>Mistakes</span><strong>${player.wrongAttempts}</strong></div>
    <div><span>Time</span><strong>${player.completionTime.toFixed(1)}s</strong></div>
    <div><span>Score</span><strong>${player.score}</strong></div>
  `;

  const leader = players.filter((p) => p.hasPlayed).sort(GameScoring.comparePlayers)[0];
  currentLeaderEl.innerHTML = leader
    ? `<p class="phase-heading">Current Leader</p><h3>${escapeHtml(leader.name)} — ${leader.score} pts</h3><p class="muted">${leader.accuracy}% accuracy · ${leader.timingScore}% timing · ${leader.fluencyScore}% fluency</p>`
    : '';

  const nextPlayer = players.find((p) => !p.hasPlayed);
  if (nextPlayer) {
    nextPlayerBoxEl.hidden = false;
    nextPlayerNameEl.textContent = nextPlayer.name;
    nextPlayerNameEl2.textContent = nextPlayer.name;
    nextReadyBtn.textContent = `${nextPlayer.name} is Ready`;
    showPhase('turn-results');
  } else {
    nextPlayerBoxEl.hidden = true;
    showFinalResults();
  }
}

// --- Final results + celebration --------------------------------------------------
// Results are read from each player's own stored fields (correctNotes,
// wrongAttempts, accuracy, timingScore, fluencyScore, speedScore,
// completionTime, score - all set once in finishTurn()) - never recomputed or
// derived from transient UI/animation state, and never shared between players.
function showFinalResults() {
  const ranked = players.filter((p) => p.hasPlayed).sort(GameScoring.comparePlayers);
  const winner = ranked[0];

  winnerBoxEl.innerHTML = winner ? `
    <div class="trophy">🏆</div>
    <div class="winner-name">${escapeHtml(winner.name)}</div>
    <div class="winner-score">${winner.score} POINTS</div>
    <div class="winner-breakdown">
      ${winner.accuracy}% Accuracy · ${winner.timingScore}% Timing · ${winner.fluencyScore}% Fluency · ${winner.completionTime.toFixed(1)}s
    </div>
  ` : '';

  const medals = ['🥇', '🥈', '🥉'];
  finalLeaderboardListEl.innerHTML = ranked.map((p, i) => `
    <li>
      <span class="rank">${medals[i] || `${i + 1}.`}</span>
      <span class="final-name">${escapeHtml(p.name)}</span>
      <span class="final-score">${p.score} pts</span>
      <span class="final-breakdown">${p.accuracy}% acc · ${p.timingScore}% tim · ${p.fluencyScore}% flu · ${p.completionTime.toFixed(1)}s</span>
    </li>
  `).join('');

  showPhase('final-results');
}

function triggerCelebration() {
  if (celebrationPlayed) return;
  celebrationPlayed = true;
  engine.playCelebrationSound();
  setTimeoutTracked(() => engine.playApplauseSound(), 250);
  if (!prefersReducedMotion) runConfetti();
}

function runConfetti() {
  const ctx = confettiCanvas.getContext('2d');
  confettiCanvas.width = window.innerWidth;
  confettiCanvas.height = window.innerHeight;
  confettiCanvas.hidden = false;

  const colors = ['#ffe08a', '#4caf50', '#d9534f', '#61dafb', '#fff'];
  const pieces = Array.from({ length: 120 }, () => ({
    x: Math.random() * confettiCanvas.width,
    y: -20 - Math.random() * confettiCanvas.height,
    size: 4 + Math.random() * 6,
    speed: 2 + Math.random() * 3,
    drift: (Math.random() - 0.5) * 2,
    color: colors[Math.floor(Math.random() * colors.length)],
    rotation: Math.random() * Math.PI,
  }));

  const durationMs = 3000;
  const startTime = performance.now();

  function frame(now) {
    const elapsed = now - startTime;
    ctx.clearRect(0, 0, confettiCanvas.width, confettiCanvas.height);
    pieces.forEach((p) => {
      p.y += p.speed;
      p.x += p.drift;
      p.rotation += 0.05;
      ctx.save();
      ctx.translate(p.x, p.y);
      ctx.rotate(p.rotation);
      ctx.fillStyle = p.color;
      ctx.fillRect(-p.size / 2, -p.size / 2, p.size, p.size);
      ctx.restore();
    });
    if (elapsed < durationMs) {
      requestAnimationFrame(frame);
    } else {
      ctx.clearRect(0, 0, confettiCanvas.width, confettiCanvas.height);
      confettiCanvas.hidden = true;
    }
  }
  requestAnimationFrame(frame);
}

// --- Play again / new game --------------------------------------------------------
samePlayersBtn.addEventListener('click', () => {
  resetAllPlayerStats();
  currentPlayerIndex = 0;
  selectedSongId = null;
  celebrationPlayed = false;
  showSongSelect();
});

newGameBtn.addEventListener('click', () => {
  players = [];
  selectedSongId = null;
  currentPlayerIndex = 0;
  celebrationPlayed = false;
  showPhase('mode-select');
});

// --- Global keyboard input (only live during an active, unpaused turn) -------------
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

// --- Cleanup on exit: no background state survives leaving Game Mode --------------
function cleanupGame() {
  clearPendingTimeouts();
  window.removeEventListener('keydown', handleKeyDown);
  window.removeEventListener('keyup', handleKeyUp);
  engine.stopAll();
}
exitGameLink.addEventListener('click', cleanupGame);
window.addEventListener('pagehide', cleanupGame);
