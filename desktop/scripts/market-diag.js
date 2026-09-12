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
  const log = (m) => console.log("MARKETDIAG: " + m);
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

  // Sample the bounty board + events every 15s for ~2 minutes.
  for (let i = 0; i < 8; i++) {
    await sleep(15000);
    // Count bounty toasts in events display as a proxy for placement volume.
    const eventsText = (
      document.querySelector("events-display")?.textContent ?? ""
    ).toLowerCase();
    const bountyMentions = (eventsText.match(/bounty/g) ?? []).length;
    // Board rows = live pools.
    const board = document.querySelector("bounty-board");
    const rows = board ? board.querySelectorAll("button").length : -1;
    const boardText = (board?.textContent ?? "")
      .replace(/\s+/g, " ")
      .slice(0, 300);
    log(
      `t+${(i + 1) * 15}s boardRows=${rows} bountyMentions=${bountyMentions} board="${boardText}"`,
    );
  }
  return "SMOKE_OK";
})();
