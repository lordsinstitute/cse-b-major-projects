import { test, expect } from "@playwright/test";
import { launchWithExtension } from "./helpers/launch-extension.js";
import { serveFixtures } from "./helpers/serve-fixtures.js";
import { send, unlockedVault, addViaMessage, openLoginPage, refreshVaultFor } from "./helpers/vault.js";

/**
 * Phase 3C — field selection and frame safety for vault autofill (real Chrome).
 * Every fixture is local; nothing is ever submitted anywhere.
 */

const PORT = 8226;
const CROSS_PORT = 8227;
let server;
let crossServer;
test.beforeAll(() => { server = serveFixtures(PORT); crossServer = serveFixtures(CROSS_PORT); });
test.afterAll(() => { server.close(); crossServer.close(); });

const url = (name) => `http://localhost:${PORT}/${name}`;
const CRED = { site: "localhost", username: "alice@test.example", secret: "FieldSelectSecret-1!" };

/** Opens a fixture with an unlocked vault holding one localhost credential; returns everything the test needs. */
async function setup(fixture, credential = CRED) {
  const { context, extensionId } = await launchWithExtension();
  const { popup, profileId } = await unlockedVault(context, extensionId);
  const item = await addViaMessage(popup, profileId, credential);
  const page = await openLoginPage(context, url(fixture));
  const fill = () => send(popup, { type: "SAX_VAULT_FILL", profileId, itemId: item.id });
  return { context, popup, profileId, item, page, fill, extensionId };
}
const empty = async (page, ...ids) => { for (const id of ids) await expect(page.locator(id), id).toHaveValue(""); };

test("hidden, off-page, transparent, zero-size and type=hidden decoys are never filled; the visible fields are", async () => {
  const { context, page, fill } = await setup("vault-fields-hidden.html");
  try {
    const r = await fill();
    expect(r.ok, JSON.stringify(r)).toBe(true);
    expect(r.usernameFilled).toBe(true);
    await expect(page.locator("#realUser")).toHaveValue(CRED.username);
    await expect(page.locator("#realPassword")).toHaveValue(CRED.secret);
    await empty(page, "#decoyDisplayNone", "#decoyOffscreen", "#decoyOpacity", "#decoyVisibility", "#decoyHiddenType", "#decoyTiny", "#decoyInHiddenDiv", "#decoyHiddenPassword");
  } finally {
    await context.close();
  }
});

test("disabled and read-only username fields are skipped; the password is still filled and the outcome says so", async () => {
  const { context, page, fill } = await setup("vault-fields-disabled.html");
  try {
    const r = await fill();
    expect(r.ok).toBe(true);
    expect(r.usernameFilled).toBe(false);
    expect(r.usernameSkipped).toBe("none_found");
    await expect(page.locator("#realPassword")).toHaveValue(CRED.secret);
    await empty(page, "#disabledUser", "#readonlyUser");
  } finally {
    await context.close();
  }
});

test("when every password field is disabled or read-only, nothing at all is filled", async () => {
  const { context, page, fill } = await setup("vault-fields-disabled-password.html");
  try {
    const r = await fill();
    expect(r.ok).toBe(false);
    expect(r.code).toBe("no_password_field");
    await empty(page, "#user", "#disabledPassword", "#readonlyPassword");
  } finally {
    await context.close();
  }
});

test("several password fields with no clear signal: nothing is filled until the user clicks into one", async () => {
  const { context, page, fill } = await setup("vault-fields-ambiguous.html");
  try {
    const refused = await fill();
    expect(refused.ok).toBe(false);
    expect(refused.code).toBe("ambiguous_password_fields");
    expect(refused.error).toMatch(/click into/i);
    await empty(page, "#user", "#pw1", "#pw2", "#pw3");

    await page.click("#pw2"); // the user's explicit selection
    const filled = await fill();
    expect(filled.ok, JSON.stringify(filled)).toBe(true);
    await expect(page.locator("#pw2")).toHaveValue(CRED.secret);
    await expect(page.locator("#user")).toHaveValue(CRED.username);
    await empty(page, "#pw1", "#pw3");
  } finally {
    await context.close();
  }
});

test("autocomplete hints: current-password is chosen over new-password/confirm fields without guessing", async () => {
  const { context, page, fill } = await setup("vault-fields-autocomplete.html");
  try {
    const r = await fill();
    expect(r.ok, JSON.stringify(r)).toBe(true);
    await expect(page.locator("#pwCurrent")).toHaveValue(CRED.secret);
    await expect(page.locator("#user")).toHaveValue(CRED.username);
    await empty(page, "#pwNew", "#pwConfirm");
  } finally {
    await context.close();
  }
});

test("a sign-up form whose only password field is a NEW password is not filled automatically", async () => {
  const { context, page, fill } = await setup("vault-fields-signup.html");
  try {
    const refused = await fill();
    expect(refused.ok).toBe(false);
    expect(refused.code).toBe("ambiguous_password_fields");
    await empty(page, "#email", "#pwNew");
    await page.click("#pwNew"); // explicit user choice
    expect((await fill()).ok).toBe(true);
    await expect(page.locator("#pwNew")).toHaveValue(CRED.secret);
  } finally {
    await context.close();
  }
});

test("unrelated fields (search, newsletter, coupon, captcha, one-time code) are never filled", async () => {
  const { context, page, fill } = await setup("vault-fields-unrelated.html");
  try {
    const r = await fill();
    expect(r.ok, JSON.stringify(r)).toBe(true);
    await expect(page.locator("#realUser")).toHaveValue(CRED.username);
    await expect(page.locator("#realPassword")).toHaveValue(CRED.secret);
    await empty(page, "#searchBox", "#newsletterEmail", "#couponBox", "#captchaBox", "#searchUsersBox", "#otpAfterPassword");
  } finally {
    await context.close();
  }
});

test("an ambiguous username is left empty (never guessed); the password is filled into the one identified field, and the popup says so", async () => {
  const { context, popup, profileId, item, page } = await setup("vault-fields-two-usernames.html");
  try {
    await refreshVaultFor(popup, page);
    await page.bringToFront();
    await popup.locator("#vaultMatchesList .vault-fill-btn").first().click();
    await expect(popup.locator("#vaultActionMessage")).toContainText(/Filled the password.*username was not filled.*could not be identified safely/i);
    await expect(page.locator("#pw")).toHaveValue(CRED.secret);
    await empty(page, "#f1", "#f2");
    // The popup text is status only.
    expect(await popup.locator("#vaultActionMessage").textContent()).not.toContain(CRED.secret);
    expect(await popup.locator("#vaultActionMessage").textContent()).not.toContain(CRED.username);
    void profileId; void item;
  } finally {
    await context.close();
  }
});

test("a password-only form is filled, and a missing username is reported, not invented", async () => {
  const { context, page, fill } = await setup("vault-fields-password-only.html");
  try {
    const r = await fill();
    expect(r.ok).toBe(true);
    expect(r).toMatchObject({ passwordFilled: true, usernameFilled: false, usernameSkipped: "none_found" });
    await expect(page.locator("#pw")).toHaveValue(CRED.secret);
  } finally {
    await context.close();
  }
});

test("a credential with no username fills only the password and reports no skipped username", async () => {
  const { context, page, fill } = await setup("vault-fields-unrelated.html", { site: "localhost", secret: "NoUsernameSecret-1!" });
  try {
    const r = await fill();
    expect(r.ok).toBe(true);
    expect(r.usernameFilled).toBe(false);
    expect(r.usernameSkipped).toBeUndefined();
    await expect(page.locator("#realPassword")).toHaveValue("NoUsernameSecret-1!");
    await empty(page, "#realUser");
  } finally {
    await context.close();
  }
});

test("frame safety: only the top-level form is filled; same-origin AND cross-origin (same hostname, other port) iframes are untouched", async () => {
  const { context, extensionId } = await launchWithExtension();
  try {
    const { popup, profileId } = await unlockedVault(context, extensionId);
    const item = await addViaMessage(popup, profileId, CRED);
    const crossSrc = `http://localhost:${CROSS_PORT}/vault-login-target.html`;
    const page = await openLoginPage(context, `${url("vault-top-and-iframe.html")}?crossSrc=${encodeURIComponent(crossSrc)}`);
    const same = page.frameLocator("#sameOrigin");
    const cross = page.frameLocator("#crossOrigin");
    await expect(same.locator("#loginPassword")).toBeVisible();
    await expect(cross.locator("#loginPassword")).toBeVisible();

    const r = await send(popup, { type: "SAX_VAULT_FILL", profileId, itemId: item.id });
    expect(r.ok, JSON.stringify(r)).toBe(true);
    await expect(page.locator("#topUser")).toHaveValue(CRED.username);
    await expect(page.locator("#topPassword")).toHaveValue(CRED.secret);
    await page.waitForTimeout(500);
    for (const frame of [same, cross]) {
      await expect(frame.locator("#loginEmail")).toHaveValue("");
      await expect(frame.locator("#loginPassword")).toHaveValue("");
    }
  } finally {
    await context.close();
  }
});
