import { Execution, Game } from "../game/Game";

/**
 * Persistent bounty-market janitor: once per tick, expires every pool whose
 * deadline passed (refunding contributors + emitting BountyExpiredEvent).
 * Registered by GameRunner.init only when bounties are enabled; stays alive
 * for the whole game and no-ops on ticks with no pools.
 */
export class BountyExpiryExecution implements Execution {
  private mg: Game | null = null;

  init(mg: Game, _ticks: number): void {
    this.mg = mg;
  }

  tick(ticks: number): void {
    this.mg?.expireBounties(ticks);
  }

  isActive(): boolean {
    return true;
  }

  activeDuringSpawnPhase(): boolean {
    return true;
  }
}
