/* feedback_gym static dashboard */
(function () {
  const $ = (s, el = document) => el.querySelector(s);
  const $$ = (s, el = document) => [...el.querySelectorAll(s)];

  let DATA = null;
  let RUNS_INDEX = { runs: [] };
  let compareCache = {};

  function fmt(v, digits = 3) {
    if (v === null || v === undefined || Number.isNaN(v)) return "N/A";
    if (typeof v === "number") return v.toFixed(digits);
    return String(v);
  }

  function scoreClass(v) {
    if (v === null || v === undefined) return "";
    if (v >= 0.7) return "score-good";
    if (v >= 0.4) return "score-mid";
    return "score-bad";
  }

  function deltaClass(d) {
    if (d === null || d === undefined || Number.isNaN(d)) return "delta-zero";
    if (Math.abs(d) < 1e-9) return "delta-zero";
    return d > 0 ? "delta-pos" : "delta-neg";
  }

  function sparkline(values, w = 96, h = 22) {
    if (!values || !values.length) return "";
    const nums = values.map(Number).filter((x) => !Number.isNaN(x));
    if (!nums.length) return "";
    const min = Math.min(...nums);
    const max = Math.max(...nums);
    const span = max - min || 1;
    const pts = nums
      .map((v, i) => {
        const x = (i / Math.max(1, nums.length - 1)) * (w - 2) + 1;
        const y = h - 2 - ((v - min) / span) * (h - 4);
        return `${x.toFixed(1)},${y.toFixed(1)}`;
      })
      .join(" ");
    return `<span class="spark"><svg width="${w}" height="${h}" viewBox="0 0 ${w} ${h}">
      <polyline fill="none" stroke="#6ea8fe" stroke-width="1.5" points="${pts}"/>
    </svg></span>`;
  }

  function partScore(parts, key) {
    const p = parts && parts[key];
    if (!p) return null;
    if (p.status === "unavailable" || p.status === "n/a") return null;
    return p.score;
  }

  function renderProtocols() {
    const tbody = $("#protocols-body");
    tbody.innerHTML = "";
    DATA.protocols.forEach((p, idx) => {
      const r = partScore(p.parts, "reward");
      const i = partScore(p.parts, "inhibit");
      const g = partScore(p.parts, "guard");
      const notes = (p.notes || []).join("; ");
      const tr = document.createElement("tr");
      tr.dataset.idx = String(idx);
      tr.innerHTML = `
        <td><code>${p.id}</code></td>
        <td class="num ${scoreClass(p.final)}">${fmt(p.final)}</td>
        <td class="num ${scoreClass(r)}">${fmt(r)}</td>
        <td class="num ${scoreClass(i)}">${fmt(i)}</td>
        <td class="num ${scoreClass(g)}">${fmt(g)}</td>
        <td>${notes || "—"}</td>`;
      tr.addEventListener("click", () => showProtocolDetail(idx, tr));
      tbody.appendChild(tr);
    });
  }

  function showProtocolDetail(idx, tr) {
    $$("#protocols-body tr").forEach((r) => r.classList.remove("selected"));
    tr.classList.add("selected");
    const p = DATA.protocols[idx];
    const box = $("#protocol-detail");
    box.classList.add("open");
    box.innerHTML = `<h2>${p.id} — part breakdown</h2>
      <div class="kv">
        <span>reward p</span><span>${fmt(p.reward_percentile, 0)}</span>
        <span>guard p</span><span>${fmt(p.guard_percentile, 0)}</span>
        <span>final</span><span class="${scoreClass(p.final)}">${fmt(p.final)}</span>
      </div>
      <pre>${JSON.stringify(p.parts, null, 2)}</pre>`;
  }

  function renderFeatures() {
    const tbody = $("#features-body");
    tbody.innerHTML = "";
    DATA.features.forEach((f) => {
      const orphan = f.orphan
        ? '<span class="badge orphan">orphan</span>'
        : "";
      const status = `<span class="badge ${f.status}">${f.status}</span>`;
      const tr = document.createElement("tr");
      tr.innerHTML = `
        <td><code>${f.id}</code> ${orphan}</td>
        <td>${(f.usableFor || []).join(", ")}</td>
        <td class="num">${f.best_p ?? "—"}</td>
        <td class="num ${scoreClass(f.score)}">${fmt(f.score)}</td>
        <td class="num">${fmt(f.sep)}</td>
        <td>${sparkline(f.sparkline)}</td>
        <td>${status}</td>
        <td>${f.latency || ""}</td>`;
      tbody.appendChild(tr);
    });
  }

  function renderSweeps() {
    const tbody = $("#sweeps-body");
    tbody.innerHTML = "";
    DATA.features
      .filter((f) => f.sweep && f.sweep.length)
      .forEach((f) => {
        const tr = document.createElement("tr");
        const curve = f.sweep
          .map((r) => `p${r.p}:${fmt(r.primary, 2)}`)
          .join(" · ");
        tr.innerHTML = `
          <td><code>${f.id}</code></td>
          <td>${f.sweep_role || ""}</td>
          <td class="num">${f.best_p ?? "—"}</td>
          <td>${sparkline(f.sparkline, 140, 24)}</td>
          <td style="font-family:var(--mono);font-size:11px;color:var(--muted)">${curve}</td>`;
        tbody.appendChild(tr);
      });
  }

  async function loadRun(runMeta) {
    if (!runMeta) return null;
    const key = runMeta.run_id;
    if (compareCache[key]) return compareCache[key];
    const url = runMeta.run || runMeta.summary;
    const res = await fetch(url, { cache: "no-store" });
    if (!res.ok) throw new Error(`HTTP ${res.status} for ${url}`);
    const data = await res.json();
    compareCache[key] = data;
    return data;
  }

  function numOrNull(v) {
    return typeof v === "number" && !Number.isNaN(v) ? v : null;
  }

  function protocolFinal(run, id) {
    const p = (run.protocols || []).find((x) => x.id === id);
    return p ? numOrNull(p.final) : null;
  }

  function featureField(run, id, field) {
    const f = (run.features || []).find((x) => x.id === id);
    return f ? numOrNull(f[field]) : null;
  }

  function renderDeltaCell(a, b) {
    if (a === null && b === null) return `<td class="num delta-zero">—</td>`;
    if (a === null || b === null) {
      return `<td class="num">${fmt(a)} → ${fmt(b)}</td>`;
    }
    const d = b - a;
    const sign = d > 0 ? "+" : "";
    return `<td class="num ${deltaClass(d)}">${fmt(a)} → ${fmt(b)} <span>(${sign}${fmt(d)})</span></td>`;
  }

  async function renderCompare() {
    const box = $("#compare-body");
    const runs = RUNS_INDEX.runs || [];
    if (runs.length < 2) {
      box.innerHTML = `
        <div class="compare-empty">
          <p><strong>Need at least two runs to compare.</strong></p>
          <p>Latest: <code>${DATA ? DATA.run_id : "—"}</code>. Indexed runs: <code>${runs.length}</code>.</p>
          <p>Re-run <code>python3 runners/run_gym.py</code> (optionally with different corpora/presets)
             to populate <code>results/</code> and <code>ui/data/runs_index.json</code>.</p>
        </div>`;
      return;
    }

    const opts = runs
      .map(
        (r) =>
          `<option value="${r.run_id}">${r.run_id} · ${r.corpus || "?"}</option>`
      )
      .join("");
    box.innerHTML = `
      <div class="compare-controls">
        <label>Run A
          <select id="compare-a">${opts}</select>
        </label>
        <label>Run B
          <select id="compare-b">${opts}</select>
        </label>
      </div>
      <div id="compare-tables"></div>`;

    const selA = $("#compare-a");
    const selB = $("#compare-b");
    // Default: previous + latest
    selA.selectedIndex = Math.max(0, runs.length - 2);
    selB.selectedIndex = runs.length - 1;

    async function refresh() {
      const metaA = runs.find((r) => r.run_id === selA.value);
      const metaB = runs.find((r) => r.run_id === selB.value);
      const tables = $("#compare-tables");
      try {
        const [a, b] = await Promise.all([loadRun(metaA), loadRun(metaB)]);
        const protoIds = [
          ...new Set([
            ...(a.protocols || []).map((p) => p.id),
            ...(b.protocols || []).map((p) => p.id),
          ]),
        ];
        const featIds = [
          ...new Set([
            ...(a.features || []).map((f) => f.id),
            ...(b.features || []).map((f) => f.id),
          ]),
        ];

        const protoRows = protoIds
          .map((id) => {
            const fa = protocolFinal(a, id);
            const fb = protocolFinal(b, id);
            return `<tr><td><code>${id}</code></td>${renderDeltaCell(fa, fb)}</tr>`;
          })
          .join("");

        const featRows = featIds
          .map((id) => {
            const sa = featureField(a, id, "score");
            const sb = featureField(b, id, "score");
            const ea = featureField(a, id, "sep");
            const eb = featureField(b, id, "sep");
            const pa = featureField(a, id, "best_p");
            const pb = featureField(b, id, "best_p");
            return `<tr>
              <td><code>${id}</code></td>
              ${renderDeltaCell(sa, sb)}
              ${renderDeltaCell(ea, eb)}
              ${renderDeltaCell(pa, pb)}
            </tr>`;
          })
          .join("");

        tables.innerHTML = `
          <p class="hint">A = <code>${a.run_id}</code> (${a.corpus || "?"}) ·
            B = <code>${b.run_id}</code> (${b.corpus || "?"})</p>
          <h2>Protocol final Δ</h2>
          <table>
            <thead><tr><th>id</th><th class="num">final A → B (Δ)</th></tr></thead>
            <tbody>${protoRows}</tbody>
          </table>
          <h2 style="margin-top:18px">Feature score / sep / best_p Δ</h2>
          <table>
            <thead>
              <tr>
                <th>id</th>
                <th class="num">score</th>
                <th class="num">sep</th>
                <th class="num">best_p</th>
              </tr>
            </thead>
            <tbody>${featRows}</tbody>
          </table>`;
      } catch (e) {
        tables.innerHTML = `<p class="hint" style="color:var(--bad)">Compare load failed: ${e}</p>
          <p class="hint">Serve <code>feedback_gym/ui</code> over HTTP so <code>../results/</code> fetches work.</p>`;
      }
    }

    selA.addEventListener("change", refresh);
    selB.addEventListener("change", refresh);
    refresh();
  }

  function activateTab(name) {
    $$(".tab").forEach((t) => t.classList.toggle("active", t.dataset.tab === name));
    $$(".tab-panel").forEach((p) => {
      p.style.display = p.id === `panel-${name}` ? "block" : "none";
    });
  }

  async function boot() {
    try {
      const res = await fetch("data/latest.json", { cache: "no-store" });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      DATA = await res.json();
    } catch (e) {
      $("#boot-error").style.display = "block";
      $("#boot-error").textContent =
        `Could not load data/latest.json (${e}). Serve ui/ over HTTP or re-run the gym.`;
      return;
    }
    try {
      const idx = await fetch("data/runs_index.json", { cache: "no-store" });
      if (idx.ok) RUNS_INDEX = await idx.json();
    } catch (_) {
      RUNS_INDEX = { runs: [] };
    }
    $("#run-meta").textContent =
      `${DATA.timestamp} · run ${DATA.run_id} · corpus ${DATA.corpus}`;
    renderProtocols();
    renderFeatures();
    renderSweeps();
    renderCompare();
    $$(".tab").forEach((t) =>
      t.addEventListener("click", () => activateTab(t.dataset.tab))
    );
    activateTab("protocols");
  }

  boot();
})();
