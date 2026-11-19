package whaley.core

class GameCheckpointSuite extends munit.FunSuite {
  private val level = Level(1, 10, 20, 32, Set.empty, Set.empty,
    Vec2(128, 100), Vector(Vec2(250, 500)),
    Vector(Vec2(144, 114), Vec2(240, 300)),
    Vector(HazardSpawn(Vec2(144, 114), -1)), Vec2(280, 600))

  private def atFirstCoin(): Game = {
    val game = new Game(level, BubbleMode.ExtraBounce)
    game.setInvincible(true)
    game.pointerDown(Vec2(20, 0))
    game.pointerUp(Vec2(20, 0))
    game.tick()
    game
  }

  test("coin save records stable ordinal, remaining-coin evidence, mode and counters exactly once") {
    val game = atFirstCoin()
    val saved = game.checkpoint.get
    assertEquals(saved, GameCheckpoint(1, BubbleMode.ExtraBounce, 0, Vector(0), 1L, 1))
    assertEquals(game.snapshot.coins.map(_.id), Vector(1))
    assertEquals(game.snapshot.collected, 1)
    (0 until 5).foreach(_ => game.tick())
    assertEquals(game.checkpoint, Some(saved), "time after a coin must not rewrite its durable save")
    assertEquals(game.snapshot.collected, 1)
  }

  test("death retries at the coin with live penalties; relaunch restores the saved penalties") {
    val game = atFirstCoin()
    val saved = game.checkpoint.get
    (0 until 5).foreach(_ => game.tick())
    game.pointerDown(Vec2(280, 0))
    game.setInvincible(false)
    game.tick()
    assertEquals(game.snapshot.status, Status.Dead)
    val fatalTick = game.snapshot.tick
    (0 until 120).foreach(_ => game.tick())
    assertEquals(game.snapshot.tick, fatalTick + 120L, "the original two-second death pose counts toward time")
    val died = game.snapshot
    assertEquals(died.bubblesUsed, 2)
    assert(game.resume())
    val retried = game.snapshot
    assertEquals(retried.player.position, Vec2(128, 98))
    assertEquals(retried.status, Status.Playing)
    assertEquals(retried.tick, died.tick)
    assertEquals(retried.bubblesUsed, died.bubblesUsed)
    assertEquals(retried.collected, 1)
    assertEquals(retried.coins.map(_.id), Vector(1))
    assertEquals(retried.bubbles.map(b => (b.position, b.radius, b.bouncesLeft, b.selected)),
      Vector((Vec2(250, 500), 22.0, 3, false)))
    assertEquals(game.checkpoint, Some(saved))
    assertEquals(game.drainSounds(), Vector.empty)

    val reopened = new Game(level, saved.mode)
    assert(reopened.restoreCheckpoint(saved))
    assertEquals(reopened.snapshot.player.position, retried.player.position)
    assertEquals(reopened.snapshot.tick, 1L)
    assertEquals(reopened.snapshot.bubblesUsed, 1)
    assertEquals(reopened.snapshot.collected, 1)
    reopened.pointerDown(Vec2(20, 0))
    assertEquals(reopened.snapshot.bubblesUsed, 2, "held pointers must not survive a checkpoint")
  }

  test("a death before the first coin retries at origin while an explicit restart clears penalties") {
    val game = new Game(level)
    game.pointerDown(Vec2(20, 0))
    game.tick()
    assertEquals(game.snapshot.status, Status.Dead)
    assert(!game.resume())
    assertEquals(game.snapshot.player.position, level.spawn)
    assertEquals(game.snapshot.tick, 1L)
    assertEquals(game.snapshot.bubblesUsed, 1)
    game.restart()
    assertEquals(game.snapshot.tick, 0L)
    assertEquals(game.snapshot.bubblesUsed, 0)
    assertEquals(game.checkpoint, None)
  }

  test("the most recently collected coin replaces the checkpoint even when its ordinal is lower") {
    val descending = level.copy(spawn = Vec2(128, 200), hazards = Vector.empty,
      coins = Vector(Vec2(144, 120), Vec2(144, 214)))
    val game = new Game(descending)
    game.tick()
    assertEquals(game.checkpoint.map(_.lastCoinId), Some(1))
    (0 until 100).foreach(_ => game.tick())
    val saved = game.checkpoint.get
    assertEquals(saved.lastCoinId, 0)
    assertEquals(saved.collectedCoinIds, Vector(0, 1))
    assert(game.resume())
    assertEquals(game.snapshot.player.position, Vec2(128, 104))
    assertEquals(game.snapshot.coins, Vector.empty)
    assertEquals(game.snapshot.collected, 2)
  }

  test("restart and level completion discard the durable coin checkpoint") {
    val game = atFirstCoin()
    game.restart()
    assertEquals(game.checkpoint, None)
    assertEquals(game.snapshot.coins.length, 2)
    assertEquals(game.snapshot.collected, 0)
    assert(game.isInvincible, "restart must not silently change the invincibility preference")

    val winning = new Game(level.copy(hazards = Vector.empty, goal = Vec2(144, 114)))
    winning.tick()
    assertEquals(winning.snapshot.status, Status.Won)
    assertEquals(winning.snapshot.collected, 1)
    assertEquals(winning.checkpoint, None)
  }

  test("restoring rejects mismatched modes, unknown coins, duplicate IDs and unsupported versions atomically") {
    val game = atFirstCoin()
    val saved = game.checkpoint.get
    val before = game.snapshot
    val invalid = Vector(
      saved.copy(levelNumber = 2), saved.copy(mode = BubbleMode.Normal),
      saved.copy(lastCoinId = 1), saved.copy(collectedCoinIds = Vector(0, 0)),
      saved.copy(collectedCoinIds = Vector(0, 99)), saved.copy(version = 2),
      saved.copy(elapsedTicks = -1), saved.copy(elapsedTicks = GameCheckpoint.MaxElapsedTicks + 1),
      saved.copy(bubblesUsed = -1))
    invalid.foreach { item =>
      assert(!game.restoreCheckpoint(item), item.toString)
      assertEquals(game.snapshot, before)
      assertEquals(game.checkpoint, Some(saved))
    }
  }

  test("checkpoint storage round trips and rejects corrupt, oversized and unknown-level records") {
    val saved = atFirstCoin().checkpoint.get
    val encoded = GameCheckpointCodec.encode(saved)
    assertEquals(GameCheckpointCodec.decode(encoded, Vector(level)), Some(saved))
    val invalid = Vector("", "{}", encoded + "|extra", encoded.replace("|1|1|", "|9|1|"),
      "whaley-checkpoint|1|99|ExtraBounce|0|1|1|0",
      "whaley-checkpoint|1|1|Surprise|0|1|1|0",
      "whaley-checkpoint|1|1|ExtraBounce|0|NaN|1|0",
      "whaley-checkpoint|1|1|ExtraBounce|0|99999999999999999999|1|0",
      "whaley-checkpoint|1|1|ExtraBounce|0|1|-1|0",
      "whaley-checkpoint|1|1|ExtraBounce|0|1|1|0,0", "x" * 65537)
    invalid.foreach(value => assertEquals(GameCheckpointCodec.decode(value, Vector(level)), None))
  }

  test("restored elapsed time does not carry the old hazard phase into a new scene") {
    val phased = level.copy(hazards = Vector(HazardSpawn(Vec2(280, 500), 180)))
    val game = new Game(phased)
    assert(game.restoreCheckpoint(GameCheckpoint(1, BubbleMode.Normal, 0, Vector(0), 135L, 2)))
    assertEquals(game.snapshot.hazards.map(_.active), Vector(false))
    (0 until 15).foreach(_ => game.tick())
    assertEquals(game.snapshot.hazards.map(_.active), Vector(true))
    assertEquals(game.snapshot.tick, 150L)
  }

  test("every actual level coin can be persisted and restored at its original bottom-left") {
    for (original <- LevelData.all; (center, id) <- original.coins.zipWithIndex) {
      val saved = GameCheckpoint(original.number, BubbleMode.Normal, id, Vector(id), 60L, 2)
      assert(saved.validFor(original), s"level ${original.number}, coin $id at $center")
      assertEquals(GameCheckpointCodec.decode(GameCheckpointCodec.encode(saved), LevelData.all), Some(saved))
      val game = new Game(original)
      assert(game.restoreCheckpoint(saved))
      assertEquals(game.snapshot.player.position, center - Vec2(16, 16))
      assertEquals(game.snapshot.collected, 1)
      assert(!game.snapshot.coins.exists(_.id == id))
    }
  }
}
