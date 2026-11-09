"""
End-to-end test for RBAC (role-based access control).

Usage:
    Make sure your server is running first:
        uvicorn app.main:app --reload

    Then, in a separate terminal:
        python test_rbac_flow.py

NOTE on bootstrapping your first admin:
    Every self-registered user starts as "analyst" (by design — nobody should
    be able to grant themselves admin just by signing up). This script
    promotes a test user directly in the database to simulate the ONE-TIME
    manual step a real deployment needs: someone with DB access has to
    promote the very first admin by hand. After that, admins can promote
    other users through the API itself (PATCH /admin/users/{id}/role).
"""

import sqlite3
import sys

import requests

BASE_URL = "http://127.0.0.1:8000"
DB_PATH = "dev.db"  # adjust if you're using a different DATABASE_URL


def check(label: str, condition: bool):
    status = "PASS" if condition else "FAIL"
    print(f"[{status}] {label}")
    if not condition:
        sys.exit(1)


def register_and_login(email: str, password: str = "testpass123"):
    requests.post(f"{BASE_URL}/auth/register", json={"email": email, "password": password})
    r = requests.post(f"{BASE_URL}/auth/login", json={"email": email, "password": password})
    return r.json()["access_token"]


def get_user_id(token: str) -> int:
    r = requests.get(f"{BASE_URL}/auth/me", headers={"Authorization": f"Bearer {token}"})
    return r.json()["id"]


def main():
    at = chr(64)
    analyst_email = "rbac.analyst" + at + "example.com"
    admin_email = "rbac.admin" + at + "example.com"

    analyst_token = register_and_login(analyst_email)
    admin_token = register_and_login(admin_email)

    # 1. Fresh users are analysts by default and CANNOT hit admin routes
    r = requests.get(f"{BASE_URL}/admin/users", headers={"Authorization": f"Bearer {analyst_token}"})
    check(f"Analyst blocked from /admin/users (got {r.status_code})", r.status_code == 403)

    r = requests.get(f"{BASE_URL}/admin/users", headers={"Authorization": f"Bearer {admin_token}"})
    check(f"Second analyst also blocked before promotion (got {r.status_code})", r.status_code == 403)

    # 2. Bootstrap: promote the "admin" test user directly in the DB
    admin_user_id = get_user_id(admin_token)
    try:
        conn = sqlite3.connect(DB_PATH)
        conn.execute("UPDATE users SET role = 'ADMIN' WHERE id = ?", (admin_user_id,))
        conn.commit()
        conn.close()
    except sqlite3.OperationalError as e:
        print(f"Could not open {DB_PATH} directly — are you using Postgres instead of SQLite?")
        print(f"If so, promote user id {admin_user_id} to admin manually, then adjust this script.")
        raise e

    # Re-login to be safe (role is re-checked from DB on every request anyway,
    # but this mirrors what a real user would do)
    admin_token = register_and_login(admin_email)

    # 3. Promoted admin CAN now hit admin routes
    r = requests.get(f"{BASE_URL}/admin/users", headers={"Authorization": f"Bearer {admin_token}"})
    check(f"Admin can access /admin/users after promotion (got {r.status_code})", r.status_code == 200)
    print("   -> users visible to admin:", [u["email"] for u in r.json()])

    # 4. Admin promotes the analyst through the API itself
    analyst_id = get_user_id(analyst_token)
    r = requests.patch(
        f"{BASE_URL}/admin/users/{analyst_id}/role",
        json={"role": "admin"},
        headers={"Authorization": f"Bearer {admin_token}"},
    )
    check(f"Admin can promote another user via API (got {r.status_code})", r.status_code == 200)
    check("Promoted user's role is now admin", r.json()["role"] == "admin")

    # 5. Promoted-via-API user can now access admin routes too
    analyst_token = register_and_login(analyst_email)
    r = requests.get(f"{BASE_URL}/admin/users", headers={"Authorization": f"Bearer {analyst_token}"})
    check(f"Newly-promoted user can access /admin/users (got {r.status_code})", r.status_code == 200)

    # 6. Invalid role values are rejected
    r = requests.patch(
        f"{BASE_URL}/admin/users/{analyst_id}/role",
        json={"role": "superuser"},
        headers={"Authorization": f"Bearer {admin_token}"},
    )
    check(f"Invalid role value is rejected (got {r.status_code})", r.status_code == 422)

    # 7. Unauthenticated requests are rejected
    r = requests.get(f"{BASE_URL}/admin/users")
    check(f"No-token request rejected (got {r.status_code})", r.status_code == 401)

    print("\nAll checks passed — RBAC is working end to end.")
    print("Check your server's terminal output — you should see 'RBAC DENY' audit log lines")
    print("for each of the blocked attempts above.")


if __name__ == "__main__":
    try:
        main()
    except requests.exceptions.ConnectionError:
        print("Could not connect to the server.")
        print(f"Make sure it's running at {BASE_URL} (uvicorn app.main:app --reload)")
        sys.exit(1)