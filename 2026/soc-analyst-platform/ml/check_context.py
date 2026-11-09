from huggingface_hub import InferenceClient
import chromadb
import os
from dotenv import load_dotenv

load_dotenv()

hf_client = InferenceClient(token=os.getenv("HUGGINGFACE_API_KEY"))
chroma_client = chromadb.PersistentClient(path="chroma_db")
collection = chroma_client.get_or_create_collection(name="alert_history")

query = "suspicious SSH login attempts"
print("Generating embedding...")
query_embedding = hf_client.feature_extraction(query, model="sentence-transformers/all-MiniLM-L6-v2")
print(f"Embedding generated, length: {len(query_embedding)}")

print("Querying ChromaDB...")
results = collection.query(query_embeddings=[query_embedding], n_results=5)
print("Raw results:", results)