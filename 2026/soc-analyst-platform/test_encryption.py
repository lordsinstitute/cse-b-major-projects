"""
Test for encryption-at-rest on sensitive fields.

Unlike the other test scripts, this one does NOT need the server running —
it talks to the database layer directly, because that's what's being tested.

Usage:
    python test_encryption.py

The important check is #3: it opens the raw SQLite file and confirms the
plaintext secret genuinely isn't in there. A round-trip test alone would
pass even if encryption did nothing, so that check is the one that
actually proves something.
"""

import os
import sqlite3
import sys

from app.database import Base, engine, SessionLocal
from app import models, models_integration  # noqa: F401 — registers tables
from app.models_integration import Integration
from app.encryption import encrypt_value, decrypt_value, mask_secret, EncryptionError

DB_PATH = "dev.db"
FAKE_KEY = "gsk_" + "x" * 40 + "SECRET"


def check(label: str, condition: bool):
    status = "PASS" if condition else "FAIL"
    print(f"[{status}] {label}")
    if not condition:
        sys.exit(1)


def main():
    Base.metadata.create_all(bind=engine)

    # Clean up any leftover row from a previous run so the test is repeatable
    db = SessionLocal()
    db.query(Integration).filter(Integration.name == "encryption-test").delete()
    db.commit()
    db.close()

    # 1. Write a record containing a sensitive value
    db = SessionLocal()
    integ = Integration(name="encryption-test", provider="virustotal", api_key=FAKE_KEY)
    db.add(integ)
    db.commit()
    db.refresh(integ)
    integ_id = integ.id
    db.close()
    print(f"Created test integration (id={integ_id})\n")

    # 2. Read it back through the ORM — should be transparently decrypted
    db = SessionLocal()
    loaded = db.query(Integration).filter(Integration.name == "encryption-test").first()
    check("ORM read returns the original plaintext", loaded.api_key == FAKE_KEY)
    db.close()

    # 3. THE REAL TEST — inspect the raw database, bypassing SQLAlchemy entirely
    if not os.path.exists(DB_PATH):
        print(f"\nSkipping raw-file checks: {DB_PATH} not found.")
        print("(You're probably using Postgres — inspect the column manually instead.)")
    else:
        conn = sqlite3.connect(DB_PATH)
        row = conn.execute(
            "SELECT name, api_key FROM integrations WHERE name = ?", ("encryption-test",)
        ).fetchone()
        conn.close()

        raw_stored = str(row[1])
        print(f"\nRaw value stored on disk:\n  {raw_stored[:80]}...\n")

        check("Raw DB column does NOT contain the plaintext", FAKE_KEY not in raw_stored)
        check("Raw DB column looks like a Fernet token", raw_stored.startswith("gAAAAA"))
        check("Non-sensitive column is still readable plaintext", row[0] == "encryption-test")

        # 4. Grep the whole file, in case it leaked anywhere else
        with open(DB_PATH, "rb") as f:
            raw_bytes = f.read()
        check("Plaintext secret appears NOWHERE in the database file", FAKE_KEY.encode() not in raw_bytes)

    # 5. Masking helper for safe display
    masked = mask_secret(FAKE_KEY)
    check("Masked value hides the middle of the secret", FAKE_KEY not in masked and "..." in masked)
    print(f"   -> masked for display: {masked}")

    # 6. Tampered ciphertext is detected rather than silently mis-decrypting
    tampered = encrypt_value("hello")[:-6] + "AAAAAA"
    try:
        decrypt_value(tampered)
        check("Tampered ciphertext is rejected", False)
    except EncryptionError:
        check("Tampered ciphertext is rejected", True)

    # 7. Identical plaintext produces different ciphertext (no pattern leakage)
    a = encrypt_value("identical-value")
    b = encrypt_value("identical-value")
    check("Same input encrypts to different output each time", a != b)
    check("...but both still decrypt correctly", decrypt_value(a) == decrypt_value(b) == "identical-value")

    print("\nAll checks passed — encryption at rest is working.")
    print("Note: the master key itself lives in .env. This protects against")
    print("leaked DB dumps and SQL injection, not against someone who has .env.")


if __name__ == "__main__":
    main()