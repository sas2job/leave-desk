document.addEventListener("DOMContentLoaded", () => {
  const dialog = document.querySelector("[data-calendar-event-dialog]");
  if (!dialog || typeof dialog.showModal !== "function") return;
  let trigger = null;
  document.querySelectorAll("[data-calendar-event]").forEach((bar) => {
    bar.addEventListener("click", () => {
      trigger = bar;
      dialog.querySelector("#calendar-event-title").textContent = bar.dataset.calendarEventTitle || "Период отсутствия";
      dialog.querySelector("[data-calendar-event-details]").textContent = bar.getAttribute("aria-label");
      dialog.showModal();
    });
  });
  dialog.querySelector("[data-calendar-event-close]").addEventListener("click", () => dialog.close());
  dialog.addEventListener("close", () => trigger?.focus());
});
