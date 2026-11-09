"""
Test for rate limiting on /auth/login.

Usage:
    Make sure your server is running first:
        uvicorn app.main:app --reload

    Then, in a separate terminal:
        python test_rate_limit.py

NOTE: the limit is 5/minute. If you run this script twice in quick
succession, the second run may immediately show 429s from the start —
that's correct behavior, not a bug. Wait a minute between runs, or
restart the server to reset the in-memory limit counter.
"""

import sys

import requests

BASE_URL = "http://127.0.0.1:8000"


def check(label: str, condition: bool):
    status = "PASS" if condition else "FAIL"
    print(f"[{status}] {label}")
    if not condition:
        sys.exit(1)


def main():
    at = chr(64)
    email = "ratelimit.test" + at + "example.com"
    password = "wrongpassword"  # intentionally wrong — we're testing the LIMIT, not login success

    print("Sending 7 rapid requests to /auth/login (limit is 5/minute)...\n")

    statuses = []
    for i in range(1, 8):
        r = requests.post(f"{BASE_URL}/auth/login", json={"email": email, "password": password})
        statuses.append(r.status_code)
        print(f"Request {i}: status={r.status_code}  body={r.json()}")

    check("First 5 requests were processed normally (401, not blocked)", statuses[:5] == [401] * 5)
    check("6th request was blocked (429)", statuses[5] == 429)
    check("7th request was also blocked (429)", statuses[6] == 429)

    print("\nAll checks passed — rate limiting is working.")
    print("Note: the limit resets after 1 minute, or immediately if you restart the server.")


if __name__ == "__main__":
    try:
        main()
    except requests.exceptions.ConnectionError:
        print("Could not connect to the server.")
        print(f"Make sure it's running at {BASE_URL} (uvicorn app.main:app --reload)")
        sys.exit(1)