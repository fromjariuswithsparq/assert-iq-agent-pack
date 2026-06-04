/* Assert.IQ cross-page search — vendored, no dependencies.
 * Index loaded from window.__ASSERT_IQ_SEARCH (search-index.js).
 * Keyboard: "/" focuses, ↑/↓ navigate, Enter opens, Esc clears. */
(function () {
  "use strict";

  var INDEX = window.__ASSERT_IQ_SEARCH || [];
  if (!INDEX.length) return;

  var input    = document.getElementById("aiq-search-input");
  var resultEl = document.getElementById("aiq-search-results");
  if (!input || !resultEl) return;

  // Determine current page filename (relative). Default to index.html if served at /.
  var path = (location.pathname || "").split("/").pop() || "";
  if (!path || path === "" || path === "/") path = "index.html";

  var MAX_RESULTS = 20;
  var activeIdx = -1;
  var currentResults = [];

  function escHtml(s) {
    return String(s)
      .replace(/&/g, "&amp;").replace(/</g, "&lt;")
      .replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&#39;");
  }

  function highlight(text, q) {
    if (!q) return escHtml(text);
    var out = "";
    var lower = text.toLowerCase();
    var qlow = q.toLowerCase();
    var i = 0;
    while (i < text.length) {
      var hit = lower.indexOf(qlow, i);
      if (hit === -1) { out += escHtml(text.slice(i)); break; }
      out += escHtml(text.slice(i, hit));
      out += '<mark class="aiq-hl">' + escHtml(text.slice(hit, hit + q.length)) + "</mark>";
      i = hit + q.length;
    }
    return out;
  }

  function score(entry, q) {
    var t = entry.t.toLowerCase();
    if (t === q) return 1000;
    if (t.startsWith(q)) return 500 - entry.l * 10;
    var idx = t.indexOf(q);
    if (idx === -1) return -1;
    return 100 - idx - entry.l * 5;
  }

  function search(q) {
    q = q.trim().toLowerCase();
    if (!q) return [];
    var scored = [];
    for (var i = 0; i < INDEX.length; i++) {
      var s = score(INDEX[i], q);
      if (s >= 0) scored.push({ e: INDEX[i], s: s });
    }
    scored.sort(function (a, b) {
      // Boost current page slightly so local jumps win ties.
      var bonus = function (x) { return x.e.p === path ? 5 : 0; };
      return (b.s + bonus(b)) - (a.s + bonus(a));
    });
    return scored.slice(0, MAX_RESULTS).map(function (x) { return x.e; });
  }

  function render(results, q) {
    if (!q) {
      resultEl.innerHTML = '<div class="aiq-hint">Type to search across all pages. Press <b>↑/↓</b> to navigate, <b>Enter</b> to open, <b>Esc</b> to clear.</div>';
      resultEl.hidden = false;
      activeIdx = -1;
      currentResults = [];
      return;
    }
    if (!results.length) {
      resultEl.innerHTML = '<div class="aiq-empty">No matches for &ldquo;' + escHtml(q) + '&rdquo;</div>';
      resultEl.hidden = false;
      activeIdx = -1;
      currentResults = [];
      return;
    }

    // Group by page, preserving result order.
    var groups = [];
    var byPage = {};
    results.forEach(function (e) {
      if (!byPage[e.p]) {
        byPage[e.p] = { p: e.p, pt: e.pt, items: [] };
        groups.push(byPage[e.p]);
      }
      byPage[e.p].items.push(e);
    });

    var html = "";
    var flat = [];
    groups.forEach(function (g) {
      var here = g.p === path ? '<span class="aiq-result-here">this page</span>' : "";
      html += '<div class="aiq-group">' + escHtml(g.pt) + here + "</div>";
      g.items.forEach(function (e) {
        var idx = flat.length;
        flat.push(e);
        html +=
          '<a class="aiq-result" data-idx="' + idx + '" href="' +
          escHtml(e.p) + "#" + escHtml(e.a) + '" role="option">' +
          '<span class="aiq-result-level">H' + e.l + "</span>" +
          highlight(e.t, q) +
          "</a>";
      });
    });
    resultEl.innerHTML = html;
    resultEl.hidden = false;
    currentResults = flat;
    activeIdx = -1;
  }

  function setActive(i) {
    var nodes = resultEl.querySelectorAll(".aiq-result");
    nodes.forEach(function (n) { n.classList.remove("aiq-active"); });
    if (i >= 0 && i < nodes.length) {
      nodes[i].classList.add("aiq-active");
      nodes[i].scrollIntoView({ block: "nearest" });
      activeIdx = i;
    }
  }

  function open(entry) {
    if (!entry) return;
    var url = entry.p + "#" + entry.a;
    if (entry.p === path) {
      // Same page: just update hash (forces :target re-trigger).
      if (location.hash === "#" + entry.a) {
        // Re-apply by clearing+resetting so the flash animation replays.
        history.replaceState(null, "", entry.p);
        location.hash = "#" + entry.a;
      } else {
        location.hash = "#" + entry.a;
      }
    } else {
      location.href = url;
    }
    resultEl.hidden = true;
    input.blur();
  }

  // Wire input
  input.addEventListener("input", function () {
    var q = input.value;
    render(search(q), q.trim());
  });

  input.addEventListener("focus", function () {
    if (resultEl.children.length || input.value) resultEl.hidden = false;
    else render([], "");
  });

  input.addEventListener("keydown", function (ev) {
    var nodes = resultEl.querySelectorAll(".aiq-result");
    if (ev.key === "ArrowDown") {
      ev.preventDefault();
      if (nodes.length) setActive((activeIdx + 1) % nodes.length);
    } else if (ev.key === "ArrowUp") {
      ev.preventDefault();
      if (nodes.length) setActive((activeIdx - 1 + nodes.length) % nodes.length);
    } else if (ev.key === "Enter") {
      ev.preventDefault();
      if (activeIdx >= 0) open(currentResults[activeIdx]);
      else if (currentResults.length) open(currentResults[0]);
    } else if (ev.key === "Escape") {
      input.value = "";
      resultEl.hidden = true;
      input.blur();
    }
  });

  // Click handler on results (delegated)
  resultEl.addEventListener("click", function (ev) {
    var a = ev.target.closest(".aiq-result");
    if (!a) return;
    var idx = parseInt(a.getAttribute("data-idx"), 10);
    if (!isNaN(idx) && currentResults[idx] && currentResults[idx].p === path) {
      ev.preventDefault();
      open(currentResults[idx]);
    }
  });

  // Close on outside click
  document.addEventListener("click", function (ev) {
    if (!document.getElementById("aiq-search").contains(ev.target)) {
      resultEl.hidden = true;
    }
  });

  // "/" to focus, but not when typing in another field.
  document.addEventListener("keydown", function (ev) {
    if (ev.key !== "/") return;
    var t = ev.target;
    var tag = (t && t.tagName || "").toLowerCase();
    if (tag === "input" || tag === "textarea" || (t && t.isContentEditable)) return;
    ev.preventDefault();
    input.focus();
    input.select();
  });
})();
