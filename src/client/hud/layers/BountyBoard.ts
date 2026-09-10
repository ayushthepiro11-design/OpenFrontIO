import { html, LitElement } from "lit";
import { customElement, state } from "lit/decorators.js";
import { EventBus } from "../../../core/EventBus";
import { Controller } from "../../Controller";
import { GoToPlayerEvent } from "../../TransformHandler";
import { renderNumber, translateText } from "../../Utils";
import { GameView, PlayerView } from "../../view";

interface BountyRow {
  player: PlayerView;
  total: number;
}

/**
 * Most-wanted board: every live player with gold pooled on their head,
 * sorted by pool size. Clicking a row flies the camera to that player
 * (GoToPlayerEvent) — the fastest way to find paid work.
 *
 * Renders nothing while no bounties exist. Refresh is throttled to 2 Hz via
 * getTickIntervalMs; bounty pools only move on placements/payouts anyway.
 */
@customElement("bounty-board")
export class BountyBoard extends LitElement implements Controller {
  eventBus: EventBus | null = null;
  game: GameView | null = null;

  @state() private rows: BountyRow[] = [];

  createRenderRoot() {
    return this;
  }

  getTickIntervalMs(): number {
    return 500;
  }

  tick() {
    if (!this.game) return;
    const next: BountyRow[] = [];
    for (const player of this.game.players()) {
      const total = player.bountyTotal();
      if (total > 0 && player.isAlive()) {
        next.push({ player, total });
      }
    }
    next.sort((a, b) => b.total - a.total);
    const top = next.slice(0, 5);
    // Re-render only when the board membership or amounts actually moved.
    if (
      top.length !== this.rows.length ||
      top.some(
        (r, i) =>
          r.player.id() !== this.rows[i]?.player.id() ||
          r.total !== this.rows[i]?.total,
      )
    ) {
      this.rows = top;
    }
  }

  private focusPlayer(player: PlayerView) {
    this.eventBus?.emit(new GoToPlayerEvent(player, 10));
  }

  render() {
    if (this.rows.length === 0) return html``;
    return html`
      <div
        class="pointer-events-auto w-full sm:w-auto rounded-lg bg-gray-800/92 backdrop-blur-sm shadow-lg px-3 py-2"
      >
        <div
          class="text-[11px] font-bold uppercase tracking-wider text-amber-300/90 mb-1"
        >
          ${translateText("bounty.board_title")}
        </div>
        <div class="flex flex-col gap-1">
          ${this.rows.map(
            (row) => html`
              <button
                class="flex items-center justify-between gap-3 rounded-md px-2 py-1 text-sm text-white hover:bg-white/10 transition-colors"
                @click=${() => this.focusPlayer(row.player)}
                title=${row.player.displayName()}
              >
                <span class="truncate max-w-[10rem]"
                  >${row.player.displayName()}</span
                >
                <span
                  translate="no"
                  class="tabular-nums font-semibold text-amber-200"
                  >${renderNumber(row.total)}</span
                >
              </button>
            `,
          )}
        </div>
      </div>
    `;
  }
}
