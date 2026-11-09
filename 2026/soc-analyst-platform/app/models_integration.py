"""
Example of a model with encrypted fields.

This is a realistic stand-in for what the platform will actually need:
each connected data source (Elastic, VirusTotal, AbuseIPDB, Groq...) has
credentials that must be stored, retrieved, and used — but never sit in
the database as readable plaintext.
"""

from sqlalchemy import Column, Integer, String, DateTime, func

from app.database import Base
from app.encrypted_type import EncryptedString


class Integration(Base):
    __tablename__ = "integrations"

    id = Column(Integer, primary_key=True, index=True)

    # Not sensitive — safe to query and index normally.
    name = Column(String, unique=True, index=True, nullable=False)
    provider = Column(String, nullable=False)  # e.g. "virustotal", "elastic", "groq"

    # Sensitive — encrypted at rest. Reads/writes look like normal strings
    # in Python, but the database only ever holds ciphertext.
    api_key = Column(EncryptedString, nullable=False)
    api_secret = Column(EncryptedString, nullable=True)

    created_at = Column(DateTime(timezone=True), server_default=func.now())