"""
Combined CICIDS2017 ingest for Elastic.  Save as ml/ingest_all_days.py

Default: adds THURSDAY + FRIDAY alerts and a few test-fixture alerts on top of
what is already in Elastic (your existing Tuesday/Wednesday alerts are untouched).

Usage (from the project root):
    python ml/ingest_all_days.py --dry-run          # no Elastic, just shows the sample
    python ml/ingest_all_days.py                    # push Thursday + Friday + fixtures
    python ml/ingest_all_days.py --days tuesday wednesday thursday friday
        (only after running ml/reset_alerts_index.py, otherwise you get duplicates)
"""
import argparse
import glob
import json
import os
import random
import re
import uuid
from datetime import datetime, timedelta, timezone

import pandas as pd

# ---- one MITRE map for all days ----
MITRE_MAP = {
    "BENIGN": None,
    "FTP-Patator": "T1110",
    "SSH-Patator": "T1110",
    "DoS Hulk": "T1498",
    "DoS GoldenEye": "T1498",
    "DoS slowloris": "T1498",
    "DoS Slowhttptest": "T1498",
    "DDoS": "T1498",
    "PortScan": "T1046",
    "Web Attack - Brute Force": "T1110",
    "Web Attack - XSS": "T1059",
    "Web Attack - Sql Injection": "T1190",
    "Infiltration": "T1190",
    "Bot": "T1071",
    "Heartbleed": "T1190",
}
MITRE_NAMES = {
    "T1110": "Brute Force",
    "T1498": "Network Denial of Service",
    "T1046": "Network Service Discovery",
    "T1059": "Command and Scripting Interpreter",
    "T1190": "Exploit Public-Facing Application",
    "T1071": "Application Layer Protocol (C2)",
}

DAY_PATTERNS = {
    "tuesday": "Tuesday*",
    "wednesday": "Wednesday*",
    "thursday": "Thursday*",
    "friday": "Friday*",
}
# working-hours window each day's alerts are spread over (UTC, arbitrary but fixed)
DAY_START = {
    "tuesday": datetime(2017, 7, 4, 9, 0, tzinfo=timezone.utc),
    "wednesday": datetime(2017, 7, 5, 9, 0, tzinfo=timezone.utc),
    "thursday": datetime(2017, 7, 6, 9, 0, tzinfo=timezone.utc),
    "friday": datetime(2017, 7, 7, 9, 0, tzinfo=timezone.utc),
}

MAX_PER_ATTACK_LABEL = 60   # keeps rare and common attack types balanced
BENIGN_PER_FILE = 40

# Test fixtures: public IPs so threat-intel enrichment has something to look up.
# 8.8.8.8 and 1.1.1.1 are well-known clean resolvers. To demo a flagged IP, replace
# one entry with an address you looked up yourself on AbuseIPDB / VirusTotal.
FIXTURE_IPS = ["8.8.8.8", "1.1.1.1", "9.9.9.9", "208.67.222.222", "8.8.4.4"]


def clean_label(label: str) -> str:
    """Web attack labels arrive garbled (e.g. 'Web Attack ï¿½ XSS'). Normalise them."""
    label = str(label).strip()
    label = re.sub(r"^(Web Attack)\s*[^A-Za-z0-9\s]+\s*", r"\1 - ", label)
    return label


def make_alert(row, label, ts):
    is_attack = label != "BENIGN"
    tech = MITRE_MAP.get(label)
    desc = f"Traffic flow labeled: {label}"
    if tech:
        desc += f" (MITRE {tech} - {MITRE_NAMES[tech]})"
    return {
        "alert_id": f"alrt_{uuid.uuid4().hex[:8]}",
        "timestamp": ts.isoformat(),
        "source": "EDR",
        "source_system": "CICIDS2017_dataset",
        "severity_raw": "high" if is_attack else "low",
        "asset_id": f"host-{int(row['Destination Port'])}",
        "asset_criticality": "unknown",
        "description": desc,
        "mitre_technique": tech or "",
        "raw_log": row.to_json(),
    }


def build_day(day, data_dir, rng):
    files = sorted(glob.glob(os.path.join(data_dir, DAY_PATTERNS[day])))
    if not files:
        raise SystemExit(f"No files matching {DAY_PATTERNS[day]} in {data_dir}")
    df = pd.concat((pd.read_csv(f, encoding="latin-1") for f in files), ignore_index=True)
    df.columns = df.columns.str.strip()
    df["Label"] = df["Label"].map(clean_label)

    parts = []
    for label, grp in df.groupby("Label"):
        n = BENIGN_PER_FILE * len(files) if label == "BENIGN" else MAX_PER_ATTACK_LABEL
        parts.append(grp.sample(n=min(n, len(grp)), random_state=42))
    sample = pd.concat(parts).sample(frac=1, random_state=42)

    unknown = {l for l in sample["Label"].unique() if l not in MITRE_MAP}
    if unknown:
        print(f"  WARNING unmapped labels (no MITRE technique): {unknown}")

    # spread timestamps over an 8-hour window, sorted, so they are close but not identical
    offsets = sorted(rng.uniform(0, 8 * 3600) for _ in range(len(sample)))
    start = DAY_START[day]
    alerts = []
    for off, (_, row) in zip(offsets, sample.iterrows()):
        ts = start + timedelta(seconds=off)
        alerts.append(make_alert(row, row["Label"], ts))
    print(f"{day}: {len(alerts)} alerts  {sample['Label'].value_counts().to_dict()}")
    return alerts


def build_fixtures():
    now = datetime.now(timezone.utc)
    out = []
    for i, ip in enumerate(FIXTURE_IPS):
        out.append({
            "alert_id": f"fixture_{i+1:02d}",
            "timestamp": (now - timedelta(minutes=10 * (i + 1))).isoformat(),
            "source": "SIEM",
            "source_system": "test_fixture",
            "severity_raw": "high",
            "asset_id": "host-22",
            "source_ip": ip,
            "asset_criticality": "unknown",
            "description": f"Repeated failed SSH logins from {ip} (MITRE T1110 - Brute Force)",
            "mitre_technique": "T1110",
            "raw_log": json.dumps({"fixture": True, "src": ip, "dport": 22, "failed_logins": 25 + i}),
        })
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--days", nargs="+", default=["thursday", "friday"],
                    choices=list(DAY_PATTERNS))
    ap.add_argument("--data-dir", default="ml/data/cicids2017/MachineLearningCVE")
    ap.add_argument("--no-fixtures", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    rng = random.Random(42)
    alerts = []
    for day in args.days:
        alerts += build_day(day, args.data_dir, rng)
    if not args.no_fixtures:
        alerts += build_fixtures()

    mapped = sum(1 for a in alerts if a["mitre_technique"])
    print(f"\nTotal alerts: {len(alerts)}   with MITRE technique: {mapped}")

    if args.dry_run:
        print("Dry run: nothing pushed.")
        return

    from dotenv import load_dotenv
    from elasticsearch import Elasticsearch, helpers
    load_dotenv()
    client = Elasticsearch(
        os.getenv("ELASTIC_URL"),
        api_key=os.getenv("ELASTIC_API_KEY"),
        request_timeout=60, max_retries=3, retry_on_timeout=True,
    )
    actions = [{"_index": "alerts", "_source": a} for a in alerts]
    ok, errors = helpers.bulk(client.options(request_timeout=60), actions,
                              raise_on_error=False, chunk_size=100)
    print(f"Successfully indexed: {ok}")
    print(f"Errors: {len(errors) if errors else 0}")


if __name__ == "__main__":
    main()