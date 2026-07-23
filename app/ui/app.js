(() => {
  "use strict";

  const $ = selector => document.querySelector(selector);
  const $$ = selector => [...document.querySelectorAll(selector)];
  const colors = ["#f5b942", "#5ba8ff", "#50d18b", "#b585ff", "#ff727b", "#ece06b"];
  const actionColors = {
    place: "#f5a142", auto_upgrade: "#47d18c", upgrade: "#5ba8ff",
    ability: "#b585ff", target: "#e7d45a", sell: "#ef626c", wait: "#7d8797",
  };

  const state = {
    profile: null,
    tasks: [],
    strategy: null,
    strategies: [],
    catalog: { modes: [], stages: [], difficulties: [], teams: [] },
    runtime: { active: false, paused: false, state: "IDLE", stats: {}, challenges: {}, crafting: {} },
    status: {},
    selectedTask: 0,
    selectedAction: null,
    selectedPlacement: null,
    markerDrag: null,
    actionDrag: null,
    sequence: 0,
    mapUrl: null,
    startedAt: null,
    dirty: false,
  };

  const bridge = {
    send(op, payload = {}) {
      try {
        window.webkit.messageHandlers.animeMacroBridge.postMessage({ op, payload });
      } catch (error) {
        toast(`bridge error: ${error.message}`, true);
      }
    },
  };

  const escapeHtml = value => String(value ?? "").replace(/[&<>'"]/g, char => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", "'": "&#39;", '"': "&quot;",
  })[char]);
  const number = (value, fallback = 0) => Number.isFinite(Number(value)) ? Number(value) : fallback;
  const slug = value => String(value || "").toLowerCase().replace(/['’]/g, "").replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "").slice(0, 64) || "strategy";
  const nextId = type => `${type}-${Date.now().toString(36)}-${(++state.sequence).toString(36)}`;
  const placements = () => (state.strategy?.actions || []).filter(action => action.type === "place");
  const findPlacement = id => placements().find(action => action.id === id);
  const optionList = (values, selected) => values.map(value => {
    const key = typeof value === "object" ? value.id : value;
    const label = typeof value === "object" ? (value.name || value.id) : value;
    return `<option value="${escapeHtml(key)}"${String(key) === String(selected) ? " selected" : ""}>${escapeHtml(label)}</option>`;
  }).join("");

  function toast(message, error = false) {
    const element = $("#toast");
    element.textContent = message;
    element.className = `toast show${error ? " error" : ""}`;
    clearTimeout(toast.timer);
    toast.timer = setTimeout(() => { element.className = "toast"; }, 2600);
  }

  function log(message, level = "") {
    const list = $("#logList");
    const entry = document.createElement("div");
    entry.className = `log-entry ${level}`;
    const now = new Date();
    entry.innerHTML = `<time>${now.toLocaleTimeString([], { hour12: false, hour: "2-digit", minute: "2-digit", second: "2-digit" })}</time><span>${escapeHtml(message)}</span>`;
    list.append(entry);
    while (list.children.length > 100) list.firstChild.remove();
    list.scrollTop = list.scrollHeight;
  }

  function markDirty(dirty = true) {
    state.dirty = dirty;
    $("#saveState").textContent = dirty ? "unsaved changes" : "saved";
  }

  function showView(name) {
    $$(".tab").forEach(tab => tab.classList.toggle("active", tab.dataset.view === name));
    $$(".view").forEach(view => view.classList.toggle("active", view.id === `view-${name}`));
    if (name === "positions") renderPositions();
    bridge.send("view_changed", { view: name });
  }

  function setDockStatus(payload) {
    const docked = !!payload.docked;
    $("#dashboardPreview").classList.toggle("docked", docked);
    const indicator = $("#dockStatus");
    indicator.classList.toggle("docked", docked);
    indicator.lastChild.textContent = docked ? " docked" : " waiting";
    $("#previewLabel").textContent = payload.message || (docked ? "real roblox window" : "waiting for roblox");
  }

  function setMap(payload) {
    state.mapUrl = payload?.image_url || null;
    if (state.mapUrl) {
      $("#positionImage").src = state.mapUrl;
      $("#positionCanvas").classList.add("has-image");
    } else {
      $("#positionImage").removeAttribute("src");
      $("#positionCanvas").classList.remove("has-image");
    }
    renderMarkers();
  }

  function runtimePill() {
    const pill = $("#runtimePill");
    const active = !!state.runtime.active;
    const paused = !!state.runtime.paused;
    const errored = state.runtime.state === "RECOVERY";
    pill.className = `pill ${errored ? "error" : paused ? "paused" : active ? "running" : "idle"}`;
    pill.querySelector("span").textContent = errored ? "error" : paused ? "paused" : active ? "running" : "idle";
    $("#stateText").textContent = state.runtime.state || "IDLE";
    $("#currentTaskText").textContent = state.runtime.task || "no active task";
    $("#startBtn").disabled = active;
    $("#dashboardStartBtn").disabled = active;
    $("#pauseBtn").disabled = !active;
    $("#pauseBtn").textContent = paused ? "resume" : "pause";
    $("#stopBtn").disabled = !active;
    $("#inputDot").classList.toggle("armed", active && !paused);
    $("#inputStatus").textContent = active && !paused ? "run input active" : "input disarmed";
    const stats = state.runtime.stats || {};
    $("#runsStat").textContent = stats.runs || 0;
    $("#winsStat").textContent = stats.victories || 0;
    $("#lossesStat").textContent = stats.defeats || 0;
    $("#rateStat").textContent = `${stats.win_rate || 0}%`;
  }

  function renderReadyChecks(status = {}) {
    state.status = { ...state.status, ...status };
    status = state.status;
    const checks = [
      ["#checkRoblox", status.roblox_window_found],
      ["#checkAccess", status.accessibility],
      ["#checkScreen", status.screen_recording],
      ["#checkVision", status.vision_connected],
      ["#checkWebhook", status.webhook_configured, true],
    ];
    checks.forEach(([selector, good, optional]) => {
      const item = $(selector);
      item.classList.toggle("ok", !!good);
      item.classList.toggle("warn", optional && !good);
    });
  }

  function renderRunTasks() {
    const enabled = state.tasks.map((task, index) => ({ task, index })).filter(item => item.task.enabled !== false);
    const options = enabled.map(({ task, index }) =>
      `<option value="${index}">${escapeHtml(task.name)} · ${escapeHtml(task.map)} ${escapeHtml(task.stage)}</option>`
    ).join("");
    $("#runTaskSelect").innerHTML = options || '<option value="">no enabled tasks</option>';
    if (enabled.some(item => item.index === state.selectedTask)) $("#runTaskSelect").value = String(state.selectedTask);
    else if (enabled[0]) state.selectedTask = enabled[0].index;
    $("#taskCountBadge").textContent = String(state.tasks.length);
  }

  function strategyOptions(selected) {
    const list = state.strategies.map(item => ({ id: item.id, name: item.name }));
    return '<option value="">choose strategy</option>' + optionList(list, selected);
  }

  function taskRow(task, index) {
    const strategies = strategyOptions(task.strategy);
    return `<tr data-task-index="${index}" class="${index === state.selectedTask ? "selected" : ""}">
      <td><input class="task-enable" data-task-field="enabled" type="checkbox"${task.enabled !== false ? " checked" : ""}></td>
      <td><input data-task-field="name" value="${escapeHtml(task.name)}"></td>
      <td><select data-task-field="mode">${optionList(state.catalog.modes.map(mode => mode.id), task.mode)}</select></td>
      <td><input data-task-field="repetitions" type="number" min="1" value="${task.infinite ? 1 : escapeHtml(task.repetitions || 1)}" title="set infinite from row menu"></td>
      <td><input data-task-field="map" value="${escapeHtml(task.map)}"></td>
      <td><select data-task-field="stage">${optionList(state.catalog.stages, task.stage)}</select></td>
      <td><select data-task-field="difficulty">${optionList(state.catalog.difficulties, task.difficulty)}</select></td>
      <td><select data-task-field="team">${optionList(state.catalog.teams, task.team)}</select></td>
      <td><select data-task-field="strategy">${strategies}</select></td>
      <td><div class="row-actions">
        <button data-task-action="up" title="move up">↑</button>
        <button data-task-action="down" title="move down">↓</button>
        <button data-task-action="infinite" title="toggle infinite">${task.infinite ? "∞" : "1x"}</button>
        <button data-task-action="remove" class="remove" title="remove">×</button>
      </div></td>
    </tr>`;
  }

  function renderTasks() {
    $("#taskRows").innerHTML = state.tasks.map(taskRow).join("");
    const current = state.tasks[state.selectedTask];
    $("#taskSelectionText").textContent = current ? `selected: ${current.name}` : "no task selected";
    renderTaskDetails();
    renderRunTasks();
  }

  function renderTaskDetails() {
    const task = state.tasks[state.selectedTask];
    $("#taskChallengeKind").value = task?.challenge_kind || "";
    $("#taskRouteJson").value = task?.navigation_actions?.length
      ? JSON.stringify(task.navigation_actions, null, 2)
      : "";
    $("#taskTeamRouteJson").value = task?.team_actions?.length
      ? JSON.stringify(task.team_actions, null, 2)
      : "";
    $("#taskChallengeKind").disabled = !task;
    $("#taskRouteJson").disabled = !task;
    $("#taskTeamRouteJson").disabled = !task;
  }

  function syncTaskDetails(showErrors = true) {
    const task = state.tasks[state.selectedTask];
    if (!task) return true;
    const challengeKind = $("#taskChallengeKind").value;
    if (challengeKind) task.challenge_kind = challengeKind;
    else delete task.challenge_kind;
    const routeText = $("#taskRouteJson").value.trim();
    if (!routeText) {
      delete task.navigation_actions;
    } else {
      try {
        const actions = JSON.parse(routeText);
        if (!Array.isArray(actions)) throw new Error("route must be a JSON array");
        task.navigation_actions = actions;
      } catch (error) {
        if (showErrors) toast(`custom route: ${error.message}`, true);
        return false;
      }
    }
    const teamRouteText = $("#taskTeamRouteJson").value.trim();
    if (!teamRouteText) {
      delete task.team_actions;
      return true;
    }
    try {
      const actions = JSON.parse(teamRouteText);
      if (!Array.isArray(actions)) throw new Error("route must be a JSON array");
      task.team_actions = actions;
      return true;
    } catch (error) {
      if (showErrors) toast(`team route: ${error.message}`, true);
      return false;
    }
  }

  function defaultTask() {
    return {
      enabled: true,
      name: "new task",
      mode: "Story",
      map: "King's Tomb",
      stage: "Act 1",
      difficulty: "Mastery",
      team: "current",
      strategy: state.strategy?.id || state.strategies[0]?.id || "",
      repetitions: 1,
      infinite: false,
      retry: { maximum_consecutive_failures: 2, on_exhausted: "stop" },
    };
  }

  function loadStrategy(strategy, clean = true) {
    state.strategy = structuredClone(strategy);
    state.selectedAction = null;
    state.selectedPlacement = placements()[0]?.id || null;
    $("#strategyName").value = state.strategy.name || "";
    $("#strategyMap").value = state.strategy.map || "";
    $("#strategyStage").value = state.strategy.stage || "";
    $("#strategyDifficulty").value = state.strategy.difficulty || "";
    $("#strategyTeam").innerHTML = optionList(state.catalog.teams, state.strategy.team);
    $("#positionMode").value = state.tasks[state.selectedTask]?.mode || "Story";
    $("#positionMap").value = state.strategy.map || "";
    $("#positionStage").value = state.strategy.stage || "Act 1";
    $("#positionDifficulty").value = state.strategy.difficulty || "Mastery";
    $("#strategySelect").innerHTML = strategyOptions(state.strategy.id);
    $("#strategySelect").value = state.strategy.id;
    renderActions();
    renderPositions();
    if (clean) markDirty(false);
    bridge.send("load_map", { task: positionTask() });
  }

  function syncStrategyMeta() {
    if (!state.strategy) return;
    state.strategy.name = $("#strategyName").value.trim() || "new strategy";
    state.strategy.id = state.strategy.id === "new-strategy" ? slug(state.strategy.name) : state.strategy.id;
    state.strategy.map = $("#strategyMap").value.trim() || "King's Tomb";
    state.strategy.stage = $("#strategyStage").value.trim() || "Act 1";
    state.strategy.difficulty = $("#strategyDifficulty").value.trim() || "Mastery";
    state.strategy.team = $("#strategyTeam").value || "current";
  }

  function placementOptions(selected) {
    return placements().map((placement, index) =>
      `<option value="${escapeHtml(placement.id)}"${placement.id === selected ? " selected" : ""}>#${index + 1} · slot ${placement.unit_slot}</option>`
    ).join("") || '<option value="">no placements</option>';
  }

  function field(label, html, full = false) {
    return `<label class="field${full ? " full" : ""}">${label}${html}</label>`;
  }

  function inputField(action, key, type = "number", extra = "") {
    return `<input data-action-field="${key}" type="${type}" value="${escapeHtml(action[key] ?? "")}" ${extra}>`;
  }

  function selectField(action, key, values) {
    return `<select data-action-field="${key}">${optionList(values, action[key])}</select>`;
  }

  function actionFields(action) {
    const at = field("time (ms)", inputField(action, "at_ms", "number", 'min="0" step="500"'));
    if (action.type === "place") {
      return at
        + field("unit slot", selectField(action, "unit_slot", [1, 2, 3, 4, 5, 6]))
        + field("x", inputField(action, "x", "number", 'min="0" max="816" step="0.1"'))
        + field("y", inputField(action, "y", "number", 'min="0" max="638" step="0.1"'));
    }
    if (action.type === "wait") {
      return at + field("duration (ms)", inputField(action, "duration_ms", "number", 'min="0" step="500"'));
    }
    const placement = field("placement", `<select data-action-field="placement_id">${placementOptions(action.placement_id)}</select>`, true);
    if (action.type === "upgrade") return at + placement + field("levels", selectField(action, "levels", [1, 2, 3, 4, 5, "max"]));
    if (action.type === "ability") return at + placement + field("mode", selectField(action, "mode", ["once", "auto", "off"]));
    if (action.type === "target") return at + placement + field("priority", selectField(action, "mode", ["first", "last", "strongest", "weakest", "closest", "flying"]));
    return at + placement;
  }

  function renderActions() {
    const actions = state.strategy?.actions || [];
    $("#actionList").innerHTML = actions.map((action, index) =>
      `<article class="action-card${action.id === state.selectedAction ? " selected" : ""}" data-action-index="${index}" draggable="true" style="--action-color:${actionColors[action.type] || "#f5b942"}">
        <div class="action-header">
          <span class="action-index">${index + 1}</span>
          <strong>${escapeHtml(action.type.replace("_", " "))}</strong>
          <button data-remove-action="${index}" title="remove">×</button>
        </div>
        <div class="action-fields">${actionFields(action)}</div>
      </article>`
    ).join("");
  }

  function newAction(type) {
    const lastTime = Math.max(0, ...(state.strategy.actions || []).map(action => number(action.at_ms, 0)));
    const placement = placements()[0]?.id || "";
    const action = { id: nextId(type), type, at_ms: lastTime + 5000 };
    if (type === "place") Object.assign(action, { unit_slot: 1, x: 408, y: 319, target_mode: "first", ability_mode: "off", upgrade_target: 0 });
    if (type === "wait") action.duration_ms = 5000;
    if (["auto_upgrade", "upgrade", "ability", "target", "sell"].includes(type)) action.placement_id = placement;
    if (type === "upgrade") action.levels = 1;
    if (type === "ability") action.mode = "once";
    if (type === "target") action.mode = "first";
    state.strategy.actions.push(action);
    state.selectedAction = action.id;
    markDirty();
    renderActions();
    renderPositions();
  }

  function positionTask() {
    return {
      mode: $("#positionMode")?.value || state.tasks[state.selectedTask]?.mode || "Story",
      map: $("#positionMap")?.value || state.strategy?.map || "King's Tomb",
      stage: $("#positionStage")?.value || state.strategy?.stage || "Act 1",
      difficulty: $("#positionDifficulty")?.value || state.strategy?.difficulty || "Mastery",
      name: state.strategy?.name || "map",
    };
  }

  function renderMarkers() {
    const list = placements();
    $("#positionMarkers").innerHTML = list.map((placement, index) =>
      `<button class="placement-marker${placement.id === state.selectedPlacement ? " selected" : ""}"
        data-placement-id="${escapeHtml(placement.id)}"
        style="left:${placement.x / 816 * 100}%;top:${placement.y / 638 * 100}%;--marker-color:${colors[placement.unit_slot - 1]}">
        ${index + 1}
      </button>`
    ).join("");
  }

  function renderPositionFields() {
    const placement = findPlacement(state.selectedPlacement);
    if (!placement) {
      $("#positionX").value = "";
      $("#positionY").value = "";
      $("#positionAutoUpgrade").checked = false;
      return;
    }
    $("#positionUnitSlot").value = String(placement.unit_slot);
    $("#positionX").value = placement.x;
    $("#positionY").value = placement.y;
    $("#positionTime").value = placement.at_ms || 0;
    $("#positionAutoUpgrade").checked = state.strategy.actions.some(action => action.type === "auto_upgrade" && action.placement_id === placement.id);
  }

  function renderPositions() {
    if (!state.strategy) return;
    renderMarkers();
    renderPositionFields();
  }

  function addPosition(x, y) {
    const action = {
      id: nextId("place"),
      type: "place",
      unit_slot: number($("#positionUnitSlot").value, 1),
      x: Math.round(x * 10) / 10,
      y: Math.round(y * 10) / 10,
      at_ms: number($("#positionTime").value, 25000),
      target_mode: "first",
      ability_mode: "off",
      upgrade_target: 0,
    };
    state.strategy.actions.push(action);
    state.selectedPlacement = action.id;
    state.selectedAction = action.id;
    markDirty();
    renderActions();
    renderPositions();
  }

  function syncSettings() {
    if (!syncTaskDetails()) return false;
    const profile = state.profile;
    profile.runtime.start_action = $("#settingStartAction").value;
    profile.runtime.align_before_run = $("#settingAlign").checked;
    profile.runtime.auto_camera = $("#settingCamera").checked;
    profile.runtime.save_diagnostics = $("#settingDiagnostics").checked;
    profile.runtime.allow_return_to_lobby = $("#settingReturnLobby").checked;
    profile.runtime.queue_start_over = $("#taskStartOver").checked;
    profile.camera.zoom_in_presses = number($("#settingZoomIn").value, 18);
    profile.camera.pitch_drags = number($("#settingPitchDrags").value, 2);
    profile.camera.zoom_out_delta = number($("#settingZoomOut").value, -20);
    profile.camera.settle_ms = number($("#settingSettle").value, 1800);
    profile.crafting.enabled = $("#settingCraftEnabled").checked;
    profile.crafting.live_confirmation = $("#settingCraftConfirmed").checked;
    profile.crafting.trigger.every = number($("#settingCraftEvery").value, 20);
    try {
      const workflow = JSON.parse($("#settingCraftWorkflow").value || "[]");
      if (!Array.isArray(workflow)) throw new Error("workflow must be a JSON array");
      profile.crafting.workflow = workflow;
    } catch (error) {
      toast(`craft workflow: ${error.message}`, true);
      return false;
    }
    profile.challenges.enabled = $("#settingChallengesEnabled").checked;
    profile.challenges.check_interval_minutes = number($("#settingChallengeInterval").value, 30);
    profile.challenges.regular_cap = number($("#settingChallengeCap").value, 10);
    profile.challenges.caps = {
      regular_side: profile.challenges.regular_cap,
      hourly: number($("#settingChallengeHourlyCap").value, 1),
      daily: number($("#settingChallengeDailyCap").value, 1),
      weekly: number($("#settingChallengeWeeklyCap").value, 1),
    };
    profile.challenges.fallback_counters = $("#settingChallengeFallback").checked;
    profile.webhooks.enabled = $("#settingWebhookEnabled").checked;
    profile.webhooks.include_screenshot = $("#settingWebhookScreenshot").checked;
    profile.tasks = state.tasks;
    profile.teams = [...$("#teamSettings").querySelectorAll(".team-row")].map(row => ({
      id: row.querySelector('[data-team-field="id"]').value,
      name: row.querySelector('[data-team-field="name"]').value,
    })).filter(team => team.id && team.name);
    return true;
  }

  function renderChallengeStatuses(challenges = state.runtime.challenges || {}) {
    state.runtime.challenges = challenges || {};
    const labels = {
      regular_side: "regular side",
      hourly: "hourly",
      daily: "daily",
      weekly: "weekly",
    };
    $("#challengeStatusList").innerHTML = Object.entries(labels).map(([kind, label]) => {
      const status = state.runtime.challenges[kind] || {};
      return `<div><span>${label}</span><strong>${number(status.current, 0)} / ${number(status.maximum, kind === "regular_side" ? 10 : 1)}</strong></div>`;
    }).join("");
  }

  function renderSettings() {
    if (!state.profile) return;
    const profile = state.profile;
    $("#settingStartAction").value = profile.runtime.start_action || "auto";
    $("#settingAlign").checked = profile.runtime.align_before_run !== false;
    $("#settingCamera").checked = profile.runtime.auto_camera !== false;
    $("#settingDiagnostics").checked = profile.runtime.save_diagnostics !== false;
    $("#settingReturnLobby").checked = !!profile.runtime.allow_return_to_lobby;
    $("#taskStartOver").checked = !!profile.runtime.queue_start_over;
    $("#settingZoomIn").value = profile.camera.zoom_in_presses || 18;
    $("#settingPitchDrags").value = profile.camera.pitch_drags || 2;
    $("#settingZoomOut").value = profile.camera.zoom_out_delta || -20;
    $("#settingSettle").value = profile.camera.settle_ms || 1800;
    $("#settingCraftEnabled").checked = !!profile.crafting.enabled;
    $("#settingCraftConfirmed").checked = !!profile.crafting.live_confirmation;
    $("#settingCraftEvery").value = profile.crafting.trigger?.every || 20;
    $("#settingCraftWorkflow").value = JSON.stringify(profile.crafting.workflow || [], null, 2);
    $("#settingChallengesEnabled").checked = !!profile.challenges.enabled;
    $("#settingChallengeInterval").value = profile.challenges.check_interval_minutes || 30;
    $("#settingChallengeCap").value = profile.challenges.regular_cap || 10;
    $("#settingChallengeHourlyCap").value = profile.challenges.caps?.hourly || 1;
    $("#settingChallengeDailyCap").value = profile.challenges.caps?.daily || 1;
    $("#settingChallengeWeeklyCap").value = profile.challenges.caps?.weekly || 1;
    $("#settingChallengeFallback").checked = profile.challenges.fallback_counters !== false;
    $("#settingWebhookEnabled").checked = !!profile.webhooks.enabled;
    $("#settingWebhookScreenshot").checked = profile.webhooks.include_screenshot !== false;
    $("#runStartSelect").value = profile.runtime.start_action || "auto";
    $("#teamSettings").innerHTML = (profile.teams || []).map((team, index) =>
      `<div class="team-row" data-team-index="${index}">
        <input data-team-field="id" value="${escapeHtml(team.id)}">
        <input data-team-field="name" value="${escapeHtml(team.name)}">
        <button data-remove-team="${index}">×</button>
      </div>`
    ).join("");
    renderChallengeStatuses();
  }

  function renderCatalog() {
    $("#positionMode").innerHTML = optionList(state.catalog.modes.map(mode => mode.id), "Story");
    $("#positionStage").innerHTML = optionList(state.catalog.stages, "Act 1");
    $("#positionDifficulty").innerHTML = optionList(state.catalog.difficulties, "Mastery");
    $("#strategyTeam").innerHTML = optionList(state.catalog.teams, "current");
  }

  function updatePositionFromFields() {
    const placement = findPlacement(state.selectedPlacement);
    if (!placement) return;
    placement.unit_slot = number($("#positionUnitSlot").value, 1);
    placement.x = number($("#positionX").value, placement.x);
    placement.y = number($("#positionY").value, placement.y);
    placement.at_ms = number($("#positionTime").value, placement.at_ms);
    const hasAuto = state.strategy.actions.some(action => action.type === "auto_upgrade" && action.placement_id === placement.id);
    if ($("#positionAutoUpgrade").checked && !hasAuto) {
      state.strategy.actions.push({ id: nextId("auto-upgrade"), type: "auto_upgrade", placement_id: placement.id, at_ms: placement.at_ms + 10000 });
    } else if (!$("#positionAutoUpgrade").checked && hasAuto) {
      state.strategy.actions = state.strategy.actions.filter(action => !(action.type === "auto_upgrade" && action.placement_id === placement.id));
    }
    markDirty();
    renderActions();
    renderMarkers();
  }

  function installEvents() {
    $$(".tab").forEach(tab => tab.addEventListener("click", () => showView(tab.dataset.view)));
    $("#openTasksBtn").addEventListener("click", () => showView("tasks"));
    $("#openStrategyBtn").addEventListener("click", () => showView("strategy"));
    $("#openPositionsBtn").addEventListener("click", () => showView("positions"));
    $("#minimizeBtn").addEventListener("click", () => bridge.send("hide"));
    $("#alignBtn").addEventListener("click", () => bridge.send("align"));

    const start = () => {
      state.selectedTask = number($("#runTaskSelect").value, state.selectedTask);
      bridge.send("start", { task_index: state.selectedTask + 1, start_action: $("#runStartSelect").value });
    };
    $("#startBtn").addEventListener("click", start);
    $("#dashboardStartBtn").addEventListener("click", start);
    $("#pauseBtn").addEventListener("click", () => bridge.send(state.runtime.paused ? "resume" : "pause"));
    $("#stopBtn").addEventListener("click", () => bridge.send("stop", { reason: "gui stop" }));
    $("#emergencyBtn").addEventListener("click", () => bridge.send("stop", { reason: "gui emergency stop" }));
    $("#runTaskSelect").addEventListener("change", event => {
      state.selectedTask = number(event.target.value, 0);
      renderTasks();
    });

    $("#addTaskBtn").addEventListener("click", () => {
      state.tasks.push(defaultTask());
      state.selectedTask = state.tasks.length - 1;
      markDirty();
      renderTasks();
    });
    $("#duplicateTaskBtn").addEventListener("click", () => {
      const task = state.tasks[state.selectedTask];
      if (!task) return;
      const copy = structuredClone(task);
      copy.name = `${copy.name} copy`;
      state.tasks.splice(state.selectedTask + 1, 0, copy);
      state.selectedTask += 1;
      markDirty();
      renderTasks();
    });
    $("#saveTasksBtn").addEventListener("click", () => {
      if (!syncSettings()) return;
      bridge.send("save_profile", { profile: state.profile });
    });
    $("#taskRows").addEventListener("click", event => {
      const row = event.target.closest("tr");
      if (!row) return;
      const index = number(row.dataset.taskIndex);
      if (index !== state.selectedTask && !syncTaskDetails()) return;
      state.selectedTask = index;
      const action = event.target.dataset.taskAction;
      let changed = false;
      if (action === "remove") {
        state.tasks.splice(index, 1);
        state.selectedTask = Math.max(0, Math.min(index, state.tasks.length - 1));
        changed = true;
      } else if (action === "up" && index > 0) {
        [state.tasks[index - 1], state.tasks[index]] = [state.tasks[index], state.tasks[index - 1]];
        state.selectedTask = index - 1;
        changed = true;
      } else if (action === "down" && index < state.tasks.length - 1) {
        [state.tasks[index + 1], state.tasks[index]] = [state.tasks[index], state.tasks[index + 1]];
        state.selectedTask = index + 1;
        changed = true;
      } else if (action === "infinite") {
        state.tasks[index].infinite = !state.tasks[index].infinite;
        changed = true;
      }
      if (changed) {
        markDirty();
        renderTasks();
      } else {
        $$("#taskRows tr").forEach(item => item.classList.toggle("selected", number(item.dataset.taskIndex) === state.selectedTask));
        $("#taskSelectionText").textContent = `selected: ${state.tasks[state.selectedTask].name}`;
        renderTaskDetails();
      }
    });
    $("#taskRows").addEventListener("input", event => {
      const row = event.target.closest("tr");
      const key = event.target.dataset.taskField;
      if (!row || !key) return;
      const task = state.tasks[number(row.dataset.taskIndex)];
      task[key] = event.target.type === "checkbox" ? event.target.checked : key === "repetitions" ? number(event.target.value, 1) : event.target.value;
      markDirty();
      renderRunTasks();
    });
    $("#taskChallengeKind").addEventListener("change", () => {
      syncTaskDetails(false);
      markDirty();
    });
    $("#taskRouteJson").addEventListener("input", () => markDirty());
    $("#taskRouteJson").addEventListener("change", () => syncTaskDetails());
    $("#taskTeamRouteJson").addEventListener("input", () => markDirty());
    $("#taskTeamRouteJson").addEventListener("change", () => syncTaskDetails());
    $("#taskStartOver").addEventListener("change", () => markDirty());

    ["#strategyName", "#strategyMap", "#strategyStage", "#strategyDifficulty", "#strategyTeam"].forEach(selector =>
      $(selector).addEventListener("input", () => { syncStrategyMeta(); markDirty(); })
    );
    $$("[data-add-action]").forEach(button => button.addEventListener("click", () => newAction(button.dataset.addAction)));
    $("#newStrategyBtn").addEventListener("click", () => bridge.send("new_strategy"));
    $("#strategySelect").addEventListener("change", event => {
      if (event.target.value) bridge.send("load_strategy", { id: event.target.value });
    });
    $("#saveStrategyBtn").addEventListener("click", () => {
      syncStrategyMeta();
      bridge.send("save_strategy", { strategy: state.strategy });
    });
    $("#copyStrategyBtn").addEventListener("click", () => { syncStrategyMeta(); bridge.send("copy_strategy", { strategy: state.strategy }); });
    $("#importStrategyBtn").addEventListener("click", () => bridge.send("import_strategy"));
    $("#previewStrategyBtn").addEventListener("click", () => bridge.send("preview_strategy", { strategy: state.strategy }));

    $("#actionList").addEventListener("click", event => {
      const card = event.target.closest(".action-card");
      if (card) {
        state.selectedAction = state.strategy.actions[number(card.dataset.actionIndex)].id;
        renderActions();
      }
      if (event.target.dataset.removeAction !== undefined) {
        const index = number(event.target.dataset.removeAction);
        const removed = state.strategy.actions.splice(index, 1)[0];
        if (removed.type === "place") {
          state.strategy.actions = state.strategy.actions.filter(action => action.placement_id !== removed.id);
          if (state.selectedPlacement === removed.id) state.selectedPlacement = placements()[0]?.id || null;
        }
        markDirty();
        renderActions();
        renderPositions();
      }
    });
    $("#actionList").addEventListener("input", event => {
      const card = event.target.closest(".action-card");
      const key = event.target.dataset.actionField;
      if (!card || !key) return;
      const action = state.strategy.actions[number(card.dataset.actionIndex)];
      const numeric = ["at_ms", "duration_ms", "unit_slot", "x", "y", "levels"].includes(key) && event.target.value !== "max";
      action[key] = numeric ? number(event.target.value) : event.target.value;
      markDirty();
      renderPositions();
    });
    $("#actionList").addEventListener("dragstart", event => {
      const card = event.target.closest(".action-card");
      if (card) state.actionDrag = number(card.dataset.actionIndex);
    });
    $("#actionList").addEventListener("dragover", event => event.preventDefault());
    $("#actionList").addEventListener("drop", event => {
      event.preventDefault();
      const card = event.target.closest(".action-card");
      if (!card || state.actionDrag === null) return;
      const target = number(card.dataset.actionIndex);
      const [action] = state.strategy.actions.splice(state.actionDrag, 1);
      state.strategy.actions.splice(target, 0, action);
      state.actionDrag = null;
      markDirty();
      renderActions();
    });

    $("#positionCanvas").addEventListener("click", event => {
      if (event.target.closest(".placement-marker")) return;
      const rect = event.currentTarget.getBoundingClientRect();
      addPosition((event.clientX - rect.left) / rect.width * 816, (event.clientY - rect.top) / rect.height * 638);
    });
    $("#positionCanvas").addEventListener("mousemove", event => {
      const rect = event.currentTarget.getBoundingClientRect();
      const x = Math.max(0, Math.min(816, (event.clientX - rect.left) / rect.width * 816));
      const y = Math.max(0, Math.min(638, (event.clientY - rect.top) / rect.height * 638));
      $("#positionCoords").textContent = `x ${x.toFixed(1)} · y ${y.toFixed(1)}`;
      if (state.markerDrag) {
        const placement = findPlacement(state.markerDrag);
        placement.x = Math.round(x * 10) / 10;
        placement.y = Math.round(y * 10) / 10;
        markDirty();
        renderMarkers();
      }
    });
    $("#positionMarkers").addEventListener("mousedown", event => {
      const marker = event.target.closest(".placement-marker");
      if (!marker) return;
      event.preventDefault();
      state.selectedPlacement = marker.dataset.placementId;
      state.markerDrag = state.selectedPlacement;
      renderPositions();
    });
    window.addEventListener("mouseup", () => { state.markerDrag = null; });
    $("#positionMarkers").addEventListener("click", event => {
      const marker = event.target.closest(".placement-marker");
      if (!marker) return;
      event.stopPropagation();
      state.selectedPlacement = marker.dataset.placementId;
      renderPositions();
    });
    ["#positionUnitSlot", "#positionX", "#positionY", "#positionTime", "#positionAutoUpgrade"].forEach(selector =>
      $(selector).addEventListener("input", updatePositionFromFields)
    );
    $("#deletePositionBtn").addEventListener("click", () => {
      const id = state.selectedPlacement;
      if (!id) return;
      state.strategy.actions = state.strategy.actions.filter(action => action.id !== id && action.placement_id !== id);
      state.selectedPlacement = placements()[0]?.id || null;
      markDirty();
      renderActions();
      renderPositions();
    });
    $("#savePositionsBtn").addEventListener("click", () => {
      syncStrategyMeta();
      bridge.send("save_strategy", { strategy: state.strategy });
    });
    $("#dryPositionBtn").addEventListener("click", () => bridge.send("preview_strategy", { strategy: state.strategy }));
    $("#loadMapImageBtn").addEventListener("click", () => bridge.send("load_map", { task: positionTask() }));
    $("#captureMapBtn").addEventListener("click", () => bridge.send("capture_map", { task: positionTask() }));
    ["#positionMode", "#positionMap", "#positionStage", "#positionDifficulty"].forEach(selector =>
      $(selector).addEventListener("change", () => bridge.send("load_map", { task: positionTask() }))
    );

    $("#saveSettingsBtn").addEventListener("click", () => {
      if (!syncSettings()) return;
      bridge.send("save_profile", { profile: state.profile });
    });
    $("#saveWebhookBtn").addEventListener("click", () => {
      const url = $("#webhookUrl").value.trim();
      if (!url) { toast("paste a webhook url first", true); return; }
      bridge.send("set_webhook", { url });
    });
    $("#testWebhookBtn").addEventListener("click", () => bridge.send("test_webhook"));
    $("#addTeamBtn").addEventListener("click", () => {
      state.profile.teams.push({ id: String(state.profile.teams.length + 1), name: `team ${state.profile.teams.length + 1}` });
      renderSettings();
      markDirty();
    });
    $("#teamSettings").addEventListener("click", event => {
      if (event.target.dataset.removeTeam === undefined) return;
      state.profile.teams.splice(number(event.target.dataset.removeTeam), 1);
      renderSettings();
      markDirty();
    });
    $(".settings-grid")?.addEventListener("input", () => markDirty());
  }

  window.MacroApp = {
    receive(message) {
      const { event, payload = {} } = message;
      if (event === "bootstrap") {
        state.profile = structuredClone(payload.profile);
        state.tasks = state.profile.tasks;
        state.strategies = payload.strategies || [];
        state.catalog = payload.catalog;
        state.runtime = payload.runtime || state.runtime;
        state.status = payload.status || {};
        state.selectedTask = Math.max(
          0,
          Math.min(state.tasks.length - 1, (state.runtime.task_index || 1) - 1),
        );
        renderCatalog();
        renderSettings();
        renderTasks();
        runtimePill();
        renderReadyChecks(payload.status);
        renderChallengeStatuses(state.runtime.challenges);
        loadStrategy(payload.strategy);
        if (payload.map) setMap(payload.map);
        log("gui ready");
      } else if (event === "dock_status") {
        setDockStatus(payload);
      } else if (event === "map") {
        setMap(payload);
        if (payload.image_url) toast("map image loaded");
      } else if (event === "strategy") {
        loadStrategy(payload);
      } else if (event === "strategy_saved") {
        state.strategies = payload.strategies || state.strategies;
        loadStrategy(payload.strategy);
        renderTasks();
        toast("strategy saved");
      } else if (event === "profile_saved") {
        state.profile = structuredClone(payload.profile);
        state.tasks = state.profile.tasks;
        markDirty(false);
        renderSettings();
        renderTasks();
        toast("settings saved");
      } else if (event === "runtime") {
        state.runtime = { ...state.runtime, ...payload };
        runtimePill();
        if (payload.challenges) renderChallengeStatuses(payload.challenges);
      } else if (event === "progress") {
        $("#progressArea").textContent = payload.area || "run";
        $("#progressMessage").textContent = payload.message || "";
        $("#footerMessage").textContent = payload.message || "";
        $("#progressBar").style.width = payload.area === "strategy" ? "70%" : payload.area === "camera" ? "35%" : "15%";
        if (payload.stats) state.runtime.stats = payload.stats;
        runtimePill();
        log(`${payload.area}: ${payload.message}`);
      } else if (event === "run_started" || event === "started") {
        state.runtime = { ...state.runtime, active: true, paused: false, state: payload.state, stats: payload.stats };
        state.startedAt = Date.now();
        runtimePill();
        log(payload.task ? `started ${payload.task}` : "run started");
      } else if (event === "paused" || event === "resumed") {
        state.runtime.paused = event === "paused";
        state.runtime.state = payload.state;
        runtimePill();
        log(event);
      } else if (event === "result") {
        state.runtime.stats = payload.stats || state.runtime.stats;
        if (payload.challenges) renderChallengeStatuses(payload.challenges);
        runtimePill();
        $("#progressBar").style.width = "100%";
        log(`${payload.result}: ${payload.task}`, payload.result === "victory" ? "success" : "error");
        toast(`${payload.result} · ${payload.task}`);
      } else if (event === "complete" || event === "stopped") {
        state.runtime = { ...state.runtime, active: false, paused: false, state: "IDLE", stats: payload.stats || state.runtime.stats };
        runtimePill();
        $("#progressArea").textContent = "ready";
        $("#progressMessage").textContent = payload.message || event;
        log(payload.message || event, event === "complete" ? "success" : "");
      } else if (event === "challenge" || event === "challenge_skipped") {
        if (payload.challenges) renderChallengeStatuses(payload.challenges);
        log(payload.message || `${event}: ${payload.task || ""}`);
      } else if (event === "craft" || event === "craft_skipped") {
        log(payload.message || event, event === "craft" ? "success" : "");
      } else if (event === "map_captured") {
        bridge.send("load_map", { task: positionTask() });
        log("bird's-eye map saved");
      } else if (event === "webhook_status") {
        renderReadyChecks({ webhook_configured: payload.configured });
      } else if (event === "toast") {
        toast(payload.message);
      } else if (event === "error") {
        state.runtime.state = "RECOVERY";
        runtimePill();
        log(payload.message, "error");
        toast(payload.message, true);
      }
    },
  };

  setInterval(() => {
    if (!state.runtime.active || !state.startedAt) return;
    const seconds = Math.floor((Date.now() - state.startedAt) / 1000);
    const h = String(Math.floor(seconds / 3600)).padStart(2, "0");
    const m = String(Math.floor(seconds % 3600 / 60)).padStart(2, "0");
    const s = String(seconds % 60).padStart(2, "0");
    $("#uptimeText").textContent = `uptime ${h}:${m}:${s}`;
  }, 1000);

  document.addEventListener("DOMContentLoaded", () => {
    installEvents();
    bridge.send("ready");
  });
})();
