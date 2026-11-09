from dotenv import load_dotenv
import os
import pandas as pd
import uuid
from datetime import datetime, timezone
from elasticsearch import Elasticsearch, helpers

load_dotenv()

client = Elasticsearch(
    os.getenv("ELASTIC_URL"),
    api_key=os.getenv("ELASTIC_API_KEY"),
    request_timeout=60,
    max_retries=3,
    retry_on_timeout=True,
)

MITRE_MAP = {
    "BENIGN": None,
    "DoS Hulk": "T1498",
    "DoS GoldenEye": "T1498",
    "DoS slowloris": "T1498",
    "DoS Slowhttptest": "T1498",
    "Heartbleed": "T1190",
}

MITRE_NAMES = {
    "T1498": "Network Denial of Service",
    "T1190": "Exploit Public-Facing Application",
}


def map_mitre(label: str):
    return MITRE_MAP.get(label.strip())


df = pd.read_csv("ml/data/cicids2017/MachineLearningCVE/Wednesday-workingHours.pcap_ISCX.csv")
df.columns = df.columns.str.strip()

attacks = df[df['Label'] != 'BENIGN']
benign = df[df['Label'] == 'BENIGN'].sample(n=150, random_state=42)
sample = pd.concat([attacks.sample(n=min(350, len(attacks)), random_state=42), benign])

print(f"Sample composition:\n{sample['Label'].value_counts()}\n")


def row_to_alert(row):
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
actions = [{"_index": "alerts", "_source": alert} for alert in alerts]

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