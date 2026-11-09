from dotenv import load_dotenv
import os
from elasticsearch import Elasticsearch

load_dotenv()

client = Elasticsearch(
    os.getenv("ELASTIC_URL"),
    api_key=os.getenv("ELASTIC_API_KEY")
)

info = client.info()
print("Connected to Elastic cluster:", info["cluster_name"])