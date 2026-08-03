#!/usr/bin/env python3
"""Merge all WL/EU pool JSON archives into one L3 master target list."""

from __future__ import annotations

import argparse
import json
import os
from datetime import datetime, timezone
from glob import glob


def is_valid_host(host: str) -> bool:
    host = host.strip()
    if not host or len(host) > 253:
        return False
    lower = host.lower()
    if lower in {"0.0.0.0", "localhost"} or lower.startswith("127."):
        return False
    if " " in host or "\n" in host:
        return False
    return True


def parse_pool(path: str) -> list[dict]:
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except Exception:
        return []

    tags = data.get("tags")
    outbounds = data.get("outbounds") or []
    pairs: list[tuple[str, dict]] = []
    if tags and outbounds and len(tags) == len(outbounds):
        pairs = list(zip(tags, outbounds))
    else:
        for ob in outbounds:
            if isinstance(ob, dict) and ob.get("tag"):
                pairs.append((ob["tag"], ob))

    source = "eu" if "eu_pool" in path.lower() else "wl"
    rows: list[dict] = []
    for tag, ob in pairs:
        if not isinstance(ob, dict):
            continue
        host = ob.get("server")
        if not host:
            continue
        host = str(host).strip()
        if not is_valid_host(host):
            continue
        port = ob.get("server_port", 443)
        try:
            port = int(port)
        except Exception:
            port = 443
        if port <= 0 or port > 65535:
            continue
        rows.append(
            {
                "tag": str(tag),
                "host": host,
                "port": port,
                "source": source,
                "from": os.path.basename(path),
            }
        )
    return rows


def collect_files(roots: list[str]) -> list[str]:
    found: set[str] = set()
    for root in roots:
        if not os.path.isdir(root):
            continue
        for dirpath, _, filenames in os.walk(root):
            if "/.git/" in dirpath:
                continue
            for name in filenames:
                lower = name.lower()
                if not lower.endswith(".json"):
                    continue
                if "wl_pool" in lower or "eu_pool" in lower:
                    found.add(os.path.join(dirpath, name))
    return sorted(found)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--roots",
        nargs="*",
        default=["/opt/vpn-master", "/root"],
        help="directories to scan recursively",
    )
    parser.add_argument(
        "-o",
        "--output",
        default="/opt/vpn-master/data/l3_master_targets.json",
    )
    args = parser.parse_args()

    files = collect_files(args.roots)
    by_tag: dict[str, dict] = {}
    for path in files:
        for row in parse_pool(path):
            by_tag.setdefault(row["tag"], row)

    targets = list(by_tag.values())
    hosts = sorted({t["host"].lower() for t in targets})

    payload = {
        "version": 1,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "source_files": len(files),
        "target_count": len(targets),
        "unique_hosts": len(hosts),
        "unique_host_ports": len({(t["host"].lower(), t["port"]) for t in targets}),
        "hosts": [{"host": h} for h in hosts],
        "targets": targets,
    }

    os.makedirs(os.path.dirname(args.output), exist_ok=True)
    with open(args.output, "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False)

    print(json.dumps({k: payload[k] if k != "hosts" else len(payload["hosts"]) for k in payload}, indent=2))
    print("written", args.output, "bytes", os.path.getsize(args.output))


if __name__ == "__main__":
    main()
