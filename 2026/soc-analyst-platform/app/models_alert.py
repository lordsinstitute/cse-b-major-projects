"""
The Alert model — this is the normalized shape every alert takes once it's
ingested from SIEM, EDR, or cloud audit log sources, per the shared format
in /docs/alert-schema.md.

Two decisions made here that weren't fully settled in that doc (flagged
back to the team, not changed silently):

1. `false_positive_score` lives directly on this table, not a separate
   one. It's a strict 1:1 relationship with the alert (one score per
   alert), so a join table would add overhead with no real benefit.

2. `triage_status` was added — not in the original schema, but the
   backend needs *some* field to track where an alert sits in the
   pipeline (just ingested vs. cleared threshold vs. under investigation
   vs. resolved). Without it there's no way to query "what's still
   pending" without re-deriving it every time.
"""

import enum

from sqlalchemy import Column, Integer, String, Text, DateTime, Float, Enum, JSON, func

from app.database import Base
from app.encrypted_type import EncryptedString


class AlertSource(str, enum.Enum):
    SIEM = "SIEM"
    EDR = "EDR"
    CLOUD_AUDIT = "cloud_audit"


class AssetCriticality(str, enum.Enum):
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"
    UNKNOWN = "unknown"


class TriageStatus(str, enum.Enum):
    PENDING = "pending"
    CLEARED_THRESHOLD = "cleared_threshold"
    INVESTIGATING = "investigating"
    RESOLVED = "resolved"
    DISMISSED = "dismissed"


class Alert(Base):
    __tablename__ = "alerts"

    id = Column(Integer, primary_key=True, index=True)

    alert_id = Column(String, unique=True, index=True, nullable=False)
    timestamp = Column(DateTime(timezone=True), nullable=False)
    source = Column(Enum(AlertSource), nullable=False)
    source_system = Column(String, nullable=True)
    severity_raw = Column(String, nullable=False)
    asset_id = Column(String, index=True, nullable=False)
    source_ip = Column(String, nullable=True, index=True)
    asset_criticality = Column(Enum(AssetCriticality), default=AssetCriticality.UNKNOWN, nullable=True)
    description = Column(Text, nullable=False)
    mitre_technique = Column(String, nullable=True)

    raw_log = Column(EncryptedString, nullable=False)

    related_alert_ids = Column(JSON, default=list, nullable=False)

    false_positive_score = Column(Float, nullable=True)
    triage_status = Column(Enum(TriageStatus), default=TriageStatus.PENDING, nullable=False)

    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())