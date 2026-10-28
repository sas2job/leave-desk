document.addEventListener("DOMContentLoaded", () => {
  const workdayPreset = document.querySelector("[data-workday-preset]");
  const workdayStart = document.querySelector("[data-workday-start]");
  const workdayEnd = document.querySelector("[data-workday-end]");

  if (workdayPreset && workdayStart && workdayEnd) {
    workdayPreset.addEventListener("change", () => {
      if (workdayPreset.value === "full") {
        workdayStart.value = "09:00";
        workdayEnd.value = "18:00";
      }
    });

    [workdayStart, workdayEnd].forEach((field) => {
      field.addEventListener("change", () => {
        workdayPreset.value = "";
      });
    });
  }

  document.querySelectorAll("[data-date-entry]").forEach((entry) => {
    const text = entry.querySelector("input[type='text']");
    const button = entry.querySelector("[data-date-picker-button]");
    const dialog = entry.querySelector("[data-date-dialog]");
    const monthSelect = dialog.querySelector("[data-calendar-month]");
    const yearSelect = dialog.querySelector("[data-calendar-year]");
    const days = dialog.querySelector("[data-calendar-days]");
    const min = dialog.dataset.calendarMin;
    const max = dialog.dataset.calendarMax;
    const firstYear = Number(dialog.dataset.calendarFirstYear);
    const lastYear = Number(max.slice(0, 4));
    const months = ["Январь", "Февраль", "Март", "Апрель", "Май", "Июнь",
      "Июль", "Август", "Сентябрь", "Октябрь", "Ноябрь", "Декабрь"];
    const weekdays = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"];

    if (typeof dialog.showModal !== "function") return;

    months.forEach((name, index) => {
      monthSelect.add(new Option(name, String(index + 1)));
    });
    for (let year = firstYear; year <= lastYear; year += 1) {
      yearSelect.add(new Option(String(year), String(year)));
    }

    const isoDate = (year, month, day) =>
      `${year}-${String(month).padStart(2, "0")}-${String(day).padStart(2, "0")}`;
    const selectedIso = () => {
      const match = /^(\d{2})\.(\d{2})\.(\d{4})$/.exec(text.value);
      return match ? isoDate(match[3], match[2], match[1]) : "";
    };

    const renderDays = () => {
      days.replaceChildren();
      weekdays.forEach((name) => {
        const heading = document.createElement("span");
        heading.textContent = name;
        heading.className = "date-entry__weekday";
        days.append(heading);
      });

      const year = Number(yearSelect.value);
      const month = Number(monthSelect.value);
      const firstWeekday = (new Date(year, month - 1, 1).getDay() + 6) % 7;
      for (let offset = 0; offset < firstWeekday; offset += 1) {
        days.append(document.createElement("span"));
      }

      const dayCount = new Date(year, month, 0).getDate();
      for (let day = 1; day <= dayCount; day += 1) {
        const date = isoDate(year, month, day);
        const dayButton = document.createElement("button");
        dayButton.type = "button";
        dayButton.textContent = String(day);
        dayButton.className = "date-entry__day";
        dayButton.disabled = date < min || date > max;
        dayButton.setAttribute("aria-label", new Intl.DateTimeFormat("ru-RU", {
          day: "numeric", month: "long", year: "numeric"
        }).format(new Date(year, month - 1, day)));
        if (date === selectedIso()) dayButton.setAttribute("aria-pressed", "true");
        dayButton.addEventListener("click", () => {
          text.value = `${String(day).padStart(2, "0")}.${String(month).padStart(2, "0")}.${year}`;
          dialog.close();
        });
        days.append(dayButton);
      }
    };

    button.hidden = false;
    button.addEventListener("click", () => {
      const selected = selectedIso();
      const initial = selected >= `${firstYear}-01-01` && selected <= max ? selected : min;
      yearSelect.value = initial.slice(0, 4);
      monthSelect.value = String(Number(initial.slice(5, 7)));
      renderDays();
      dialog.showModal();
    });
    monthSelect.addEventListener("change", renderDays);
    yearSelect.addEventListener("change", renderDays);
    dialog.querySelector("[data-calendar-close]").addEventListener("click", () => dialog.close());
    dialog.addEventListener("close", () => button.focus());
  });
});
