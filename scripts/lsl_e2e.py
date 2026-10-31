"""End-to-end LSL check (test tool, needs pylsl): start neurofeed-mcp with the
simulated Muse, enable LSL streaming, receive EEG with real liblsl.
Usage: python scripts/lsl_e2e.py target/release/neurofeed-mcp"""
import json, subprocess, sys, threading, time
import pylsl

proc = subprocess.Popen([sys.argv[1], "--no-hardware"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
rid = 0
def rpc(method, params=None, notify=False):
    global rid
    msg = {"jsonrpc": "2.0", "method": method}
    if params is not None: msg["params"] = params
    if not notify:
        rid += 1; msg["id"] = rid
    proc.stdin.write(json.dumps(msg) + "\n"); proc.stdin.flush()
    if notify: return None
    return json.loads(proc.stdout.readline())
def run(cmd, params=None):
    r = rpc("tools/call", {"name": "command_run", "arguments": {"id": cmd, "params": params}})
    return json.loads(r["result"]["content"][0]["text"])

rpc("initialize", {"protocolVersion": "2024-11-05", "capabilities": {}, "clientInfo": {"name": "e2e", "version": "0"}})
rpc("notifications/initialized", notify=True)
run("streaming.set", {"enabled": True, "protocol": "lsl", "separate_groups": True})
stop = False
def pump():
    while not stop:
        run("streaming.status"); time.sleep(0.05)
threading.Thread(target=pump, daemon=True).start()
streams = pylsl.resolve_byprop("source_id", "neurofeed:sim:muse_s:eeg", timeout=5)
print("resolved:", [(s.name(), s.type(), s.channel_count(), s.nominal_srate()) for s in pylsl.resolve_streams(2.0)])
inlet = pylsl.StreamInlet(streams[0])
labels, ch = [], inlet.info().desc().child("channels").child("channel")
while not ch.empty():
    labels.append(ch.child_value("label")); ch = ch.next_sibling()
inlet.pull_chunk(timeout=1.0)
time.sleep(2.0)
data, ts = inlet.pull_chunk(timeout=1.0, max_samples=100000)
rate = (len(ts) - 1) / (ts[-1] - ts[0]) if len(ts) > 1 else 0
st = None
stop = True; time.sleep(0.1)
print(json.dumps({"labels": labels, "samples": len(data), "rate_from_stamps": round(rate, 1), "first": data[0] if data else None, "offset": inlet.time_correction(), "status_consumers": run("streaming.status")["stats"]["lsl_consumers"]}))
proc.terminate()
