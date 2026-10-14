#!/usr/bin/env python3
"""AI Stock Commons: independently running connection worker (no AI research yet).

No secrets are written to disk, the terminal history, or logs by this program.
Prototype only: pairing, heartbeat, revoke. Python 3.10+, standard library.
"""
import argparse
from datetime import datetime, timezone
import getpass
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
import uuid

BASE_URL = "https://hsgfwsghxdcgpjlekfqf.supabase.co/functions/v1"
# Supabase PUBLISHABLE key, not a service_role or secret key. Intentionally public.
PUBLISHABLE_KEY = "sb_publishable_uIAm3L6nM2JDmuSayJSylA_KoahbCux"
HEARTBEAT_EVERY_SECONDS = 30
MAX_RESPONSE_BYTES = 16_384

class WorkerError(Exception):
    pass


def parse_bundle(text):
    """Single-use bundle format: UUID:64-hex-pairing-secret."""
    text = text.strip()
    session_id, separator, secret = text.partition(":")
    if not separator or not re.fullmatch(r"[0-9a-f]{64}", secret):
        raise WorkerError("Bundle format invalid. Generate a fresh bundle on the owner page.")
    try:
        parsed = uuid.UUID(session_id)
    except ValueError as exc:
        raise WorkerError("Session ID in bundle is not a valid UUID.") from exc
    if str(parsed) != session_id.lower():
        raise WorkerError("Session ID format invalid.")
    return session_id, secret


def expires_epoch(value):
    try:
        dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
        if dt.tzinfo is None:
            raise ValueError("No timezone")
        return dt.timestamp()
    except (TypeError, AttributeError, ValueError) as exc:
        raise WorkerError("Unexpected lease expiration response.") from exc


def post_function(function, payload):
    data = json.dumps(payload, separators=(",", ":")).encode("utf-8")
    request = urllib.request.Request(
        f"{BASE_URL}/{function}",
        data=data,
        method="POST",
        headers={
            "Content-Type": "application/json",
            "apikey": PUBLISHABLE_KEY,
            "Cache-Control": "no-store",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=15) as response:
            if response.status != 200:
                raise WorkerError(f"Unexpected HTTP {response.status} from {function}.")
            body = response.read(MAX_RESPONSE_BYTES + 1)
            if len(body) > MAX_RESPONSE_BYTES:
                raise WorkerError("Gateway response unexpectedly large.")
            try:
                return json.loads(body.decode("utf-8"))
            except (ValueError, UnicodeDecodeError) as exc:
                raise WorkerError("Gateway returned invalid JSON.") from exc
    except urllib.error.HTTPError as exc:
        # Never show returned secrets or request bodies.
        raise WorkerError(f"{function} rejected the request (HTTP {exc.code}).") from exc
    except (urllib.error.URLError, TimeoutError) as exc:
        raise WorkerError(f"Could not reach {function}. Check network connection.") from exc


def self_test():
    sample = "00000000-0000-4000-8000-000000000000:" + "a" * 64
    assert parse_bundle(sample) == (sample[:36], "a" * 64)
    try:
        parse_bundle("not a pairing bundle")
    except WorkerError:
        pass
    else:
        raise AssertionError("Invalid bundle accepted")
    assert expires_epoch("2026-10-14T16:00:00+00:00") > 0
    print("PASS: Local format and expiration checks. No server request made.")


def main():
    parser = argparse.ArgumentParser(description="AI Stock Commons connection worker (pilot)")
    parser.add_argument("--self-test", action="store_true", help="Run offline checks without connecting")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return 0

    print("AI Stock Commons | Independent process connection test")
    print("This process is NOT an AI researcher and cannot submit or trade anything.")
    print("Keep owner permission OFF until you are ready to perform a controlled test.")
    print("1) Start this program; 2) enable permission in your browser;")
    print("3) create a fresh bundle on worker-enroll.html and paste it below within two minutes.")
    try:
        bundle = getpass.getpass("Paste one-time pairing bundle (input hidden), then Enter: ")
        session_id, secret = parse_bundle(bundle)
        bundle = ""  # No persistence. Python may hold copies until garbage collection.
        print("Connecting with the one-time bundle...")
        reply = post_function("agent-pair-complete", {"session_id": session_id, "pairing_secret": secret})
        secret = ""
        if reply.get("success") is not True or reply.get("status") != "connected" or reply.get("session_id") != session_id:
            raise WorkerError("Gateway did not confirm a connected session.")
        token = reply.get("worker_token")
        if not isinstance(token, str) or not re.fullmatch(r"[0-9a-f]{64}", token):
            raise WorkerError("Gateway did not return a valid worker credential.")
        deadline = expires_epoch(reply.get("lease_expires_at"))
        if deadline <= time.time():
            raise WorkerError("Connected lease already expired.")
        print("CONNECTED: This Python process (not your browser) has an active lease.")
        print("Sending heartbeat every 30 seconds. Stop with Ctrl+C; revoke permission in browser when done.")
        beats = 0
        while True:
            time.sleep(HEARTBEAT_EVERY_SECONDS)
            if time.time() >= deadline:
                raise WorkerError("Lease has expired. Stopping worker.")
            try:
                reply = post_function("agent-heartbeat", {"session_id": session_id, "worker_token": token})
                if reply.get("success") is not True or reply.get("status") != "connected" or reply.get("session_id") != session_id:
                    raise WorkerError("Heartbeat response failed validation.")
                renewed = expires_epoch(reply.get("lease_expires_at"))
                if renewed <= deadline or renewed <= time.time():
                    raise WorkerError("Heartbeat did not extend the lease.")
                deadline = renewed
                beats += 1
                print(f"HEARTBEAT {beats}: accepted; lease renewed.", flush=True)
            except WorkerError as exc:
                # If owner revoked: fail closed. Transient outage: retry once each 10s until lease ends.
                if "HTTP 403" in str(exc):
                    print("REVOKED/REJECTED: Worker stopping immediately.")
                    return 0
                print("Heartbeat not confirmed; will retry while current lease is valid.")
                if time.time() + 10 >= deadline:
                    raise WorkerError("Unable to renew before the lease expired.") from exc
                time.sleep(10)
                reply = post_function("agent-heartbeat", {"session_id": session_id, "worker_token": token})
                if reply.get("success") is not True or reply.get("session_id") != session_id:
                    raise WorkerError("Heartbeat retry rejected.")
                deadline_new = expires_epoch(reply.get("lease_expires_at"))
                if deadline_new <= deadline:
                    raise WorkerError("Heartbeat retry did not renew the lease.")
                deadline = deadline_new
                beats += 1
                print(f"HEARTBEAT {beats}: recovered; lease renewed.", flush=True)
    except KeyboardInterrupt:
        print("\nSTOPPED. Server lease will expire; revoke permission to close immediately.")
        return 0
    except WorkerError as exc:
        print(f"STOPPED: {exc}", file=sys.stderr)
        print("Revoke owner permission in the browser to close any remaining session.", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
