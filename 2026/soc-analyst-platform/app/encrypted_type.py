"""
A SQLAlchemy column type that encrypts on write and decrypts on read,
automatically.

Usage in a model:

    from app.encrypted_type import EncryptedString

    class Integration(Base):
        api_key = Column(EncryptedString, nullable=False)

Your application code then reads and writes `integration.api_key` as a
normal string — the encryption is invisible at the ORM level, while the
database only ever stores ciphertext.

Trade-off worth knowing: you CANNOT do a SQL WHERE lookup on an encrypted
column (the DB only sees ciphertext, and Fernet output differs every time
even for identical input). If you ever need to search by a sensitive
value, store a separate hashed lookup column alongside it.
"""

from sqlalchemy.types import TypeDecorator, Text

from app.encryption import encrypt_value, decrypt_value


class EncryptedString(TypeDecorator):
    """Transparently encrypts a string column at rest."""

    impl = Text  # ciphertext is longer than plaintext — don't use a short String(n)
    cache_ok = True

    def process_bind_param(self, value, dialect):
        """Called on the way INTO the database."""
        if value is None:
            return None
        return encrypt_value(value)

    def process_result_value(self, value, dialect):
        """Called on the way OUT of the database."""
        if value is None:
            return None
        return decrypt_value(value)