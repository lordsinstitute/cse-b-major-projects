# Alert Schema

This is the shared alert format for the SOC Analyst Platform. Every alert — whether it comes
from the SIEM, an EDR-style dataset, or cloud audit logs — gets normalized into this shape
before it reaches Ghouse's triage model or Razzaq's investigation agent.

**Everyone should build against this format.** If it needs to change, update this file first
and let the team know — don't change field names silently in your own code.

The machine-readable version lives in [`alert-schema.json`](./alert-schema.json) (JSON Schema,
draft-07) — Wahab can use this directly for backend request validation.

## Fields

| Field | Type | Required | Notes |
|---|---|---|---|
| `alert_id` | string | Yes | Unique ID, generated at ingestion if the source doesn't provide one |
| `timestamp` | string (ISO 8601) | Yes | When the alert was generated, UTC |
| `source` | string | Yes | One of: `SIEM`, `EDR`, `cloud_audit` |
| `source_system` | string | No | Which specific tool, e.g. `Elastic Security`, `CICIDS_dataset` |
| `severity_raw` | string | Yes | Severity as given by the source, before our own triage score |
| `asset_id` | string | Yes | Affected host / user / resource identifier |
| `asset_criticality` | string | No | `low` / `medium` / `high` / `unknown` — feeds the triage model |
| `description` | string | Yes | Short human-readable summary |
| `mitre_technique` | string | No | MITRE ATT&CK technique ID if already mapped, e.g. `T1110` |
| `raw_log` | string | Yes | The original, unmodified log line — this is what every citation traces back to |
| `related_alert_ids` | array of strings | No | Other alerts that look related (same asset/time window) |

## Example

```json
{
  "alert_id": "alrt_8f3c1a2b",
  "timestamp": "2026-08-03T14:32:10Z",
  "source": "SIEM",
  "source_system": "Elastic Security",
  "severity_raw": "high",
  "asset_id": "host-web-03",
  "asset_criticality": "high",
  "description": "Multiple failed SSH login attempts followed by a successful login",
  "mitre_technique": "T1110",
  "raw_log": "2026-08-03T14:32:10Z sshd[2211]: Failed password for root from 203.0.113.7 port 51122 ssh2 (x7), then Accepted password for root from 203.0.113.7",
  "related_alert_ids": []
}
```

## Why `raw_log` matters so much

This field is the backbone of the "evidence-cited, not a black box" promise of the whole
platform. Every claim the investigation agent makes in its final report has to be traceable
back to something in a `raw_log` field — if it isn't, that's a hallucination, not a finding.
Don't strip or summarize this field during ingestion; store it exactly as received.

## Open questions (update this section as we go)

 ## Open questions (update this section as we go)

- [x] Do we need a `false_positive_score` field written back by Ghouse's model, or does that
      live in a separate table Wahab manages?
      **Resolved (Wahab):** lives directly on the `alerts` table — it's a strict 1:1
      relationship with the alert, so a separate table would just add a join for no benefit.
- [ ] Should `asset_criticality` be inferred automatically from `asset_id`, or does someone
      maintain a manual asset-criticality list?

**Also added by Wahab (not in the original schema):** a `triage_status` field on the alerts
table (`pending` / `cleared_threshold` / `investigating` / `resolved` / `dismissed`) — needed
so the backend can track pipeline state without re-deriving it from other fields on every query.

## Status
First draft — Week 1. Expect this to evolve once Ghouse and Wahab start building against it
in Week 3. Change it here, don't fork it silently.