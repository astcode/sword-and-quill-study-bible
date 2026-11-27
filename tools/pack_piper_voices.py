#!/usr/bin/env python3
"""
Packages fast Piper/VITS ONNX neural voices (Ryan US Male, Lessac US Female) + Apache-2.0 lexicon
into chunked raw-deflate (.sqz) files (<30 MB each) for 100% offline iPad download
from https://swordandquillbible.com/modules/voices/<pack-id>/.
"""
import json
import os
import zlib

LEX_PATH = "/tmp/vits-test/lexicon-en-us.txt"

PACKS = [
    {
        "id": "piper-ryan-en",
        "title": "Ryan · Fast Neural Narrator (US Male)",
        "src_dir": "/tmp/vits-test/vits-piper-en_US-ryan-medium",
        "onnx": "en_US-ryan-medium.onnx",
    },
    {
        "id": "piper-lessac-en",
        "title": "Lessac · Fast Neural Narrator (US Female)",
        "src_dir": "/tmp/vits-test/vits-piper-en_US-lessac-medium",
        "onnx": "en_US-lessac-medium.onnx",
    },
]


def compress_raw(data: bytes) -> bytes:
    c = zlib.compressobj(level=6, method=zlib.DEFLATED, wbits=-15)
    return c.compress(data) + c.flush()


def pack_one(spec):
    out_dir = f"/tmp/vits-test/out/{spec['id']}"
    os.makedirs(out_dir, exist_ok=True)
    files = []

    with open(os.path.join(spec["src_dir"], spec["onnx"]), "rb") as f:
        model_bytes = f.read()

    # Split into 2 parts (~27 MB each, well under GitHub 50 MB warning)
    n_parts = 2
    chunk_sz = (len(model_bytes) + n_parts - 1) // n_parts
    for i in range(n_parts):
        chunk = model_bytes[i * chunk_sz : (i + 1) * chunk_sz]
        comp = compress_raw(chunk)
        fname = f"model.part{i}.sqz"
        with open(os.path.join(out_dir, fname), "wb") as out:
            out.write(comp)
        files.append({
            "file": fname,
            "target": "model.onnx",
            "append": i > 0,
            "rawSize": len(chunk),
            "compressedSize": len(comp),
        })

    for target, path in [
        ("tokens.txt", os.path.join(spec["src_dir"], "tokens.txt")),
        ("lexicon-en-us.txt", LEX_PATH),
    ]:
        with open(path, "rb") as f:
            raw = f.read()
        comp = compress_raw(raw)
        fname = target + ".sqz"
        with open(os.path.join(out_dir, fname), "wb") as out:
            out.write(comp)
        files.append({
            "file": fname,
            "target": target,
            "append": False,
            "rawSize": len(raw),
            "compressedSize": len(comp),
        })

    manifest = {
        "id": spec["id"],
        "title": spec["title"],
        "version": 1,
        "totalDownloadBytes": sum(f["compressedSize"] for f in files),
        "totalDiskBytes": sum(f["rawSize"] for f in files),
        "files": files,
    }
    with open(os.path.join(out_dir, "manifest.json"), "w", encoding="utf-8") as out:
        json.dump(manifest, out, indent=2)

    print(
        f"{spec['id']}: download={manifest['totalDownloadBytes']/1e6:.2f} MB | "
        f"disk={manifest['totalDiskBytes']/1e6:.2f} MB"
    )


def main():
    for spec in PACKS:
        pack_one(spec)


if __name__ == "__main__":
    main()
