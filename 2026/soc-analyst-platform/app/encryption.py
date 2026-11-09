"""
Application-level encryption for sensitive fields.

Uses Fernet (symmetric AES-128-CBC + HMAC authentication) from the
`cryptography` library. Symmetric = the same key encrypts and decrypts,
which is what we want: unlike passwords (which are hashed one-way and
never recovered), API keys have to be readable again so we can actually
call Groq, VirusTotal, etc.

Fernet also authenticates the ciphertext, so tampering is detected rather
than silently producing garbage on decrypt.

IMPORTANT — honest limitation:
    The master key itself lives in .env in plaintext. This does NOT make
    data magically safe; it shifts the problem from "protect the whole
    database" to "protect one key." That's still a real win (leaked DB
    dumps and SQL-injection payloads become useless without the key), but
    don't overstate it in the report.
"""

from cryptography.fernet import Fernet, InvalidToken

from app.config import settings


class EncryptionError(Exception):
    """Raised when a value can't be decrypted (wrong key, tampered, or corrupt)."""


def _get_cipher() -> Fernet:
    if not settings.encryption_key:
        raise RuntimeError(
            "ENCRYPTION_KEY is not set. Generate one with:\n"
            "  python -c \"from cryptography.fernet import Fernet; "
            "print(Fernet.generate_key().decode())\""
        )
    return Fernet(settings.encryption_key.encode())


def encrypt_value(plaintext: str) -> str:
    """Encrypt a string for storage. Returns a URL-safe base64 token."""
    if plaintext is None:
        return None
    cipher = _get_cipher()
    return cipher.encrypt(plaintext.encode()).decode()


def decrypt_value(ciphertext: str) -> str:
    """Decrypt a stored value back to its original string."""
    if ciphertext is None:
        return None
    cipher = _get_cipher()
    try:
        return cipher.decrypt(ciphertext.encode()).decode()
    except InvalidToken:
        # Wrong key, corrupted data, or someone tampered with the stored value.
        raise EncryptionError(
            "Could not decrypt value — wrong ENCRYPTION_KEY or the data was altered."
        )


def mask_secret(plaintext: str, visible_chars: int = 4) -> str:
    """
    Produce a safe display version of a secret, e.g. 'gsk_...NTZzl'.

    Use this anywhere a secret might end up in an API response, a log line,
    or the dashboard — analysts need to recognise which key is configured
    without the full value leaking into places it shouldn't be.
    """
    if not plaintext:
        return ""
    if len(plaintext) <= visible_chars * 2:
        return "*" * len(plaintext)
    return f"{plaintext[:visible_chars]}...{plaintext[-visible_chars:]}"