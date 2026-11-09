"""
Alert ingestion endpoint. Accepts a new alert matching docs/alert-schema.json,
validates it, and stores it in the Alert table - this is the entry point for
getting real alert data into the system (from Elastic, a feed, or a manual
test POST), rather than only ever inserting test data via one-off scripts.
"""

from datetime import datetime, timezone
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from app.dependencies import get_db, get_current_user  # adjust names if different
from app.models_alert import Alert, AlertSource, AssetCriticality, TriageStatus
from app.models_audit import AuditLog

router = APIRouter(prefix="/alerts", tags=["alerts"])


# --- Request/response schemas, mirroring docs/alert-schema.json ---

class AlertIn(BaseModel):
    alert_id: str
    timestamp: Optional[datetime] = None  # defaults to now if not given
    source: AlertSource
    source_system: Optional[str] = None
    severity_raw: str
    asset_id: str
    source_ip: Optional[str] = None
    asset_criticality: AssetCriticality = AssetCriticality.UNKNOWN
    description: str
    mitre_technique: Optional[str] = None
    raw_log: str
    related_alert_ids: List[str] = Field(default_factory=list)


class AlertOut(BaseModel):
    id: int
    alert_id: str
    timestamp: datetime
    source: AlertSource
    source_system: Optional[str]
    severity_raw: str
    asset_id: str
    source_ip: Optional[str] = None
    asset_criticality: AssetCriticality
    description: str
    mitre_technique: Optional[str]
    related_alert_ids: List[str]
    triage_status: TriageStatus
    created_at: datetime

    class Config:
        from_attributes = True


@router.post("", response_model=AlertOut, status_code=201)
def ingest_alert(
    alert_in: AlertIn,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    """Ingests one new alert. Rejects duplicates (same alert_id) with a 400,
    since alert_id is expected to be unique per the schema."""

    existing = db.query(Alert).filter(Alert.alert_id == alert_in.alert_id).first()
    if existing:
        raise HTTPException(
            status_code=400,
            detail=f"Alert '{alert_in.alert_id}' already exists (id={existing.id})",
        )

    alert = Alert(
        alert_id=alert_in.alert_id,
        timestamp=alert_in.timestamp or datetime.now(timezone.utc),
        source=alert_in.source,
        source_system=alert_in.source_system,
        severity_raw=alert_in.severity_raw,
        asset_id=alert_in.asset_id,
        source_ip=alert_in.source_ip,
        asset_criticality=alert_in.asset_criticality,
        description=alert_in.description,
        mitre_technique=alert_in.mitre_technique,
        raw_log=alert_in.raw_log,
        related_alert_ids=alert_in.related_alert_ids,
        triage_status=TriageStatus.PENDING,
    )
    db.add(alert)
    db.commit()
    db.refresh(alert)

    db.add(AuditLog(
        event_type="alert_ingested",
        actor_type="user",
        actor_user_id=getattr(current_user, "id", None),
        alert_id=alert.id,
        detail={"alert_id": alert.alert_id, "source": alert.source, "severity_raw": alert.severity_raw},
    ))
    db.commit()

    return alert


@router.get("", response_model=List[AlertOut])
def list_alerts(
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
    limit: int = 50,
):
    """Lists the most recently ingested alerts, newest first."""
    return (
        db.query(Alert)
        .order_by(Alert.created_at.desc())
        .limit(limit)
        .all()
    )


@router.get("/{alert_id}", response_model=AlertOut)
def get_alert(
    alert_id: str,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    """Retrieves a single alert by its string alert_id."""
    alert = db.query(Alert).filter(Alert.alert_id == alert_id).first()
    if not alert:
        raise HTTPException(status_code=404, detail=f"Alert '{alert_id}' not found")
    return alert