"""
Integration smoke test for the deployed Users Service.

Usage:
  API_URL=https://... \
  COGNITO_CLIENT_ID=... \
  TEST_EMAIL=smoke@anycompany.com \
  TEST_PASSWORD=TestPass123! \
  python tests/integration/smoke_test.py

Exit code 0 = all assertions passed.
Exit code 1 = one or more assertions failed.
"""

import os
import sys
import json
import time
import requests

API_URL = os.environ["API_URL"].rstrip("/")
TEST_EMAIL = os.environ.get("TEST_EMAIL", "smoke@anycompany.com")
TEST_PASSWORD = os.environ.get("TEST_PASSWORD", "TestPass123!")

_failures = []


def check(label: str, condition: bool, detail: str = "") -> None:
    if condition:
        print(f"  PASS  {label}")
    else:
        msg = f"  FAIL  {label}" + (f" — {detail}" if detail else "")
        print(msg)
        _failures.append(msg)


def req(method: str, path: str, *, token: str = None, **kwargs) -> requests.Response:
    headers = kwargs.pop("headers", {})
    if token:
        headers["Authorization"] = f"Bearer {token}"
    return requests.request(method, f"{API_URL}{path}", headers=headers, timeout=15, **kwargs)


def run():
    print("=== Smoke test starting ===")
    print(f"API_URL: {API_URL}")

    # ── Step 1: Login ──────────────────────────────────────────────────────────
    print("\n[1] POST /auth/login")
    r = req("POST", "/auth/login", json={"email": TEST_EMAIL, "password": TEST_PASSWORD})
    check("status 200", r.status_code == 200, f"got {r.status_code}: {r.text[:200]}")
    tokens = r.json() if r.status_code == 200 else {}
    access_token = tokens.get("access_token", "")
    refresh_token = tokens.get("refresh_token", "")
    check("access_token present", bool(access_token))
    check("refresh_token present", bool(refresh_token))

    if not access_token:
        print("\nCannot continue without an access token. Aborting.")
        return

    # ── Step 2: Create user ────────────────────────────────────────────────────
    print("\n[2] POST /users")
    user_email = f"smoke-{int(time.time())}@anycompany.com"
    r = req("POST", "/users", token=access_token, json={"email": user_email, "name": "Smoke User"})
    check("status 201", r.status_code == 201, f"got {r.status_code}: {r.text[:200]}")
    created = r.json() if r.status_code == 201 else {}
    user_id = created.get("user_id", "")
    check("user_id present", bool(user_id))
    check("status ACTIVE", created.get("status") == "ACTIVE")

    if not user_id:
        print("\nCannot continue without user_id. Aborting.")
        return

    # ── Step 3: Get user ───────────────────────────────────────────────────────
    print("\n[3] GET /users/{user_id}")
    r = req("GET", f"/users/{user_id}", token=access_token)
    check("status 200", r.status_code == 200, f"got {r.status_code}: {r.text[:200]}")
    got = r.json() if r.status_code == 200 else {}
    check("user_id matches", got.get("user_id") == user_id)
    check("email matches", got.get("email") == user_email)
    check("name matches", got.get("name") == "Smoke User")

    # ── Step 4: Update user ────────────────────────────────────────────────────
    print("\n[4] PUT /users/{user_id}")
    created_at = got.get("updated_at", "")
    time.sleep(1)  # ensure updated_at will differ
    r = req("PUT", f"/users/{user_id}", token=access_token, json={"name": "Smoke User Updated"})
    check("status 200", r.status_code == 200, f"got {r.status_code}: {r.text[:200]}")
    updated = r.json() if r.status_code == 200 else {}
    check("name updated", updated.get("name") == "Smoke User Updated")
    check("updated_at changed", updated.get("updated_at") != created_at)

    # ── Step 5: List users ─────────────────────────────────────────────────────
    print("\n[5] GET /users")
    r = req("GET", "/users", token=access_token)
    check("status 200", r.status_code == 200, f"got {r.status_code}: {r.text[:200]}")
    listing = r.json() if r.status_code == 200 else {}
    ids_in_list = [u["user_id"] for u in listing.get("items", [])]
    check("user in list", user_id in ids_in_list)
    check("count field present", "count" in listing)

    # ── Step 6: Delete user ────────────────────────────────────────────────────
    print("\n[6] DELETE /users/{user_id}")
    r = req("DELETE", f"/users/{user_id}", token=access_token)
    check("status 204", r.status_code == 204, f"got {r.status_code}: {r.text[:200]}")

    # ── Step 7: Get deleted user ───────────────────────────────────────────────
    print("\n[7] GET /users/{user_id} → 404")
    r = req("GET", f"/users/{user_id}", token=access_token)
    check("status 404", r.status_code == 404, f"got {r.status_code}: {r.text[:200]}")

    # ── Step 8: Unauthenticated request ───────────────────────────────────────
    print("\n[8] POST /users without token → 401")
    r = req("POST", "/users", json={"email": "noauth@example.com", "name": "NoAuth"})
    check("status 401", r.status_code == 401, f"got {r.status_code}: {r.text[:200]}")

    # ── Step 9: Refresh token ─────────────────────────────────────────────────
    print("\n[9] POST /auth/refresh")
    r = req("POST", "/auth/refresh", json={"refresh_token": refresh_token})
    check("status 200", r.status_code == 200, f"got {r.status_code}: {r.text[:200]}")
    refreshed = r.json() if r.status_code == 200 else {}
    check("new access_token present", bool(refreshed.get("access_token")))

    # ── Step 10: Logout ───────────────────────────────────────────────────────
    print("\n[10] POST /auth/logout")
    r = req("POST", "/auth/logout", json={"access_token": access_token})
    check("status 204", r.status_code == 204, f"got {r.status_code}: {r.text[:200]}")

    # ── Summary ───────────────────────────────────────────────────────────────
    print(f"\n=== Results: {10 - len(_failures)}/10 steps passed ===")
    if _failures:
        print("\nFailed checks:")
        for f in _failures:
            print(f)
        sys.exit(1)
    else:
        print("All checks passed.")
        sys.exit(0)


if __name__ == "__main__":
    run()
