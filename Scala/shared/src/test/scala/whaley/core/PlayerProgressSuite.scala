package whaley.core

class PlayerProgressSuite extends munit.FunSuite {
  private val levels = LevelData.all
  private def checkpoint(number: Int, mode: BubbleMode = BubbleMode.Normal): GameCheckpoint =
    GameCheckpoint(number, mode, 1, Vector(0, 1), 480L, 9)

  test("multi-level saves preserve gameplay checkpoints and invincibility across a process-style reload") {
    val first = checkpoint(1, BubbleMode.ExtraBounce)
    val fourth = checkpoint(4)
    val written = PlayerProgress(4, rewardVisible = false, invincible = true,
      checkpoints = Map(4 -> fourth, 1 -> first))
    val loaded = PlayerProgressCodec.decode(PlayerProgressCodec.encode(written), levels).get
    assertEquals(loaded, written)
    loaded.checkpoints.foreach { case (number, saved) =>
      val game = new Game(levels(number - 1), saved.mode)
      assert(game.restoreCheckpoint(saved))
      game.setInvincible(loaded.invincible)
      assertEquals(game.snapshot.player.position, levels(number - 1).coins(1) - Vec2(16, 16))
      assertEquals(game.snapshot.coins.map(_.id), levels(number - 1).coins.indices.drop(2).toVector)
      assertEquals(game.snapshot.collected, 2)
      assertEquals(game.snapshot.tick, 480L)
      assertEquals(game.snapshot.bubblesUsed, 9)
      assert(game.isInvincible)
    }
  }

  test("a loaded checkpoint unlocks its practice level without claiming game completion") {
    val written = PlayerProgress(1, rewardVisible = false, checkpoints = Map(6 -> checkpoint(6)))
    val loaded = PlayerProgressCodec.decode(PlayerProgressCodec.encode(written), levels).get
    assertEquals(loaded.levelsAchieved, 6)
    val gallery = new GalleryScene(() => 0)
    gallery.restoreProgress(loaded.levelsAchieved, loaded.rewardVisible)
    assert(gallery.levelUnlocked(6))
    assert(!gallery.completedGame)
    assert(!gallery.rewardVisible)
    assertEquals(gallery.gameMode, BubbleMode.Normal)
  }

  test("completed-game progression survives reload independently of cleared checkpoints") {
    val written = PlayerProgress(7, rewardVisible = false, invincible = false)
    val loaded = PlayerProgressCodec.decode(PlayerProgressCodec.encode(written), levels).get
    val gallery = new GalleryScene(() => 0)
    gallery.restoreProgress(loaded.levelsAchieved, loaded.rewardVisible)
    assert(gallery.completedGame)
    assertEquals(gallery.gameMode, BubbleMode.Infinite)
    assertEquals(loaded.checkpoints, Map.empty)
    assertEquals(gallery.drainSounds(), Vector.empty, "loading progress must not replay historical sounds")
  }

  test("invalid envelopes, booleans, versions and duplicate levels are rejected as one record") {
    val saved = GameCheckpointCodec.encode(checkpoint(1))
    val other = GameCheckpointCodec.encode(checkpoint(4))
    val invalid = Vector(
      "", "whaley-progress|2\n1|true|false", "whaley-progress|1\n0|true|false",
      "whaley-progress|1\n8|true|false", "whaley-progress|1\n1|TRUE|false",
      "whaley-progress|1\n1|true|maybe", "whaley-progress|1\n1|true|false|extra",
      s"whaley-progress|1\n1|true|false\n$saved\n$saved",
      s"whaley-progress|1\n4|true|false\n$saved\n$other\nbroken-checkpoint",
      "whaley-progress|1\n1|true|false\n" + GameCheckpointCodec.encode(checkpoint(99)),
      "whaley-progress|1\n1|true|false\n" + GameCheckpointCodec.encode(checkpoint(1).copy(version = 2)),
      "x" * 400001)
    invalid.foreach(raw => assertEquals(PlayerProgressCodec.decode(raw, levels), None))
  }

  test("the default record is valid and clearing one level does not discard another checkpoint") {
    assertEquals(PlayerProgressCodec.decode(PlayerProgressCodec.encode(PlayerProgress()), levels), Some(PlayerProgress()))
    val written = PlayerProgress(4, checkpoints = Map(1 -> checkpoint(1), 4 -> checkpoint(4)))
    val afterQuit = written.copy(checkpoints = written.checkpoints.removed(1))
    val loaded = PlayerProgressCodec.decode(PlayerProgressCodec.encode(afterQuit), levels).get
    assertEquals(loaded.checkpoints.keySet, Set(4))
    assertEquals(loaded.checkpoints(4), checkpoint(4))
    assertEquals(loaded.levelsAchieved, 4)
  }
}
