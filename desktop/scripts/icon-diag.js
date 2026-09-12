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
  const log = (m) => console.log("ICONDIAG: " + m);

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
  const W = window.innerWidth,
    H = window.innerHeight;
  const grid = [];
  for (const fx of [0.3, 0.5, 0.7])
    for (const fy of [0.3, 0.5, 0.7]) grid.push([W * fx, H * fy]);
  await sleep(16000);

  // Find an open radial with the bounty slice and DUMP its DOM.
  let dumped = false;
  outer: for (let round = 0; round < 6; round++) {
    for (const [x, y] of grid) {
      rightClick(x, y);
      await sleep(600);
      const bountyContent = document.querySelector(
        'g.menu-item-content[data-id="place_bounty"]',
      );
      if (bountyContent) {
        const img = bountyContent.querySelector("image");
        const pathEl = document.querySelector('path[data-id="place_bounty"]');
        log("CONTENT_HTML=" + bountyContent.outerHTML.slice(0, 600));
        log(
          "IMG_HREF=" +
            (img
              ? (img.getAttribute("href") ?? img.getAttribute("xlink:href"))
              : "NO_IMG"),
        );
        log(
          "IMG_ATTRS=w:" +
            (img ? img.getAttribute("width") : "?") +
            " h:" +
            (img ? img.getAttribute("height") : "?") +
            " opacity:" +
            (img ? img.getAttribute("opacity") : "?"),
        );
        log("PATH_FILL=" + (pathEl ? pathEl.getAttribute("fill") : "NO_PATH"));
        // natural size check: does the SVG image have intrinsic dimensions?
        if (img) {
          const href =
            img.getAttribute("href") ?? img.getAttribute("xlink:href");
          try {
            const probe = new Image();
            probe.src = href;
            await new Promise((res) => {
              probe.onload = res;
              probe.onerror = res;
              setTimeout(res, 5000);
            });
            log(
              "PROBE natural=" + probe.naturalWidth + "x" + probe.naturalHeight,
            );
          } catch (e) {
            log("PROBE_ERROR=" + e.message);
          }
        }
        dumped = true;
        break outer;
      }
    }
    await sleep(3000);
  }
  if (!dumped) throw new Error("never found a bounty slice");
  await sleep(500);
  return "READY_FOR_SCREENSHOT";
})();
