from dotenv import load_dotenv
import os
import chromadb
from huggingface_hub import InferenceClient

load_dotenv()

hf_client = InferenceClient(token=os.getenv("HUGGINGFACE_API_KEY"))
chroma_client = chromadb.PersistentClient(path="ml/chroma_db")
collection = chroma_client.get_or_create_collection(name="alert_history")

query = "suspicious SSH login attempts"
query_embedding = hf_client.feature_extraction(query, model="sentence-transformers/all-MiniLM-L6-v2")

results = collection.query(
    query_embeddings=[query_embedding],
    n_results=5
)

print(f"Top 5 results for: '{query}'\n")
for doc, meta, distance in zip(results["documents"][0], results["metadatas"][0], results["distances"][0]):
    print(f"- {doc}")
    print(f"  MITRE: {meta['mitre_technique']} | Severity: {meta['severity']} | Distance: {distance:.4f}\n")