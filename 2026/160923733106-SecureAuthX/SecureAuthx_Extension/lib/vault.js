/**
 * SecureAuthX — vault.js (Phase 3B)
 *
 * CRUD over the DECRYPTED in-memory vault payload, plus encrypt/decrypt
 * (lib/crypto.js) and persistence (lib/storage.js). Never sends anything
 * across a message boundary itself -- background.js owns that discipline.
 * No cloud, backend, account, sync, or network call exists here.
 */

import { deriveVaultKey, generateVaultSalt, encryptVaultPayload, decryptVaultPayload } from "./crypto.js";
import { getVaultRecord, setVaultRecord } from "./storage.js";

export const VAULT_VERSION = 1;
const MAX_SITE_LENGTH = 253;
const MAX_USERNAME_LENGTH = 254;
const MAX_SECRET_LENGTH = 512;
const MAX_NOTES_LENGTH = 2000;
const MAX_ACCOUNT_LABEL_LENGTH = 40;
const MAX_ID_LENGTH = 100;
export const MAX_ITEMS = 500;

function generateItemId() {
  if (typeof crypto !== "undefined" && crypto.randomUUID) return crypto.randomUUID();
  return Array.from(crypto.getRandomValues(new Uint8Array(16))).map((b) => b.toString(16).padStart(2, "0")).join("");
}

function isPlainObject(v) {
  if (v === null || typeof v !== "object" || Array.isArray(v)) return false;
  const proto = Object.getPrototypeOf(v);
  return proto === Object.prototype || proto === null;
}
const isStr = (v, max) => typeof v === "string" && v.length <= max;
const isOptStr = (v, max) => v === undefined || v === null || isStr(v, max);

/** Lowercase + trim only. Matching is ALWAYS exact equality afterward. */
function normalizeSite(site) {
  return (typeof site === "string" ? site : "").trim().toLowerCase();
}

/**
 * Sites are stored as bare HOSTNAMES (what URL.hostname returns). A value
 * with a scheme, port, path, or whitespace could never match any page, so it
 * is rejected up front rather than silently saved as an unusable entry.
 */
const HOSTNAME_RE = /^(?=.{1,253}$)[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)*$/;
export function isValidSiteHostname(site) {
  return site === "[::1]" || HOSTNAME_RE.test(site);
}

/**
 * `strictSite: false` is used ONLY when re-validating items that were
 * already stored/exported (types and lengths are still enforced): earlier
 * builds accepted any site string, and a vault must never become unopenable
 * because an old entry has an unusual site value.
 */
export function validateItemInput(input, { strictSite = true } = {}) {
  if (!isPlainObject(input)) return { ok: false, error: "Invalid credential." };
  const { site, username, secret, accountLabel, notes } = input;
  if (typeof site !== "string") return { ok: false, error: "Site must be text." };
  const trimmedSite = normalizeSite(site);
  if (!trimmedSite) return { ok: false, error: "Site is required." };
  if (trimmedSite.length > MAX_SITE_LENGTH) return { ok: false, error: "Site is too long." };
  if (strictSite && !isValidSiteHostname(trimmedSite)) {
    return { ok: false, error: "Enter just the domain, like example.com (no https://, port, or path)." };
  }
  if (!isOptStr(username, MAX_USERNAME_LENGTH)) return { ok: false, error: "Username must be text up to 254 characters." };
  if (typeof secret !== "string" || !secret) return { ok: false, error: "Password/secret is required." };
  if (secret.length > MAX_SECRET_LENGTH) return { ok: false, error: "Password/secret is too long." };
  if (!isOptStr(accountLabel, MAX_ACCOUNT_LABEL_LENGTH)) return { ok: false, error: "Account label must be text up to 40 characters." };
  if (!isOptStr(notes, MAX_NOTES_LENGTH)) return { ok: false, error: "Notes must be text up to 2000 characters." };
  return { ok: true };
}

export function createEmptyVaultPayload() {
  return { version: VAULT_VERSION, items: [] };
}

/**
 * Validates a whole decrypted vault payload (used after decryption on load
 * and on import, so imported data can never bypass item validation).
 * Returns a SANITIZED copy: only known fields survive, so unexpected keys in
 * a hostile-but-decryptable file never enter the live vault.
 */
export function validateVaultPayload(payload) {
  const bad = { ok: false, error: "Vault data is malformed or from an unsupported version." };
  if (!isPlainObject(payload) || payload.version !== VAULT_VERSION || !Array.isArray(payload.items)) return bad;
  if (payload.items.length > MAX_ITEMS) return { ok: false, error: "Vault has too many items." };
  const seen = new Set();
  const items = [];
  for (const raw of payload.items) {
    if (!isPlainObject(raw)) return bad;
    if (!isStr(raw.id, MAX_ID_LENGTH) || !raw.id || seen.has(raw.id)) return bad;
    seen.add(raw.id);
    if (!validateItemInput(raw, { strictSite: false }).ok) return bad;
    if (!Number.isFinite(raw.createdAt) || !Number.isFinite(raw.updatedAt)) return bad;
    items.push({
      id: raw.id, site: normalizeSite(raw.site), username: raw.username || "", secret: raw.secret,
      accountLabel: raw.accountLabel || "", notes: raw.notes || "", createdAt: raw.createdAt, updatedAt: raw.updatedAt,
    });
  }
  return { ok: true, payload: { version: VAULT_VERSION, items } };
}

/**
 * Loads + decrypts a profile's vault (or returns a fresh empty one with a
 * new salt if none exists yet; nothing is persisted until saveVault()).
 * Throws on wrong master password OR tampered/malformed/wrong-version data.
 */
export async function loadVault(profileId, masterPassword) {
  const record = await getVaultRecord(profileId);
  if (!record) return { payload: createEmptyVaultPayload(), saltHex: generateVaultSalt(), isNew: true };
  const vaultKey = await deriveVaultKey(masterPassword, record.saltHex);
  const decrypted = await decryptVaultPayload(vaultKey, record.ivHex, record.ciphertextHex);
  const checked = validateVaultPayload(decrypted);
  if (!checked.ok) throw new Error("Vault record is malformed or from an unsupported version.");
  return { payload: checked.payload, saltHex: record.saltHex, isNew: false };
}

export async function saveVault(profileId, masterPassword, saltHex, payload) {
  const vaultKey = await deriveVaultKey(masterPassword, saltHex);
  const { ivHex, ciphertextHex } = await encryptVaultPayload(vaultKey, payload);
  await setVaultRecord(profileId, { version: VAULT_VERSION, saltHex, ivHex, ciphertextHex });
  return { ivHex, ciphertextHex };
}

export function addItem(payload, input) {
  if (payload.items.length >= MAX_ITEMS) return { ok: false, error: `Vault supports a maximum of ${MAX_ITEMS} items.` };
  const validation = validateItemInput(input);
  if (!validation.ok) return validation;
  const { site, username, secret, accountLabel, notes } = input;
  const now = Date.now();
  const item = {
    id: generateItemId(), site: normalizeSite(site), username: username || "", secret,
    accountLabel: accountLabel || "", notes: notes || "", createdAt: now, updatedAt: now,
  };
  payload.items.push(item);
  return { ok: true, item };
}

export function updateItem(payload, id, updates = {}) {
  const item = payload.items.find((i) => i.id === id);
  if (!item) return { ok: false, error: "Credential not found." };
  if (!isPlainObject(updates)) return { ok: false, error: "Invalid update." };
  const merged = {
    site: updates.site !== undefined ? updates.site : item.site,
    username: updates.username !== undefined ? updates.username : item.username,
    secret: updates.secret !== undefined ? updates.secret : item.secret,
    accountLabel: updates.accountLabel !== undefined ? updates.accountLabel : item.accountLabel,
    notes: updates.notes !== undefined ? updates.notes : item.notes,
  };
  const validation = validateItemInput(merged);
  if (!validation.ok) return validation;
  item.site = normalizeSite(merged.site);
  item.username = merged.username || "";
  item.secret = merged.secret;
  item.accountLabel = merged.accountLabel || "";
  item.notes = merged.notes || "";
  item.updatedAt = Date.now();
  return { ok: true, item };
}

export function deleteItem(payload, id) {
  const index = payload.items.findIndex((i) => i.id === id);
  if (index === -1) return { ok: false, error: "Credential not found." };
  payload.items.splice(index, 1);
  return { ok: true };
}

/** EXACT hostname match only -- no fuzzy or subdomain equivalence. NOTE: hostname only; the port is not part of the match. */
export function findItemsForSite(payload, site) {
  const normalized = normalizeSite(site);
  return payload.items.filter((i) => i.site === normalized);
}

export function searchItems(payload, query) {
  const q = (typeof query === "string" ? query : "").trim().toLowerCase();
  if (!q) return payload.items;
  return payload.items.filter(
    (i) => i.site.includes(q) || (i.username || "").toLowerCase().includes(q) || (i.accountLabel || "").toLowerCase().includes(q)
  );
}

/** Strips secret AND notes -- the only shape any list/search/match result may carry across a boundary. */
export function toListSummary(item) {
  const { secret, notes, ...rest } = item;
  return rest;
}

/* ==================================================================== *
 * Phase 3C: request validation for every vault message the background
 * accepts. Pure and side-effect free so it can be unit tested. Anything
 * that does not match its schema is refused BEFORE a handler runs:
 * wrong types, unknown keys, oversized strings, unknown message types.
 * ==================================================================== */

const ITEM_FIELDS = ["site", "username", "secret", "accountLabel", "notes"];
const PASSWORD_OPTION_KEYS = ["useUpper", "useLower", "useDigits", "useSymbols"];
const hasOnlyKeys = (obj, allowed) => Object.keys(obj).every((k) => allowed.includes(k));
const isId = (v) => typeof v === "string" && v.length > 0 && v.length <= MAX_ID_LENGTH;

export function validateVaultRequest(message) {
  const bad = (error = "Invalid request.") => ({ ok: false, error });
  if (!isPlainObject(message) || typeof message.type !== "string") return bad();
  const profileOk = isId(message.profileId);
  const optionalPassword = message.masterPassword === undefined || isStr(message.masterPassword, 1024);

  switch (message.type) {
    case "SAX_VAULT_UNLOCK":
      return profileOk && optionalPassword ? { ok: true } : bad();
    case "SAX_VAULT_LOCK":
    case "SAX_VAULT_STATUS":
    case "SAX_VAULT_MATCHES_FOR_ACTIVE_TAB":
    case "SAX_VAULT_EXPORT":
      return profileOk ? { ok: true } : bad();
    case "SAX_VAULT_LIST":
      return profileOk && (message.query === undefined || isStr(message.query, 200)) ? { ok: true } : bad();
    case "SAX_VAULT_GET_ITEM":
    case "SAX_VAULT_DELETE_ITEM":
    case "SAX_VAULT_FILL":
      return profileOk && isId(message.itemId) ? { ok: true } : bad();
    case "SAX_VAULT_ADD_ITEM":
      return profileOk && isPlainObject(message.item) && hasOnlyKeys(message.item, ITEM_FIELDS) ? { ok: true } : bad();
    case "SAX_VAULT_UPDATE_ITEM":
      return profileOk && isId(message.itemId) && isPlainObject(message.updates) && hasOnlyKeys(message.updates, ITEM_FIELDS)
        ? { ok: true } : bad();
    case "SAX_VAULT_GENERATE_PASSWORD": {
      const lengthOk = message.length === undefined || (Number.isInteger(message.length) && message.length >= 8 && message.length <= 128);
      const o = message.options;
      const optionsOk = o === undefined || (isPlainObject(o) && hasOnlyKeys(o, PASSWORD_OPTION_KEYS) && Object.values(o).every((v) => typeof v === "boolean"));
      return lengthOk && optionsOk ? { ok: true } : bad();
    }
    case "SAX_VAULT_IMPORT":
      return profileOk && isPlainObject(message.exportData) && optionalPassword &&
        (message.confirmOverwrite === undefined || typeof message.confirmOverwrite === "boolean") ? { ok: true } : bad();
    default:
      return bad("Unknown request.");
  }
}

const EXPORT_FORMAT = "secureauthx-vault-export";

/** The export IS the stored ciphertext record -- nothing is decrypted to make it. */
export function buildExportPayload(vaultRecord) {
  return {
    format: EXPORT_FORMAT, version: vaultRecord.version,
    saltHex: vaultRecord.saltHex, ivHex: vaultRecord.ivHex, ciphertextHex: vaultRecord.ciphertextHex,
  };
}

export function validateImportPayload(data) {
  if (!data || typeof data !== "object") return { ok: false, error: "Not a valid export file." };
  if (data.format !== EXPORT_FORMAT) return { ok: false, error: "Not a SecureAuthX vault export file." };
  if (data.version !== VAULT_VERSION) return { ok: false, error: "Unsupported vault export version." };
  if (typeof data.saltHex !== "string" || typeof data.ivHex !== "string" || typeof data.ciphertextHex !== "string") {
    return { ok: false, error: "Export file is missing required fields." };
  }
  // Strict shape checks so malformed/hostile files are rejected before any crypto runs.
  const HEX = /^[0-9a-f]+$/i;
  if (!HEX.test(data.saltHex) || data.saltHex.length !== 32) return { ok: false, error: "Export file has an invalid salt." };
  if (!HEX.test(data.ivHex) || data.ivHex.length !== 24) return { ok: false, error: "Export file has an invalid IV." };
  if (!HEX.test(data.ciphertextHex) || data.ciphertextHex.length % 2 !== 0 || data.ciphertextHex.length < 32 || data.ciphertextHex.length > 4000000) {
    return { ok: false, error: "Export file has invalid ciphertext." };
  }
  return { ok: true };
}

/**
 * Truly-random generator for vault credentials -- deliberately separate
 * from crypto.js's DETERMINISTIC deriveSitePassword(). Uses
 * crypto.getRandomValues() only, never Math.random().
 */
const RANDOM_PASSWORD_CHARSETS = {
  lower: "abcdefghijklmnopqrstuvwxyz", upper: "ABCDEFGHIJKLMNOPQRSTUVWXYZ",
  digits: "0123456789", symbols: "!@#$%^&*()-_=+[]{}",
};

export function generateRandomPassword(length = 20, options = {}) {
  const { useUpper = true, useLower = true, useDigits = true, useSymbols = true } = options;
  const sets = [];
  if (useLower) sets.push(RANDOM_PASSWORD_CHARSETS.lower);
  if (useUpper) sets.push(RANDOM_PASSWORD_CHARSETS.upper);
  if (useDigits) sets.push(RANDOM_PASSWORD_CHARSETS.digits);
  if (useSymbols) sets.push(RANDOM_PASSWORD_CHARSETS.symbols);
  if (sets.length === 0) throw new Error("At least one character set must be enabled");
  if (length < sets.length) throw new Error("length must be at least the number of enabled character sets");

  const fullSet = sets.join("");
  const chars = [];
  const guarantee = crypto.getRandomValues(new Uint8Array(sets.length));
  sets.forEach((set, i) => chars.push(set[guarantee[i] % set.length]));
  const fill = crypto.getRandomValues(new Uint8Array(Math.max(0, length - chars.length)));
  for (let i = 0; i < fill.length; i++) chars.push(fullSet[fill[i] % fullSet.length]);
  const shuffle = crypto.getRandomValues(new Uint8Array(chars.length));
  for (let i = chars.length - 1; i > 0; i--) {
    const j = shuffle[i] % (i + 1);
    [chars[i], chars[j]] = [chars[j], chars[i]];
  }
  return chars.slice(0, length).join("");
}
