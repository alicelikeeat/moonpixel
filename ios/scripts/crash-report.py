#!/usr/bin/env python3
"""Print the newest MoonPixel crash reports (.ips) in a readable form: the exception and the crashed
thread's frames with their symbols and source lines. Used by CI after the UI tests."""
import glob, json, os, sys

paths = sorted(glob.glob(os.path.expanduser("~/Library/Logs/DiagnosticReports/MoonPixel*.ips")), key=os.path.getmtime, reverse=True)[:2]
if not paths:
    print("no crash reports")
for p in paths:
    print("===== crash report", os.path.basename(p))
    try:
        text = open(p, errors="replace").read()
        body = json.loads(text[text.index("\n") + 1:])
        ex = body.get("exception", {})
        print("exception:", ex.get("type"), ex.get("signal"), ex.get("subtype", ""), body.get("termination", {}).get("indicator", ""))
        for t in body.get("threads", []):
            if not t.get("triggered"):
                continue
            images = body.get("usedImages", [])
            for i, f in enumerate(t.get("frames", [])[:40]):
                img = images[f.get("imageIndex", 0)].get("name", "?") if f.get("imageIndex", -1) < len(images) else "?"
                print(f"  #{i:02d} {img:24.24} {f.get('symbol', '?')}  {f.get('sourceFile', '')}:{f.get('sourceLine', '')}")
    except Exception as e:
        print("could not read:", e)
        print(open(p, errors="replace").read()[:4000])
