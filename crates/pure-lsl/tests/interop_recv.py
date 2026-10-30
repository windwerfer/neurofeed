"""Test-only receiver: resolve a stream by name with pylsl (liblsl) and
print what arrived as JSON. Usage: interop_recv.py NAME N_SAMPLES"""
import json, sys
import pylsl

name, n = sys.argv[1], int(sys.argv[2])
found = pylsl.resolve_byprop("name", name, timeout=5.0)
if not found:
    print(json.dumps({"error": "not found"}))
    sys.exit(1)
inlet = pylsl.StreamInlet(found[0], max_buflen=60)
info = inlet.info(timeout=5.0)
labels, ch = [], info.desc().child("channels").child("channel")
while not ch.empty():
    labels.append(ch.child_value("label"))
    ch = ch.next_sibling()
print("READY", flush=True)
samples, stamps = [], []
while len(samples) < n:
    s, t = inlet.pull_sample(timeout=5.0)
    if s is None:
        break
    samples.append(s)
    stamps.append(t)
print(json.dumps({
    "name": info.name(), "type": info.type(), "channels": info.channel_count(),
    "srate": info.nominal_srate(), "format": info.channel_format(), "uid": info.uid(),
    "hostname": info.hostname(), "labels": labels, "samples": samples, "stamps": stamps,
    "offset": inlet.time_correction(timeout=5.0), "now": pylsl.local_clock(),
}), flush=True)
