# SecureAuthX — Known limitations (Phase 3B)

These are documented, deliberate, or not-yet-addressed limits of the local password vault. Each is covered by an automated test where a test is possible.

## Matching is by hostname, NOT by port

A saved credential matches the active tab by **exact hostname** (what `URL.hostname` returns, for example `localhost` or `login.example.com`). The **port and the scheme are not part of the match**, apart from the HTTPS requirement described in the fill rules.

- A credential saved for `localhost` is offered on `http://localhost:3000/` **and** `http://localhost:8080/`. Two different local services on different ports are treated as one site.
- There are no subdomain or "related domain" matches: `www.example.com`, `login.example.com` and `example.com` are three different sites.
- Because the port is not part of the match, the vault refuses site values that contain a port, scheme, or path (for example `localhost:8300` or `https://example.com/login`). Enter the bare domain only.
- A test documents this behaviour (`KNOWN LIMITATION: matching ignores the port`).

## Clipboard: copied passwords are NOT cleared automatically

"Copy" puts the selected password on the system clipboard and SecureAuthX **does not clear it later**. The Vault tab says so permanently, and again after every copy.

Why: clearing it safely (only if the clipboard still contains what was copied, and never overwriting something newer the user copied) requires reading the clipboard. That needs a new permission (`clipboardRead`) or an offscreen document, and either changes the extension's permission surface, so it was deliberately not added. A popup-only timer would not work either, because the popup closes as soon as it loses focus.

Prefer **Fill**, which never touches the clipboard.

## Inactivity timeout (30 minutes)

The vault lives on the same in-memory session as the master password. It is wiped when the session expires after 30 minutes without vault or generator activity, on manual lock, or when the browser stops the MV3 service worker.

- It is verified deterministically in real Chrome by driving the service worker's own timer (no 30-minute wait): the session is scheduled for exactly 30 minutes, activity reschedules it, and firing it locks the vault, refuses every vault operation, and requires the master password again.
- JavaScript cannot guarantee memory is zeroed. Removing the references is best effort; this is not a claim of cryptographic memory wiping.

## Other limits

- **No "save this password?" prompt.** Credentials are added only from the Vault tab. Detecting form submissions across arbitrary sites was judged too risky for this phase.
- **Import replaces the whole vault** (after an explicit confirmation) and requires an unlocked vault. The imported items are validated and re-encrypted under the current profile's key.
- **Unlocking an already-unlocked profile.** If the profile was unlocked for this browser session (for example through the password generator's "remember" option), pressing Unlock with an empty password field opens the vault from that session. Any password that is typed is always verified.
- **Delete has no confirmation dialog**, and the import flow uses native `prompt`/`confirm`/`alert`. Both belong to the later UI redesign.
- **PBKDF2-SHA256 (250,000 iterations)** is used for key derivation, not Argon2, to avoid adding a WASM dependency.
- **Concurrent saves** are not serialized. Twelve simultaneous adds were observed to persist 12/12, but a guarantee was not proven.
