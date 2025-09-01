function getToken() {
  return localStorage.getItem("X_AUTH") || "token";
}

async function loadConfig() {
  const resp = await fetch("/config", { headers: { "X-Auth": getToken() } });
  if (!resp.ok) return;
  const cfg = await resp.json();
  document.getElementById("downloadDir").value = cfg.downloadDir;
  document.getElementById("port").value = cfg.port;
  document.getElementById("workerAddr").value = cfg.workerAddr;
}

document.getElementById("configForm").addEventListener("submit", async (e) => {
  e.preventDefault();
  const cfg = {
    downloadDir: document.getElementById("downloadDir").value,
    port: parseInt(document.getElementById("port").value, 10),
    workerAddr: document.getElementById("workerAddr").value,
  };
  await fetch("/config", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Auth": getToken(),
    },
    body: JSON.stringify(cfg),
  });
  alert("Saved");
});

loadConfig();
