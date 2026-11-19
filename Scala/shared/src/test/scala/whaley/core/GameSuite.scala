package whaley.core

class GameSuite extends munit.FunSuite {
  private def fixture(
      spawn: Vec2 = Vec2(128, 100),
      bubbles: Vector[Vec2] = Vector.empty,
      coins: Vector[Vec2] = Vector.empty,
      hazards: Vector[HazardSpawn] = Vector.empty,
      walls: Set[(Int, Int)] = Set.empty,
      grounds: Set[(Int, Int)] = Set.empty,
      goal: Vec2 = Vec2(280, 600)
  ): Level = Level(1, 10, 20, 32, walls, grounds, spawn, bubbles, coins, hazards, goal)

  test("fixed tick movement is independent of renderer frame pacing") {
    val level = fixture(bubbles = Vector(Vec2(144, 80)))
    val sixty = new Game(level)
    val oneFortyFour = new Game(level)
    val slow = new FixedStepClock()
    val fast = new FixedStepClock()
    (0 until 60).foreach(_ => slow.advance(1.0 / 60)(() => sixty.tick()))
    (0 until 144).foreach(_ => fast.advance(1.0 / 144)(() => oneFortyFour.tick()))
    assertEquals(sixty.snapshot, oneFortyFour.snapshot)
    assertEquals(sixty.snapshot.tick, 60L)
  }

  test("wall-clock gaps are bounded and invalid times cannot poison accumulator") {
    val clock = new FixedStepClock()
    var ticks = 0
    assertEquals(clock.advance(10)(() => ticks += 1), 15)
    assertEquals(clock.advance(Double.NaN)(() => ticks += 1), 0)
    assertEquals(clock.advance(Double.PositiveInfinity)(() => ticks += 1), 0)
    assertEquals(clock.advance(-1)(() => ticks += 1), 0)
    assertEquals(ticks, 15)
    clock.reset()
    assertEquals(clock.advance(1.0 / 120)(() => ticks += 1), 0)
    assertEquals(clock.advance(1.0 / 120)(() => ticks += 1), 1)
  }

  test("normal falling uses original one-pixel ticks and lands on wall top") {
    val game = new Game(fixture(spawn = Vec2(128, 110), walls = Set((4, 2))))
    game.tick()
    assertEquals(game.snapshot.player.position.y, 109.0)
    (0 until 30).foreach(_ => game.tick())
    assertEquals(game.snapshot.player.position.y, 96.0)
    assertEquals(game.snapshot.player.airMode, AirMode.Grounded)
  }

  test("ground markers stop descent at their bottom edge without becoming walls") {
    val game = new Game(fixture(spawn = Vec2(128, 110), grounds = Set((4, 3))))
    (0 until 30).foreach(_ => game.tick())
    assertEquals(game.snapshot.player.position.y, 96.0)
    assertEquals(game.snapshot.player.airMode, AirMode.Grounded)
  }

  test("a contact below the player produces original staged upward bounce") {
    val game = new Game(fixture(bubbles = Vector(Vec2(144, 80))))
    game.tick()
    val origin = game.snapshot.player.position.y
    assertEquals(game.snapshot.player.airMode, AirMode.JumpingUp)
    assertEquals(game.snapshot.bubbles.head.bouncesLeft, 1)
    game.tick()
    assertEquals(game.snapshot.player.position.y, origin + 3)
    val positions = (0 until 75).map { _ => game.tick(); game.snapshot.player.position.y }
    assert(positions.max - origin >= 90 && positions.max - origin <= 93)
    assertEquals(game.snapshot.player.position.x, 128.0)
  }

  test("bounce trace follows the source's 45, 87 and 90 pixel speed boundaries") {
    // Golden values are derived from WhaleyScene.gameLoop's branch order and
    // Constants.m, not recorded from a running Objective-C renderer. This
    // catches a velocity/gravity rewrite or an off-by-one change at the apex.
    val expected = Map(
      1 -> (99.0, AirMode.JumpingUp),
      2 -> (102.0, AirMode.JumpingUp),
      16 -> (144.0, AirMode.JumpingUp),
      17 -> (147.0, AirMode.JumpingUp),
      37 -> (187.0, AirMode.JumpingUp),
      39 -> (189.0, AirMode.JumpingUp),
      40 -> (190.0, AirMode.JumpingDown),
      44 -> (186.0, AirMode.JumpingDown),
      65 -> (144.0, AirMode.JumpingDown)
    )
    val game = new Game(fixture(bubbles = Vector(Vec2(144, 80))))
    (1 to 65).foreach { tick =>
      game.tick()
      expected.get(tick).foreach { positionAndMode =>
        assertEquals((game.snapshot.player.position.y, game.snapshot.player.airMode), positionAndMode,
          s"source-derived tick $tick")
      }
    }
  }

  test("side contact pushes laterally without claiming an upward bounce") {
    val game = new Game(fixture(bubbles = Vector(Vec2(120, 112))))
    game.tick()
    assertNotEquals(game.snapshot.player.airMode, AirMode.JumpingUp)
    game.tick()
    assert(game.snapshot.player.position.x > 128)
  }

  test("falling side contact does not leave persistent lateral drift") {
    val game = new Game(fixture(bubbles = Vector(Vec2(120, 112))))
    (0 until 3).foreach(_ => game.tick())
    assertEquals(game.snapshot.bubbles.size, 0)
    assertEquals(game.snapshot.player.position.x, 134.0)
    (0 until 10).foreach(_ => game.tick())
    assertEquals(game.snapshot.player.position.x, 134.0)
  }

  test("a blocked three-pixel descent falls to the wall boundary before grounding") {
    val game = new Game(fixture(bubbles = Vector(Vec2(132, 80)), walls = Set((6, 3))))
    val trace = (0 until 120).map { _ => game.tick(); game.snapshot.player }
    val landings = trace.filter(_.airMode == AirMode.Grounded)
    assert(landings.nonEmpty)
    assert(landings.forall(_.position.y == 128.0))
    assert(trace.exists(p => p.position.y == 129.0 && p.airMode == AirMode.Falling))
  }

  test("a ground marker allows ascent and catches descent at its lower edge") {
    val game = new Game(fixture(bubbles = Vector(Vec2(144, 80)), grounds = Set((4, 4))))
    val trace = (0 until 150).map { _ => game.tick(); game.snapshot.player }
    assert(trace.exists(p => p.position.y > 160 && p.airMode == AirMode.JumpingUp))
    assertEquals(game.snapshot.player.position.y, 128.0)
    assertEquals(game.snapshot.player.airMode, AirMode.Grounded)
  }

  test("a normal bubble is removed after its second confirmed bounce") {
    val game = new Game(fixture(bubbles = Vector(Vec2(144, 80))))
    (0 until 300).foreach(_ => game.tick())
    assertEquals(game.snapshot.bubbles.size, 0)
  }

  test("gallery extra-bounce reward configures both seeded and newly shot bubbles") {
    val game = new Game(fixture(bubbles = Vector(Vec2(144, 80))), BubbleMode.ExtraBounce)
    assertEquals(game.snapshot.bubbles.head.bouncesLeft, 3)
    game.tick()
    assertEquals(game.snapshot.bubbles.head.bouncesLeft, 2)
    assertEquals(game.snapshot.player.airMode, AirMode.JumpingUp)
    game.pointerDown(Vec2(280, 20))
    assertEquals(game.snapshot.bubbles.last.bouncesLeft, 3)
    game.restart()
    assertEquals(game.snapshot.bubbles.map(_.bouncesLeft), Vector(3))
  }

  test("reward modes allow centered shots within the original inclusive 22-unit band") {
    for (mode <- Vector(BubbleMode.ExtraBounce, BubbleMode.Infinite)) {
      for ((touchX, expectedX) <- Vector(121.0 -> 128.0, 122.0 -> 144.0,
          144.0 -> 144.0, 166.0 -> 144.0, 167.0 -> 161.0)) {
        val game = new Game(fixture(), mode)
        game.pointerDown(Vec2(touchX, 20))
        assertEquals(game.snapshot.bubbles.head.position.x, expectedX, s"$mode at $touchX")
      }
    }
    val normal = new Game(fixture())
    normal.pointerDown(Vec2(144, 20))
    assertEquals(normal.snapshot.bubbles.head.position.x, 161.0)
  }

  test("completed-game infinite bubbles survive repeated confirmed bounces") {
    val game = new Game(fixture(bubbles = Vector(Vec2(144, 80))), BubbleMode.Infinite)
    var jumps = 0
    var previous = game.snapshot.player.airMode
    (0 until 1000).foreach { _ =>
      game.tick()
      val current = game.snapshot.player.airMode
      if (current == AirMode.JumpingUp && previous != AirMode.JumpingUp) jumps += 1
      previous = current
    }
    assert(jumps >= 3)
    assertEquals(game.snapshot.bubbles.map(_.bouncesLeft), Vector(2))
  }

  test("one pointer selects, expands, moves, releases and cancellation clears hold") {
    val game = new Game(fixture(spawn = Vec2(32, 500), bubbles = Vector(Vec2(144, 80))))
    game.pointerDown(Vec2(144, 80))
    game.pointerDown(Vec2(240, 30)) // a second pointer cannot steal the first
    (0 until 6).foreach(_ => game.tick())
    assertEquals(game.snapshot.bubbles.head.radius, 64.0)
    assertEquals(game.snapshot.bubblesUsed, 0)
    game.pointerMove(Vec2(180, 100))
    assertEquals(game.snapshot.bubbles.head.position, Vec2(180, 100))
    game.cancelPointer()
    (0 until 6).foreach(_ => game.tick())
    assertEquals(game.snapshot.bubbles.head.radius, 22.0)
    assert(!game.snapshot.bubbles.head.selected)
    game.pointerMove(Vec2(10, 10))
    assertEquals(game.snapshot.bubbles.head.position, Vec2(180, 100))
  }

  test("cancel during expansion preserves relative drag offset and clears acquisition") {
    val game = new Game(fixture(spawn = Vec2(32, 500), bubbles = Vector(Vec2(144, 80))))
    game.pointerDown(Vec2(155, 80)) // 11 / SmallSize is a 32-pixel expanded offset
    game.tick()
    game.pointerMove(Vec2(187, 112))
    game.cancelPointer()
    (0 until 12).foreach(_ => game.tick())
    val bubble = game.snapshot.bubbles.head
    assertEquals(bubble.position, Vec2(176, 112))
    assertEquals(bubble.radius, 22.0)
    assert(!bubble.selected)
    assertEquals(game.snapshot.bubblesUsed, 0)
  }

  test("left and right taps shoot from the corresponding side of Whaley") {
    val game = new Game(fixture())
    game.pointerDown(Vec2(20, 20)); game.pointerUp(Vec2(20, 20))
    game.pointerDown(Vec2(280, 20)); game.pointerUp(Vec2(280, 20))
    (0 until 12).foreach(_ => game.tick())
    assertEquals(game.snapshot.bubbles.map(_.position.x), Vector(128.0, 161.0))
    assertEquals(game.snapshot.bubbles.map(_.position.y), Vector(20.0, 20.0))
    assert(game.snapshot.bubbles.forall(_.frozen))
    assertEquals(game.snapshot.bubblesUsed, 2)
  }

  test("tap above Whaley and nonfinite pointer inputs do not create projectiles") {
    val game = new Game(fixture())
    game.pointerDown(Vec2(20, 150)); game.pointerUp(Vec2(20, 150))
    game.pointerDown(Vec2(Double.NaN, 0)); game.pointerUp(Vec2(0, 0))
    game.pointerDown(Vec2(0, Double.PositiveInfinity))
    assertEquals(game.snapshot.bubblesUsed, 0)
  }

  test("coins are collected once and the original goal completes a level") {
    val game = new Game(fixture(coins = Vector(Vec2(144, 114)), goal = Vec2(144, 114)))
    game.tick()
    assertEquals(game.snapshot.collected, 1)
    assertEquals(game.snapshot.coins.size, 0)
    assertEquals(game.snapshot.status, Status.Won)
    val terminal = game.snapshot
    game.tick()
    assertEquals(game.snapshot, terminal)
    game.pointerDown(Vec2(0, 0))
    assertEquals(game.snapshot.bubblesUsed, 0)
    game.restart()
    assertEquals(game.snapshot.status, Status.Playing)
    assertEquals(game.snapshot.coins.size, 1)
    assertEquals(game.snapshot.tick, 0L)
  }

  test("always-on hazard kills; inactive phased hazard does not") {
    val dead = new Game(fixture(hazards = Vector(HazardSpawn(Vec2(144, 114), -1))))
    dead.tick()
    assertEquals(dead.snapshot.status, Status.Dead)
    val waiting = new Game(fixture(hazards = Vector(HazardSpawn(Vec2(144, 114), 0))))
    waiting.tick()
    assertEquals(waiting.snapshot.status, Status.Playing)
  }

  test("invincibility changes hazard lethality without disabling the hazard or ordinary movement") {
    val game = new Game(fixture(hazards = Vector(HazardSpawn(Vec2(144, 114), -1))))
    game.setInvincible(true)
    game.tick()
    assertEquals(game.snapshot.status, Status.Playing)
    assertEquals(game.snapshot.player.position, Vec2(128, 99))
    assertEquals(game.snapshot.hazards.map(_.active), Vector(true))
    assertEquals(game.drainSounds(), Vector.empty)
    game.setInvincible(false)
    game.tick()
    assertEquals(game.snapshot.status, Status.Dead)
    (0 until 5).foreach(_ => game.tick())
    assertEquals(game.drainSounds(), Vector(SoundCue.Death))
    assertEquals(game.drainSounds(), Vector.empty)
    game.setInvincible(true)
    assertEquals(game.snapshot.status, Status.Dead, "a setting toggle must not resurrect a dead player")
  }

  test("sound cues describe confirmed gameplay outcomes and drain once") {
    val shot = new Game(fixture())
    shot.pointerDown(Vec2(20, 20))
    shot.pointerUp(Vec2(20, 20))
    assertEquals(shot.drainSounds(), Vector.empty, "the original has no shooting sound")
    val jumping = new Game(fixture(bubbles = Vector(Vec2(144, 80))))
    jumping.tick()
    assertEquals(jumping.drainSounds(), Vector(SoundCue.Jump))
    jumping.tick()
    assertEquals(jumping.drainSounds(), Vector.empty)
    val lateral = new Game(fixture(bubbles = Vector(Vec2(120, 112))))
    lateral.tick()
    assertEquals(lateral.drainSounds(), Vector(SoundCue.Bounce))
    val winning = new Game(fixture(coins = Vector(Vec2(144, 114)), goal = Vec2(144, 114)))
    winning.tick()
    winning.tick()
    assertEquals(winning.drainSounds(), Vector(SoundCue.Coin, SoundCue.Goal))
    assertEquals(winning.drainSounds(), Vector.empty)
  }

  test("anvil repeats after ten active seconds only in the original levels and resets with the scene") {
    for (number <- Vector(1, 2, 4)) {
      val game = new Game(fixture().copy(number = number))
      (0 until 599).foreach(_ => game.tick())
      assertEquals(game.drainSounds(), Vector.empty)
      game.tick()
      val expected = if (number == 1 || number == 4) Vector(SoundCue.Anvil) else Vector.empty
      assertEquals(game.drainSounds(), expected)
      (0 until 600).foreach(_ => game.tick())
      assertEquals(game.drainSounds(), expected)
      game.restart()
      (0 until 599).foreach(_ => game.tick())
      assertEquals(game.drainSounds(), Vector.empty)
    }
  }

  test("hazard phases alternate after two seconds with the original activation delay") {
    val game = new Game(fixture(hazards = Vector(HazardSpawn(Vec2(280, 500), 180), HazardSpawn(Vec2(280, 530), 0))))
    val boundaries = Map(
      0 -> Vector(false, false), 14 -> Vector(false, false),
      15 -> Vector(true, false), 119 -> Vector(true, false),
      120 -> Vector(false, false), 134 -> Vector(false, false),
      135 -> Vector(false, true), 239 -> Vector(false, true),
      240 -> Vector(false, false), 254 -> Vector(false, false),
      255 -> Vector(true, false)
    )
    (0 to 255).foreach { tick =>
      boundaries.get(tick).foreach(expected => assertEquals(game.snapshot.hazards.map(_.active), expected))
      game.tick()
    }
  }

  test("screen/world transform round trips with camera offset and rejects letterbox") {
    val viewport = Viewport(1000, 700, 320)
    val world = Vec2(75, 400)
    val back = viewport.toWorld(viewport.toScreen(world)).get
    assertEqualsDouble(back.x, world.x, 1e-8)
    assertEqualsDouble(back.y, world.y, 1e-8)
    assertEquals(viewport.toWorld(Vec2(0, 350)), None)
    assertEquals(viewport.toWorld(Vec2(Double.NaN, 0)), None)
  }

  test("wide levels track player horizontally without shrinking the scene") {
    val wide = fixture(spawn = Vec2(2700, 200)).copy(width = 175, height = 17)
    val game = new Game(wide)
    val viewport = Viewport.forGame(wide, game.snapshot, 640, 1136)
    assertEquals(viewport.viewWidth, 320.0)
    assertEquals(viewport.cameraLeft, 2556.0)
    val center = viewport.toScreen(game.snapshot.player.center)
    assertEqualsDouble(center.x, 320, 1e-8)
    val back = viewport.toWorld(center).get
    assertEqualsDouble(back.x, game.snapshot.player.center.x, 1e-8)
  }

  test("restart restores all simulation state including projectile identity") {
    val game = new Game(fixture(bubbles = Vector(Vec2(144, 80))))
    val initial = game.snapshot
    game.pointerDown(Vec2(20, 20)); game.pointerUp(Vec2(20, 20))
    (0 until 80).foreach(_ => game.tick())
    game.restart()
    assertEquals(game.snapshot, initial)
  }
}
