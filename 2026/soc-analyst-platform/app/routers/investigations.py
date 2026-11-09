"""
Investigation endpoints - wires Razzaq's RAG investigation agent (ml/investigate.py)
into Wahab's Postgres schema (Alert, Investigation, AuditLog).

NOTE: this file assumes app/dependencies.py exposes `get_db` (a DB session
dependency) and `get_current_user` (an auth dependency), matching the pattern
used in app/routers/auth.py and app/routers/admin.py. If those names differ,
adjust the two imports below to match.
"""

import os
import re
import sys
import importlib.util
from datetime import datetime, timezone
from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.dependencies import get_db, get_current_user  # adjust names if different
from app.models_alert import Alert, TriageStatus
from app.models_investigation import Investigation, InvestigationStatus
from app.models_audit import AuditLog

# --- Wire in the ml/ investigation agent ---
# ml/investigate.py lives outside the app/ package. Rather than fiddling
# with sys.path (which can behave inconsistently across platforms and
# reload/subprocess setups), we load the file directly by its absolute
# path using importlib - this always works regardless of sys.path state.
_INVESTIGATE_PATH = Path(__file__).resolve().parent.parent.parent / "ml" / "investigate.py"

if not _INVESTIGATE_PATH.is_file():
    raise RuntimeError(
        f"Could not find ml/investigate.py at expected path: {_INVESTIGATE_PATH}\n"
        f"This file (investigations.py) is expected to live at app/routers/investigations.py, "
        f"with ml/investigate.py as a sibling of app/ at the project root. Check your folder structure."
    )

_spec = importlib.util.spec_from_file_location("investigate_agent", str(_INVESTIGATE_PATH))
_investigate_module = importlib.util.module_from_spec(_spec)
sys.modules["investigate_agent"] = _investigate_module  # so relative state (chroma client etc.) initializes once
_spec.loader.exec_module(_investigate_module)

run_investigation = _investigate_module.investigate

router = APIRouter(prefix="/investigate", tags=["investigations"])


def _extract_severity(brief: str) -> str:
    """Pulls a short severity label (Low/Medium/High/Critical) out of the
    brief's SEVERITY ASSESSMENT section, for storing as confidence_score.
    Falls back to 'unknown' if the pattern isn't found - the full brief
    text is still stored in incident_brief regardless."""
    match = re.search(
        r"SEVERITY ASSESSMENT.*?\n(.*?)(–|-)",
        brief,
        re.IGNORECASE | re.DOTALL,
    )
    if match:
        candidate = match.group(1).strip().strip("*").strip()
        for level in ("Critical", "High", "Medium", "Low"):
            if level.lower() in candidate.lower():
                return level
    return "unknown"


@router.post("/{alert_id}")
def create_investigation(
    alert_id: str,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    """Runs the RAG investigation agent for a given alert and stores the
    result. `alert_id` is the alert's own string ID (e.g. 'alrt_57c0f997'),
    not the Postgres integer primary key."""

    alert = db.query(Alert).filter(Alert.alert_id == alert_id).first()
    if not alert:
        raise HTTPException(status_code=404, detail=f"Alert '{alert_id}' not found")

    existing = db.query(Investigation).filter(Investigation.alert_id == alert.id).first()
    if existing:
        raise HTTPException(
            status_code=400,
            detail=f"An investigation already exists for this alert (investigation id={existing.id})",
        )

    investigation = Investigation(
        alert_id=alert.id,
        status=InvestigationStatus.IN_PROGRESS,
    )
    db.add(investigation)
    db.commit()
    db.refresh(investigation)

    try:
        # Use the alert's own description as the semantic query - this is
        # the same pattern proven to retrieve relevant context in ml/investigate.py's
        # own test runs.
        brief, context = run_investigation(alert.description)

        investigation.incident_brief = brief
        investigation.citations = [
            {"alert_id": c["alert_id"], "mitre_technique": c["mitre_technique"], "severity": c["severity"]}
            for c in context
        ]
        investigation.timeline = [
            {"alert_id": c["alert_id"], "text": c["text"]} for c in context
        ]
        investigation.confidence_score = _extract_severity(brief)
        investigation.status = InvestigationStatus.COMPLETED
        investigation.completed_at = datetime.now(timezone.utc)

        alert.triage_status = TriageStatus.INVESTIGATED if hasattr(TriageStatus, "INVESTIGATED") else alert.triage_status

        db.add(AuditLog(
            event_type="investigation_completed",
            actor_type="ai_agent",
            actor_user_id=getattr(current_user, "id", None),
            alert_id=alert.id,
            detail={
                "alert_id": alert.alert_id,
                "citation_count": len(context),
                "confidence_score": investigation.confidence_score,
            },
        ))

        db.commit()
        db.refresh(investigation)

    except Exception as e:
        investigation.status = InvestigationStatus.FAILED if hasattr(InvestigationStatus, "FAILED") else investigation.status
        db.commit()
        raise HTTPException(status_code=500, detail=f"Investigation failed: {str(e)}")

    return {
        "investigation_id": investigation.id,
        "alert_id": alert.alert_id,
        "status": investigation.status,
        "incident_brief": investigation.incident_brief,
        "citations": investigation.citations,
        "confidence_score": investigation.confidence_score,
        "created_at": investigation.created_at,
        "completed_at": investigation.completed_at,
    }


@router.get("/{alert_id}")
def get_investigation(
    alert_id: str,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    """Retrieves an existing investigation for the given alert, if one exists."""
    alert = db.query(Alert).filter(Alert.alert_id == alert_id).first()
    if not alert:
        raise HTTPException(status_code=404, detail=f"Alert '{alert_id}' not found")

    investigation = db.query(Investigation).filter(Investigation.alert_id == alert.id).first()
    if not investigation:
        raise HTTPException(
            status_code=404,
            detail=f"No investigation exists yet for alert '{alert_id}' - POST to this endpoint to create one",
        )

    return {
        "investigation_id": investigation.id,
        "alert_id": alert.alert_id,
        "status": investigation.status,
        "incident_brief": investigation.incident_brief,
        "citations": investigation.citations,
        "confidence_score": investigation.confidence_score,
        "created_at": investigation.created_at,
        "completed_at": investigation.completed_at,
    }