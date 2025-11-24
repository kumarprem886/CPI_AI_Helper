$folder = "C:\CPI-AI-Error-Helper"
$zipPath = "C:\CPI-AI-Error-Helper.zip"

if (Test-Path $folder) { Remove-Item $folder -Recurse -Force }
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }

New-Item -ItemType Directory -Path $folder | Out-Null

# ---------------- manifest.json ----------------
@'
{
  "manifest_version": 3,
  "name": "CPI AI Error Helper",
  "version": "1.0",
  "description": "Adds an 'Explain Error (AI)' button in SAP CPI monitoring using Gemini.",
  "permissions": ["storage"],
  "host_permissions": ["https://*/*","http://*/*"],
  "content_scripts": [
    {
      "matches": ["https://*/*","http://*/*"],
      "js": ["content.js"],
      "run_at": "document_idle"
    }
  ],
  "options_page": "options.html"
}
'@ | Set-Content "$folder\manifest.json"

# ---------------- content.js ----------------
@'
function isCpiPage() {
  return window.location.href.includes("cfapps.eu20.hana.ondemand.com");
}

function showAiPanel(text) {
  let panel = document.getElementById("cpi-ai-panel");
  if (!panel) {
    panel = document.createElement("div");
    panel.id = "cpi-ai-panel";
    panel.style = "position:fixed;right:20px;bottom:20px;width:420px;height:260px;background:white;border:1px solid #ccc;border-radius:8px;z-index:999999;padding:8px;display:flex;flex-direction:column;box-shadow:0 2px 12px rgba(0,0,0,.3);";
    const header = document.createElement("div");
    header.style = "display:flex;justify-content:space-between;align-items:center;margin-bottom:4px;";
    const title = document.createElement("div");
    title.textContent = "CPI AI Error Helper";
    title.style = "font-weight:bold;font-size:13px";
    const closeBtn = document.createElement("button");
    closeBtn.textContent = "×";
    closeBtn.style = "border:none;background:transparent;font-size:18px;cursor:pointer";
    closeBtn.onclick = () => panel.remove();
    header.appendChild(title); header.appendChild(closeBtn);
    const content = document.createElement("div");
    content.id = "cpi-ai-panel-content";
    content.style = "flex:1;overflow-y:auto;font-size:12px;white-space:pre-wrap";
    panel.appendChild(header); panel.appendChild(content);
    document.body.appendChild(panel);
  }
  document.getElementById("cpi-ai-panel-content").textContent = text;
}

async function callGemini(errorText, apiKey) {
  const body = { contents: [{ parts: [{ text: "Analyze SAP CPI error:\n" + errorText + "\nGive: root cause + fix + config to check" }] }] };
  const url = "https://generativelanguage.googleapis.com/v1/models/gemini-1.5-flash:generateContent?key=" + encodeURIComponent(apiKey);
  const res = await fetch(url, { method:"POST", headers:{ "Content-Type":"application/json" }, body: JSON.stringify(body) });
  const data = await res.json();
  return data?.candidates?.[0]?.content?.parts?.map(p => p.text).join("\n") || "No explanation returned.";
}

function addButton(el) {
  if (el.dataset.aiAdded === "true") return;
  const btn = document.createElement("button");
  btn.textContent = "Explain Error (AI)";
  btn.style = "margin-left:8px;padding:2px 6px;font-size:11px;cursor:pointer;border:1px solid #888;border-radius:4px;background:#f5f5f5";
  btn.onclick = () => {
    const text = el.innerText.trim();
    showAiPanel("Analyzing error using Gemini...");
    chrome.storage.local.get(["geminiApiKey"], async (r) => {
      if (!r.geminiApiKey) return showAiPanel("Gemini API key not set.\nRight-click extension → Options");
      try { showAiPanel(await callGemini(text, r.geminiApiKey)); }
      catch (e) { showAiPanel("Gemini error:\n" + e); }
    });
  };
  el.appendChild(btn);
  el.dataset.aiAdded = "true";
}

function scan() {
  if (!isCpiPage()) return;
  const nodes = document.querySelectorAll("span,div,td,pre");
  nodes.forEach(el => {
    const t = (el.textContent || "").toUpperCase();
    if (t.includes("FAILED") || t.includes("ERROR") || t.includes("EXCEPTION") || t.includes("DEPLOYMENT ERROR")) {
      addButton(el);
    }
  });
}

setInterval(scan, 3000);
'@ | Set-Content "$folder\content.js"

# ---------------- options.html ----------------
@'
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>CPI AI Helper Settings</title>
</head>
<body style="font-family:Arial;padding:18px">
<h2>CPI AI Helper – Settings</h2>
<label>Gemini API Key:</label>
<input id="apiKey" type="password" style="width:100%;padding:6px">
<button id="saveBtn" style="margin-top:10px;padding:6px 12px;cursor:pointer">Save</button>
<div id="status" style="margin-top:10px;color:green"></div>
<script src="options.js"></script>
</body>
</html>
'@ | Set-Content "$folder\options.html"

# ---------------- options.js ----------------
@'
document.addEventListener("DOMContentLoaded", () => {
  const input = document.getElementById("apiKey");
  chrome.storage.local.get(["geminiApiKey"], (r) => { if (r.geminiApiKey) input.value = r.geminiApiKey; });
  document.getElementById("saveBtn").onclick = () => {
    chrome.storage.local.set({ geminiApiKey: input.value.trim() }, () => {
      document.getElementById("status").textContent = "Saved!";
      setTimeout(() => document.getElementById("status").textContent = "", 2000);
    });
  };
});
'@ | Set-Content "$folder\options.js"

Compress-Archive -Path $folder\* -DestinationPath $zipPath

Write-Host "`n✔ DONE!"
Write-Host "Extension folder created:  $folder"
Write-Host "ZIP created:               $zipPath"
Write-Host "`nNext steps:"
Write-Host "1) Open Chrome → chrome://extensions"
Write-Host "2) Enable Developer Mode"
Write-Host "3) Load unpacked → select C:\CPI-AI-Error-Helper"
Write-Host "4) Open Options → paste Gemini API key"

