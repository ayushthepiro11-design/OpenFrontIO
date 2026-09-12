import { Execution, Game, Gold, Player, PlayerID } from "../game/Game";
import { toInt } from "../Util";

/**
 * Pools gold from `sender` onto `recipient`'s head (the bounty market).
 *
 * Unlike a donation, the gold leaves the sender immediately and sits in the
 * game's bounty pool; it pays out to whoever lands the killing blow
 * (GameImpl.conquerPlayer -> resolveBounty), or refunds when the target dies
 * with no conqueror (PlayerExecution.removeOnDeath -> refundBounties).
 *
 * Anonymous placements hide the placer from the bounty toast for a 10%
 * burn fee (gold sink): the fee is removed from the placer but never
 * enters the pool.
 */
export class BountyExecution implements Execution {
  private target: Player;
  private gold: Gold | null = null;

  private mg: Game;

  private active = true;

  constructor(
    private placer: Player,
    private targetID: PlayerID,
    goldNum: number | null,
    private anonymous: boolean = false,
  ) {
    this.gold = goldNum !== null ? toInt(goldNum) : null;
  }

  init(mg: Game, ticks: number): void {
    this.mg = mg;

    if (!mg.hasPlayer(this.targetID)) {
      console.warn(`BountyExecution target ${this.targetID} not found`);
      this.active = false;
      return;
    }

    this.target = mg.player(this.targetID);

    // No amount given -> default to a quarter of the placer's gold.
    this.gold ??= this.placer.gold() / 4n;
  }

  tick(ticks: number): void {
    if (this.gold === null) throw new Error("not initialized");
    if (
      this.mg.config().bountiesEnabled() &&
      this.mg.canPlaceBounty(this.placer, this.target)
    ) {
      const minAmount = this.mg.config().bountyMinAmount();
      if (this.gold < minAmount) {
        console.warn(
          `bounty of ${this.gold} on ${this.target.name()} below minimum ${minAmount}`,
        );
      } else if (
        this.mg.placeBounty(
          this.placer,
          this.target,
          this.gold,
          this.anonymous,
        ) === 0n
      ) {
        console.warn(
          `could not pool bounty from ${this.placer.name()} onto ${this.target.name()}`,
        );
      }
    } else {
      console.warn(
        `cannot place bounty from ${this.placer.name()} onto ${this.target.name()}`,
      );
    }
    this.active = false;
  }

  isActive(): boolean {
    return this.active;
  }

  activeDuringSpawnPhase(): boolean {
    return false;
  }
}
