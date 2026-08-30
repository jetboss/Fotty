import json
import os
import time

import requests

URL = "https://p2p.pixel-invoice.com/proxy/acestream/session/3f57b5917b8a4f2ba220d85342d6be2e/manifest.m3u8"
API_PASSWORD = os.getenv("P2P_API_PASSWORD", "").strip()
if not API_PASSWORD:
    raise SystemExit("Set P2P_API_PASSWORD before running monitor_manifest_v2.py")


def monitor():
    headers = {"api-password": API_PASSWORD}
    last_seq = -1
    while True:
        try:
            resp = requests.get(URL, headers=headers, timeout=5)
            if resp.status_code == 200:
                content = resp.text
                lines = content.splitlines()
                seq = -1
                for line in lines:
                    if "EXT-X-MEDIA-SEQUENCE" in line:
                        seq = int(line.split(":")[1])

                print(f"[{time.strftime('%H:%M:%S')}] Status: 200 | Sequence: {seq}")
                if seq == last_seq:
                    print("!!! SEQUENCE FROZEN !!!")
                last_seq = seq
            else:
                print(f"[{time.strftime('%H:%M:%S')}] Status: {resp.status_code}")
        except Exception as e:
            print(f"Error: {e}")

        time.sleep(5)


if __name__ == "__main__":
    monitor()
