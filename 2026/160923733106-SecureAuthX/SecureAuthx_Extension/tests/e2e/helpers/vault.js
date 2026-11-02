import fs from "node:fs";
import path from "node:path";
import { expect } from "@playwright/test";
import { openPopup, TEST_MASTER_PASSWORD } from "./popup.js";
import { FIXTURES_DIR } from "./serve-fixtures.js";

export { TEST_MASTER_PASSWORD, FIXTURES_DIR };
export const LOGIN_HTML = fs.readFileSync(path.join(FIXTURES_DIR, "vault-login-target.html"), "utf8");
export const SESSION_TIMEOUT_MS = 30 * 60 * 1000;

/** Send a runtime message from the popup page (a trusted extension page). */
export const send = (popup, message) => popup.evaluate((m) => browser.runtime.sendMessage(m), message);
export const getProfileId = (popup) =>
  popup.evaluate(async () => (await browser.storage.local.get("sax_profiles_state")).sax_profiles_state.defaultProfileId);
export const readAllStorage = (popup) => popup.evaluate(() => browser.storage.local.get(null));

export async function openVaultTab(context, extensionId) {
  const popup = await openPopup(context, extensionId);
  await popup.click('[data-tab="vault"]');
  await popup.locator("#vaultLockedView").waitFor({ state: "visible" });
  return popup;
}

export async function unlockViaUi(popup, password = TEST_MASTER_PASSWORD) {
  await popup.fill("#vaultUnlockPassword", password);
  await popup.click("#vaultUnlockBtn");
}

export async function unlockedVault(context, extensionId) {
  const popup = await openVaultTab(context, extensionId);
  await unlockViaUi(popup);
  await popup.locator("#vaultUnlockedView").waitFor({ state: "visible" });
  return { popup, profileId: await getProfileId(popup) };
}

export async function addViaMessage(popup, profileId, item) {
  const r = await send(popup, { type: "SAX_VAULT_ADD_ITEM", profileId, item });
  expect(r.ok, JSON.stringify(r)).toBe(true);
  return r.item;
}

/** Re-opens the Vault tab view while `target` is focused (background.js resolves the ACTIVE tab). */
export async function refreshVaultFor(popup, target) {
  await target.bringToFront();
  await popup.click('[data-tab="passwords"]');
  await target.bringToFront();
  await popup.click('[data-tab="vault"]');
  await popup.locator("#vaultUnlockedView").waitFor({ state: "visible" });
  await popup.waitForTimeout(400);
}

export async function openLoginPage(context, url) {
  const page = await context.newPage();
  await page.goto(url, { waitUntil: "load" });
  await page.waitForTimeout(500); // let content scripts reach document_idle
  await page.bringToFront();
  return page;
}

export async function mockPage(context, url, html = LOGIN_HTML) {
  await context.route(url, (route) => route.fulfill({ status: 200, contentType: "text/html", body: html }));
}

export async function getWorker(context) {
  return context.serviceWorkers()[0] ?? (await context.waitForEvent("serviceworker"));
}

/* ---------- deterministic clock for the 30-minute session timer ----------
 * Intercepts the REAL service worker's setTimeout/clearTimeout for the
 * session-expiry delay only. The real extension code schedules and
 * reschedules its timer as normal; the test decides when "30 minutes"
 * have passed by firing the captured callback. */
export async function installSessionTimerControl(worker) {
  await worker.evaluate((ms) => {
    const realSet = globalThis.setTimeout.bind(globalThis);
    const realClear = globalThis.clearTimeout.bind(globalThis);
    const timers = new Map();
    let nextId = 9000000;
    globalThis.__saxTimerControl = { timers };
    globalThis.setTimeout = (fn, delay, ...args) => {
      if (delay === ms) {
        const id = nextId++;
        timers.set(id, { fn, delay, cancelled: false, args });
        return id;
      }
      return realSet(fn, delay, ...args);
    };
    globalThis.clearTimeout = (id) => {
      const t = timers.get(id);
      if (t) { t.cancelled = true; return; }
      realClear(id);
    };
  }, SESSION_TIMEOUT_MS);
}
export const liveSessionTimerDelays = (worker) =>
  worker.evaluate(() => [...globalThis.__saxTimerControl.timers.values()].filter((t) => !t.cancelled).map((t) => t.delay));
export const cancelledSessionTimerCount = (worker) =>
  worker.evaluate(() => [...globalThis.__saxTimerControl.timers.values()].filter((t) => t.cancelled).length);
/** "30 minutes pass": fire every live session timer exactly as the browser would. */
export const expireSessions = (worker) =>
  worker.evaluate(() => {
    const live = [...globalThis.__saxTimerControl.timers.values()].filter((t) => !t.cancelled);
    for (const t of live) { t.cancelled = true; t.fn(...t.args); }
    return live.length;
  });

/** Builds an export file encrypted under `password` (extension crypto, run inside the popup page). */
export const buildExportFile = (popup, password, payload) =>
  popup.evaluate(async ({ password, payload }) => {
    const c = await import(browser.runtime.getURL("lib/crypto.js"));
    const salt = c.generateVaultSalt();
    const key = await c.deriveVaultKey(password, salt);
    const enc = await c.encryptVaultPayload(key, payload);
    return { format: "secureauthx-vault-export", version: 1, saltHex: salt, ...enc };
  }, { password, payload });

export const vaultItem = (id, site, username, secret, extra = {}) => ({
  id, site, username, secret, accountLabel: "", notes: "", createdAt: 1, updatedAt: 2, ...extra,
});
