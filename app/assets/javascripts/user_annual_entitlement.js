document.addEventListener("DOMContentLoaded", () => {
  const flag = document.querySelector("#user_extended_annual_leave");
  const days = document.querySelector("#user_annual_base_days");
  if (!flag || !days) return;
  flag.addEventListener("change", () => {
    if (flag.checked && Number(days.value) === 28) days.value = "30";
    if (!flag.checked) days.value = "28";
  });
});
