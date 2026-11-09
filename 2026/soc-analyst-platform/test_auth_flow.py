"""
End-to-end test for the JWT auth flow (register -> login -> protected route -> refresh).

Usage:
    Make sure your server is running first:
        uvicorn app.main:app --reload

    Then, in a separate terminal:
        python test_auth_flow.py

Each run generates a fresh random email so you can run it repeatedly
without hitting "Email already registered" error.
"""

import random
import string
import sys

import requests

BASE_URL = "http://127.0.0.1:8000"


def random_email() -> str:
    suffix = "".join(random.choices(string.ascii_lowercase + string.digits, k=8))
    return f"test.{suffix}@example.com"


def check(label: str, condition: bool):
    status = "PASS" if condition else "FAIL"
    print(f"[{status}] {label}")
    if not condition:
        sys.exit(1)


def main():
    email = random_email()
    password = "testpass123"

    print(f"Using test account: {email}\n")

    # 1. Register
    r = requests.post(f"{BASE_URL}/auth/register", json={"email": email, "password": password})
    check(f"Register returns 201 (got {r.status_code})", r.status_code == 201)
    print("   ->", r.json())

    # 2. Login
    r = requests.post(f"{BASE_URL}/auth/login", json={"email": email, "password": password})
    check(f"Login returns 200 (got {r.status_code})", r.status_code == 200)
    tokens = r.json()
    check("Login response has access_token", "access_token" in tokens)
    check("Login response has refresh_token", "refresh_token" in tokens)
    access_token = tokens["access_token"]
    refresh_token = tokens["refresh_token"]

    # 3. Access protected route with token
    r = requests.get(f"{BASE_URL}/auth/me", headers={"Authorization": f"Bearer {access_token}"})
    check(f"/auth/me with token returns 200 (got {r.status_code})", r.status_code == 200)
    check("/auth/me returns the same email", r.json().get("email") == email)
    print("   ->", r.json())

    # 4. Access protected route WITHOUT token (should fail)
    r = requests.get(f"{BASE_URL}/auth/me")
    check(f"/auth/me with no token returns 401/403 (got {r.status_code})", r.status_code in (401, 403))

    # 5. Refresh to get a new access token
    r = requests.post(f"{BASE_URL}/auth/refresh", json={"refresh_token": refresh_token})
    check(f"Refresh returns 200 (got {r.status_code})", r.status_code == 200)
    new_access_token = r.json()["access_token"]

    # 6. New access token also works
    r = requests.get(f"{BASE_URL}/auth/me", headers={"Authorization": f"Bearer {new_access_token}"})
    check(f"/auth/me with NEW token returns 200 (got {r.status_code})", r.status_code == 200)

    # 7. Refresh endpoint should reject an access token (wrong type)
    r = requests.post(f"{BASE_URL}/auth/refresh", json={"refresh_token": access_token})
    check(f"Refresh with an access token is rejected (got {r.status_code})", r.status_code == 401)

    # 8. Duplicate registration should fail
    r = requests.post(f"{BASE_URL}/auth/register", json={"email": email, "password": password})
    check(f"Duplicate register returns 400 (got {r.status_code})", r.status_code == 400)

    # 9. Wrong password should fail
    r = requests.post(f"{BASE_URL}/auth/login", json={"email": email, "password": "wrongpassword"})
    check(f"Wrong password returns 401 (got {r.status_code})", r.status_code == 401)

    print("\nAll checks passed — auth flow is working end to end.")


if __name__ == "__main__":
    try:
        main()
    except requests.exceptions.ConnectionError:
        print("Could not connect to the server.")
        print(f"Make sure it's running at {BASE_URL} (uvicorn app.main:app --reload)")
        sys.exit(1)
