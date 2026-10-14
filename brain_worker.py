#!/usr/bin/env python3
"""AI Stock Commons: independent worker + ONE human-triggered AI research draft.

Reuses the already tested worker.py secure pairing/heartbeat helpers.
Never submits research or trades. Fail closed on revoked credentials.
"""
import argparse
from datetime import datetime, timezone
import getpass
import os
from pathlib import Path
import queue
import re
import sys
import tempfile
import threading
import time

from worker import WorkerError, expires_epoch, parse_bundle, post_function, self_test as connection_self_test
from research_brain import ResearchError, check_ticker, report_text, research_once, self_test as brain_self_test

HEARTBEAT_SECONDS = 30


def heartbeat(session_id, token, deadline):
    """Verify server authorization again and renew a live lease."""
    reply = post_function("agent-heartbeat", {"session_id": session_id, "worker_token": token})
    if (reply.get("success") is not True or reply.get("status") != "connected"
        or reply.get("session_id") != session_id):
        raise WorkerError("Heartbeat was not confirmed.")
    new_deadline = expires_epoch(reply.get("lease_expires_at"))
    if new_deadline <= deadline or new_deadline <= time.time():
        raise WorkerError("Heartbeat did not extend the session lease.")
    return new_deadline


def save_local_draft(draft):
    """Private ephemeral disk location OUTSIDE the public GitHub repository."""
    folder = Path(tempfile.gettempdir()) / "ai_stock_commons_private_drafts"
    folder.mkdir(mode=0o700, exist_ok=True)
    folder.chmod(0o700)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    path = folder / f"{draft.ticker}_{stamp}.md"
    fd = os.open(str(path), os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write(report_text(draft))
    return path


def start_research(ticker, results):
    """Background thread allows heartbeats during a slow API request."""
    def run():
        try:
            results.put((True, research_once(ticker)))
        except (ResearchError, Exception) as exc:
            # Do not log exception text from unknown libraries / providers.
            results.put((False, type(exc).__name__))
    task = threading.Thread(target=run, name="one_research_request", daemon=True)
    task.start()


def main():
    parser = argparse.ArgumentParser(description="AI Stock Commons controlled independent research pilot")
    parser.add_argument("--self-test", action="store_true", help="Offline format/security tests")
    parser.add_argument("--ticker", default="RKLB", help="Explicit research ticker (default RKLB)")
    args = parser.parse_args()
    if args.self_test:
        connection_self_test()
        brain_self_test()
        return 0

    ticker = check_ticker(args.ticker)
    if not os.environ.get("OPENAI_API_KEY", "").strip():
        print("STOPPED: OPENAI_API_KEY missing. Add it as a Codespaces secret; never paste into chat or GitHub code.")
        return 2

    print("AI Stock Commons | Independent research pilot V0.2")
    print(f"ONE DRAFT for {ticker}. Uses paid model API and web search; no automatic repeats.")
    print("Research is NOT published; NO trading or external assignments are enabled.")
    print("Keep permission OFF until you are ready. Stop anytime: Ctrl+C + revoke in browser.")
    print("Start worker; enable permission; create a fresh bundle at worker-enroll.html.")

    try:
        bundle = getpass.getpass("Paste one-time pairing bundle (hidden), then Enter: ")
        session_id, secret = parse_bundle(bundle)
        bundle = ""
        response = post_function("agent-pair-complete", {"session_id": session_id, "pairing_secret": secret})
        secret = ""
        if (response.get("success") is not True or response.get("status") != "connected"
            or response.get("session_id") != session_id):
            raise WorkerError("Pairing gateway did not confirm connection.")
        token = response.get("worker_token")
        if not isinstance(token, str) or not re.fullmatch(r"[0-9a-f]{64}", token):
            raise WorkerError("Pairing gateway returned an invalid worker credential.")
        deadline = expires_epoch(response.get("lease_expires_at"))
        if deadline <= time.time():
            raise WorkerError("Connected lease expired.")
        print("CONNECTED: independent Python process. Waiting for first verified heartbeat.", flush=True)
        beats = 0
        work_started = False
        finished = False
        result_queue = queue.Queue(maxsize=1)
        next_beat = time.monotonic() + HEARTBEAT_SECONDS

        while True:
            # Fail closed when the worker's local lease is expired.
            if time.time() >= deadline:
                raise WorkerError("Lease expired; stopping immediately.")

            if work_started and not finished:
                try:
                    success, result = result_queue.get_nowait()
                except queue.Empty:
                    pass
                else:
                    # Verify still authorized BEFORE any local output or draft write.
                    try:
                        deadline = heartbeat(session_id, token, deadline)
                    except WorkerError:
                        print("REVOKED/REJECTED: result discarded; stopping worker.")
                        return 0
                    finished = True
                    if success:
                        path = save_local_draft(result)
                        print(f"DRAFT READY (private; NOT published): {path}", flush=True)
                        print(f"Source URLs in API response: {len(result.citations)}", flush=True)
                        print("Requires human fact checking. Leave running only until you revoke permission.", flush=True)
                    else:
                        print("RESEARCH FAILED (no draft saved). Revoke permission and retry later if desired.")

            if time.monotonic() >= next_beat:
                try:
                    deadline = heartbeat(session_id, token, deadline)
                except WorkerError as exc:
                    if "HTTP 403" in str(exc):
                        print("REVOKED/REJECTED: worker stopping immediately. Draft will not be published.")
                        return 0
                    # Fail closed after unexpected outage; no background work continues.
                    raise WorkerError("Heartbeat not confirmed; stop and revoke permission.") from exc
                beats += 1
                print(f"HEARTBEAT {beats}: accepted; lease renewed.", flush=True)
                if not work_started:
                    work_started = True
                    print(f"Starting ONE source-backed AI research request for {ticker}...", flush=True)
                    start_research(ticker, result_queue)
                next_beat = time.monotonic() + HEARTBEAT_SECONDS
            time.sleep(0.5)

    except KeyboardInterrupt:
        print("\nSTOPPED: manually revoke owner permission now to close server session.")
        return 0
    except (WorkerError, ResearchError) as exc:
        print(f"STOPPED: {exc}", file=sys.stderr)
        print("Revoke permission in the browser and verify owner permission OFF.", file=sys.stderr)
        return 1

if __name__ == "__main__":
    sys.exit(main())
