import { test, expect } from "@playwright/test";
import { launchWithExtension } from "./helpers/launch-extension.js";
import { serveFixtures } from "./helpers/serve-fixtures.js";
import {
  TEST_MASTER_PASSWORD, send, readAllStorage, openVaultTab, unlockViaUi, unlockedVault, addViaMessage, openLoginPage, mockPage,
  getWorker, installSessionTimerControl, expireSessions, refreshVaultFor,
} from "./helpers/vault.js";
import { looksLikeTyposquat } from "../../lib/scoring.js";

/**
 * Phase 3C — adversarial tests for the autofill boundary (real Chrome, local fixtures only;
 * "remote" hosts are served from local mocks, nothing leaves the machine).
 */

const PORT = 8228;
let server;
test.beforeAll(() => { server = serveFixtures(PORT); });
test.afterAll(() => { server.close(); });

const LOGIN = `http://localhost:${PORT}/vault-login-target.html`;
const CRED = { site: "localhost", username: "carol@test.example", secret: "BoundarySecret-7731!" };

const tabIdFor = (worker, url) => worker.evaluate(async (u) => (await chrome.tabs.query({})).find((t) => t.url === u).id, url);
const fromWorker = (worker, tabId, msg) => worker.evaluate(({ tabId, msg }) => chrome.tabs.sendMessage(tabId, msg, { frameId: 0 }), { tabId, msg });
const blank = async (page) => { await expect(page.locator("#loginPassword")).toHaveValue(""); await expect(page.locator("#loginEmail")).toHaveValue(""); };

/* ============ the content script re-checks everything itself ============ */

test("content script: a wrong or stale expectedOrigin fills nothing; the identical message with the right origin fills (control)", async () => {
  const { context, extensionId } = await launchWithExtension();
  try {
    await unlockedVault(context, extensionId);
    const page = await openLoginPage(context, LOGIN);
    const worker = await getWorker(context);
    const tabId = await tabIdFor(worker, LOGIN);
    const msg = (expectedOrigin) => ({ type: "SAX_FILL_CREDENTIAL", expectedOrigin, username: CRED.username, password: CRED.secret });

    for (const wrong of ["https://evil.example", `http://localhost:${PORT + 1}`, `http://127.0.0.1:${PORT}`, `https://localhost:${PORT}`, "null", ""]) {
      const r = await fromWorker(worker, tabId, msg(wrong));
      expect(r.ok, wrong).toBe(false);
      expect(r.code, wrong).toBe("origin_mismatch");
      expect(JSON.stringify(r)).not.toContain(CRED.secret);
    }
    await blank(page);

    const ok = await fromWorker(worker, tabId, msg(`http://localhost:${PORT}`));
    expect(ok.ok).toBe(true);
    await expect(page.locator("#loginPassword")).toHaveValue(CRED.secret);
  } finally {
    await context.close();
  }
});

test("content script: malformed fill messages are refused and fill nothing", async () => {
  const { context, extensionId } = await launchWithExtension();
  try {
    await unlockedVault(context, extensionId);
    const page = await openLoginPage(context, LOGIN);
    const worker = await getWorker(context);
    const tabId = await tabIdFor(worker, LOGIN);
    const origin = `http://localhost:${PORT}`;
    for (const bad of [
      { type: "SAX_FILL_CREDENTIAL" },
      { type: "SAX_FILL_CREDENTIAL", expectedOrigin: origin },
      { type: "SAX_FILL_CREDENTIAL", expectedOrigin: origin, password: 12345 },
      { type: "SAX_FILL_CREDENTIAL", expectedOrigin: origin, password: "" },
      { type: "SAX_FILL_CREDENTIAL", expectedOrigin: origin, password: "x".repeat(513) },
      { type: "SAX_FILL_CREDENTIAL", expectedOrigin: origin, password: "p", username: { u: 1 } },
      { type: "SAX_FILL_CREDENTIAL", expectedOrigin: origin, password: "p", username: "u".repeat(255) },
      { type: "SAX_FILL_CREDENTIAL", expectedOrigin: 5, password: "p" },
    ]) {
      const r = await fromWorker(worker, tabId, bad);
      expect(r.ok, JSON.stringify(bad).slice(0, 80)).toBe(false);
      expect(r.code).toBe("invalid_request");
    }
    await blank(page);
  } finally {
    await context.close();
  }
});

test("content script: only the background service worker can trigger a fill (an extension page calling directly is refused)", async () => {
  const { context, extensionId } = await launchWithExtension();
  try {
    const { popup } = await unlockedVault(context, extensionId);
    const page = await openLoginPage(context, LOGIN);
    const tabId = await popup.evaluate(async (u) => (await browser.tabs.query({})).find((t) => t.url === u).id, LOGIN);
    const r = await popup.evaluate(
      ({ tabId, secret }) => browser.tabs.sendMessage(tabId, { type: "SAX_FILL_CREDENTIAL", expectedOrigin: `http://localhost:${location.port}`, username: "u", password: secret }, { frameId: 0 }),
      { tabId, secret: CRED.secret }
    );
    expect(r.ok).toBe(false);
    expect(r.code).toBe("not_allowed");
    await blank(page);
  } finally {
    await context.close();
  }
});

/* ============ the background re-verifies the tab at the last moment ============ */

test("if the tab navigates to another origin after the checks but before the fill, nothing is filled", async () => {
  const { context, extensionId } = await launchWithExtension();
  try {
    const { popup, profileId } = await unlockedVault(context, extensionId);
    const item = await addViaMessage(popup, profileId, CRED);
    const page = await openLoginPage(context, LOGIN);
    const worker = await getWorker(context);
    const other = `http://127.0.0.1:${PORT}/vault-login-target.html`;

    // Deterministic navigation race: the first browser.tabs.get() (the background's last-moment re-check)
    // first navigates the tab to a different origin, exactly as a real redirect between check and fill would.
    await worker.evaluate((otherUrl) => {
      const original = chrome.tabs.get.bind(chrome.tabs);
      chrome.tabs.get = async (tabId) => {
        chrome.tabs.get = original; // one shot
        await chrome.tabs.update(tabId, { url: otherUrl });
        await new Promise((resolve) => setTimeout(resolve, 2000));
        return original(tabId);
      };
    }, other);

    const r = await send(popup, { type: "SAX_VAULT_FILL", profileId, itemId: item.id });
    expect(r.ok).toBe(false);
    expect(r.code).toBe("tab_changed");
    expect(JSON.stringify(r)).not.toContain(CRED.secret);
    await page.waitForLoadState("load");
    await blank(page);
  } finally {
    await context.close();
  }
});

/* ============ locking, expiry, and unlocking never fill ============ */

test("after a manual lock or a session expiry, a fill is refused and nothing is filled; the password reopens it", async () => {
  const { context, extensionId } = await launchWithExtension();
  try {
    const { popup, profileId } = await unlockedVault(context, extensionId);
    const item = await addViaMessage(popup, profileId, CRED);
    const page = await openLoginPage(context, LOGIN);
    const worker = await getWorker(context);
    await installSessionTimerControl(worker);
    const fill = () => send(popup, { type: "SAX_VAULT_FILL", profileId, itemId: item.id });

    await send(popup, { type: "SAX_VAULT_LOCK", profileId });
    const afterLock = await fill();
    expect(afterLock).toMatchObject({ ok: false, code: "locked" });
    await blank(page);

    expect((await send(popup, { type: "SAX_VAULT_UNLOCK", profileId, masterPassword: TEST_MASTER_PASSWORD })).ok).toBe(true);
    expect(await expireSessions(worker)).toBeGreaterThanOrEqual(1); // "30 minutes pass"
    const afterExpiry = await fill();
    expect(afterExpiry).toMatchObject({ ok: false, code: "locked" });
    await blank(page);

    await send(popup, { type: "SAX_VAULT_UNLOCK", profileId, masterPassword: TEST_MASTER_PASSWORD });
    expect((await fill()).ok).toBe(true);
    await expect(page.locator("#loginPassword")).toHaveValue(CRED.secret);
  } finally {
    await context.close();
  }
});

test("unlocking the vault never fills anything: only an explicit Fill does", async () => {
  const { context, extensionId } = await launchWithExtension();
  try {
    const { popup, profileId } = await unlockedVault(context, extensionId);
    await addViaMessage(popup, profileId, CRED);
    await send(popup, { type: "SAX_VAULT_LOCK", profileId });
    const page = await openLoginPage(context, LOGIN); // a matching login page is already open

    await popup.click('[data-tab="passwords"]');
    await popup.click('[data-tab="vault"]');
    await popup.locator("#vaultLockedView").waitFor({ state: "visible" });
    await unlockViaUi(popup);
    await popup.locator("#vaultUnlockedView").waitFor({ state: "visible" });
    await page.bringToFront();
    await page.waitForTimeout(2500); // plenty of time for any automatic fill to happen
    await blank(page);

    // Listing and matching are read-only too.
    expect((await send(popup, { type: "SAX_VAULT_MATCHES_FOR_ACTIVE_TAB", profileId })).items).toHaveLength(1);
    await blank(page);

    // Explicit action fills.
    await refreshVaultFor(popup, page);
    await page.bringToFront();
    await popup.locator("#vaultMatchesList .vault-fill-btn").first().click();
    await expect(page.locator("#loginPassword")).toHaveValue(CRED.secret);
  } finally {
    await context.close();
  }
});

/* ============ destination rules ============ */

test("HTTP is refused on a real host but allowed on loopback (the documented exception)", async () => {
  const { context, extensionId } = await launchWithExtension();
  try {
    const { popup, profileId } = await unlockedVault(context, extensionId);
    const loop = await addViaMessage(popup, profileId, { site: "127.0.0.1", username: "u@test.example", secret: "LoopbackSecret-1!" });
    const remote = await addViaMessage(popup, profileId, { site: "plain-http.example", username: "u@test.example", secret: "RemoteSecret-1!" });
    await mockPage(context, "http://plain-http.example/**");

    const insecure = await openLoginPage(context, "http://plain-http.example/login.html");
    const blocked = await send(popup, { type: "SAX_VAULT_FILL", profileId, itemId: remote.id });
    expect(blocked).toMatchObject({ ok: false, code: "insecure_page", warning: true });
    await blank(insecure);

    const loopback = await openLoginPage(context, `http://127.0.0.1:${PORT}/vault-login-target.html`);
    const allowed = await send(popup, { type: "SAX_VAULT_FILL", profileId, itemId: loop.id });
    expect(allowed.ok, JSON.stringify(allowed)).toBe(true);
    await expect(loopback.locator("#loginPassword")).toHaveValue("LoopbackSecret-1!");
  } finally {
    await context.close();
  }
});

test("lookalike brand domains are blocked on HTTPS, while the genuine brand domain is not", async () => {
  const { context, extensionId } = await launchWithExtension();
  try {
    const { popup, profileId } = await unlockedVault(context, extensionId);
    const lookalikes = ["paypa1.example", "paypal-secure.example", "g00gle.example", "amaz0n.example", "microsoft-support.example", "faceb00k.example"];
    for (const host of lookalikes) {
      expect(looksLikeTyposquat(host), `test data sanity: ${host}`).toBeTruthy();
      const item = await addViaMessage(popup, profileId, { site: host, username: "u@test.example", secret: `Phish-${host}-1!` });
      await mockPage(context, `https://${host}/**`);
      const page = await openLoginPage(context, `https://${host}/login.html`);
      const r = await send(popup, { type: "SAX_VAULT_FILL", profileId, itemId: item.id });
      expect(r, host).toMatchObject({ ok: false, code: "lookalike_domain", warning: true });
      expect(JSON.stringify(r)).not.toContain("Phish-");
      await blank(page);
    }
    // False-positive control: the real brand's own domain is not blocked.
    expect(looksLikeTyposquat("www.paypal.com")).toBeFalsy();
    const real = await addViaMessage(popup, profileId, { site: "www.paypal.com", username: "u@test.example", secret: "RealBrandSecret-1!" });
    await mockPage(context, "https://www.paypal.com/**");
    const realPage = await openLoginPage(context, "https://www.paypal.com/login.html");
    const ok = await send(popup, { type: "SAX_VAULT_FILL", profileId, itemId: real.id });
    expect(ok.ok, JSON.stringify(ok)).toBe(true);
    await expect(realPage.locator("#loginPassword")).toHaveValue("RealBrandSecret-1!");
  } finally {
    await context.close();
  }
});

test("exact hostname only: parent domains, subdomains, suffix tricks, and trailing-dot hosts are never matched or filled", async () => {
  const { context, extensionId } = await launchWithExtension();
  try {
    const { popup, profileId } = await unlockedVault(context, extensionId);
    const item = await addViaMessage(popup, profileId, { site: "example.test", username: "u@test.example", secret: "ExactOnly-1!" });
    for (const host of ["www.example.test", "login.example.test", "example.test.evil.example", "notexample.test", "example.test."]) {
      await mockPage(context, `https://${host}/**`);
      const page = await openLoginPage(context, `https://${host}/login.html`);
      const matches = await send(popup, { type: "SAX_VAULT_MATCHES_FOR_ACTIVE_TAB", profileId });
      expect(matches.items, host).toEqual([]);
      const r = await send(popup, { type: "SAX_VAULT_FILL", profileId, itemId: item.id });
      expect(r, host).toMatchObject({ ok: false, code: "site_mismatch" });
      await blank(page);
    }
    // Control: the exact host (written in upper case in the URL) matches and fills.
    await mockPage(context, "https://example.test/**");
    const exact = await openLoginPage(context, "https://EXAMPLE.test/login.html");
    expect((await send(popup, { type: "SAX_VAULT_MATCHES_FOR_ACTIVE_TAB", profileId })).items).toHaveLength(1);
    expect((await send(popup, { type: "SAX_VAULT_FILL", profileId, itemId: item.id })).ok).toBe(true);
    await expect(exact.locator("#loginPassword")).toHaveValue("ExactOnly-1!");
  } finally {
    await context.close();
  }
});

/* ============ background message validation ============ */

test("malformed background requests are refused quickly with a generic 'invalid_request', for every message type, with no secret in the reply", async () => {
  const { context, extensionId } = await launchWithExtension();
  try {
    const { popup, profileId } = await unlockedVault(context, extensionId);
    const item = await addViaMessage(popup, profileId, CRED);
    const raced = (p, ms = 4000) => Promise.race([p, new Promise((_, rej) => setTimeout(() => rej(new Error("HUNG")), ms))]);
    const long = (n) => "x".repeat(n);
    const bad = [
      { type: "SAX_VAULT_FILL" }, { type: "SAX_VAULT_FILL", profileId }, { type: "SAX_VAULT_FILL", profileId, itemId: 5 },
      { type: "SAX_VAULT_FILL", profileId, itemId: { $ne: 1 } }, { type: "SAX_VAULT_FILL", profileId: ["a"], itemId: item.id },
      { type: "SAX_VAULT_FILL", profileId, itemId: long(101) },
      { type: "SAX_VAULT_GET_ITEM", profileId, itemId: null }, { type: "SAX_VAULT_DELETE_ITEM", profileId, itemId: [] },
      { type: "SAX_VAULT_UPDATE_ITEM", profileId, itemId: item.id, updates: { createdAt: 1 } },
      { type: "SAX_VAULT_ADD_ITEM", profileId, item: { site: "a.example", secret: "x", id: "forced" } },
      { type: "SAX_VAULT_ADD_ITEM", profileId, item: { site: "a.example", secret: "x", __proto__x: 1, extra: 1 } },
      { type: "SAX_VAULT_LIST", profileId, query: long(201) }, { type: "SAX_VAULT_LIST", profileId: 5 },
      { type: "SAX_VAULT_UNLOCK", profileId, masterPassword: 12345 }, { type: "SAX_VAULT_UNLOCK", profileId: {} },
      { type: "SAX_VAULT_LOCK" }, { type: "SAX_VAULT_STATUS", profileId: "" }, { type: "SAX_VAULT_EXPORT" },
      { type: "SAX_VAULT_MATCHES_FOR_ACTIVE_TAB", profileId: null },
      { type: "SAX_VAULT_IMPORT", profileId, exportData: null }, { type: "SAX_VAULT_IMPORT", profileId, exportData: {}, confirmOverwrite: "yes" },
      { type: "SAX_VAULT_GENERATE_PASSWORD", length: 3 }, { type: "SAX_VAULT_GENERATE_PASSWORD", length: "20" },
      { type: "SAX_VAULT_GENERATE_PASSWORD", length: 20, options: { bogus: true } },
    ];
    for (const message of bad) {
      const r = await raced(send(popup, message));
      expect(r.ok, JSON.stringify(message).slice(0, 90)).toBe(false);
      expect(r.code, JSON.stringify(message).slice(0, 90)).toBe("invalid_request");
      expect(JSON.stringify(r)).not.toContain(CRED.secret);
    }
    const unknown = await raced(send(popup, { type: "SAX_VAULT_DOES_NOT_EXIST", profileId }));
    expect(unknown.ok).toBe(false);
    expect(unknown.error).toMatch(/unknown/i);

    // The vault is unharmed: the credential is intact and still fillable.
    expect((await send(popup, { type: "SAX_VAULT_GET_ITEM", profileId, itemId: item.id })).item.secret).toBe(CRED.secret);
  } finally {
    await context.close();
  }
});

/* ============ secrets never appear where they should not ============ */

test("secret exclusion: no credential, username, note, or master password in any response, console output, DOM, or error message", async () => {
  const { context, extensionId } = await launchWithExtension();
  try {
    const consoleLines = [];
    const capture = (tag) => (m) => consoleLines.push(`[${tag}/${m.type()}] ${m.text()}`);
    context.on("console", capture("any"));
    const worker = await getWorker(context);
    worker.on("console", capture("service-worker"));
    const S = "ExclusionSecret-9902!", U = "dave@test.example", N = "ExclusionNote-4410";

    const popup = await openVaultTab(context, extensionId);
    popup.on("console", capture("popup"));
    await popup.evaluate(() => {
      window.__traffic = [];
      const original = browser.runtime.sendMessage.bind(browser.runtime);
      browser.runtime.sendMessage = async (...args) => {
        const response = await original(...args);
        window.__traffic.push({ type: args[0] && args[0].type, request: JSON.stringify(args[0]), response: JSON.stringify(response) });
        return response;
      };
    });
    const page = await openLoginPage(context, LOGIN);
    page.on("console", capture("page"));
    await popup.bringToFront();

    await unlockViaUi(popup);
    await popup.locator("#vaultUnlockedView").waitFor({ state: "visible" });
    await popup.click("details:has(#vaultNewSite) summary");
    await popup.fill("#vaultNewSite", "localhost");
    await popup.fill("#vaultNewUsername", U);
    await popup.fill("#vaultNewSecret", S);
    await popup.fill("#vaultNewNotes", N);
    await popup.click("#vaultAddBtn");
    await popup.locator("#vaultItemsList .detail-row").first().waitFor();
    await popup.fill("#vaultSearchInput", "local");
    await popup.waitForTimeout(300);

    // Page DOM before any fill: nothing about the credential is there.
    const pageDomBefore = await page.content();
    expect(pageDomBefore).not.toContain(S);
    expect(pageDomBefore).not.toContain(U);

    await refreshVaultFor(popup, page);
    await page.bringToFront();
    await popup.locator("#vaultMatchesList .vault-fill-btn").first().click();
    await expect(page.locator("#loginPassword")).toHaveValue(S);

    // Failure paths: wrong host, then locked.
    const profileId = await popup.evaluate(async () => (await browser.storage.local.get("sax_profiles_state")).sax_profiles_state.defaultProfileId);
    const itemId = await popup.locator("#vaultMatchesList .vault-fill-btn").first().getAttribute("data-id");
    const other = await openLoginPage(context, `http://127.0.0.1:${PORT}/vault-login-target.html`);
    const wrongHost = await send(popup, { type: "SAX_VAULT_FILL", profileId, itemId });
    expect(wrongHost.ok).toBe(false);
    await send(popup, { type: "SAX_VAULT_LOCK", profileId });
    const lockedFill = await send(popup, { type: "SAX_VAULT_FILL", profileId, itemId });
    expect(lockedFill.ok).toBe(false);
    await send(popup, { type: "SAX_VAULT_UNLOCK", profileId, masterPassword: "wrong-password-attempt" });

    // 1) Every response seen by the popup: no secret/note/master password; failure replies carry no username either.
    const traffic = await popup.evaluate(() => window.__traffic);
    expect(traffic.length).toBeGreaterThan(8);
    for (const entry of traffic) {
      for (const secretText of [S, N, TEST_MASTER_PASSWORD, "wrong-password-attempt"]) {
        expect(entry.response, `${entry.type} response`).not.toContain(secretText);
      }
    }
    for (const reply of [wrongHost, lockedFill]) for (const text of [S, U, N, TEST_MASTER_PASSWORD]) expect(JSON.stringify(reply)).not.toContain(text);
    const fillReply = traffic.find((t) => t.type === "SAX_VAULT_FILL");
    expect(Object.keys(JSON.parse(fillReply.response)).every((k) => ["ok", "code", "error", "passwordFilled", "usernameFilled", "usernameSkipped"].includes(k))).toBe(true);
    expect(fillReply.response).not.toContain(U);
    // 2) The master password appears only inside UNLOCK requests; the secret only inside the ADD request.
    for (const entry of traffic) {
      if (entry.type !== "SAX_VAULT_UNLOCK") expect(entry.request, entry.type).not.toContain(TEST_MASTER_PASSWORD);
      if (entry.type !== "SAX_VAULT_ADD_ITEM") expect(entry.request, entry.type).not.toContain(S);
    }
    // 3) Console output from popup, page, and service worker.
    expect(consoleLines.join("\n")).not.toMatch(new RegExp([S, U, N, TEST_MASTER_PASSWORD].map((t) => t.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")).join("|")));
    // 4) DOM: the popup never renders the secret or note; the filled page holds the value only as a property, not in any attribute.
    const popupDom = await popup.content();
    for (const text of [S, N, TEST_MASTER_PASSWORD]) expect(popupDom).not.toContain(text);
    await page.bringToFront();
    const attrs = await page.evaluate(() => [...document.querySelectorAll("*")].flatMap((e) => [...e.attributes].map((a) => a.value)).join("|"));
    expect(attrs).not.toContain(S);
    expect(attrs).not.toContain(U);
    // 5) Persistent storage holds ciphertext only.
    const storage = JSON.stringify(await readAllStorage(popup));
    for (const text of [S, U, N, TEST_MASTER_PASSWORD]) expect(storage).not.toContain(text);
    void other;
  } finally {
    await context.close();
  }
});
