(async () => {
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const waitFor = async (desc, fn, timeoutMs = 30000) => {
    const t0 = Date.now();
    while (Date.now() - t0 < timeoutMs) {
      try {
        const v = fn();
        if (v) return v;
      } catch (e) {
        /* retry */
      }
      await sleep(250);
    }
    throw new Error("timeout: " + desc);
  };
  const log = (m) => console.log("ALLYDIAG: " + m);

  await waitFor("game-mode-selector upgrade", () =>
    customElements.get("game-mode-selector"),
  );
  const selector = document.querySelector("game-mode-selector");
  await waitFor(
    "selector rendered",
    () => selector && selector.children.length > 0,
    20000,
  );
  const soloBtn = await waitFor("solo card button", () => {
    const btns = [...selector.querySelectorAll("button")];
    return btns.find((b) =>
      b.textContent.trim().toLowerCase().includes("solo"),
    );
  });
  soloBtn.click();
  const soloModal = document.querySelector("single-player-modal");
  await waitFor(
    "solo modal open",
    () => !soloModal.classList.contains("hidden"),
  );
  soloModal.randomSpawn = true;
  await sleep(300);
  const startBtn = await waitFor("start button", () =>
    soloModal.querySelector("o-button"),
  );
  startBtn.click();
  await waitFor(
    "in-game class",
    () => document.body.classList.contains("in-game"),
    120000,
  );
  log("game started");

  const overlay = await waitFor("input overlay", () =>
    document.getElementById("game-input-overlay"),
  );
  const rightClick = (x, y) => {
    overlay.dispatchEvent(
      new MouseEvent("contextmenu", {
        bubbles: true,
        cancelable: true,
        composed: true,
        clientX: x,
        clientY: y,
        button: 2,
      }),
    );
  };
  const sliceIds = () => [
    ...new Set(
      [...document.querySelectorAll("g.menu-item-content[data-id]")].map((g) =>
        g.getAttribute("data-id"),
      ),
    ),
  ];
  const clickSlice = (id) => {
    const menu = [
      ...document.querySelectorAll('g.menu-item-content[data-id="' + id + '"]'),
    ].pop();
    if (!menu) return false;
    const svg = menu.closest("svg");
    const pathEl = svg ? svg.querySelector('path[data-id="' + id + '"]') : null;
    if (!pathEl) return false;
    pathEl.dispatchEvent(
      new MouseEvent("click", { bubbles: true, cancelable: true }),
    );
    return true;
  };

  const W = window.innerWidth,
    H = window.innerHeight;
  const grid = [];
  for (const fx of [0.3, 0.5, 0.7])
    for (const fy of [0.3, 0.5, 0.7]) grid.push([W * fx, H * fy]);
  await sleep(16000);
  log("settled");

  // Find a tile whose radial offers an alliance request, click it.
  let allied = false;
  outer: for (let round = 0; round < 8; round++) {
    for (const [x, y] of grid) {
      rightClick(x, y);
      await sleep(700);
      const ids = sliceIds();
      if (ids.length > 0)
        log("slices at " + x + "," + y + ": " + ids.join(","));
      if (ids.includes("ally_request")) {
        log("clicking ally_request");
        clickSlice("ally_request");
        await sleep(1000);
        allied = true;
        break outer;
      }
    }
    await sleep(3000);
  }
  if (!allied) throw new Error("never found an ally_request slice");

  // Tribes accept all requests on their tick; wait and check events + panel.
  await sleep(12000);
  const eventsText = (
    document.querySelector("events-display")?.textContent ?? ""
  ).toLowerCase();
  log("events after wait: " + eventsText.slice(0, 400));
  const accepted =
    eventsText.includes("accept") || eventsText.includes("allian");
  log("alliance accepted (per events): " + accepted);

  // Re-open radial on same tiles: an allied target should show break/embargo,
  // and bounty slice state. Log what we see.
  for (const [x, y] of grid.slice(0, 3)) {
    rightClick(x, y);
    await sleep(700);
    log("post-ally slices at " + x + "," + y + ": " + sliceIds().join(","));
  }
  return "SMOKE_OK";
})();
