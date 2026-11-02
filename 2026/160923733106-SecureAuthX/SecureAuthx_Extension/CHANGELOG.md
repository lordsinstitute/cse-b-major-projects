# Changelog

## Phase 3B — local encrypted password vault (finalized)

Added
- AES-256-GCM encrypted local vault (`lib/vault.js`, `lib/crypto.js`): PBKDF2 vault key with its own random salt, fresh 96-bit IV per save, non-extractable key, ciphertext-only storage (`lib/storage.js`).
- Vault tab: unlock, lock, add/update/delete/search, random password generator, encrypted export/import, user-initiated Fill with exact-hostname matching, an HTTPS requirement (loopback exception), and lookalike-domain blocking.
- Vault messages are accepted only from the extension's own pages.
- Tests: `tests/batch5-vault.test.js`, `tests/phase3b-regression.test.js`, `tests/e2e/vault.spec.js`, `tests/e2e/vault-finalization.spec.js`.

Finalization fixes (each defect was confirmed against the real extension before it was fixed)
- Ill-typed credential fields (non-string site, object secret, array username) were accepted or left the caller hanging, and a stored malformed item broke search. Inputs are now strictly validated and every vault handler fails with a generic error instead of hanging.
- Sites that could never match (`localhost:8300`, full URLs) were silently accepted. Sites must now be bare hostnames.
- A wrong master password was ignored when the profile already had a live session. A supplied password is now always verified.
- Import persisted data before validating it, and a file encrypted under a different password replaced the vault key. Import now requires an unlocked vault, validates every item, and re-encrypts under the current profile's key.
- Vault payloads are fully validated (and sanitized) after decryption on load.

Documented (not changed): hostname-versus-port matching and the absence of automatic clipboard clearing. See `docs/LIMITATIONS.md`.
