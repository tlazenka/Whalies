package whaley.core

class CharacterExpressionSuite extends munit.FunSuite {
  import CharacterExpression.*
  private val level = Level(1, 40, 40, 32, Set.empty, Set.empty, Vec2(100, 100),
    Vector.empty, Vector.empty, Vector.empty, Vec2(1200, 1200))
  private def initial: Snapshot = new Game(level).snapshot.copy(
    player = PlayerView(Vec2(100, 100), AirMode.Grounded, false))

  private final class Trace(start: Snapshot = initial) {
    val presentation = new CharacterPresentation()
    var state: Snapshot = start
    def frame: CharacterFrame = presentation.frame(state)
    def step(cues: Vector[SoundCue] = Vector.empty,
             change: Snapshot => Snapshot = state => state): CharacterFrame = {
      val next = change(state.copy(tick = state.tick + 1))
      presentation.observeTick(level, state, next, cues)
      state = next
      frame
    }
    def run(count: Int): CharacterFrame = {
      for (_ <- 0 until count) step()
      frame
    }
  }
  private def at(position: Vec2)(state: Snapshot): Snapshot =
    state.copy(player = state.player.copy(position = position))

  test("gaze holds its target, requires a meaningful improvement and releases a collected coin") {
    val first = CoinView(1, Vec2(176, 116))
    val second = CoinView(2, Vec2(178, 116))
    val trace = new Trace(initial.copy(coins = Vector(first, second)))
    val locked = Some(CharacterTarget(CharacterTargetKind.Coin, 1))
    assertEquals(trace.step().target, locked)
    trace.step(change = _.copy(coins = Vector(first, second.copy(position = Vec2(174, 116)))))
    assertEquals(trace.run(20).target, locked, "a near tie does not flicker after the minimum hold")
    val better = trace.step(change = _.copy(coins = Vector(first, second.copy(position = Vec2(140, 116)))))
    assertEquals(better.target, Some(CharacterTarget(CharacterTargetKind.Coin, 2)))
    assertEquals(trace.step(change = _.copy(coins = Vector(first))).target, locked,
      "disappearance releases a target immediately, even inside its hold")

    val held = new Trace(initial.copy(coins = Vector(first, second)))
    held.step()
    held.step(change = _.copy(coins = Vector(first, second.copy(position = Vec2(140, 116)))))
    assertEquals(held.run(16).target, locked)
    assertEquals(held.step().target, Some(CharacterTarget(CharacterTargetKind.Coin, 2)))

    val hazard = new Trace(initial.copy(hazards = Vector(HazardView(Vec2(180, 116), true))))
    val hazardTarget = Some(CharacterTarget(CharacterTargetKind.Hazard, 0))
    assertEquals(hazard.step().target, hazardTarget)
    hazard.run(18)
    // Exercise the retention-only band directly: the same target remains
    // eligible at 170 pixels with a 93-pixel projected clearance, while a
    // 20-pixel coin is eligible for acquisition. Distance cannot lower rank.
    val retained = hazard.step(change = s => at(Vec2(103, 103))(s).copy(
      hazards = Vector(HazardView(Vec2(239, 239), true)),
      coins = Vector(CoinView(9, Vec2(139, 119)))))
    assertEquals(retained.target, hazardTarget,
      "a closer coin cannot displace a retained higher-priority hazard")
    assertEquals(hazard.step(change = _.copy(hazards = Vector.empty)).target,
      Some(CharacterTarget(CharacterTargetKind.Coin, 9)))
  }

  test("target tie breaks are stable and gaze accounts for the body's facing flip") {
    val coins = Vector(CoinView(7, Vec2(156, 156)), CoinView(2, Vec2(156, 156)))
    val right = new Trace(initial.copy(coins = coins))
    val rightFrame = right.step()
    assertEquals(rightFrame.target, Some(CharacterTarget(CharacterTargetKind.Coin, 2)))
    assertEquals(rightFrame.column, 2, "up-right in the unflipped sprite")
    // Moving toward the target keeps it eligible when the body is facing left.
    val left = new Trace(initial.copy(coins = coins, player = initial.player.copy(facingLeft = true)))
    val leftFrame = left.step(change = at(Vec2(101, 100)))
    assertEquals(leftFrame.column, 0, "the later facing flip restores the same world gaze")
    assertEquals(leftFrame.row, Pensive.row)
  }

  test("an approaching hazard preempts a young coin lock before it is currently close") {
    val trace = new Trace(initial.copy(coins = Vector(CoinView(1, Vec2(196, 116)))))
    trace.step(Vector(SoundCue.Coin))
    assertEquals(trace.frame.expression, Happy)
    val incoming = trace.step(change = s => at(Vec2(103, 100))(s).copy(
      hazards = Vector(HazardView(Vec2(209, 116), active = true))))
    assertEquals(incoming.target, Some(CharacterTarget(CharacterTargetKind.Hazard, 0)))
    assertEquals(incoming.expression, Alarmed, "90 pixels away but inside the 18-tick projected path")
    val safe = trace.step(change = _.copy(hazards = Vector.empty, coins = Vector.empty))
    assertEquals(safe.expression, Neutral, "the interrupted happy reaction does not resume")
  }

  test("inactive hazards do not take attention and approaching nonurgent hazards remain pensive") {
    val trace = new Trace(initial.copy(coins = Vector(CoinView(1, Vec2(150, 116))),
      hazards = Vector(HazardView(Vec2(120, 116), active = false))))
    assertEquals(trace.step().target, Some(CharacterTarget(CharacterTargetKind.Coin, 1)))
    val approach = new Trace(initial)
    val frame = approach.step(change = s => at(Vec2(103, 100))(s).copy(
      hazards = Vector(HazardView(Vec2(239, 116), active = true)),
      coins = Vector(CoinView(1, Vec2(150, 116)))))
    assertEquals(frame.expression, Pensive)
    assertEquals(frame.target, Some(CharacterTarget(CharacterTargetKind.Hazard, 0)))
  }

  test("relief requires a survived close call followed by twelve safe ticks") {
    val trace = new Trace(initial.copy(hazards = Vector(HazardView(Vec2(170, 116), active = true))))
    assertEquals(trace.step(change = at(Vec2(120, 100))).expression, Alarmed)
    trace.step(change = at(Vec2(30, 100)))
    assertNotEquals(trace.run(10).expression, Relief)
    assertEquals(trace.step().expression, Relief)
    assertEquals(trace.run(47).expression, Relief)
    assertNotEquals(trace.step().expression, Relief)

    val merelyNearby = new Trace(initial.copy(hazards = Vector(HazardView(Vec2(166, 116), active = true))))
    merelyNearby.step()
    merelyNearby.step(change = at(Vec2(30, 100)))
    assertNotEquals(merelyNearby.run(20).expression, Relief)

    val spawnedNearby = new Trace(initial.copy(hazards = Vector(HazardView(Vec2(150, 116), active = true))))
    spawnedNearby.step()
    spawnedNearby.step(change = at(Vec2(30, 100)))
    assertNotEquals(spawnedNearby.run(20).expression, Relief,
      "spawning inside the close-call band did not cross into it")
  }

  test("coin combos advance once per collected coin, expire and cannot celebrate through danger") {
    val trace = new Trace()
    assertEquals(trace.step(Vector(SoundCue.Coin)).expression, Happy)
    assertEquals(trace.step(Vector(SoundCue.Coin)).expression, Playful)
    assertEquals(trace.step(Vector(SoundCue.Coin)).expression, Happy)
    assertEquals(trace.run(6), CharacterFrame(Happy, 4, None))
    assertEquals(trace.run(48).expression, Neutral)
    trace.run(40)
    assertEquals(trace.step(Vector(SoundCue.Coin)).expression, Happy)
    val simultaneous = new Trace()
    assertEquals(simultaneous.step(Vector(SoundCue.Coin, SoundCue.Coin)).expression, Playful)

    val looking = new Trace(initial.copy(coins = Vector(CoinView(7, Vec2(156, 156)))))
    assertEquals(looking.step(Vector.fill(3)(SoundCue.Coin)),
      CharacterFrame(Happy, 2, Some(CharacterTarget(CharacterTargetKind.Coin, 7))))
    assertEquals(looking.step(change = _.copy(coins = Vector(CoinView(7, Vec2(156, 76))))),
      CharacterFrame(Happy, 8, Some(CharacterTarget(CharacterTargetKind.Coin, 7))))

    val danger = new Trace(initial.copy(hazards = Vector(HazardView(Vec2(151, 116), active = true))))
    assertEquals(danger.step(Vector.fill(3)(SoundCue.Coin)).expression, Alarmed)
    assertEquals(danger.step(change = _.copy(hazards = Vector.empty)).expression, Neutral)
  }

  test("upward bounce chains progress to a playful face, keep their gaze and reset on landing") {
    val trace = new Trace(initial.copy(player = initial.player.copy(airMode = AirMode.JumpingUp)))
    assertEquals(trace.step(Vector(SoundCue.Jump)).expression, Happy)
    assertEquals(trace.step(Vector(SoundCue.Jump)).expression, TongueOut)
    assertEquals(trace.step(Vector(SoundCue.Jump)), CharacterFrame(Playful, 4, None))
    assertEquals(trace.run(24), CharacterFrame(Playful, 4, None))
    assertEquals(trace.run(3).expression, Neutral)
    trace.step(change = s => s.copy(player = s.player.copy(airMode = AirMode.Grounded)))
    val bounced = trace.step(Vector(SoundCue.Jump), s => s.copy(player = s.player.copy(airMode = AirMode.JumpingUp)))
    assertEquals(bounced.expression, Happy)
  }

  test("side-contact reactions debounce the same bubble and count alternating ricochets") {
    val bubbles = Vector(BubbleView(1, Vec2(96, 116), 22, 2, false, true),
      BubbleView(2, Vec2(136, 116), 22, 2, false, true))
    val trace = new Trace(initial.copy(bubbles = bubbles))
    assertEquals(trace.step(Vector(SoundCue.Bounce)).expression, TongueOut)
    assertEquals(trace.step(Vector(SoundCue.Bounce), at(Vec2(103, 100))).expression, EyeRoll)
    assertEquals(trace.step(Vector(SoundCue.Bounce), at(Vec2(100, 100))).expression, Exasperated)
    trace.run(91)
    assertEquals(trace.step(Vector(SoundCue.Bounce)).expression, TongueOut)

    val repeated = new Trace(initial.copy(bubbles = bubbles.take(1)))
    repeated.step(Vector(SoundCue.Bounce))
    repeated.step(Vector(SoundCue.Bounce))
    assertEquals(repeated.run(23).expression, Neutral, "a duplicate contact did not restart the 24-tick reaction")

    val eyeRoll = new Trace(initial.copy(bubbles = bubbles))
    eyeRoll.step(Vector(SoundCue.Bounce))
    eyeRoll.step(Vector(SoundCue.Bounce), at(Vec2(103, 100)))
    val columns = (0 until 6).map { index =>
      if (index > 0) eyeRoll.run(6)
      eyeRoll.frame.column
    }.toVector
    assertEquals(columns, Vector(3, 0, 1, 2, 5, 4))
    assertEquals(eyeRoll.run(6).expression, Neutral)
  }

  test("reaction priority rejects lower events without queueing them") {
    val bubbles = Vector(BubbleView(1, Vec2(96, 116), 22, 2, false, true),
      BubbleView(2, Vec2(136, 116), 22, 2, false, true))
    val trace = new Trace(initial.copy(bubbles = bubbles))
    trace.step(Vector(SoundCue.Bounce))
    trace.step(Vector(SoundCue.Bounce), at(Vec2(103, 100)))
    trace.step(Vector(SoundCue.Bounce), at(Vec2(100, 100)))
    assertEquals(trace.step(Vector.fill(3)(SoundCue.Coin)).expression, Exasperated)
    assertEquals(trace.run(41).expression, Neutral)
  }

  test("safe grounded idle relaxes and whistles, while motion and danger interrupt it") {
    val trace = new Trace()
    assertEquals(trace.run(179).expression, Neutral)
    assertEquals(trace.step().expression, Relaxed)
    assertEquals(trace.run(120).expression, Whistle)
    assertEquals(trace.step(change = at(Vec2(101, 100))).expression, Neutral)
    trace.run(300)
    assertEquals(trace.step(change = _.copy(hazards = Vector(HazardView(Vec2(147, 116), true)))).expression, Alarmed)
  }

  test("duplicate observations, pause and reset cannot advance or leak reaction state") {
    val p = new ScenePresentation()
    val before = initial.copy(tick = 900)
    val after = before.copy(tick = 901)
    p.advance(1, before, 0, paused = false)
    p.observeTick(level, before, after, Vector(SoundCue.Coin))
    p.observeTick(level, before, after, Vector(SoundCue.Coin))
    val happy = p.characterFrame(after)
    assertEquals(happy.expression, Happy)
    for (_ <- 0 until 20) p.advance(1, after, 10, paused = true)
    assertEquals(p.characterFrame(after), happy)
    p.reset()
    assertEquals(p.characterFrame(after).expression, Neutral)
    p.observeTick(level, after, after.copy(tick = 902), Vector(SoundCue.Coin))
    assertEquals(p.characterFrame(after).expression, Happy)
  }

  test("terminal expressions supersede events without animating a whole-body pose") {
    val trace = new Trace(initial.copy(hazards = Vector(HazardView(Vec2(150, 116), true))))
    trace.step()
    val dead = trace.step(Vector(SoundCue.Coin), _.copy(status = Status.Dead))
    assertEquals(dead, CharacterFrame(Exasperated, 4, None))
    trace.presentation.reset()
    val won = initial.copy(status = Status.Won)
    assertEquals(trace.presentation.frame(won), CharacterFrame(Happy, 4, None))
    val scene = new ScenePresentation()
    for (_ <- 0 until 60) {
      scene.advance(level.number, won, 1.0 / 60, paused = false)
      assertEquals(scene.characterFrame(won), CharacterFrame(Happy, 4, None))
    }
  }

  test("fixed-step batching yields the same simulation and character trace") {
    val gameLevel = level.copy(spawn = Vec2(128, 100), bubbles = Vector(Vec2(144, 80)),
      coins = Vector(Vec2(144, 134), Vec2(144, 170)))
    def trace(batchSize: Int): Vector[(Snapshot, CharacterFrame)] = {
      val game = new Game(gameLevel)
      val p = new ScenePresentation()
      val clock = new FixedStepClock()
      val out = Vector.newBuilder[(Snapshot, CharacterFrame)]
      for (_ <- 0 until (180 / batchSize)) {
        clock.advance(batchSize / 60.0) { () =>
          val before = game.snapshot
          game.tick()
          val state = game.snapshot
          p.observeTick(gameLevel, before, state, game.drainSounds())
          out += ((state, p.characterFrame(state)))
        }
        p.advance(gameLevel.number, game.snapshot, batchSize / 60.0, paused = false)
      }
      out.result()
    }
    val single = trace(1)
    assertEquals(single.size, 180)
    assert(single.exists(_._2.expression == Happy))
    assertEquals(trace(9), single)
    assertEquals(trace(15), single)
  }

  test("both scene styles preserve original reward artwork and the 32-pixel face contract") {
    val p = new ScenePresentation()
    p.reset(levelsAchieved = 7)
    p.advance(1, initial, 0, paused = false)
    val next = initial.copy(tick = 1)
    p.observeTick(level, initial, next, Vector(SoundCue.Coin))
    val result = p.worldWhaleFrame(next)
    assertEquals(result, ("whaley-win-expressions.png", Rect(128, 128, 32, 32)))
    assertEquals(p.whaleFrame._1, "player-win.png")
    p.reset()
    p.advance(1, initial, 0, paused = false)
    assertEquals(p.worldWhaleFrame(initial), ("whaley-expressions.png", Rect(128, 0, 32, 32)))
    assertEquals(p.whaleFrame._1, "player.png")
  }

  test("original flag and water animation banks advance at 0.25 seconds and freeze while paused") {
    val p = new ScenePresentation()
    for (completed <- Vector(false, true)) {
      p.reset(levelsAchieved = if (completed) 7 else 1)
      p.advance(1, initial, 0, paused = false)
      val page = if (completed) "whaley-win-expressions.png" else "whaley-expressions.png"
      assertEquals(p.worldWhaleFrame(initial), (page, Rect(128, 0, 32, 32)))
      p.advance(1, initial, 0.25, paused = false)
      assertEquals(p.worldWhaleFrame(initial), (page, Rect(416, 0, 32, 32)))
      p.advance(1, initial, 20, paused = true)
      assertEquals(p.worldWhaleFrame(initial), (page, Rect(416, 0, 32, 32)))
      p.advance(1, initial, 0.25, paused = false)
      assertEquals(p.worldWhaleFrame(initial), (page, Rect(704, 0, 32, 32)))
      p.advance(1, initial, 0.25, paused = false)
      assertEquals(p.worldWhaleFrame(initial), (page, Rect(128, 0, 32, 32)))
    }
  }
}
