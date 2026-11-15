// Atualiza o painel "no ar" consultando /api/status. Sem JS, a página continua completa.
(function () {
  "use strict";

  function formatarDuracao(segundos) {
    var d = Math.floor(segundos / 86400);
    var h = Math.floor((segundos % 86400) / 3600);
    var m = Math.floor((segundos % 3600) / 60);
    if (d > 0) return d + " d " + h + " h";
    if (h > 0) return h + " h " + m + " min";
    if (m > 0) return m + " min";
    return segundos + " s";
  }

  function aplicar(status) {
    document.querySelectorAll("[data-status]").forEach(function (el) {
      var chave = el.getAttribute("data-status");
      if (!(chave in status)) return;
      el.textContent = chave === "segundos_no_ar" ? formatarDuracao(status[chave]) : status[chave];
    });
  }

  function atualizar() {
    fetch("/api/status", { headers: { Accept: "application/json" } })
      .then(function (r) { return r.ok ? r.json() : null; })
      .then(function (s) { if (s) aplicar(s); })
      .catch(function () { /* offline: mantém o último valor renderizado */ });
  }

  var inicial = document.querySelector("[data-segundos]");
  if (inicial) inicial.textContent = formatarDuracao(Number(inicial.getAttribute("data-segundos")));
  atualizar();
  setInterval(atualizar, 30000);
})();
