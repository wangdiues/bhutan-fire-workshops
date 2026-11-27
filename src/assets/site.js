for (const button of document.querySelectorAll("[data-copy]")) {
  const code = document.getElementById(button.dataset.copy);
  const status = button.parentElement.querySelector(".copy-status");
  button.addEventListener("click", async () => {
    try {
      await navigator.clipboard.writeText(code.textContent);
      status.textContent = "Copied. Paste into the RStudio editor.";
    } catch {
      const range = document.createRange();
      range.selectNodeContents(code);
      const selection = window.getSelection();
      selection.removeAllRanges();
      selection.addRange(range);
      status.textContent = "Code selected. Press Ctrl+C to copy it.";
    }
  });
}
