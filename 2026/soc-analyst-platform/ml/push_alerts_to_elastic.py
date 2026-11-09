from dotenv import load_dotenv
import os
import pandas as pd
import uuid
from datetime import datetime, timezone
from elasticsearch import Elasticsearch, helpers

load_dotenv()

# Connect to Elastic
client = Elasticsearch(
    os.getenv("ELASTIC_URL"),
    api_key=os.getenv("ELASTIC_API_KEY"),
    request_timeout=60,       # give it up to 60 seconds instead of the default
    max_retries=3,            # automatically retry failed requests
    retry_on_timeout=True,
)

# ---- MITRE ATT&CK mapping table ----
# Maps CICIDS2017 attack labels -> MITRE ATT&CK technique IDs
# Reference: https://attack.mitre.org/techniques/
MITRE_MAP = {
    "BENIGN": None,  # no technique for normal traffic
    "FTP-Patator": "T1110",              # Brute Force
    "SSH-Patator": "T1110",              # Brute Force
    "DoS Hulk": "T1498",                 # Network Denial of Service
    "DoS GoldenEye": "T1498",
    "DoS slowloris": "T1498",
    "DoS Slowhttptest": "T1498",
    "DDoS": "T1498",
    "PortScan": "T1046",                 # Network Service Discovery
    "Web Attack - Brute Force": "T1110",
    "Web Attack - XSS": "T1059",         # Command and Scripting Interpreter
    "Web Attack - Sql Injection": "T1190",  # Exploit Public-Facing Application
    "Infiltration": "T1190",
    "Bot": "T1071",                      # Application Layer Protocol (C2)
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


def map_mitre(label: str):
    """Look up the MITRE technique for a CICIDS2017 label. Handles labels
    the map doesn't know about by returning None instead of crashing."""
    label_clean = label.strip()
    return MITRE_MAP.get(label_clean)


# Load Tuesday's file — has real attack labels (Brute Force), not just BENIGN
df = pd.read_csv("ml/data/cicids2017/MachineLearningCVE/Tuesday-WorkingHours.pcap_ISCX.csv")
df.columns = df.columns.str.strip()  # fix the whitespace bug

# Take a sample that's weighted toward attacks, not just random (random 500 rows
# from Tuesday would mostly be BENIGN and we wouldn't see much MITRE mapping)
attacks = df[df['Label'] != 'BENIGN']
benign = df[df['Label'] == 'BENIGN'].sample(n=200, random_state=42)
sample = pd.concat([attacks.sample(n=min(300, len(attacks)), random_state=42), benign])

print(f"Sample composition:\n{sample['Label'].value_counts()}\n")


def row_to_alert(row):
    """Convert one CICIDS2017 row into our alert-schema.json format,
    now enriched with a MITRE ATT&CK technique if one applies."""
    label = row['Label']
    is_attack = label != 'BENIGN'
    technique_id = map_mitre(label)
    technique_name = MITRE_NAMES.get(technique_id, "")

    description = f"Traffic flow labeled: {label}"
    if technique_id:
        description += f" (MITRE {technique_id} - {technique_name})"

    return {
        "alert_id": f"alrt_{uuid.uuid4().hex[:8]}",
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "source": "EDR",
        "source_system": "CICIDS2017_dataset",
        "severity_raw": "high" if is_attack else "low",
        "asset_id": f"host-{row['Destination Port']}",
        "asset_criticality": "unknown",
        "description": description,
        "mitre_technique": technique_id if technique_id else "",
        "raw_log": row.to_json(),
    }


alerts = [row_to_alert(row) for _, row in sample.iterrows()]

actions = [
    {"_index": "alerts", "_source": alert}
    for alert in alerts
]

success, errors = helpers.bulk(
    client.options(request_timeout=60),
    actions,
    raise_on_error=False,
    chunk_size=100,
)
print(f"Successfully indexed: {success}")
print(f"Errors: {len(errors) if errors else 0}")

mapped_count = sum(1 for a in alerts if a["mitre_technique"])
print(f"Alerts with a MITRE technique mapped: {mapped_count} / {len(alerts)}")