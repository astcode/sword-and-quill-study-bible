#!/usr/bin/env python3
"""
Packages Kokoro-82M int8 ONNX English model + 11 voices + Apache-2.0 US English lexicon
into chunked raw-deflate (.sqz) files (<35 MB each) for 100% offline iPad download
from https://swordandquillbible.com/modules/voices/kokoro-en-v0_19/.
"""
import json
import os
import sys
import zlib

SRC_DIR = sys.argv[1] if len(sys.argv) > 1 else "/tmp/sherpa-test/kokoro-int8-en-v0_19"
LEX_PATH = sys.argv[2] if len(sys.argv) > 2 else "/tmp/sherpa-test/lexicon-en-us.txt"
OUT_DIR = sys.argv[3] if len(sys.argv) > 3 else "/tmp/sherpa-test/kokoro-pack"


def compress_raw(data: bytes) -> bytes:
    c = zlib.compressobj(level=6, method=zlib.DEFLATED, wbits=-15)
    return c.compress(data) + c.flush()


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    files = []

    model_path = os.path.join(SRC_DIR, "model.int8.onnx")
    with open(model_path, "rb") as f:
        model_bytes = f.read()

    # Split model.int8.onnx into 3 raw-deflated parts (~31 MB each, well under GitHub 50 MB warning)
    n_parts = 3
    chunk_sz = (len(model_bytes) + n_parts - 1) // n_parts
    for i in range(n_parts):
        chunk = model_bytes[i * chunk_sz : (i + 1) * chunk_sz]
        comp = compress_raw(chunk)
        fname = f"model.part{i}.sqz"
        with open(os.path.join(OUT_DIR, fname), "wb") as out:
            out.write(comp)
        files.append({
            "file": fname,
            "target": "model.int8.onnx",
            "append": i > 0,
            "rawSize": len(chunk),
            "compressedSize": len(comp),
        })
        print(f"  {fname}: raw={len(chunk)/1e6:.2f} MB -> comp={len(comp)/1e6:.2f} MB")

    for target, path in [
        ("voices.bin", os.path.join(SRC_DIR, "voices.bin")),
        ("tokens.txt", os.path.join(SRC_DIR, "tokens.txt")),
        ("lexicon-en-us.txt", LEX_PATH),
    ]:
        with open(path, "rb") as f:
            raw = f.read()
        comp = compress_raw(raw)
        fname = target + ".sqz"
        with open(os.path.join(OUT_DIR, fname), "wb") as out:
            out.write(comp)
        files.append({
            "file": fname,
            "target": target,
            "append": False,
            "rawSize": len(raw),
            "compressedSize": len(comp),
        })
        print(f"  {fname}: raw={len(raw)/1e6:.2f} MB -> comp={len(comp)/1e6:.2f} MB")

    manifest = {
        "id": "kokoro-en-v0_19",
        "title": "Kokoro-82M Studio Neural Voices",
        "version": 1,
        "totalDownloadBytes": sum(f["compressedSize"] for f in files),
        "totalDiskBytes": sum(f["rawSize"] for f in files),
        "files": files,
    }
    with open(os.path.join(OUT_DIR, "manifest.json"), "w", encoding="utf-8") as out:
        json.dump(manifest, out, indent=2)

    print(
        f"Done! Total download: {manifest['totalDownloadBytes']/1e6:.2f} MB | "
        f"On-disk: {manifest['totalDiskBytes']/1e6:.2f} MB -> {OUT_DIR}"
    )


if __name__ == "__main__":
    main()
