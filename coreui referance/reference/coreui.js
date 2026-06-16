/* ============================================================================
   CoreUI UI — versatile GUI library
   ----------------------------------------------------------------------------
   A declarative dark-theme component kit. The API mirrors Roblox UI libraries
   (a declarative style) so it converts to Luau almost line-for-line.

   Every component factory returns a HANDLE with :set() / :get() (where stateful)
   plus the DOM element, exactly like a Lua object you call :Set() on.

   JS                                       Luau equivalent
   ---------------------------------------------------------------------------
   CoreUI.createWindow({...})              -> CoreUI:CreateWindow({...})
   win.tab({icon,name})                  -> Window:CreateTab(name, icon)
   win.notify({title,text})              -> CoreUI:Notify({Title, Content})
   tab.group({title,col})                -> Tab:CreateGroup(title)
   group.sub({title})                    -> Group:CreateSection(title)

   group.button({name,desc,label})       -> Group:CreateButton({Name, Callback})
   group.buttonRow([...])                -> two buttons in a row
   group.toggle({name,desc,value})       -> Group:CreateToggle({Name, Default, Callback})
   group.slider({name,min,max,value})    -> Group:CreateSlider({Name, Min, Max, Default})
   group.dropdown({name,options,value})  -> Group:CreateDropdown({Name, Options})
   group.multi({name,options,value})     -> Group:CreateDropdown({MultiSelect=true})
   group.input({name,placeholder})       -> Group:CreateInput({Name, Placeholder})
   group.keybind({name,value})           -> Group:CreateKeybind({Name, Default})
   group.color({name,value})             -> Group:CreateColorpicker({Name, Default})
   group.paragraph({title,body})         -> Group:CreateParagraph({Title, Content})
   group.label({key,value})              -> Group:CreateLabel(...)
   group.divider()                       -> Group:CreateDivider()
   group.list([...])                     -> a bullet list
   group.player({username,...})          -> a player / info panel
   ============================================================================ */

(function (global) {
  "use strict";

  /* ---- icons (stroke = currentColor) ------------------------------------- */
  const I = {
    logo: `<svg viewBox="0 0 32 32" fill="none"><defs><linearGradient id="rg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#ff8a3d"/><stop offset="1" stop-color="#f2680c"/></linearGradient></defs><rect x="3" y="3" width="26" height="26" rx="8" fill="url(#rg)"/><circle cx="16" cy="16" r="6.6" stroke="#fff" stroke-width="2.2" fill="none"/><circle cx="16" cy="16" r="2.7" fill="#fff"/></svg>`,
    home:   s(`<path d="M4 11 12 4l8 7"/><path d="M6 10v9h12v-9"/><path d="M10 19v-5h4v5"/>`),
    cursor: s(`<path d="M5 4l13 7-5.5 1.8L11 19 5 4Z"/>`),
    input:  s(`<rect x="3" y="6" width="18" height="12" rx="2"/><path d="M7 10v4M7 12h2"/><path d="M12 14h5"/>`),
    list:   s(`<path d="M8 6h12M8 12h12M8 18h12"/><circle cx="4" cy="6" r="1.1"/><circle cx="4" cy="12" r="1.1"/><circle cx="4" cy="18" r="1.1"/>`),
    palette:s(`<path d="M12 3a9 9 0 1 0 0 18c1.2 0 2-.9 2-2 0-.5-.2-1-.5-1.3-.3-.4-.5-.8-.5-1.2 0-1 .9-1.7 1.9-1.7H17a4 4 0 0 0 4-4c0-3.9-4-6.8-9-6.8Z"/><circle cx="7.5" cy="11" r="1"/><circle cx="12" cy="7.5" r="1"/><circle cx="16.5" cy="11" r="1"/>`),
    layers: s(`<path d="M12 3 3 8l9 5 9-5-9-5Z"/><path d="m3 14 9 5 9-5"/>`),
    bug:    s(`<path d="M9 8a3 3 0 0 1 6 0M8 8h8a4 4 0 0 1 4 4v2a8 8 0 0 1-16 0v-2a4 4 0 0 1 4-4Z"/><path d="M12 10v9M4 11H2.5M4 16l-2 1M4 7 2.5 6M20 11h1.5M20 16l2 1M20 7l1.5-1"/>`),
    person: s(`<circle cx="12" cy="8" r="3.6"/><path d="M5 20c.6-3.6 3.4-6 7-6s6.4 2.4 7 6"/>`),
    gear:   s(`<circle cx="12" cy="12" r="3.1"/><path d="M19.4 13c.04-.33.06-.66.06-1s-.02-.67-.06-1l2-1.5-2-3.5-2.3 1c-.5-.42-1.08-.76-1.7-1l-.35-2.5h-4l-.35 2.5c-.62.24-1.2.58-1.7 1l-2.3-1-2 3.5 2 1.5c-.04.33-.06.66-.06 1s.02.67.06 1l-2 1.5 2 3.5 2.3-1c.5.42 1.08.76 1.7 1l.35 2.5h4l.35-2.5c.62-.24 1.2-.58 1.7-1l2.3 1 2-3.5-2-1.5Z"/>`),
    search: s(`<circle cx="11" cy="11" r="7"/><path d="m20 20-3.2-3.2"/>`),
    min:    s(`<path d="M5 12h14"/>`),
    max:    `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><rect x="5" y="5" width="14" height="14" rx="2"/></svg>`,
    close:  s(`<path d="M6 6l12 12M18 6 6 18"/>`),
    chev:   s(`<path d="m6 15 6-6 6 6"/>`),
    ddchev: s(`<path d="m6 9 6 6 6-6"/>`),
    check:  s(`<path d="m5 12 5 5L20 7"/>`),
    avatar: s(`<circle cx="12" cy="9" r="4"/><path d="M5 20c.5-3.5 3.3-6 7-6s6.5 2.5 7 6"/>`),
  };
  function s(inner) {
    return `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">${inner}</svg>`;
  }
  function el(tag, cls, html) {
    const n = document.createElement(tag);
    if (cls) n.className = cls;
    if (html != null) n.innerHTML = html;
    return n;
  }
  function clamp(v, a, b) { return Math.max(a, Math.min(b, v)); }

  /* close every open popover (dropdown / colour) ------------------------- */
  document.addEventListener("click", (e) => {
    document.querySelectorAll(".coreui-dropdown.is-open, .coreui-color.is-open").forEach((d) => {
      if (!d.contains(e.target)) d.classList.remove("is-open");
    });
  });

  /* build the "name + description" header used by most fields ------------- */
  function fieldHead(o) {
    const main = el("div", "coreui-field-main");
    main.appendChild(el("div", "coreui-field-name", o.name || ""));
    if (o.desc) main.appendChild(el("div", "coreui-field-desc", o.desc));
    return main;
  }

  /* =======================================================================
     CONTROLS — shared by Group cards and Subsections
     ===================================================================== */
  function makeControls(mount) {
    const api = {};

    /* ---- toggle ---------------------------------------------------------- */
    api.toggle = function (o) {
      o = o || {};
      const f = el("div", "coreui-field");
      const row = el("div", "coreui-field-row");
      row.appendChild(fieldHead(o));
      const t = el("button", "coreui-toggle" + (o.value ? " is-on" : ""));
      t.type = "button";
      const fire = () => o.onChange && o.onChange(t.classList.contains("is-on"));
      t.addEventListener("click", () => { t.classList.toggle("is-on"); fire(); });
      row.appendChild(t);
      f.appendChild(row); mount.appendChild(f);
      return { element: t, get: () => t.classList.contains("is-on"),
               set: (v) => { t.classList.toggle("is-on", !!v); fire(); } };
    };

    /* ---- slider ---------------------------------------------------------- */
    api.slider = function (o) {
      o = o || {};
      const min = o.min ?? 0, max = o.max ?? 100, step = o.step ?? 1;
      let val = clamp(o.value ?? min, min, max);
      const f = el("div", "coreui-field is-stack");
      const row = el("div", "coreui-field-row");
      row.appendChild(fieldHead(o));
      const valBox = el("div", "coreui-slider-val", String(val) + (o.suffix || ""));
      row.appendChild(valBox);
      f.appendChild(row);

      const track = el("div", "coreui-slider coreui-field-control");
      const fill = el("div", "coreui-slider-fill");
      const knob = el("div", "coreui-slider-knob");
      track.appendChild(fill); track.appendChild(knob);
      f.appendChild(track); mount.appendChild(f);

      function render() {
        const pct = (val - min) / (max - min);
        fill.style.width = (pct * 100) + "%";
        knob.style.left = (pct * 100) + "%";
        valBox.textContent = String(val) + (o.suffix || "");
      }
      function setFromX(clientX) {
        const r = track.getBoundingClientRect();
        let pct = clamp((clientX - r.left) / r.width, 0, 1);
        let raw = min + pct * (max - min);
        val = clamp(Math.round(raw / step) * step, min, max);
        render(); o.onChange && o.onChange(val);
      }
      let dragging = false;
      track.addEventListener("pointerdown", (e) => { dragging = true; setFromX(e.clientX); });
      window.addEventListener("pointermove", (e) => dragging && setFromX(e.clientX));
      window.addEventListener("pointerup", () => dragging = false);
      render();
      return { element: track, get: () => val,
               set: (v) => { val = clamp(v, min, max); render(); o.onChange && o.onChange(val); } };
    };

    /* ---- dropdown (single) & multi --------------------------------------- */
    function buildDropdown(o, multi) {
      o = o || {};
      const opts = o.options || [];
      let single = o.value ?? null;
      let selected = new Set(multi ? (o.value || []) : []);

      const f = el("div", "coreui-field" + (o.stack ? " is-stack" : ""));
      const row = el("div", "coreui-field-row");
      if (o.name) row.appendChild(fieldHead(o));
      const dd = el("div", "coreui-dropdown coreui-field-control");
      const box = el("button", "coreui-dd-box" + (multi ? " is-multi" : ""));
      box.type = "button";
      const valEl = el("span", "coreui-dd-val");
      box.appendChild(valEl);
      box.appendChild(el("span", "coreui-dd-chev", I.ddchev));
      const menu = el("div", "coreui-dd-menu");
      dd.appendChild(box); dd.appendChild(menu);
      if (o.width) box.style.minWidth = o.width + "px";

      function label() {
        if (multi) {
          if (!selected.size) { valEl.textContent = o.placeholder || "None"; valEl.classList.remove("has-val"); }
          else { valEl.textContent = [...selected].join(", "); valEl.classList.add("has-val"); }
        } else {
          valEl.textContent = single ?? (o.placeholder || "None");
          valEl.classList.toggle("has-val", single != null);
        }
      }
      function rebuild() {
        menu.innerHTML = "";
        opts.forEach((opt) => {
          const sel = multi ? selected.has(opt) : single === opt;
          const oi = el("div", "coreui-dd-opt" + (sel ? " is-sel" : ""));
          oi.appendChild(el("span", "coreui-dd-tick", I.check));
          oi.appendChild(el("span", null, opt));
          oi.addEventListener("click", (e) => {
            e.stopPropagation();
            if (multi) {
              selected.has(opt) ? selected.delete(opt) : selected.add(opt);
              label(); rebuild(); o.onChange && o.onChange([...selected]);
            } else {
              single = opt; label(); dd.classList.remove("is-open");
              o.onChange && o.onChange(single);
            }
          });
          menu.appendChild(oi);
        });
      }
      box.addEventListener("click", (e) => {
        e.stopPropagation();
        const open = dd.classList.contains("is-open");
        document.querySelectorAll(".coreui-dropdown.is-open,.coreui-color.is-open").forEach((x) => x.classList.remove("is-open"));
        if (!open) { rebuild(); dd.classList.add("is-open"); }
      });
      label(); rebuild();
      if (o.stack) { f.appendChild(row); f.appendChild(dd); }
      else { row.appendChild(dd); f.appendChild(row); }
      mount.appendChild(f);
      return { element: dd,
        get: () => multi ? [...selected] : single,
        set: (v) => { if (multi) selected = new Set(v || []); else single = v; label(); rebuild();
                      o.onChange && o.onChange(multi ? [...selected] : single); } };
    }
    api.dropdown = (o) => buildDropdown(o, false);
    api.multi = (o) => buildDropdown(o, true);

    /* ---- text input ------------------------------------------------------ */
    api.input = function (o) {
      o = o || {};
      const f = el("div", "coreui-field is-stack");
      const row = el("div", "coreui-field-row");
      row.appendChild(fieldHead(o));
      f.appendChild(row);
      const inp = el("input", "coreui-input coreui-field-control");
      inp.type = "text"; inp.placeholder = o.placeholder || "";
      if (o.value) inp.value = o.value;
      inp.addEventListener("input", () => o.onChange && o.onChange(inp.value));
      inp.addEventListener("keydown", (e) => { if (e.key === "Enter") o.onEnter && o.onEnter(inp.value); });
      f.appendChild(inp); mount.appendChild(f);
      return { element: inp, get: () => inp.value, set: (v) => { inp.value = v; } };
    };

    /* ---- keybind --------------------------------------------------------- */
    api.keybind = function (o) {
      o = o || {};
      let key = o.value || "None";
      const f = el("div", "coreui-field");
      const row = el("div", "coreui-field-row");
      row.appendChild(fieldHead(o));
      const b = el("button", "coreui-keybind", key);
      b.type = "button";
      function listen() {
        b.classList.add("is-listening"); b.textContent = "...";
        const onKey = (e) => {
          e.preventDefault();
          key = e.key === " " ? "Space" : (e.key.length === 1 ? e.key.toUpperCase() : e.key);
          b.textContent = key; b.classList.remove("is-listening");
          window.removeEventListener("keydown", onKey, true);
          o.onChange && o.onChange(key);
        };
        window.addEventListener("keydown", onKey, true);
      }
      b.addEventListener("click", listen);
      row.appendChild(b); f.appendChild(row); mount.appendChild(f);
      return { element: b, get: () => key, set: (v) => { key = v; b.textContent = v; } };
    };

    /* ---- colour picker --------------------------------------------------- */
    api.color = function (o) {
      o = o || {};
      let val = o.value || "#f2680c";
      const presets = o.presets || ["#f2680c","#ff5757","#ffb020","#34c759","#2dd4bf","#3b82f6","#8b5cf6","#ec4899","#ededf0","#8c8c94","#3a3a3e","#161618"];
      const f = el("div", "coreui-field");
      const row = el("div", "coreui-field-row");
      row.appendChild(fieldHead(o));
      const wrap = el("div", "coreui-color coreui-field-control");
      const sw = el("button", "coreui-color-sw"); sw.type = "button"; sw.style.setProperty("--cc", val);
      const menu = el("div", "coreui-color-menu");
      const grid = el("div", "coreui-color-grid");
      presets.forEach((c) => {
        const chip = el("button", "coreui-color-chip"); chip.type = "button"; chip.style.background = c;
        chip.addEventListener("click", (e) => { e.stopPropagation(); apply(c); });
        grid.appendChild(chip);
      });
      const native = el("div", "coreui-color-native");
      const inp = el("input"); inp.type = "color"; inp.value = val;
      inp.addEventListener("input", () => apply(inp.value));
      const hex = el("span", "coreui-color-hex", val.toUpperCase());
      native.appendChild(inp); native.appendChild(hex);
      menu.appendChild(grid); menu.appendChild(native);
      wrap.appendChild(sw); wrap.appendChild(menu);
      function apply(c) { val = c; sw.style.setProperty("--cc", c); inp.value = c; hex.textContent = c.toUpperCase(); o.onChange && o.onChange(c); }
      sw.addEventListener("click", (e) => {
        e.stopPropagation();
        const open = wrap.classList.contains("is-open");
        document.querySelectorAll(".coreui-dropdown.is-open,.coreui-color.is-open").forEach((x) => x.classList.remove("is-open"));
        if (!open) wrap.classList.add("is-open");
      });
      row.appendChild(wrap); f.appendChild(row); mount.appendChild(f);
      return { element: wrap, get: () => val, set: apply };
    };

    /* ---- buttons --------------------------------------------------------- */
    api.button = function (o) {
      o = o || {};
      if (o.name || o.desc) {           // titled button -> stacked field
        const f = el("div", "coreui-field is-stack");
        const row = el("div", "coreui-field-row");
        row.appendChild(fieldHead(o));
        f.appendChild(row);
        const b = el("button", "coreui-btn coreui-field-control" + (o.accent ? " is-accent" : ""), o.label || "Button");
        b.type = "button"; b.addEventListener("click", () => o.onClick && o.onClick());
        f.appendChild(b); mount.appendChild(f);
        return { element: b };
      }
      const wrap = el("div", "coreui-btnrow is-single");
      const b = el("button", "coreui-btn" + (o.accent ? " is-accent" : ""), o.label || "Button");
      b.type = "button"; b.addEventListener("click", () => o.onClick && o.onClick());
      wrap.appendChild(b); mount.appendChild(wrap);
      return { element: b };
    };

    api.buttonRow = function (list) {
      const wrap = el("div", "coreui-btnrow");
      (list || []).forEach((o) => {
        const b = el("button", "coreui-btn" + (o.accent ? " is-accent" : ""), o.label || "Button");
        b.type = "button"; b.addEventListener("click", () => o.onClick && o.onClick());
        wrap.appendChild(b);
      });
      mount.appendChild(wrap);
      return { element: wrap };
    };

    /* ---- text elements --------------------------------------------------- */
    api.paragraph = function (o) {
      o = o || {};
      const p = el("div", "coreui-paragraph");
      if (o.title) p.appendChild(el("div", "coreui-p-title", o.title));
      p.appendChild(el("div", "coreui-p-body", o.body || o.text || ""));
      mount.appendChild(p);
      return { element: p };
    };
    api.label = function (o) {
      o = o || {};
      const r = el("div", "coreui-labelrow");
      r.appendChild(el("span", "k", o.key || o.text || ""));
      if (o.value != null) r.appendChild(el("span", "v", o.value));
      mount.appendChild(r);
      return { element: r, set: (v) => { const ve = r.querySelector(".v"); if (ve) ve.textContent = v; } };
    };
    api.divider = function () { const d = el("div", "coreui-divider"); mount.appendChild(d); return { element: d }; };
    api.list = function (items) {
      const ul = el("ul", "coreui-list");
      (items || []).forEach((it) => {
        const li = el("li", it.dim ? "is-dim" : "");
        li.innerHTML = it.name ? `<b>${it.name}:</b> ${it.value || ""}` : (it.text || "");
        ul.appendChild(li);
      });
      mount.appendChild(ul);
      return { element: ul };
    };

    /* ---- player / info card --------------------------------------------- */
    api.player = function (o) {
      o = o || {};
      const p = el("div", "coreui-player");
      const av = el("div", "coreui-avatar", o.avatar ? "" : I.avatar);
      if (o.avatar) { const img = el("img"); img.src = o.avatar; av.innerHTML = ""; av.appendChild(img); }
      const info = el("div", "coreui-player-info");
      const nameRow = el("div", "coreui-player-name");
      nameRow.appendChild(el("span", null, o.displayName || o.username || "Player"));
      if (o.badge) nameRow.appendChild(el("span", "coreui-badge", o.badge));
      info.appendChild(nameRow);
      const sub = "@" + (o.username || "player") + (o.userId ? "  ·  ID " + o.userId : "");
      info.appendChild(el("div", "coreui-player-sub", sub));
      p.appendChild(av); p.appendChild(info);
      mount.appendChild(p);
      return { element: p };
    };

    /* ---- nested collapsible subsection ----------------------------------- */
    api.sub = function (o) {
      o = o || {};
      const sub = el("div", "coreui-sub" + (o.collapsed ? " is-collapsed" : ""));
      const head = el("div", "coreui-sub-head");
      head.appendChild(el("div", "coreui-sub-title", o.title || "Section"));
      head.appendChild(el("div", "coreui-chev", I.chev));
      const body = el("div", "coreui-sub-body");
      head.addEventListener("click", (e) => { if (!e.target.closest("button,input,.coreui-dropdown,.coreui-color")) sub.classList.toggle("is-collapsed"); });
      sub.appendChild(head); sub.appendChild(body); mount.appendChild(sub);
      return makeControls(body);
    };

    api._mount = mount;
    return api;
  }

  /* =======================================================================
     GROUP
     ===================================================================== */
  function makeGroup(col, o) {
    o = o || {};
    const group = el("div", "coreui-group" + (o.collapsed ? " is-collapsed" : ""));
    const head = el("div", "coreui-group-head");
    head.appendChild(el("div", "coreui-group-title", o.title || "Group"));
    head.appendChild(el("div", "coreui-chev", I.chev));
    const card = el("div", "coreui-card");
    head.addEventListener("click", (e) => { if (!e.target.closest("button,input,.coreui-dropdown,.coreui-color")) group.classList.toggle("is-collapsed"); });
    group.appendChild(head); group.appendChild(card); col.appendChild(group);
    return makeControls(card);
  }

  /* =======================================================================
     WINDOW
     ===================================================================== */
  function createWindow(opts) {
    opts = opts || {};
    const mount = opts.mount || document.body;

    const backdrop = el("div", "coreui-backdrop");
    const win = el("div", "coreui-window");

    const bar = el("div", "coreui-titlebar");
    bar.appendChild(el("div", "coreui-logo", I.logo));
    bar.appendChild(el("div", "coreui-title", opts.title || "CoreUI"));
    const btns = el("div", "coreui-winbtns");
    [["search", I.search], ["min", I.min], ["max", I.max], ["close", I.close]].forEach(([n, ic]) => {
      const b = el("button", "coreui-winbtn" + (n === "close" ? " is-close" : ""), ic);
      b.type = "button"; b.dataset.act = n; btns.appendChild(b);
    });
    bar.appendChild(btns);

    const body = el("div", "coreui-body");
    const sidebar = el("div", "coreui-sidebar");
    const content = el("div", "coreui-content");
    body.appendChild(sidebar); body.appendChild(content);

    const status = el("div", "coreui-statusbar");
    const stLeft = el("div", "coreui-st-left", "—");
    status.appendChild(stLeft);
    status.appendChild(el("div", "coreui-st-mid", opts.subtitle || ""));
    status.appendChild(el("div", "coreui-st-right", opts.version || ""));

    const toasts = el("div", "coreui-toasts");

    win.appendChild(bar); win.appendChild(body); win.appendChild(status); win.appendChild(toasts);
    backdrop.appendChild(win); mount.appendChild(backdrop);

    if (opts.liveClock !== false) {
      const tick = () => {
        const d = new Date(); let h = d.getHours(); const m = d.getMinutes();
        const ap = h >= 12 ? "PM" : "AM"; h = h % 12 || 12;
        stLeft.textContent = `${h}:${String(m).padStart(2, "0")} ${ap}`;
      };
      tick(); setInterval(tick, 10000);
    } else { stLeft.textContent = opts.time || ""; }

    const tabs = [];
    function select(i) {
      tabs.forEach((t, j) => { t.btn.classList.toggle("is-active", j === i); t.page.classList.toggle("is-active", j === i); });
      content.scrollTop = 0;
    }

    const winApi = {
      tab(o) {
        o = o || {};
        const btn = el("button", "coreui-navbtn", I[o.icon] || I.gear);
        btn.type = "button"; if (o.name) btn.dataset.tip = o.name;
        const page = el("div", "coreui-page" + (o.single ? " is-single" : ""));
        const cols = el("div", "coreui-columns");
        const colEls = [el("div", "coreui-col")];
        if (!o.single) colEls.push(el("div", "coreui-col"));
        colEls.forEach((c) => cols.appendChild(c));
        page.appendChild(cols);
        sidebar.appendChild(btn); content.appendChild(page);
        const idx = tabs.length;
        btn.addEventListener("click", () => select(idx));
        tabs.push({ btn, page });
        if (idx === (opts.active || 0)) select(idx);
        return { group: (g) => makeGroup(colEls[(g && g.col) || 0] || colEls[0], g), select: () => select(idx), el: page };
      },
      notify(o) {
        o = o || {};
        const t = el("div", "coreui-toast");
        if (o.title) t.appendChild(el("div", "coreui-toast-title", o.title));
        t.appendChild(el("div", "coreui-toast-text", o.text || o.content || ""));
        toasts.appendChild(t);
        setTimeout(() => { t.classList.add("is-out"); setTimeout(() => t.remove(), 260); }, o.duration || 3200);
      },
      select,
    };
    return winApi;
  }

  global.CoreUI = { createWindow };
})(window);
