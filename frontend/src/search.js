document.getElementById("searchForm").addEventListener("submit", async (e) => {
  e.preventDefault();
  const q = document.getElementById("query").value;
  const resp = await fetch(`/search?q=${encodeURIComponent(q)}`, {
    headers: { "X-Auth": "token" },
  });
  if (!resp.ok) return;
  const data = await resp.json();
  const list = document.getElementById("results");
  list.innerHTML = "";
  data.forEach((item) => {
    const li = document.createElement("li");
    const a = document.createElement("a");
    a.href = item.magnet;
    a.textContent = item.title;
    li.appendChild(a);
    list.appendChild(li);
  });
});
