from dotenv import load_dotenv
import os
import requests

load_dotenv()

VT_KEY = os.getenv("VIRUSTOTAL_API_KEY")
ABUSE_KEY = os.getenv("ABUSEIPDB_API_KEY")

# A commonly-used test IP from Google's public DNS (should come back clean)
test_ip = "8.8.8.8"

# --- VirusTotal check ---
vt_response = requests.get(
    f"https://www.virustotal.com/api/v3/ip_addresses/{test_ip}",
    headers={"x-apikey": VT_KEY}
)
vt_data = vt_response.json()
malicious_votes = vt_data["data"]["attributes"]["last_analysis_stats"]["malicious"]
print(f"VirusTotal - {test_ip}: {malicious_votes} vendors flagged as malicious")

# --- AbuseIPDB check ---
abuse_response = requests.get(
    "https://api.abuseipdb.com/api/v2/check",
    headers={"Key": ABUSE_KEY, "Accept": "application/json"},
    params={"ipAddress": test_ip}
)
abuse_data = abuse_response.json()
abuse_score = abuse_data["data"]["abuseConfidenceScore"]
print(f"AbuseIPDB - {test_ip}: {abuse_score}% abuse confidence score")