document.addEventListener("DOMContentLoaded", () => {
  document.querySelectorAll("[data-date-entry]").forEach((entry) => {
    const text = entry.querySelector("input[type='text']");
    const picker = entry.querySelector("[data-date-picker]");
    const button = entry.querySelector("[data-date-picker-button]");
    if (picker.type !== "date" || typeof picker.showPicker !== "function") return;

    button.hidden = false;
    button.addEventListener("click", () => {
      const match = /^(\d{2})\.(\d{2})\.(\d{4})$/.exec(text.value);
      picker.value = match ? `${match[3]}-${match[2]}-${match[1]}` : "";
      picker.showPicker();
    });

    picker.addEventListener("change", () => {
      if (!picker.value) return;

      const [year, month, day] = picker.value.split("-");
      text.value = `${day}.${month}.${year}`;
    });
  });
});
