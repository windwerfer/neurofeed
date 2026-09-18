/* feedback_gym static dashboard */
(function () {
  const $ = (s, el = document) => el.querySelector(s);
  const $$ = (s, el = document) => [...el.querySelectorAll(s)];

  let DATA = null;

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

  function renderCompareStub() {
    $("#compare-body").innerHTML =
      `<p class="hint">Compare-runs is a v1 stub. Latest run: <code>${DATA.run_id}</code>.
       Historical folders live under <code>results/</code>.</p>`;
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
    $("#run-meta").textContent =
      `${DATA.timestamp} · run ${DATA.run_id} · corpus ${DATA.corpus}`;
    renderProtocols();
    renderFeatures();
    renderSweeps();
    renderCompareStub();
    $$(".tab").forEach((t) =>
      t.addEventListener("click", () => activateTab(t.dataset.tab))
    );
    activateTab("protocols");
  }

  boot();
})();
