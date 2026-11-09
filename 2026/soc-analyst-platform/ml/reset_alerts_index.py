from dotenv import load_dotenv
import os
from elasticsearch import Elasticsearch

load_dotenv()

client = Elasticsearch(
    os.getenv("ELASTIC_URL"),
    api_key=os.getenv("ELASTIC_API_KEY")
)

client.indices.delete(index="alerts", ignore_unavailable=True)
print("Alerts index deleted")