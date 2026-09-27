#!/usr/bin/env python3
"""Simulated Neurosity Crown OSC stream (Python 3, stdlib only).

Reproduces the wire format of Neurosity's own simulator
(github.com/neurosity/notion-osc-server, "brainflow" data format):

  * UDP from local port 8000 to port 9000, broadcast enabled, sent to the
    subnet broadcast address (fallback 255.255.255.255) unless --target is set.
  * Every 1 s:  /neurosity/notion/{id}/info
                s id, s nickname, s "Crown 3", s "Crown", s "3",
                s "Neurosity, Inc", i 256, i 8, s "CP3,C3,F5,PO3,PO4,F6,C4,CP4"
  * Per sample: /neurosity/notion/{id}/raw
                [ffffffff] 8 channels in uV, s timestamp (seconds), i count
                (sample index % 256), s marker ("")
  * --quality:  /crown{id}/signalQuality at 4 Hz, 8 floats in 0..1 (one per
                pad; good ~0.9, --bad-pads ~0.1). --quality-overall sends one
                float instead, which the app ignores for pad quality. Neither
                is sent by Neurosity's simulator; the Neurosity OSC docs only
                show a single float at this address, so the real per-channel
                address/format is unverified.

The default signal is NeuroFeed's in-app simulator model
(rust/src/api/simulator.rs): ~10 uV 10 Hz alpha with a per-channel phase plus
sub-uV hash noise, at 256 Hz. --noise switches to Neurosity's uniform
-50..50 uV noise.

--epoch N packs N samples per /raw packet (8*N floats; Neurosity's docs
describe 16-sample epochs for the Crown), sample-major (ch0_s0, ch1_s0, ...)
unless --channel-major (ch0_s0, ch0_s1, ...).

--dropout EVERY:SECONDS stops /raw for SECONDS once every EVERY seconds while
/info keeps going (the Crown stays visible on the network; samples in the
gap are lost, the sample clock keeps running).

Usage, from any computer on the same LAN as the app:
  python3 tools/crown_osc_sim.py
  python3 tools/crown_osc_sim.py --target 192.168.1.42        # unicast
  python3 tools/crown_osc_sim.py --bad-pads 3,5 --line-noise 50 --quality
  python3 tools/crown_osc_sim.py --quality-overall                # app fallback
  python3 tools/crown_osc_sim.py --dropout 10:3 --duration 60
  python3 tools/crown_osc_sim.py --epoch 16 --channel-major
"""
import argparse
import math
import random
import re
import socket
import struct
import subprocess
import sys
import time

MODEL_NAME = "Crown"
MODEL_VERSION = "3"
MANUFACTURER = "Neurosity, Inc"
CHANNEL_NAMES = "CP3,C3,F5,PO3,PO4,F6,C4,CP4"
CHANNELS = 8
SAMPLE_RATE = 256
LOCAL_PORT = 8000
DEFAULT_ID = "local7cca794fb5f4675a69371e949b2"
LINE_NOISE_UV = 10.0
BAD_NOISE_UV = 150.0
GOOD_QUALITY = (0.85, 0.95)
BAD_QUALITY = (0.05, 0.15)
TICK_S = 0.004


def osc_string(s):
    raw = s.encode("utf-8") + b"\0"
    return raw + b"\0" * (-len(raw) % 4)


def osc_message(address, args):
    tags, data = [","], []

    def add(arg):
        if isinstance(arg, list):
            tags.append("[")
            for item in arg:
                add(item)
            tags.append("]")
        elif isinstance(arg, float):
            tags.append("f")
            data.append(struct.pack(">f", arg))
        elif isinstance(arg, int):
            tags.append("i")
            data.append(struct.pack(">i", arg))
        elif isinstance(arg, str):
            tags.append("s")
            data.append(osc_string(arg))
        else:
            raise TypeError(f"unsupported OSC arg {arg!r}")

    for arg in args:
        add(arg)
    return osc_string(address) + osc_string("".join(tags)) + b"".join(data)


def local_ipv4():
    probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        probe.connect(("10.255.255.255", 1))
        return probe.getsockname()[0]
    except OSError:
        return None
    finally:
        probe.close()


def subnet_broadcast():
    ip = local_ipv4()
    if not ip:
        return "255.255.255.255"
    for cmd in (["ip", "-o", "-4", "addr", "show"], ["ifconfig"]):
        try:
            out = subprocess.run(cmd, capture_output=True, text=True, timeout=2).stdout
        except (OSError, subprocess.SubprocessError):
            continue
        for line in out.splitlines():
            if re.search(rf"inet (addr:)?{re.escape(ip)}\b", line):
                m = re.search(r"(?:brd|broadcast|Bcast:)\s*(\d+\.\d+\.\d+\.\d+)", line)
                if m:
                    return m.group(1)
        if out:
            break
    return "255.255.255.255"


def app_sample(t, ch):
    phi = ch * math.pi / 2.5
    alpha = 10.0 * math.sin(2.0 * math.pi * 10.0 * t + phi)
    nx = t * 1000.7 + ch * 137.508
    noise = (math.fmod(math.sin(nx) * 9973.1, 1.0) - 0.5) * 0.8
    return alpha + noise


def neurosity_noise():
    return math.floor(random.random() * 101) - 50 + round(random.random(), 6)


def parse_dropout(text):
    try:
        every, length = (float(x) for x in text.split(":"))
    except ValueError:
        raise argparse.ArgumentTypeError("expected EVERY:SECONDS, e.g. 10:3")
    if every <= 0 or length <= 0 or length >= every:
        raise argparse.ArgumentTypeError("need 0 < SECONDS < EVERY")
    return every, length


def parse_pads(text):
    pads = {int(x) for x in text.split(",") if x.strip()}
    if not pads <= set(range(CHANNELS)):
        raise argparse.ArgumentTypeError(f"pads are 0..{CHANNELS - 1}")
    return pads


def build_args(argv):
    p = argparse.ArgumentParser(description="Simulated Neurosity Crown OSC stream.")
    p.add_argument("--target", help="unicast IP (default: subnet broadcast)")
    p.add_argument("--port", type=int, default=9000, help="remote port (default 9000)")
    p.add_argument("--device-id", default=DEFAULT_ID)
    p.add_argument("--nickname", help="default: Crown-<first 3 id chars upper>")
    p.add_argument("--noise", action="store_true", help="Neurosity's uniform -50..50 uV noise")
    p.add_argument("--bad-pads", type=parse_pads, default=set(), metavar="3,5",
                   help="channel indices (0=CP3..7=CP4) to corrupt")
    p.add_argument("--bad-mode", choices=("noise", "flat"), default="noise",
                   help=f"bad pads: {BAD_NOISE_UV:.0f} uV gaussian noise or flat 0 uV")
    p.add_argument("--dropout", type=parse_dropout, metavar="EVERY:SECONDS")
    p.add_argument("--line-noise", type=int, choices=(50, 60),
                   help=f"add {LINE_NOISE_UV:.0f} uV mains hum")
    quality = p.add_mutually_exclusive_group()
    quality.add_argument("--quality", action="store_const", const="channels", dest="quality",
                         help="send per-pad /crown{id}/signalQuality (8 floats, 0..1) at 4 Hz")
    quality.add_argument("--quality-overall", action="store_const", const="overall",
                         dest="quality",
                         help="send one overall /crown{id}/signalQuality float at 4 Hz")
    p.add_argument("--epoch", type=int, default=1, metavar="N",
                   help="samples per /raw packet (default 1)")
    p.add_argument("--channel-major", action="store_true",
                   help="with --epoch: all of ch0, then ch1, ... (default sample-major)")
    p.add_argument("--duration", type=float, help="seconds to run (default: forever)")
    return p.parse_args(argv)


class Crown:
    def __init__(self, args):
        self.args = args
        self.nickname = args.nickname or f"{MODEL_NAME}-{args.device_id[:3].upper()}"
        self.base = f"/neurosity/notion/{args.device_id}"
        self.info = osc_message(f"{self.base}/info", [
            args.device_id, self.nickname, f"{MODEL_NAME} {MODEL_VERSION}", MODEL_NAME,
            MODEL_VERSION, MANUFACTURER, SAMPLE_RATE, CHANNELS, CHANNEL_NAMES])

    def sample(self, n):
        t = n / SAMPLE_RATE
        out = []
        for ch in range(CHANNELS):
            if ch in self.args.bad_pads:
                out.append(0.0 if self.args.bad_mode == "flat" else random.gauss(0.0, BAD_NOISE_UV))
                continue
            v = neurosity_noise() if self.args.noise else app_sample(t, ch)
            if self.args.line_noise:
                v += LINE_NOISE_UV * math.sin(2.0 * math.pi * self.args.line_noise * t)
            out.append(v)
        return out

    def raw(self, n, start_ms):
        timestamp = repr((start_ms + n * 1000.0 / SAMPLE_RATE) / 1000.0)
        frames = [self.sample(n + i) for i in range(self.args.epoch)]
        if self.args.channel_major:
            floats = [f[ch] for ch in range(CHANNELS) for f in frames]
        else:
            floats = [v for f in frames for v in f]
        return osc_message(f"{self.base}/raw", [floats, timestamp, n % SAMPLE_RATE, ""])

    def quality(self):
        per_channel = [random.uniform(*(BAD_QUALITY if ch in self.args.bad_pads else GOOD_QUALITY))
                       for ch in range(CHANNELS)]
        payload = per_channel if self.args.quality == "channels" else [sum(per_channel) / CHANNELS]
        return osc_message(f"/crown{self.args.device_id}/signalQuality", payload)

    def in_dropout(self, elapsed):
        if not self.args.dropout:
            return False
        every, length = self.args.dropout
        return elapsed % every >= every - length


def main(argv=None):
    args = build_args(argv)
    crown = Crown(args)
    target = args.target or subnet_broadcast()
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    sock.bind(("0.0.0.0", LOCAL_PORT))
    dest = (target, args.port)
    print(f"crown_osc_sim: {target}:{args.port} from :{LOCAL_PORT} id={args.device_id} "
          f"nickname={crown.nickname} signal={'noise' if args.noise else 'app-model'}", flush=True)

    start = time.monotonic()
    start_ms = time.time() * 1000.0
    sent_samples = 0
    next_info = next_quality = next_report = 0.0
    window = {"raw": 0, "info": 0, "quality": 0}
    try:
        while True:
            elapsed = time.monotonic() - start
            if args.duration is not None and elapsed >= args.duration:
                break
            if elapsed >= next_info:
                sock.sendto(crown.info, dest)
                window["info"] += 1
                next_info += 1.0
            if args.quality and elapsed >= next_quality:
                sock.sendto(crown.quality(), dest)
                window["quality"] += 1
                next_quality += 0.25
            due = int(elapsed * SAMPLE_RATE)
            while sent_samples + args.epoch <= due:
                if not crown.in_dropout(sent_samples / SAMPLE_RATE):
                    sock.sendto(crown.raw(sent_samples, start_ms), dest)
                    window["raw"] += 1
                sent_samples += args.epoch
            if elapsed >= next_report + 5.0:
                next_report += 5.0
                print(f"crown_osc_sim: t={next_report:.0f}s last 5 s: raw={window['raw']} "
                      f"info={window['info']} quality={window['quality']}", flush=True)
                window = dict.fromkeys(window, 0)
            time.sleep(TICK_S)
    except KeyboardInterrupt:
        pass
    finally:
        sock.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
