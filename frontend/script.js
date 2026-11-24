// Calls the visitor-counter API and shows the number on the page.
// window.API_URL comes from config.js, which Terraform creates in S3.

async function updateVisitorCount() {
  const el = document.getElementById("visit-count");

  if (!window.API_URL) {
    el.textContent = "(counter not configured)";
    return;
  }

  try {
    const response = await fetch(window.API_URL);
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    const data = await response.json();
    el.textContent = data.visits.toLocaleString();
  } catch (error) {
    console.error("Visitor counter failed:", error);
    el.textContent = "many";
  }
}

updateVisitorCount();
