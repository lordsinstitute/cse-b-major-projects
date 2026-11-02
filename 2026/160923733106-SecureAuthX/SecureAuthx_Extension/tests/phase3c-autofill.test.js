/**
 * SecureAuthX — Phase 3C unit tests: background request validation and structural
 * guarantees of the autofill path. Run with: node --test tests/phase3c-autofill.test.js
 */
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { validateVaultRequest } from "../lib/vault.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const read = (rel) => fs.readFileSync(path.join(__dirname, rel), "utf8");
const P = "profile-1";

test("validateVaultRequest accepts every well-formed message the popup sends", () => {
  for (const m of [
    { type: "SAX_VAULT_UNLOCK", profileId: P, masterPassword: "pw" },
    { type: "SAX_VAULT_UNLOCK", profileId: P },
    { type: "SAX_VAULT_LOCK", profileId: P },
    { type: "SAX_VAULT_STATUS", profileId: P },
    { type: "SAX_VAULT_LIST", profileId: P, query: "" },
    { type: "SAX_VAULT_LIST", profileId: P },
    { type: "SAX_VAULT_GET_ITEM", profileId: P, itemId: "i1" },
    { type: "SAX_VAULT_DELETE_ITEM", profileId: P, itemId: "i1" },
    { type: "SAX_VAULT_FILL", profileId: P, itemId: "i1" },
    { type: "SAX_VAULT_MATCHES_FOR_ACTIVE_TAB", profileId: P },
    { type: "SAX_VAULT_EXPORT", profileId: P },
    { type: "SAX_VAULT_ADD_ITEM", profileId: P, item: { site: "a.com", secret: "x", username: "u", accountLabel: "L", notes: "n" } },
    { type: "SAX_VAULT_UPDATE_ITEM", profileId: P, itemId: "i1", updates: { secret: "y" } },
    { type: "SAX_VAULT_GENERATE_PASSWORD", length: 20 },
    { type: "SAX_VAULT_GENERATE_PASSWORD", length: 12, options: { useSymbols: false } },
    { type: "SAX_VAULT_IMPORT", profileId: P, exportData: { format: "x" }, masterPassword: "pw", confirmOverwrite: true },
  ]) {
    assert.equal(validateVaultRequest(m).ok, true, JSON.stringify(m));
  }
});

test("validateVaultRequest rejects malformed payloads, wrong types, unknown keys, and oversized values", () => {
  const long = (n) => "x".repeat(n);
  for (const m of [
    null, undefined, "str", 5, [], {}, { type: 5 }, { type: null },
    { type: "SAX_VAULT_NOPE", profileId: P }, { type: "SAX_VAULT_", profileId: P },
    // profile id
    { type: "SAX_VAULT_LOCK" }, { type: "SAX_VAULT_LOCK", profileId: 5 }, { type: "SAX_VAULT_LOCK", profileId: {} },
    { type: "SAX_VAULT_LOCK", profileId: "" }, { type: "SAX_VAULT_LOCK", profileId: long(101) },
    // item id
    { type: "SAX_VAULT_FILL", profileId: P }, { type: "SAX_VAULT_FILL", profileId: P, itemId: 5 },
    { type: "SAX_VAULT_FILL", profileId: P, itemId: ["a"] }, { type: "SAX_VAULT_GET_ITEM", profileId: P, itemId: "" },
    { type: "SAX_VAULT_DELETE_ITEM", profileId: P, itemId: long(101) },
    // query / password
    { type: "SAX_VAULT_LIST", profileId: P, query: {} }, { type: "SAX_VAULT_LIST", profileId: P, query: long(201) },
    { type: "SAX_VAULT_UNLOCK", profileId: P, masterPassword: 5 }, { type: "SAX_VAULT_UNLOCK", profileId: P, masterPassword: long(1025) },
    // add / update
    { type: "SAX_VAULT_ADD_ITEM", profileId: P }, { type: "SAX_VAULT_ADD_ITEM", profileId: P, item: null },
    { type: "SAX_VAULT_ADD_ITEM", profileId: P, item: "x" }, { type: "SAX_VAULT_ADD_ITEM", profileId: P, item: [] },
    { type: "SAX_VAULT_ADD_ITEM", profileId: P, item: { site: "a.com", secret: "x", extra: 1 } },
    { type: "SAX_VAULT_ADD_ITEM", profileId: P, item: { site: "a.com", secret: "x", id: "forced-id" } },
    { type: "SAX_VAULT_UPDATE_ITEM", profileId: P, itemId: "i1", updates: [] },
    { type: "SAX_VAULT_UPDATE_ITEM", profileId: P, itemId: "i1", updates: "x" },
    { type: "SAX_VAULT_UPDATE_ITEM", profileId: P, itemId: "i1", updates: { createdAt: 1 } },
    { type: "SAX_VAULT_UPDATE_ITEM", profileId: P, itemId: 5, updates: {} },
    // generator
    { type: "SAX_VAULT_GENERATE_PASSWORD", length: "20" }, { type: "SAX_VAULT_GENERATE_PASSWORD", length: 7 },
    { type: "SAX_VAULT_GENERATE_PASSWORD", length: 129 }, { type: "SAX_VAULT_GENERATE_PASSWORD", length: 12.5 },
    { type: "SAX_VAULT_GENERATE_PASSWORD", length: 12, options: [] }, { type: "SAX_VAULT_GENERATE_PASSWORD", length: 12, options: { useSymbols: "yes" } },
    { type: "SAX_VAULT_GENERATE_PASSWORD", length: 12, options: { bogus: true } },
    // import
    { type: "SAX_VAULT_IMPORT", profileId: P }, { type: "SAX_VAULT_IMPORT", profileId: P, exportData: null },
    { type: "SAX_VAULT_IMPORT", profileId: P, exportData: [] }, { type: "SAX_VAULT_IMPORT", profileId: P, exportData: {}, masterPassword: 5 },
    { type: "SAX_VAULT_IMPORT", profileId: P, exportData: {}, confirmOverwrite: "true" },
  ]) {
    assert.equal(validateVaultRequest(m).ok, false, JSON.stringify(m));
  }
});

test("validateVaultRequest errors are generic and never echo request contents", () => {
  const r = validateVaultRequest({ type: "SAX_VAULT_ADD_ITEM", profileId: P, item: { site: "a.com", secret: "SuperSecret-123", sneaky: 1 } });
  assert.equal(r.ok, false);
  assert.ok(!JSON.stringify(r).includes("SuperSecret-123"));
});

test("a prototype-pollution style key is rejected, not merged", () => {
  const evil = JSON.parse('{"type":"SAX_VAULT_ADD_ITEM","profileId":"p","item":{"site":"a.com","secret":"x","__proto__":{"polluted":true}}}');
  assert.equal(validateVaultRequest(evil).ok, false);
  assert.equal({}.polluted, undefined);
});

test("every SAX_VAULT_* handler in background.js has a schema case (no handler can run unvalidated)", () => {
  const background = read("../background/background.js");
  const vault = read("../lib/vault.js");
  const handled = [...new Set([...background.matchAll(/message\.type === "(SAX_VAULT_[A-Z_]+)"/g)].map((m) => m[1]))];
  const schemaCases = new Set([...vault.matchAll(/case "(SAX_VAULT_[A-Z_]+)"/g)].map((m) => m[1]));
  assert.ok(handled.length >= 12, `expected the vault handlers, found ${handled.length}`);
  for (const type of handled) assert.ok(schemaCases.has(type), `${type} has a handler but no schema case`);
  for (const type of schemaCases) assert.ok(handled.includes(type), `${type} has a schema case but no handler`);
});

test("background.js runs the schema check and the extension-page sender check before any vault handler", () => {
  const b = read("../background/background.js");
  const gate = b.indexOf("!isTrustedExtensionPage(sender)");
  const schema = b.indexOf("validateVaultRequest(message)");
  const firstHandler = b.indexOf('message.type === "SAX_VAULT_UNLOCK"');
  assert.ok(gate > -1 && schema > gate && firstHandler > schema, "gate, then schema, then handlers");
  assert.match(b, /sender\.id === browser\.runtime\.id/);
});

test("the fill path sends ONE message to the top frame only, with the verified origin, and re-checks the tab first", () => {
  const b = read("../background/background.js");
  const fill = b.slice(b.indexOf('message.type === "SAX_VAULT_FILL"'), b.indexOf('message.type === "SAX_VAULT_GENERATE_PASSWORD"'));
  assert.match(fill, /"SAX_FILL_CREDENTIAL"/);
  assert.match(fill, /\{ frameId: 0 \}/);
  assert.match(fill, /expectedOrigin: origin/);
  assert.ok(fill.indexOf("browser.tabs.get(tab.id)") > -1 && fill.indexOf("browser.tabs.get(tab.id)") < fill.indexOf("browser.tabs.sendMessage"), "tab re-verified before sending");
  assert.equal((fill.match(/tabs\.sendMessage/g) || []).length, 1, "exactly one message carries the credential");
  assert.match(fill, /sanitizeFillResult\(/);
  assert.ok(!/SAX_FILL_USERNAME|SAX_FILL_PASSWORD/.test(fill), "the vault fill never uses the older two-message flow");
});

test("the content script only accepts the fill from the extension itself and re-checks the origin; nothing credential-shaped is returned", () => {
  const c = read("../content/content.js");
  const start = c.indexOf("function fillVaultCredential");
  assert.ok(start > -1, "fillVaultCredential exists");
  const fn = c.slice(start, c.indexOf("browser.runtime.onMessage.addListener", start));
  assert.ok(fn.length > 200, "extracted the whole function body");
  assert.match(fn, /sender\.id !== browser\.runtime\.id/);
  assert.match(fn, /sender\.tab/);
  assert.match(fn, /sender\.url !== browser\.runtime\.getURL\("background\/background\.js"\)/);
  assert.match(fn, /expectedOrigin !== window\.location\.origin/);
  assert.ok(!/return[^;]*\bpassword\b[^;]*;/.test(fn.replace(/refuse\([^)]*\)/g, "")), "no return statement carries the password");
  assert.ok(!c.includes("SAX_FILL_USERNAME"), "the old username-only message no longer exists");
});

test("the fill-result whitelist cannot carry arbitrary data back to the popup", () => {
  const b = read("../background/background.js");
  const fn = b.slice(b.indexOf("function sanitizeFillResult"), b.indexOf("const LOOPBACK_HOSTS"));
  for (const key of ["code", "error", "passwordFilled", "usernameFilled", "usernameSkipped"]) assert.ok(fn.includes(key), key);
  assert.ok(!/\.\.\.result|Object\.assign/.test(fn), "result is copied field by field, never spread");
});

test("no console logging of any kind in the vault/autofill production code", () => {
  for (const f of ["../lib/vault.js", "../background/background.js", "../content/content.js"]) {
    const code = read(f).split("\n").filter((l) => !l.trim().startsWith("*") && !l.trim().startsWith("//") && !l.trim().startsWith("/*")).join("\n");
    assert.ok(!/console\.(log|debug|info|warn|error|trace)/.test(code), f);
  }
});
