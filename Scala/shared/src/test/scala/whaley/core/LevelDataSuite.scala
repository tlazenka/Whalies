package whaley.core

/** Smoke coverage for the generated original TMX/atlas data. The constants
  * below come from the checked-in 568h maps, not the generator's output.
  */
class LevelDataSuite extends munit.FunSuite {
  test("all six original maps retain their tile dimensions and order") {
    assertEquals(LevelData.all.map(l => (l.number, l.width, l.height, l.tileSize)), Vector(
      (1, 10, 175, 32), (2, 175, 17, 32), (3, 20, 165, 32),
      (4, 10, 175, 32), (5, 175, 17, 32), (6, 20, 165, 32)
    ))
    LevelData.all.foreach { level =>
      assert(level.walls.nonEmpty)
      assert((level.walls ++ level.grounds).forall { case (x, y) =>
        x >= 0 && x < level.width && y >= 0 && y < level.height
      })
      assert(level.bubbles.nonEmpty && level.coins.nonEmpty && level.hazards.nonEmpty)
      assertEquals(new Game(level).snapshot.player.position, level.spawn)
    }
  }

  test("object conversion accounts for TMX height and each sprite's actual size") {
    val first = LevelData.all.head
    // PlayerOrigin: x=33, rawY=5467, height=32, mapHeight=5600.
    assertEquals(first.spawn, Vec2(33, 101))
    // BubbleOrigin: x=13, rawY=5502, height=32; scaled image is 44x44.
    assertEquals(first.bubbles.head, Vec2(35, 88))
    // Flame: x=35, rawY=5237, height=24; image center adds 12, not 16.
    assertEquals(first.hazards.head, HazardSpawn(Vec2(47, 351), -1))
    assertEquals(LevelData.all.map(_.hazards.head.position), Vector(
      Vec2(47, 351), Vec2(101, 440), Vec2(300, 628),
      Vec2(47, 351), Vec2(101, 440), Vec2(300, 628)
    ))
    assertEquals(first.goal, Vec2(161, 5487))
  }

  test("wide maps use a clamped horizontal camera rather than a full-map scale") {
    val horizontal = LevelData.all(1)
    val state = new Game(horizontal).snapshot
    val start = Viewport.forGame(horizontal, state, 640, 1136)
    assertEquals(start.viewWidth, 320.0)
    assertEquals(start.cameraLeft, 0.0)
    val atRight = state.copy(player = state.player.copy(position = Vec2(horizontal.worldWidth - 32, 165)))
    val end = Viewport.forGame(horizontal, atRight, 640, 1136)
    assertEquals(end.viewWidth, 320.0)
    assertEquals(end.cameraLeft, 5280.0)
    assertEquals(end.viewHeight, 568.0)
    assertEquals(end.cameraBottom, -24.0)
    assertEquals(end.scale, 2.0)
    assertEquals(end.toScreen(Vec2(end.cameraLeft, 0)), Vec2(0, 1088))
    val restored = end.toWorld(end.toScreen(atRight.player.center)).get
    assertEqualsDouble(restored.x, atRight.player.center.x, 1e-8)
    assertEqualsDouble(restored.y, atRight.player.center.y, 1e-8)
  }
}
