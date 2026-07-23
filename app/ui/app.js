(() => {
  "use strict";

  const $ = (selector) => document.querySelector(selector);
  const $$ = (selector) => [...document.querySelectorAll(selector)];
  const unitColors = ["#ffba49", "#52b6ff", "#69db8f", "#ca82ff", "#ff6f76", "#f3df56"];
  const actionColors = { place: "#ff9a32", wait: "#8690a1", upgrade: "#5ba9ff", ability: "#c683ff", target: "#f2d755", sell: "#ff626b" };
  const actionIcons = { place: "P", wait: "W", upgrade: "U", ability: "A", target: "T", sell: "$" };
  const state = {
    strategy: null,
    strategies: [],
    reference: { w: 816, h: 638 },
    selectedUnit: 1,
    selectedAction: null,
    imageUrl: null,
    dirty: false,
    dragIndex: null,
    markerDrag: null,
    sequence: 0,
  };

  const bridge = {
    send(op, payload = {}) {
      try { window.webkit.messageHandlers.animeMacroBridge.postMessage({ op, payload }); }
      catch (error) { showToast(`Bridge unavailable: ${error.message}`, true); }
    }
  };

  const escapeHtml = (value) => String(value ?? "").replace(/[&<>'"]/g, c => ({"&":"&amp;","<":"&lt;",">":"&gt;","'":"&#39;",'"':"&quot;"}[c]));
  const number = (value, fallback = 0) => Number.isFinite(Number(value)) ? Number(value) : fallback;
  const nextId = (type) => `${type}-${Date.now().toString(36)}-${(++state.sequence).toString(36)}`;
  const placements = () => (state.strategy?.actions || []).filter(action => action.type === "place");

  function defaultOptions() {
    return {
      delay_ms: Math.max(0, number($("#placeDelay").value, 500)),
      upgrade_target: $("#upgradeTarget").value === "max" ? "max" : number($("#upgradeTarget").value),
      ability_mode: $("#abilityMode").value,
      target_mode: $("#targetMode").value,
    };
  }

  function newPlacement(x, y, unitSlot = state.selectedUnit) {
    return { id: nextId("place"), type: "place", unit_slot: Number(unitSlot), x: Math.round(x * 10) / 10, y: Math.round(y * 10) / 10, ...defaultOptions() };
  }

  function markDirty(value = true) {
    state.dirty = value;
    const badge = $("#dirtyBadge");
    badge.textContent = value ? "Unsaved" : "Saved";
    badge.className = `badge ${value ? "dirty" : "clean"}`;
  }

  function showToast(message, error = false) {
    const toast = $("#toast");
    toast.textContent = message;
    toast.className = `toast show${error ? " error" : ""}`;
    clearTimeout(showToast.timer);
    showToast.timer = setTimeout(() => toast.className = "toast", 2400);
  }

  function setStatus(text) { $("#statusText").textContent = text; }

  function syncMetadata() {
    if (!state.strategy) return;
    state.strategy.name = $("#strategyName").value.trim() || "Untitled Strategy";
    state.strategy.id = state.strategy.id || slug(state.strategy.name);
    state.strategy.map = $("#mapName").value.trim();
    state.strategy.stage = $("#stageName").value.trim();
    state.strategy.difficulty = $("#difficultyName").value.trim();
    state.strategy.team = $("#teamSelect").value;
  }

  function slug(value) {
    return value.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "").slice(0, 64) || "strategy";
  }

  function loadStrategy(strategy, clean = true) {
    state.strategy = structuredClone(strategy);
    state.reference = state.strategy.reference_resolution || state.reference;
    state.selectedAction = null;
    $("#strategyName").value = state.strategy.name || "";
    $("#mapName").value = state.strategy.map || "";
    $("#stageName").value = state.strategy.stage || "";
    $("#difficultyName").value = state.strategy.difficulty || "";
    $("#teamSelect").value = String(state.strategy.team || "current");
    renderAll();
    markDirty(!clean);
  }

  function renderStrategies() {
    const select = $("#strategySelect");
    select.innerHTML = '<option value="">Saved strategies…</option>' + state.strategies.map(item =>
      `<option value="${escapeHtml(item.id)}"${item.id === state.strategy?.id ? " selected" : ""}>${escapeHtml(item.name)} · ${item.placements} placements</option>`
    ).join("");
  }

  function renderUnitSlots() {
    $("#unitSlots").innerHTML = unitColors.map((color, index) =>
      `<button class="unit-slot${state.selectedUnit === index + 1 ? " active" : ""}" style="background:${color}" data-unit="${index + 1}" role="radio" aria-checked="${state.selectedUnit === index + 1}">${index + 1}</button>`
    ).join("");
  }

  function renderMarkers() {
    const list = placements();
    $("#markerLayer").innerHTML = list.map((action, index) => {
      const left = action.x / state.reference.w * 100;
      const top = action.y / state.reference.h * 100;
      const selected = action.id === state.selectedAction ? " selected" : "";
      return `<button class="marker${selected}" data-id="${escapeHtml(action.id)}" title="Unit ${action.unit_slot} · (${action.x}, ${action.y})" style="left:${left}%;top:${top}%;--unit-color:${unitColors[action.unit_slot - 1]}">${index + 1}</button>`;
    }).join("");
  }

  function placementOptions(selected) {
    const list = placements();
    if (!list.length) return '<option value="">No placements</option>';
    return list.map((place, index) => `<option value="${escapeHtml(place.id)}"${place.id === selected ? " selected" : ""}>#${index + 1} · Unit ${place.unit_slot}</option>`).join("");
  }

  function field(label, content) { return `<label>${label}${content}</label>`; }
  function input(action, key, type = "number", extras = "") { return `<input type="${type}" data-field="${key}" value="${escapeHtml(action[key] ?? "")}" ${extras}>`; }
  function select(action, key, options) { return `<select data-field="${key}">${options.map(([value,label]) => `<option value="${value}"${String(action[key]) === String(value) ? " selected" : ""}>${label}</option>`).join("")}</select>`; }

  function cardFields(action) {
    if (action.type === "place") return [
      field("Unit slot", select(action, "unit_slot", [1,2,3,4,5,6].map(n => [n, `Unit ${n}`]))),
      field("Delay (ms)", input(action, "delay_ms", "number", 'min="0" step="100"')),
      field("X", input(action, "x", "number", `min="0" max="${state.reference.w}" step="0.1"`)),
      field("Y", input(action, "y", "number", `min="0" max="${state.reference.h}" step="0.1"`)),
      field("Upgrade", select(action, "upgrade_target", [[0,"None"],[1,"+1"],[2,"+2"],[3,"+3"],[4,"+4"],[5,"+5"],["max","Max"]])),
      field("Ability", select(action, "ability_mode", [["off","Off"],["once","Once"],["auto","Auto"]])),
      field("Target", select(action, "target_mode", [["first","First"],["last","Last"],["strongest","Strongest"],["weakest","Weakest"],["closest","Closest"],["flying","Flying"]])),
    ].join("");
    if (action.type === "wait") return field("Duration (ms)", input(action, "duration_ms", "number", 'min="0" step="100"'));
    const target = field("Placement", `<select data-field="placement_id">${placementOptions(action.placement_id)}</select>`);
    if (action.type === "upgrade") return target + field("Levels", select(action, "levels", [[1,"+1"],[2,"+2"],[3,"+3"],[4,"+4"],[5,"+5"],["max","Max"]]));
    if (action.type === "ability") return target + field("Mode", select(action, "mode", [["once","Once"],["auto","Enable auto"],["off","Disable auto"]]));
    if (action.type === "target") return target + field("Priority", select(action, "mode", [["first","First"],["last","Last"],["strongest","Strongest"],["weakest","Weakest"],["closest","Closest"],["flying","Flying"]]));
    return target;
  }

  function renderTimeline() {
    const actions = state.strategy?.actions || [];
    $("#actionCount").textContent = `${actions.length} action${actions.length === 1 ? "" : "s"}`;
    $("#emptyTimeline").classList.toggle("visible", actions.length === 0);
    $("#timeline").innerHTML = actions.map((action, index) => {
      const label = action.type === "place" ? `Place Unit ${action.unit_slot}` : action.type[0].toUpperCase() + action.type.slice(1);
      return `<article class="action-card${state.selectedAction === action.id ? " selected" : ""}" draggable="true" data-index="${index}" data-id="${escapeHtml(action.id)}" style="--action-color:${actionColors[action.type]}">
        <div class="card-header"><span class="drag-handle">⠿</span><span class="action-icon">${actionIcons[action.type]}</span><span class="card-title">${label}</span><span class="card-index">${index + 1}</span><button class="icon-button remove-action" title="Remove">×</button></div>
        <div class="card-fields">${cardFields(action)}</div>
      </article>`;
    }).join("");
  }

  function renderAll() {
    renderStrategies(); renderUnitSlots(); renderMarkers(); renderTimeline();
  }

  function addPlacement(x, y, slot) {
    if (!state.strategy) return;
    const action = newPlacement(x, y, slot);
    state.strategy.actions.push(action);
    state.selectedAction = action.id;
    markDirty(); renderMarkers(); renderTimeline();
  }

  function addAction(type) {
    const first = placements()[0];
    if (type !== "wait" && !first) { showToast("Add a placement first", true); return; }
    const base = { id: nextId(type), type, delay_ms: 0 };
    if (type === "wait") base.duration_ms = 1000;
    else base.placement_id = first.id;
    if (type === "upgrade") base.levels = 1;
    if (type === "ability") base.mode = "once";
    if (type === "target") base.mode = "first";
    state.strategy.actions.push(base);
    state.selectedAction = base.id;
    markDirty(); renderTimeline();
    $("#timeline").scrollTop = $("#timeline").scrollHeight;
  }

  function updateField(card, target) {
    const action = state.strategy.actions[Number(card.dataset.index)];
    if (!action) return;
    const key = target.dataset.field;
    const numeric = ["unit_slot","delay_ms","x","y","duration_ms"].includes(key);
    let value = numeric ? number(target.value) : target.value;
    if (["upgrade_target","levels"].includes(key) && value !== "max") value = number(value);
    action[key] = value;
    markDirty(); renderMarkers();
    if (["unit_slot"].includes(key)) renderTimeline();
  }

  function installEvents() {
    $("#captureBtn").addEventListener("click", () => { setStatus("Capturing Roblox…"); bridge.send("capture"); });
    $("#recordBtn").addEventListener("click", () => bridge.send("record", { unit_slot: state.selectedUnit }));
    $("#previewBtn").addEventListener("click", () => { syncMetadata(); bridge.send("preview", { strategy: state.strategy }); });
    $("#saveBtn").addEventListener("click", () => { syncMetadata(); if (state.strategy.id === "new-strategy") state.strategy.id = slug(state.strategy.name); bridge.send("save", { strategy: state.strategy }); });
    $("#newBtn").addEventListener("click", () => { if (!state.dirty || confirm("Discard unsaved changes?")) bridge.send("new"); });
    $("#importBtn").addEventListener("click", () => bridge.send("import"));
    $("#copyBtn").addEventListener("click", () => { syncMetadata(); bridge.send("copy_json", { strategy: state.strategy }); });
    $("#strategySelect").addEventListener("change", event => { if (event.target.value && (!state.dirty || confirm("Discard unsaved changes?"))) bridge.send("load", { id: event.target.value }); });
    $("#deleteStrategyBtn").addEventListener("click", () => { if (state.strategy?.id && confirm(`Delete “${state.strategy.name}”?`)) bridge.send("delete", { id: state.strategy.id }); });
    ["#strategyName","#mapName","#stageName","#difficultyName","#teamSelect"].forEach(selector => $(selector).addEventListener("input", () => { syncMetadata(); markDirty(); }));

    $("#unitSlots").addEventListener("click", event => { const button = event.target.closest("[data-unit]"); if (button) { state.selectedUnit = Number(button.dataset.unit); renderUnitSlots(); } });
    $$(".action-toolbar button").forEach(button => button.addEventListener("click", () => addAction(button.dataset.add)));

    const canvas = $("#stageCanvas");
    canvas.addEventListener("mousemove", event => {
      const rect = canvas.getBoundingClientRect();
      const x = Math.max(0, Math.min(state.reference.w, (event.clientX - rect.left) / rect.width * state.reference.w));
      const y = Math.max(0, Math.min(state.reference.h, (event.clientY - rect.top) / rect.height * state.reference.h));
      $("#coordinateReadout").textContent = `x ${x.toFixed(1)} · y ${y.toFixed(1)}`;
    });
    canvas.addEventListener("mouseleave", () => $("#coordinateReadout").textContent = "x — · y —");
    canvas.addEventListener("click", event => {
      if (event.target.closest(".marker")) return;
      const rect = canvas.getBoundingClientRect();
      addPlacement((event.clientX - rect.left) / rect.width * state.reference.w, (event.clientY - rect.top) / rect.height * state.reference.h);
    });
    $("#markerLayer").addEventListener("pointerdown", event => {
      const marker = event.target.closest(".marker"); if (!marker) return;
      event.preventDefault(); marker.setPointerCapture(event.pointerId);
      state.markerDrag = { id: marker.dataset.id, pointerId: event.pointerId };
      state.selectedAction = marker.dataset.id; renderMarkers(); renderTimeline();
    });
    $("#markerLayer").addEventListener("pointermove", event => {
      if (!state.markerDrag) return;
      const rect = canvas.getBoundingClientRect();
      const action = state.strategy.actions.find(item => item.id === state.markerDrag.id); if (!action) return;
      action.x = Math.round(Math.max(0, Math.min(state.reference.w, (event.clientX - rect.left) / rect.width * state.reference.w)) * 10) / 10;
      action.y = Math.round(Math.max(0, Math.min(state.reference.h, (event.clientY - rect.top) / rect.height * state.reference.h)) * 10) / 10;
      const marker = event.target.closest(".marker"); if (marker) { marker.style.left = `${action.x/state.reference.w*100}%`; marker.style.top = `${action.y/state.reference.h*100}%`; }
      markDirty();
    });
    $("#markerLayer").addEventListener("pointerup", () => { if (state.markerDrag) { state.markerDrag = null; renderTimeline(); } });

    const timeline = $("#timeline");
    timeline.addEventListener("click", event => {
      const card = event.target.closest(".action-card"); if (!card) return;
      state.selectedAction = card.dataset.id;
      if (event.target.closest(".remove-action")) {
        const removed = state.strategy.actions.splice(Number(card.dataset.index), 1)[0];
        if (removed.type === "place") state.strategy.actions = state.strategy.actions.filter(item => item.placement_id !== removed.id);
        state.selectedAction = null; markDirty(); renderAll(); return;
      }
      renderMarkers(); $$(".action-card").forEach(item => item.classList.toggle("selected", item.dataset.id === state.selectedAction));
    });
    timeline.addEventListener("change", event => { const card = event.target.closest(".action-card"); if (card && event.target.dataset.field) updateField(card, event.target); });
    timeline.addEventListener("dragstart", event => { const card = event.target.closest(".action-card"); if (card) { state.dragIndex = Number(card.dataset.index); card.classList.add("dragging"); } });
    timeline.addEventListener("dragend", event => { event.target.closest(".action-card")?.classList.remove("dragging"); state.dragIndex = null; });
    timeline.addEventListener("dragover", event => event.preventDefault());
    timeline.addEventListener("drop", event => {
      event.preventDefault(); const target = event.target.closest(".action-card"); if (!target || state.dragIndex === null) return;
      const to = Number(target.dataset.index); const [action] = state.strategy.actions.splice(state.dragIndex, 1); state.strategy.actions.splice(to, 0, action);
      markDirty(); renderTimeline();
    });
  }

  window.MacroApp = {
    receive(message) {
      const { event, payload } = message;
      if (event === "bootstrap") {
        state.strategies = payload.strategies || []; state.reference = payload.reference_resolution; loadStrategy(payload.strategy); setStatus("Ready — capture or record placements");
      } else if (event === "strategy") loadStrategy(payload);
      else if (event === "capture") {
        state.imageUrl = payload.image_url; $("#stageImage").src = payload.image_url; $("#stageCanvas").classList.add("has-image"); $("#capturePath").textContent = payload.path; setStatus(payload.blank_or_solid ? "Capture may be blank" : "Live capture loaded"); showToast("Roblox capture loaded");
      } else if (event === "recorded_point") { addPlacement(payload.x, payload.y, payload.unit_slot); showToast(`Recorded Unit ${payload.unit_slot} at ${payload.x}, ${payload.y}`); }
      else if (event === "saved") { state.strategies = payload.strategies || state.strategies; loadStrategy(payload.strategy); showToast("Strategy saved"); }
      else if (event === "deleted") { state.strategies = payload.strategies || []; bridge.send("new"); showToast("Strategy deleted"); }
      else if (event === "toast") showToast(payload.message);
      else if (event === "error") { showToast(payload.message, true); setStatus(`Error: ${payload.message}`); }
    }
  };

  document.addEventListener("DOMContentLoaded", () => { installEvents(); renderUnitSlots(); bridge.send("ready"); });
})();
