import { test, expect } from "@playwright/test";
import { launchWithExtension } from "./helpers/launch-extension.js";
import { serveFixtures } from "./helpers/serve-fixtures.js";
import {
  TEST_MASTER_PASSWORD, send, getProfileId, readAllStorage, openVaultTab, unlockViaUi, unlockedVault, addViaMessage,
  openLoginPage, getWorker, installSessionTimerControl, liveSessionTimerDelays, cancelledSessionTimerCount, expireSessions,
  buildExportFile, vaultItem, SESSION_TIMEOUT_MS,
} from "./helpers/vault.js";
import { deriveSitePassword, reuseComparisonHash } from "../../lib/crypto.js";

/**
 * Phase 3B finalization suite (real Chrome, real extension).
 * Covers: deterministic 30-minute inactivity timeout, defect-fix regressions
 * (validation, wrong password with a live session, import), documented
 * limitations (clipboard, hostname-vs-port), and regression checks that the
 * pre-existing generator and reuse-detection paths are unchanged.
 */

const PORT_A = 8224;
const PORT_B = 8225;
let serverA;
let serverB;
test.beforeAll(() => { serverA = serveFixtures(PORT_A); serverB = serveFixtures(PORT_B); });
test.afterAll(() => { serverA.close(); serverB.close(); });

/* ============ 30-minute inactivity timeout (deterministic clock) ============ */

test("inactivity timeout: scheduled for exactly 30 minutes, activity reschedules it, expiry locks the vault and the profile", async () => {
  const { context, extensionId } = await launchWithExtension();
  try {
    const popup = await openVaultTab(context, extensionId);
    const profileId = await getProfileId(popup);
    const worker = await getWorker(context);
    await installSessionTimerControl(worker);

    await unlockViaUi(popup);
    await popup.locator("#vaultUnlockedView").waitFor({ state: "visible" });
    const item = await addViaMessage(popup, profileId, { site: "timeout.example", username: "u", secret: "TimeoutSecret-1!" });

    // Exactly one live session timer, and it is the 30-minute one.
    expect(SESSION_TIMEOUT_MS).toBe(1800000);
    expect(await liveSessionTimerDelays(worker)).toEqual([SESSION_TIMEOUT_MS]);

    // Activity reschedules: the old timer is cancelled and exactly one new 30-minute timer is live.
    const cancelledBefore = await cancelledSessionTimerCount(worker);
    expect((await send(popup, { type: "SAX_VAULT_LIST", profileId })).ok).toBe(true);
    expect(await cancelledSessionTimerCount(worker)).toBeGreaterThan(cancelledBefore);
    expect(await liveSessionTimerDelays(worker)).toEqual([SESSION_TIMEOUT_MS]);

    // Not locked early.
    expect((await send(popup, { type: "SAX_VAULT_STATUS", profileId })).unlocked).toBe(true);

    // "30 minutes pass without activity."
    expect(await expireSessions(worker)).toBe(1);

    expect((await send(popup, { type: "SAX_VAULT_STATUS", profileId })).unlocked).toBe(false);
    for (const message of [
      { type: "SAX_VAULT_LIST", profileId },
      { type: "SAX_VAULT_GET_ITEM", profileId, itemId: item.id },
      { type: "SAX_VAULT_FILL", profileId, itemId: item.id },
      { type: "SAX_VAULT_MATCHES_FOR_ACTIVE_TAB", profileId },
      { type: "SAX_VAULT_ADD_ITEM", profileId, item: { site: "b.example", secret: "x" } },
    ]) {
      const r = await send(popup, message);
      expect(r.ok, message.type).toBe(false);
      expect(JSON.stringify(r)).not.toContain("TimeoutSecret-1!");
    }
    // The master-password session expired too: the generator can no longer run without the password.
    const gen = await send(popup, { type: "SAX_GENERATE_PASSWORD", profileId, domain: "timeout.example", accountId: "Default" });
    expect(gen.ok).toBe(false);

    // The UI reflects the expiry, and only the master password reopens the vault (ciphertext persisted).
    await popup.click('[data-tab="passwords"]');
    await popup.click('[data-tab="vault"]');
    await popup.locator("#vaultLockedView").waitFor({ state: "visible" });
    expect((await send(popup, { type: "SAX_VAULT_UNLOCK", profileId })).ok).toBe(false);
    const back = await send(popup, { type: "SAX_VAULT_UNLOCK", profileId, masterPassword: TEST_MASTER_PASSWORD });
    expect(back.ok).toBe(true);
    expect((await send(popup, { type: "SAX_VAULT_GET_ITEM", profileId, itemId: item.id })).item.secret).toBe("TimeoutSecret-1!");
  } finally {
    await context.close();
  }
});

/* ============ defect-fix regressions ============ */

test("a wrong master password is rejected even when the profile already has a live session", async () => {
  const { context, extensionId } = await launchWithExtension();
  try {
    const popup = await openVaultTab(context, extensionId);
    const profileId = await getProfileId(popup);
    expect((await send(popup, { type: "SAX_UNLOCK_PROFILE", id: profileId, masterPassword: TEST_MASTER_PASSWORD })).ok).toBe(true);

    const wrong = await send(popup, { type: "SAX_VAULT_UNLOCK", profileId, masterPassword: "definitely-the-wrong-password" });
    expect(wrong.ok).toBe(false);
    expect((await send(popup, { type: "SAX_VAULT_STATUS", profileId })).unlocked).toBe(false);

    // Documented: no password supplied + an already-authenticated session opens the vault.
    expect((await send(popup, { type: "SAX_VAULT_UNLOCK", profileId })).ok).toBe(true);
    expect((await send(popup, { type: "SAX_VAULT_STATUS", profileId })).unlocked).toBe(true);
  } finally {
    await context.close();
  }
});

test("malformed vault requests fail fast with a clean error (never hang) and never poison the vault", async () => {
  const { context, extensionId } = await launchWithExtension();
  try {
    const { popup, profileId } = await unlockedVault(context, extensionId);
    const raced = (promise, ms = 4000) => Promise.race([promise, new Promise((_, reject) => setTimeout(() => reject(new Error("HUNG: no response")), ms))]);
    const keep = await addViaMessage(popup, profileId, { site: "keep.example", username: "u", secret: "KeepSecret-1!" });

    const bad = [
      { type: "SAX_VAULT_ADD_ITEM", profileId, item: { site: 5, secret: "x" } },
      { type: "SAX_VAULT_ADD_ITEM", profileId, item: { site: "a.example", secret: {} } },
      { type: "SAX_VAULT_ADD_ITEM", profileId, item: { site: "a.example", secret: "x", username: ["u"] } },
      { type: "SAX_VAULT_ADD_ITEM", profileId, item: null },
      { type: "SAX_VAULT_ADD_ITEM", profileId, item: "string" },
      { type: "SAX_VAULT_ADD_ITEM", profileId, item: [] },
      { type: "SAX_VAULT_ADD_ITEM", profileId },
      { type: "SAX_VAULT_UPDATE_ITEM", profileId, itemId: keep.id, updates: [] },
      { type: "SAX_VAULT_UPDATE_ITEM", profileId, itemId: keep.id, updates: "x" },
      { type: "SAX_VAULT_UPDATE_ITEM", profileId, itemId: keep.id, updates: { secret: {} } },
      { type: "SAX_VAULT_UPDATE_ITEM", profileId, itemId: 5, updates: { secret: "x" } },
      { type: "SAX_VAULT_GET_ITEM", profileId, itemId: {} },
      { type: "SAX_VAULT_DELETE_ITEM", profileId, itemId: [] },
    ];
    for (const message of bad) {
      const r = await raced(send(popup, message));
      expect(r.ok, JSON.stringify(message)).toBe(false);
      expect(JSON.stringify(r)).not.toContain("KeepSecret-1!");
    }

    // A non-string search query is refused by the request schema (Phase 3C), quickly and cleanly.
    const search = await raced(send(popup, { type: "SAX_VAULT_LIST", profileId, query: { x: 1 } }));
    expect(search.ok).toBe(false);
    expect(search.code).toBe("invalid_request");

    // The vault is intact and fully usable afterwards.
    await addViaMessage(popup, profileId, { site: "after.example", secret: "AfterSecret-1!" });
    const list = await send(popup, { type: "SAX_VAULT_LIST", profileId, query: "example" });
    expect(list.items.map((i) => i.site).sort()).toEqual(["after.example", "keep.example"]);
    expect((await send(popup, { type: "SAX_VAULT_GET_ITEM", profileId, itemId: keep.id })).item.secret).toBe("KeepSecret-1!");
  } finally {
    await context.close();
  }
});

test("adding a credential whose site is a URL or has a port shows a clear 'domain only' error in the UI", async () => {
  const { context, extensionId } = await launchWithExtension();
  try {
    const { popup } = await unlockedVault(context, extensionId);
    await popup.click("details:has(#vaultNewSite) summary");
    for (const badSite of ["https://example.com/login", "example.com:8443"]) {
      await popup.fill("#vaultNewSite", badSite);
      await popup.fill("#vaultNewSecret", "x");
      await popup.click("#vaultAddBtn");
      await expect(popup.locator("#vaultAddError")).toBeVisible();
      await expect(popup.locator("#vaultAddError")).toContainText(/domain/i);
    }
    await popup.fill("#vaultNewSite", "example.com");
    await popup.click("#vaultAddBtn");
    await popup.locator("#vaultItemsList .detail-row").first().waitFor();
    await expect(popup.locator("#vaultAddError")).toBeHidden();
  } finally {
    await context.close();
  }
});

test("import: re-encrypts under the profile key, validates every item before persisting, and requires an unlocked vault", async () => {
  const { context, extensionId } = await launchWithExtension();
  try {
    const { popup, profileId } = await unlockedVault(context, extensionId);
    const keep = await addViaMessage(popup, profileId, { site: "keep.example", username: "u", secret: "KeepSecret-2!" });
    const importPassword = "DifferentExportPassword-1!";
    const imp = (exportData, extra = {}) =>
      send(popup, { type: "SAX_VAULT_IMPORT", profileId, exportData, masterPassword: importPassword, confirmOverwrite: true, ...extra });

    // Malformed-but-decryptable files: rejected, nothing persisted, existing vault untouched and still openable.
    const before = JSON.stringify((await readAllStorage(popup)).sax_vault[profileId]);
    for (const items of [
      [{ id: 1, secret: 5 }, null],
      [vaultItem("dup", "a.example", "u", "s"), vaultItem("dup", "b.example", "u", "s")],
      [vaultItem("i-1", "a.example", "u", { not: "a string" })],
      [vaultItem("i-1", "a.example", ["u"], "s")],
    ]) {
      const file = await buildExportFile(popup, importPassword, { version: 1, items });
      const r = await imp(file);
      expect(r.ok, JSON.stringify(items).slice(0, 60)).toBe(false);
      expect(JSON.stringify((await readAllStorage(popup)).sax_vault[profileId])).toBe(before);
    }
    expect((await send(popup, { type: "SAX_VAULT_LIST", profileId })).items.map((i) => i.site)).toEqual(["keep.example"]);

    // Valid file encrypted under a DIFFERENT password: accepted, re-encrypted under the profile key (new salt), openable with the profile's master password.
    const good = await buildExportFile(popup, importPassword, {
      version: 1, items: [vaultItem("i-1", "imported-one.example", "u1", "ImportedSecret-1", { evil: "dropped" }), vaultItem("i-2", "imported-two.example", "u2", "ImportedSecret-2")],
    });
    const ok = await imp(good);
    expect(ok.ok, JSON.stringify(ok)).toBe(true);
    expect(JSON.stringify(ok)).not.toContain("ImportedSecret-");
    expect((await readAllStorage(popup)).sax_vault[profileId].saltHex).not.toBe(good.saltHex);

    await send(popup, { type: "SAX_VAULT_LOCK", profileId });
    expect((await send(popup, { type: "SAX_VAULT_UNLOCK", profileId, masterPassword: TEST_MASTER_PASSWORD })).ok).toBe(true);
    const list = await send(popup, { type: "SAX_VAULT_LIST", profileId });
    expect(list.items.map((i) => i.site).sort()).toEqual(["imported-one.example", "imported-two.example"]);
    const one = await send(popup, { type: "SAX_VAULT_GET_ITEM", profileId, itemId: "i-1" });
    expect(one.item.secret).toBe("ImportedSecret-1");
    expect("evil" in one.item).toBe(false);
    expect((await send(popup, { type: "SAX_VAULT_GET_ITEM", profileId, itemId: keep.id })).ok).toBe(false);

    // Importing while locked is refused.
    await send(popup, { type: "SAX_VAULT_LOCK", profileId });
    const locked = await imp(good);
    expect(locked.ok).toBe(false);
    expect(locked.error).toMatch(/unlock/i);
  } finally {
    await context.close();
  }
});

/* ============ documented limitations ============ */

test("clipboard limitation is communicated: a standing note, and an explicit 'not cleared' message after Copy", async () => {
  const { context, extensionId } = await launchWithExtension();
  try {
    const { popup, profileId } = await unlockedVault(context, extensionId);
    await addViaMessage(popup, profileId, { site: "copy.example", username: "u", secret: "CopySecret-1!" });
    await popup.click('[data-tab="passwords"]');
    await popup.click('[data-tab="vault"]');
    await popup.locator("#vaultItemsList .vault-copy-btn").first().waitFor();

    await expect(popup.locator("#vaultClipboardNote")).toBeVisible();
    await expect(popup.locator("#vaultClipboardNote")).toContainText(/does not clear the clipboard automatically/i);

    // Deterministic: record writes instead of touching the OS clipboard.
    await popup.evaluate(() => { window.__clipboardWrites = []; navigator.clipboard.writeText = async (text) => { window.__clipboardWrites.push(text); }; });
    await popup.locator("#vaultItemsList .vault-copy-btn").first().click();
    await expect(popup.locator("#vaultActionMessage")).toContainText(/not cleared automatically/i);
    await popup.waitForTimeout(1500);
    // Exactly one explicit write (the copy). No second write = nothing cleared or overwritten behind the user's back.
    expect(await popup.evaluate(() => window.__clipboardWrites)).toEqual(["CopySecret-1!"]);
  } finally {
    await context.close();
  }
});

test("KNOWN LIMITATION: matching ignores the port (same hostname on different ports is the same site)", async () => {
  const { context, extensionId } = await launchWithExtension();
  try {
    const { popup, profileId } = await unlockedVault(context, extensionId);
    await addViaMessage(popup, profileId, { site: "localhost", username: "u", secret: "PortSecret-1!" });

    await openLoginPage(context, `http://localhost:${PORT_A}/vault-login-target.html`);
    const onA = await send(popup, { type: "SAX_VAULT_MATCHES_FOR_ACTIVE_TAB", profileId });
    expect(onA.hostname).toBe("localhost");
    expect(onA.items).toHaveLength(1);

    await openLoginPage(context, `http://localhost:${PORT_B}/vault-login-target.html`);
    const onB = await send(popup, { type: "SAX_VAULT_MATCHES_FOR_ACTIVE_TAB", profileId });
    expect(onB.items).toHaveLength(1);

    // The port cannot be made part of a saved site: it is rejected with guidance instead of silently never matching.
    const withPort = await send(popup, { type: "SAX_VAULT_ADD_ITEM", profileId, item: { site: `localhost:${PORT_A}`, secret: "x" } });
    expect(withPort.ok).toBe(false);
    expect(withPort.error).toMatch(/domain/i);
  } finally {
    await context.close();
  }
});

/* ============ regression: existing features are unchanged ============ */

test("existing deterministic generator is unchanged: the extension returns exactly the library's derived password, and rejects a wrong master password", async () => {
  const { context, extensionId } = await launchWithExtension();
  try {
    const popup = await openVaultTab(context, extensionId);
    const profileId = await getProfileId(popup);
    const expected = await deriveSitePassword(TEST_MASTER_PASSWORD, "golden.example", "Default");

    const r = await send(popup, { type: "SAX_GENERATE_PASSWORD", profileId, domain: "golden.example", accountId: "Default", masterPassword: TEST_MASTER_PASSWORD, rememberSession: false });
    expect(r.ok, JSON.stringify(r)).toBe(true);
    expect(r.derived).toBe(expected);

    const wrong = await send(popup, { type: "SAX_GENERATE_PASSWORD", profileId, domain: "golden.example", accountId: "Default", masterPassword: "not-the-master-password", rememberSession: false });
    expect(wrong.ok).toBe(false);
    expect(wrong.derived).toBeUndefined();
  } finally {
    await context.close();
  }
});

test("existing reuse detection is unchanged: the same password hash on a second domain is reported as reused", async () => {
  const { context, extensionId } = await launchWithExtension();
  try {
    const popup = await openVaultTab(context, extensionId);
    const reuseHash = await reuseComparisonHash("Golden-Password-1");
    const first = await send(popup, { type: "SAX_RECORD_REUSE", domain: "a.example", reuseHash });
    expect(first.reusedElsewhere).toEqual([]);
    const second = await send(popup, { type: "SAX_RECORD_REUSE", domain: "b.example", reuseHash });
    expect(second.reusedElsewhere).toEqual(["a.example"]);
    const other = await send(popup, { type: "SAX_RECORD_REUSE", domain: "c.example", reuseHash: await reuseComparisonHash("A-Different-Password-2") });
    expect(other.reusedElsewhere).toEqual([]);
  } finally {
    await context.close();
  }
});

test("guard: twelve concurrent adds are all persisted across lock and unlock", async () => {
  const { context, extensionId } = await launchWithExtension();
  try {
    const { popup, profileId } = await unlockedVault(context, extensionId);
    const results = await Promise.all(Array.from({ length: 12 }, (_, i) => send(popup, { type: "SAX_VAULT_ADD_ITEM", profileId, item: { site: `race${i}.example`, secret: "s" + i } })));
    expect(results.every((r) => r.ok)).toBe(true);
    await send(popup, { type: "SAX_VAULT_LOCK", profileId });
    expect((await send(popup, { type: "SAX_VAULT_UNLOCK", profileId, masterPassword: TEST_MASTER_PASSWORD })).ok).toBe(true);
    expect((await send(popup, { type: "SAX_VAULT_LIST", profileId, query: "race" })).items).toHaveLength(12);
  } finally {
    await context.close();
  }
});
