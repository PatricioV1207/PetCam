(function () {
  "use strict";

  /* ---- state ---- */
  let hlsLive = null;

  /* ---- DOM refs ---- */
  const statusBadge = document.getElementById("status-badge");
  const liveVideo = document.getElementById("live-video");
  const liveLink = document.getElementById("live-link");
  const liveFallback = document.getElementById("live-fallback");
  const liveFallbackLink = document.getElementById("live-fallback-link");
  const refreshBtn = document.getElementById("refresh-btn");
  const recCount = document.getElementById("rec-count");
  const recList = document.getElementById("rec-list");
  const playbackSection = document.getElementById("playback");
  const playbackVideo = document.getElementById("playback-video");
  const playbackName = document.getElementById("playback-name");
  const playbackNote = document.getElementById("playback-note");
  const playbackDownload = document.getElementById("playback-download");
  const footerInfo = document.getElementById("footer-info");

  /* ---- helpers ---- */
  function fmtSize(bytes) {
    if (bytes < 1024) return bytes + " B";
    if (bytes < 1048576) return (bytes / 1024).toFixed(1) + " KB";
    return (bytes / 1048576).toFixed(1) + " MB";
  }

  function fmtTime(ts) {
    const d = new Date(ts * 1000);
    return d.toLocaleString();
  }

  function escapeHtml(s) {
    const el = document.createElement("span");
    el.textContent = s;
    return el.innerHTML;
  }

  /* ---- status ---- */
  async function fetchStatus() {
    try {
      const r = await fetch("/health");
      const data = await r.json();
      statusBadge.textContent = data.status === "ok" ? "online" : "error";
      statusBadge.className = "badge " + (data.status === "ok" ? "ok" : "err");
      footerInfo.textContent = "Storage: " + fmtSize(data.storage.used_bytes) +
        " / " + fmtSize(data.storage.total_bytes) +
        " (" + data.storage.percent_used + "%)";
    } catch {
      statusBadge.textContent = "offline";
      statusBadge.className = "badge err";
    }
  }

  /* ---- live stream ---- */
  function initLive(url) {
    liveLink.href = url;
    liveFallbackLink.href = url;

    if (typeof Hls === "undefined") {
      liveVideo.classList.add("hidden");
      liveFallback.classList.remove("hidden");
      return;
    }

    if (Hls.isSupported()) {
      if (hlsLive) hlsLive.destroy();
      hlsLive = new Hls();
      hlsLive.loadSource(url);
      hlsLive.attachMedia(liveVideo);
      hlsLive.on(Hls.Events.MANIFEST_PARSED, function () {
        liveVideo.play().catch(function () {});
      });
    } else if (liveVideo.canPlayType("application/vnd.apple.mpegurl")) {
      liveVideo.src = url;
    }
  }

  /* ---- recordings ---- */
  async function fetchRecordings() {
    refreshBtn.disabled = true;
    try {
      const r = await fetch("/api/recordings");
      const data = await r.json();
      renderRecordings(data.recordings);
    } catch {
      recList.innerHTML = "<li class='err'>Failed to load recordings.</li>";
    } finally {
      refreshBtn.disabled = false;
    }
  }

  function renderRecordings(recs) {
    recCount.textContent = recs.length + " file" + (recs.length !== 1 ? "s" : "");
    recList.innerHTML = "";

    if (recs.length === 0) {
      recList.innerHTML = "<li class='empty'>No recordings found.</li>";
      return;
    }

    for (const r of recs) {
      const li = document.createElement("li");
      li.className = "rec-item";

      const nameSpan = document.createElement("span");
      nameSpan.className = "rec-name";
      nameSpan.textContent = r.filename;

      const metaSpan = document.createElement("span");
      metaSpan.className = "rec-meta";
      metaSpan.textContent = fmtSize(r.size_bytes) + " \u00b7 " + fmtTime(r.modified_time);

      li.appendChild(nameSpan);
      li.appendChild(metaSpan);
      li.addEventListener("click", function () {
        playRecording(r.playable_url, r.filename, r.play_url);
      });
      recList.appendChild(li);
    }
  }

  /* ---- playback ---- */
  function playRecording(playableUrl, name, downloadUrl) {
    playbackSection.classList.remove("hidden");
    playbackNote.className = "small-note";
    playbackName.textContent = name;
    playbackDownload.href = downloadUrl;
    playbackDownload.textContent = "Download original";

    playbackVideo.src = playableUrl;
    playbackVideo.load();
    playbackVideo.play().catch(function () {});
    playbackVideo.scrollIntoView({ behavior: "smooth", block: "nearest" });
  }

  /* ---- init ---- */
  fetchStatus();
  fetchRecordings();

  refreshBtn.addEventListener("click", fetchRecordings);

  setInterval(fetchStatus, 30000);

  fetch("/health")
    .then(function (r) { return r.json(); })
    .then(function (data) {
      initLive(data.live_hls_url);
    })
    .catch(function () {
      liveFallback.classList.remove("hidden");
    });
})();
