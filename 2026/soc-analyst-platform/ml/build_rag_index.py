from dotenv import load_dotenv
import os
import chromadb
from elasticsearch import Elasticsearch
from huggingface_hub import InferenceClient

load_dotenv()

# Connect to Elastic to pull our alerts back out
es_client = Elasticsearch(
    os.getenv("ELASTIC_URL"),
    api_key=os.getenv("ELASTIC_API_KEY")
)

# Connect to HuggingFace for embeddings
hf_client = InferenceClient(token=os.getenv("HUGGINGFACE_API_KEY"))

# Set up a local ChromaDB (persists to disk in ml/chroma_db/)
chroma_client = chromadb.PersistentClient(path="ml/chroma_db")
collection = chroma_client.get_or_create_collection(name="alert_history")

# Pull alerts back from Elastic
results = es_client.search(index="alerts", size=1000, query={"match_all": {}})
hits = results["hits"]["hits"]
print(f"Pulled {len(hits)} alerts from Elastic")

# Build a text chunk for each alert - this is what gets embedded and searched later
documents = []
metadatas = []
ids = []

for hit in hits:
    alert = hit["_source"]
    # A readable text summary of the alert - this is what semantic search matches against
    text = (
    f"Alert {alert['alert_id']} on {alert['asset_id']} at {alert['timestamp']}: "
    f"{alert['description']}. Severity: {alert['severity_raw']}. "
    f"Source: {alert['source_system']}."
)
    documents.append(text)
    metadatas.append({
        "alert_id": alert["alert_id"],
        "severity": alert["severity_raw"],
        "mitre_technique": alert.get("mitre_technique", ""),
    })
    ids.append(alert["alert_id"])

# Embed all documents using HuggingFace, then store in ChromaDB
print("Generating embeddings...")
embeddings = [
    hf_client.feature_extraction(doc, model="sentence-transformers/all-MiniLM-L6-v2")
    for doc in documents
]

collection.add(
    documents=documents,
    embeddings=embeddings,
    metadatas=metadatas,
    ids=ids,
)

print(f"Indexed {len(documents)} alerts into ChromaDB collection 'alert_history'")