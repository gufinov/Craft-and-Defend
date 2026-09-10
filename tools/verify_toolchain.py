"""Offline verification of already-downloaded candidate archives. No installation."""
import argparse
import hashlib
import json
from pathlib import Path


def verify_archive(path, expected_size, expected_sha):
    if not path.is_file():
        raise ValueError(f"missing archive: {path.name}")
    if path.stat().st_size != expected_size:
        raise ValueError(f"size mismatch: {path.name}")
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    if digest.hexdigest() != expected_sha:
        raise ValueError(f"SHA-256 mismatch: {path.name}")
    return digest.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive-dir", type=Path, required=True)
    args = parser.parse_args()
    manifest = json.loads((Path(__file__).parent / "versions.json").read_text(encoding="utf-8"))
    errors = []
    for asset in manifest["assets"]:
        try:
            sha = verify_archive(args.archive_dir / asset["name"], asset["size_bytes"], asset["sha256"])
            print(f"PASS: {asset['name']} {sha}")
        except (ValueError, OSError) as exc:
            errors.append(str(exc))
    for error in errors:
        print(f"FAIL: {error}")
    print("Archive verification only; editor execution and Windows export remain separate gates.")
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
