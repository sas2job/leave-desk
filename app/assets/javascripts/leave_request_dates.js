document.addEventListener("DOMContentLoaded", () => {
  document.querySelectorAll("[data-date-entry]").forEach((entry) => {
    const text = entry.querySelector("input[type='text']");
    const button = entry.querySelector("[data-date-picker-button]");
    const dialog = entry.querySelector("[data-date-dialog]");
    const monthSelect = dialog.querySelector("[data-calendar-month]");
    const yearSelect = dialog.querySelector("[data-calendar-year]");
    const days = dialog.querySelector("[data-calendar-days]");
    const min = () => dialog.dataset.calendarMin;
    const max = () => dialog.dataset.calendarMax;
    const firstYear = Number(dialog.dataset.calendarFirstYear);
    const availableYears = new Set(dialog.dataset.calendarAvailableYears.split(",").filter(Boolean));
    const months = ["Январь", "Февраль", "Март", "Апрель", "Май", "Июнь",
      "Июль", "Август", "Сентябрь", "Октябрь", "Ноябрь", "Декабрь"];
    const weekdays = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"];

    if (typeof dialog.showModal !== "function") return;

    months.forEach((name, index) => {
      monthSelect.add(new Option(name, String(index + 1)));
    });

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
        dayButton.disabled = date < min() || date > max() || !availableYears.has(String(year));
        dayButton.setAttribute("aria-label", new Intl.DateTimeFormat("ru-RU", {
          day: "numeric", month: "long", year: "numeric"
        }).format(new Date(year, month - 1, day)));
        if (date === selectedIso()) dayButton.setAttribute("aria-pressed", "true");
        dayButton.addEventListener("click", () => {
          text.value = `${String(day).padStart(2, "0")}.${String(month).padStart(2, "0")}.${year}`;
          text.dispatchEvent(new Event("change", { bubbles: true }));
          dialog.close();
        });
        days.append(dayButton);
      }
    };

    button.hidden = false;
    button.addEventListener("click", () => {
      yearSelect.replaceChildren();
      for (let year = firstYear; year <= Number(max().slice(0, 4)); year += 1) {
        const option = new Option(String(year), String(year));
        option.disabled = !availableYears.has(String(year));
        yearSelect.add(option);
      }
      const selected = selectedIso();
      const initial = selected >= `${firstYear}-01-01` && selected <= max() ? selected : min();
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

  const planner = document.querySelector("[data-leave-planner]");
  if (!planner) return;

  const form = planner.closest("form");
  const startsOn = form.querySelector("[name='leave_request[starts_on]']");
  const endsOn = form.querySelector("[name='leave_request[ends_on]']");
  const startTime = form.querySelector("[data-workday-start]");
  const endTime = form.querySelector("[data-workday-end]");
  const fullDay = form.querySelector("[data-full-day]");
  const leaveType = form.querySelector("[data-planner-type]");
  const summary = planner.querySelector("[data-planner-summary]");
  const daysList = planner.querySelector("[data-planner-days]");
  const note = planner.querySelector("[data-planner-note]");
  const today = form.querySelector("[data-calendar-min]").dataset.calendarMin;
  const yearEnd = form.querySelector("[data-calendar-max]").dataset.calendarMax;
  let minDate = today;
  let maxDate = yearEnd;
  const fullDayTypeIds = new Set(leaveType.dataset.fullDayTypeIds.split(",").filter(Boolean));
  const statutoryTypeIds = new Set(leaveType.dataset.statutoryTypeIds.split(",").filter(Boolean));
  const familyTypeIds = new Set(leaveType.dataset.familyTypeIds.split(",").filter(Boolean));
  const holidays = new Set(planner.dataset.publicHolidays.split(",").filter(Boolean));
  const excludedTypeIds = new Set(leaveType.dataset.excludedHolidayTypeIds.split(",").filter(Boolean));
  const dayMillis = 24 * 60 * 60 * 1000;
  const configuredYears = new Set(planner.dataset.calendarAvailableYears.split(",").filter(Boolean));
  const dateLabel = new Intl.DateTimeFormat("ru-RU", { day: "numeric", month: "short", timeZone: "UTC" });
  const weekdayLabel = new Intl.DateTimeFormat("ru-RU", { weekday: "short", timeZone: "UTC" });
  let customStartTime = startTime.value;
  let customEndTime = endTime.value;

  const parseDate = (value) => {
    const match = /^(\d{2})\.(\d{2})\.(\d{4})$/.exec(value);
    if (!match) return null;
    const iso = `${match[3]}-${match[2]}-${match[1]}`;
    const date = new Date(`${iso}T00:00:00Z`);
    return Number.isNaN(date.getTime()) || date.toISOString().slice(0, 10) !== iso ? null : date;
  };

  const dateIso = (date) => date.toISOString().slice(0, 10);
  const countLabel = (count, one, few, many) => {
    const ending = count % 100;
    if (ending >= 11 && ending <= 14) return many;
    if (count % 10 === 1) return one;
    if (count % 10 >= 2 && count % 10 <= 4) return few;
    return many;
  };

  const renderPlanner = () => {
    if (leaveType.value === leaveType.dataset.birthdayTypeId) endsOn.value = startsOn.value;
    daysList.replaceChildren();
    const first = parseDate(startsOn.value);
    const last = parseDate(endsOn.value);
    if (!first || !last) {
      summary.textContent = "Выберите даты начала и окончания.";
      return;
    }
    if (last < first) {
      summary.textContent = "Дата окончания раньше даты начала.";
      return;
    }
    if (dateIso(first) < minDate || dateIso(last) > maxDate) {
      summary.textContent = `Выберите даты в допустимом периоде: ${minDate} — ${maxDate}.`;
      return;
    }
    const missingYears = [];
    for (let year = first.getUTCFullYear(); year <= last.getUTCFullYear(); year += 1) {
      if (!configuredYears.has(String(year))) missingYears.push(year);
    }
    if (missingYears.length) {
      summary.textContent = `Календарь ${missingYears.join(", ")} года ещё не размечен. Обратитесь к администратору.`;
      return;
    }

    const count = Math.round((last - first) / dayMillis) + 1;
    const excludedHolidays = excludedTypeIds.has(leaveType.value);
    const holidayCount = Array.from(holidays).filter((date) => date >= dateIso(first) && date <= dateIso(last)).length;
    const countText = `${count} ${countLabel(count, "календарная дата", "календарные даты", "календарных дат")}`;
    if (fullDay.checked && leaveType.value) {
      const counted = count - (excludedHolidays ? holidayCount : 0);
      const noun = leaveType.value === leaveType.dataset.annualTypeId ? "отпуска" : "отсутствия";
      summary.textContent = `${countText} · ${counted} ${countLabel(counted, "день", "дня", "дней")} ${noun}`;
    } else {
      summary.textContent = `${countText} · ${fullDay.checked ? "выберите вид отпуска для расчёта" : "крайние дни по выбранному времени"}`;
    }

    const visibleIndexes = count <= 14 ? Array.from({ length: count }, (_, index) => index) :
      [ ...Array.from({ length: 7 }, (_, index) => index),
        ...Array.from({ length: 7 }, (_, index) => count - 7 + index) ];
    visibleIndexes.forEach((index, position) => {
      if (count > 14 && position === 7) {
        const omitted = document.createElement("li");
        omitted.className = "leave-planner__more";
        omitted.textContent = `Ещё ${count - 14} ${countLabel(count - 14, "дата", "даты", "дат")}`;
        daysList.append(omitted);
      }
      const date = new Date(first.getTime() + index * dayMillis);
      const holiday = holidays.has(dateIso(date));
      const item = document.createElement("li");
      item.className = "leave-planner__day";
      if (holiday && excludedHolidays) item.classList.add("is-excluded");
      const day = document.createElement("time");
      day.dateTime = dateIso(date);
      day.textContent = `${weekdayLabel.format(date)} ${dateLabel.format(date)}`;
      const detail = document.createElement("span");
      if (holiday && excludedHolidays) {
        detail.textContent = "Праздник · не входит";
      } else if (fullDay.checked || (index > 0 && index < count - 1)) {
        detail.textContent = "Весь день";
      } else if (count === 1) {
        detail.textContent = `${startTime.value}–${endTime.value}`;
      } else {
        detail.textContent = index === 0 ? `с ${startTime.value}` : `до ${endTime.value}`;
      }
      item.append(day, detail);
      daysList.append(item);
    });

    if (leaveType.value && leaveType.value === leaveType.dataset.annualTypeId) {
      note.textContent = "Ежегодный отпуск: выходные входят, официальные праздники исключаются. Неполные крайние дни рассчитываются как доли календарного дня.";
    } else {
      note.textContent = "Промежуточные даты входят целиком. Итоговая длительность зависит от вида отсутствия и праздничных дат.";
    }
  };

  fullDay.addEventListener("change", () => {
    if (fullDay.checked) {
      customStartTime = startTime.value;
      customEndTime = endTime.value;
      startTime.value = "09:00";
      endTime.value = "18:00";
    } else {
      startTime.value = customStartTime;
      endTime.value = customEndTime;
    }
    [startTime, endTime].forEach((field) => {
      field.disabled = fullDay.checked;
      field.closest("[data-time-field]").hidden = fullDay.checked;
    });
    renderPlanner();
  });
  const applyTypePolicy = () => {
    const birthday = leaveType.value === leaveType.dataset.birthdayTypeId;
    endsOn.closest("[data-period-field]").hidden = birthday;
    endsOn.readOnly = birthday;
    form.querySelector("[data-date-label='starts_on']").textContent = birthday ? "Дата выходного" : "Дата начала";
    const locked = fullDayTypeIds.has(leaveType.value);
    if (locked) fullDay.checked = true;
    fullDay.disabled = locked;
    minDate = familyTypeIds.has(leaveType.value) ? "2025-01-01" : today;
    form.querySelectorAll("[data-date-dialog]").forEach((dialog) => {
      maxDate = statutoryTypeIds.has(leaveType.value) ? dialog.dataset.statutoryMax : yearEnd;
      dialog.dataset.calendarMin = minDate;
      dialog.dataset.calendarMax = maxDate;
    });
    const childcare = leaveType.value === leaveType.dataset.childcareTypeId;
    form.querySelectorAll("[data-childcare-field]").forEach((field) => {
      field.hidden = !childcare;
      field.querySelector("input, select").disabled = !childcare;
    });
    [startTime, endTime].forEach((field) => {
      field.disabled = fullDay.checked;
      field.closest("[data-time-field]").hidden = fullDay.checked;
    });
    renderPlanner();
  };
  leaveType.addEventListener("change", applyTypePolicy);
  [startTime, endTime, leaveType, startsOn, endsOn].forEach((field) => {
    field.addEventListener("change", renderPlanner);
  });
  [startsOn, endsOn].forEach((field) => field.addEventListener("input", renderPlanner));
  [startTime, endTime].forEach((field) => {
    field.disabled = fullDay.checked;
    field.closest("[data-time-field]").hidden = fullDay.checked;
  });
  applyTypePolicy();
});
