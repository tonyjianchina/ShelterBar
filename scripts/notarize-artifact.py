#!/usr/bin/env python3
"""Submit once using the existing profile; persist only sanitized diagnostics."""

import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys


PROFILE = "shelterbar-notary"
UUID = r"[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}"
STATUSES = {"Accepted", "Invalid", "Rejected", "In Progress"}
LOG_FIELDS = {
    "logFormatVersion", "jobId", "status", "statusCode", "statusSummary",
    "archiveFilename", "uploadDate", "sha256", "ticketContents", "issues",
    "severity", "code", "path", "message", "docUrl", "architecture",
    "cdhash", "digestAlgorithm",
}


def sanitize(value, submission_id):
    if isinstance(value, dict):
        return {k: sanitize(v, submission_id) for k, v in value.items() if k in LOG_FIELDS}
    if isinstance(value, list):
        return [sanitize(v, submission_id) for v in value]
    if isinstance(value, str):
        value = re.sub(r"-----BEGIN .*?-----.*?-----END .*?-----", "[redacted]", value, flags=re.S)
        value = re.sub(r"\beyJ[\w-]+\.[\w-]+\.[\w-]+\b", "[redacted]", value)
        value = re.sub(r"\b[A-Z0-9]{10}\b", lambda m: m[0] if m[0] == "5UKPG93ACW" else "[redacted]", value)
        value = re.sub(UUID, lambda m: m[0] if m[0] == submission_id else "[redacted]", value)
        value = re.sub(r"(?:\S*/)?[^\s/]*\.p8\b", "[redacted]", value)
        value = re.sub(r"(https?://[^\s?]+)\?[^\s]+", r"\1?[redacted]", value)
    return value


def invoke(arguments):
    # Raw stdout/stderr never reach the terminal, repository, or outbox.
    result = subprocess.run(
        ["xcrun", "notarytool", *arguments, "--keychain-profile", PROFILE],
        stdin=subprocess.DEVNULL, capture_output=True, text=True,
    )
    try:
        payload = json.loads(result.stdout)
    except (ValueError, TypeError):
        payload = {}
    return result.returncode, payload


def main():
    if len(sys.argv) != 3:
        sys.exit("Usage: notarize-artifact.py <archive> <diagnostics-directory>")
    archive, output = map(Path, sys.argv[1:])
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    output.mkdir(parents=True, exist_ok=True)
    receipt = output / "submission.json"
    previous = json.loads(receipt.read_text()) if receipt.exists() else {}
    submission_id = previous.get("id", "")
    if re.fullmatch(UUID, submission_id) and previous.get("sha256") == digest:
        if previous.get("status") in {"Invalid", "Rejected"}:
            sys.exit("Previous submission was rejected; inspect the sanitized log. No resubmission made.")
        if previous.get("status") == "Accepted":
            print(f"Notarization already Accepted: {archive.name} ({submission_id})", flush=True)
            return
        arguments = ["wait", submission_id, "--output-format", "json", "--timeout", "10m"]
    else:
        if previous:
            sys.exit("A different submission already exists in this diagnostics directory; stopping.")
        arguments = ["submit", str(archive), "--wait", "--output-format", "json", "--timeout", "10m"]
    print(f"Waiting for Apple notarization: {archive.name}", flush=True)
    code, result = invoke(arguments)
    candidate_id = result.get("id", submission_id)
    submission_id = candidate_id if isinstance(candidate_id, str) and re.fullmatch(UUID, candidate_id) else ""
    status = result.get("status")
    status = status if status in STATUSES else "Unknown"
    safe_result = {"id": submission_id, "status": status, "sha256": digest, "exit_code": code}
    receipt.write_text(json.dumps(safe_result, indent=2) + "\n")
    if submission_id and status in {"Accepted", "Invalid", "Rejected"}:
        log_code, log = invoke(["log", submission_id])
        (output / "notary-log.json").write_text(json.dumps(
            sanitize(log, submission_id) if log_code == 0 else {"log_unavailable": True}, indent=2,
        ) + "\n")
    print(f"Notarization status: {status}; submission: {submission_id or 'unavailable'}", flush=True)
    if code or status != "Accepted":
        sys.exit("Notarization did not complete successfully. Stopping without resubmission; raw responses suppressed.")


if __name__ == "__main__":
    main()
