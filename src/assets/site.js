for (const code of document.querySelectorAll("pre > code")) {
  if (!navigator.clipboard?.writeText) continue;
  const button = document.createElement("button");
  button.type = "button";
  button.textContent = "Copy code";
  button.className = "copy";
  button.addEventListener("click", async () => {
    try {
      await navigator.clipboard.writeText(code.textContent);
      button.textContent = "Copied";
    } catch {
      button.textContent = "Select and copy the code";
    }
  });
  code.parentElement.before(button);
}
