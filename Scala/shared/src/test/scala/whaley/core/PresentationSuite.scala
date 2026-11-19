package whaley.core

class PresentationSuite extends munit.FunSuite {
  private val font = PresentationData.gameFont
  private def snapshot(status: Status = Status.Playing): Snapshot =
    new Game(LevelData.all.head).snapshot.copy(tick = 600, status = status, collected = 2, bubblesUsed = 3)
  private def glyphs(commands: Vector[UiDraw]): Vector[GlyphQuad] = commands.collect {
    case UiDraw.Image(quad, _, _, _) if quad.page == font.page => quad
  }
  private def settle(p: ScenePresentation, state: Snapshot, mode: BubbleMode = BubbleMode.Normal): Unit = {
    p.advance(1, state, 0, paused = false, mode = mode)
    p.advance(1, state, 0.25, paused = false, mode = mode)
    p.advance(1, state, 0.25, paused = false, mode = mode)
  }

  test("all original game characters use the same 16-unit advance") {
    assertEquals(font.glyphs.size, 95)
    assert(font.glyphs.values.forall(_.advance == 16.0))
    assertEquals(font.advance("!"), 16.0)
    assertEquals(font.advance("QUIT"), 64.0)
    assertEquals(font.advance("CONTINUE"), 128.0)
  }
  test("coin readout is left aligned regardless of number of digits") {
    val starts = Vector("x0", "x9", "x10", "x100").map { text =>
      font.layout(text, 16, 8).head.destination.x
    }
    assert(starts.forall(_ == starts.head))
    val glyph = font.glyphs('!'.toInt)
    val exclamation = font.layout("!", 0, 8).head
    assertEquals(exclamation.destination.width, glyph.source.width)
    assertEquals(exclamation.destination.y, 8 + glyph.yOffset)
  }
  test("alignment uses advances while glyph offsets are preserved") {
    val left = font.layout("QUIT", 0, 0)
    val right = font.layout("QUIT", 320, 0, TextAlignment.Right)
    assertEquals(right.head.destination.x - left.head.destination.x, 256.0)
  }
  test("HUD uses the current painting name and only the original pause labels") {
    assertEquals((1 to 6).map(ScenePresentation.levelName).toVector,
      Vector("DRYDOCK AT LIVERPOOL", "THE CREATION", "IN THE OMNIBUS", "LAS MENINAS", "THE SCAPEGOAT", "PEARL EARRING"))
    val p = new ScenePresentation()
    val state = snapshot().copy(collected = 0)
    val level = LevelData.all.head
    settle(p, state)
    assertEquals(glyphs(p.commands(level, state, false, 320, 568)),
      font.layout("DRYDOCK AT LIVERPOOL", 160, 8, TextAlignment.Center))
    val paused = p.commands(level, state, true, 320, 568)
    assertEquals(glyphs(paused), font.layout("QUIT", 24, 8) ++ font.layout("CONTINUE", 320, 8, TextAlignment.Right))
    val icons = paused.collect { case UiDraw.Image(q, color, flipX, flipY) if q.page == "player.png" =>
      (q.destination, color, flipX, flipY)
    }
    assertEquals(icons, Vector((Rect(4, 8, 16, 16), UiColor(255, 0, 0), false, true),
      (Rect(172, 8, 16, 16), UiColor(), false, false)))
    assertEquals(paused.collect { case UiDraw.Black(r) => r }, Vector(Rect(0, 0, 320, 32)))
  }
  test("top bar pause and quit act on press and never leak a release action") {
    val p = new ScenePresentation()
    val state = snapshot()
    settle(p, state)
    assertEquals(p.pointerDown(state, false, Vec2(160, 16), 320, 568), Some(SceneAction.Pause))
    assertEquals(p.pointerUp(state, Vec2(160, 16), 320, 568), None)
    assertEquals(p.pointerDown(state, true, Vec2(87.99, 16), 320, 568), Some(SceneAction.Quit))
    assertEquals(p.pointerDown(state, true, Vec2(88, 16), 320, 568), Some(SceneAction.Resume))
    assertEquals(p.pointerDown(state, true, Vec2(310, 31.99), 320, 568), Some(SceneAction.Resume))
    assertEquals(p.pointerDown(state, false, Vec2(160, 32), 320, 568), None)
    assertEquals(p.pointerDown(state, false, Vec2(-1, 16), 320, 568), None)
  }
  test("held bubble flame warning retains the coin count without adding a label") {
    val p = new ScenePresentation()
    val state = snapshot().copy(
      bubbles = Vector(BubbleView(1, Vec2(100, 100), 64, 2, true, true)),
      hazards = Vector(HazardView(Vec2(100, 100), active = false)))
    settle(p, state)
    assertEquals(glyphs(p.commands(LevelData.all.head, state, false, 320, 568)),
      font.layout("x2", 16, 8) ++ font.layout("!", 160, 8, TextAlignment.Center))
  }
  test("level two includes its actual 1280 visual cells and atlas") {
    val level = PresentationData.levels(2)
    assertEquals(level.cells.size, 1280)
    assertEquals(level.cells.count(_._3 == 1), 1221)
    assertEquals(level.cells.count(_._3 == 2), 59)
    assertEquals(level.art(1), TileArt("tileset.png", Rect(2, 2, 32, 32)))
    assertEquals(level.art(2), TileArt("tileset.png", Rect(36, 2, 32, 32)))
    assert(PresentationData.requiredImages.contains("game_font.png"))
    assert(PresentationData.requiredImages.contains("tileset.png"))
  }
  test("victory clock advances independently of frozen gameplay ticks") {
    val p = new ScenePresentation()
    val won = snapshot(Status.Won)
    p.advance(1, won, 0, paused = false)
    assert(p.spout(won).nonEmpty)
    assert(!p.showingResults(won))
    p.advance(1, won, 0.25, paused = false)
    p.advance(1, won, 0.25, paused = false)
    assert(p.showingResults(won))
    assert(p.spout(won).isEmpty)
    assert(p.scoresVisible)
    p.advance(1, won, 0.25, paused = false)
    p.advance(1, won, 0.25, paused = false)
    assert(!p.scoresVisible)
    p.advance(1, won, 50, paused = true)
    assertEquals(p.elapsed, 1.0)
  }
  test("spout trimmed frames remain planted on their original bottom edge") {
    val origin = Vec2(30, 90)
    assertEquals(PresentationData.spout.length, 4)
    PresentationData.spout.foreach { frame =>
      val bounds = frame.atBottomLeft(origin)
      assertEquals(bounds.y, origin.y)
      assertEquals(bounds.width, frame.source.width)
      assertEquals(bounds.height, frame.source.height)
    }
  }
  test("original score arithmetic retains integer bubble division") {
    val p = new ScenePresentation()
    assertEquals(p.score(snapshot()), 200L + 1250L + (30000.0 / 10.1).toLong)
  }
  test("results retain original padded text, icon rows and blinking score values") {
    val p = new ScenePresentation()
    val won = snapshot(Status.Won)
    settle(p, won)
    val labels = font.layout("DRYDOCK AT LIVERPOOL", 160, 196, TextAlignment.Center) ++
      font.layout("      x 2", 64, 228) ++ font.layout("      x 3", 64, 244) ++
      font.layout("   TIME 10", 64, 260) ++ font.layout("  SCORE ", 64, 292) ++ font.layout("     HI ", 64, 308)
    val commands = p.commands(LevelData.all.head, won, false, 320, 568)
    assertEquals(glyphs(commands), labels ++ font.layout(p.score(won).toString, 192, 292) ++
      font.layout(p.score(won).toString, 192, 308))
    assert(commands.exists {
      case UiDraw.Image(q, color, false, false) => q.page == "bubble01.png" &&
        q.destination == Rect(128, 244, 16, 16) && color == UiColor(153, 153, 255)
      case _ => false
    })
    assert(commands.exists {
      case UiDraw.Image(q, _, _, _) => q.page == "coin.png" && q.destination == Rect(128, 228, 16, 16)
      case _ => false
    })
    p.advance(1, won, 0.25, paused = false)
    p.advance(1, won, 0.25, paused = false)
    assertEquals(glyphs(p.commands(LevelData.all.head, won, false, 320, 568)), labels)
  }
  test("results bubble uses progression before the win unlocks the next painting") {
    val cases = Vector(
      (5, 5, BubbleMode.Normal, "bubble01.png", UiColor(153, 153, 255), 6),
      (5, 5, BubbleMode.ExtraBounce, "bubble01.png", UiColor(211, 24, 149), 6),
      (6, 6, BubbleMode.Normal, "infinite_bubble.png", UiColor(153, 153, 255), 7),
      (6, 6, BubbleMode.ExtraBounce, "infinite_bubble.png", UiColor(211, 24, 149), 7),
      (6, 1, BubbleMode.Normal, "infinite_bubble.png", UiColor(153, 153, 255), 6),
      (7, 1, BubbleMode.Normal, "infinite_bubble.png", UiColor(), 7),
      (7, 1, BubbleMode.ExtraBounce, "infinite_bubble.png", UiColor(), 7),
      (7, 1, BubbleMode.Infinite, "infinite_bubble.png", UiColor(), 7)
    )
    cases.foreach { case (achieved, number, mode, page, color, nextAchieved) =>
      val gallery = new GalleryScene(() => 0)
      gallery.restoreProgress(achieved, reward = false)
      val p = new ScenePresentation()
      p.reset(gallery.levelsAchieved)
      val won = snapshot(Status.Won)
      p.advance(number, won, 0, paused = false, mode = mode)
      p.recordWinProgress(gallery.levelsAchieved)
      gallery.completeLevel(number)
      assertEquals(gallery.levelsAchieved, nextAchieved)
      p.advance(number, won, 0.25, paused = false, mode = mode)
      p.advance(number, won, 0.25, paused = false, mode = mode)
      val bubble = p.commands(LevelData.all(number - 1), won, false, 320, 568, mode).collect {
        case UiDraw.Image(q, tint, _, _) if q.page == "bubble01.png" || q.page == "infinite_bubble.png" =>
          (q.page, tint, q.destination)
      }
      assertEquals(bubble, Vector((page, color, Rect(128, 244, 16, 16))))
      assertEquals(p.whaleFrame._1, if (achieved > 6) "player-win.png" else "player.png",
        "completing the game does not replace artwork in the already constructed scene")
    }
  }
  test("HUD sprite artwork and animation start with the scene rather than the saved score clock") {
    val p = new ScenePresentation()
    val restored = snapshot().copy(tick = 480)
    p.reset(7)
    p.advance(1, restored, 0, paused = false)
    assertEquals(p.whaleFrame, ("player-win.png", SpriteData.playerWinFrames.head))
    val icons = p.commands(LevelData.all.head, restored, true, 320, 568, BubbleMode.Normal).collect {
      case UiDraw.Image(q, _, _, _) if q.page == "player-win.png" => q.source
    }
    assertEquals(icons, Vector.fill(2)(SpriteData.playerWinFrames.head),
      "completed-game artwork is independent of a normal practice mode")
    p.advance(1, restored, 0.25, paused = false)
    assertEquals(p.whaleFrame._2, SpriteData.playerWinFrames(1))
    p.advance(1, restored, 20, paused = true)
    assertEquals(p.whaleFrame._2, SpriteData.playerWinFrames(1))
    p.advance(1, restored, 0.25, paused = false)
    assertEquals(p.whaleFrame._2, SpriteData.playerWinFrames(2))
    p.reset(6)
    p.advance(1, restored, 0, paused = false, mode = BubbleMode.Infinite)
    assertEquals(p.whaleFrame, ("player.png", SpriteData.playerFrames.head))
    assertEquals(p.coinFrame, SpriteData.coinFrames.head)
    p.advance(1, restored, 0.1, paused = false)
    val hudCoin = p.commands(LevelData.all.head, restored, false, 320, 568).collect {
      case UiDraw.Image(q, _, _, _) if q.page == "coin.png" => q.source
    }
    assertEquals(hudCoin, Vector(SpriteData.coinFrames(1)))
    p.reset(6)
    assertEquals(p.coinFrame, SpriteData.coinFrames.head)
  }
  test("results construct a new animated coin despite frozen gameplay ticks") {
    val p = new ScenePresentation()
    val won = snapshot(Status.Won)
    settle(p, won)
    def resultCoin: Rect = p.commands(LevelData.all.head, won, false, 320, 568).collectFirst {
      case UiDraw.Image(q, _, _, _) if q.page == "coin.png" => q.source
    }.get
    assertEquals(resultCoin, SpriteData.coinFrames.head)
    p.advance(1, won, 0.1, paused = false)
    assertEquals(resultCoin, SpriteData.coinFrames(1))
    p.advance(1, won, 20, paused = true)
    assertEquals(resultCoin, SpriteData.coinFrames(1))
    for (_ <- 0 until 7) p.advance(1, won, 0.1, paused = false)
    assertEquals(resultCoin, SpriteData.coinFrames.head)
  }
  test("results require their own uncancelled press and preserve automatic advance") {
    val p = new ScenePresentation()
    val won = snapshot(Status.Won)
    p.advance(1, won, 0, paused = false)
    assertEquals(p.pointerDown(won, false, Vec2(160, 284), 320, 568), None)
    p.advance(1, won, 0.25, paused = false)
    p.advance(1, won, 0.25, paused = false)
    assertEquals(p.pointerUp(won, Vec2(160, 284), 320, 568), None)
    p.pointerDown(won, false, Vec2(160, 284), 320, 568)
    p.cancelPointer()
    assertEquals(p.pointerUp(won, Vec2(160, 284), 320, 568), None)
    p.pointerDown(won, false, Vec2(160, 284), 320, 568)
    assertEquals(p.pointerUp(won, Vec2(-1, 284), 320, 568), None)
    p.pointerDown(won, false, Vec2(160, 284), 320, 568)
    assertEquals(p.pointerUp(won, Vec2(160, 284), 320, 568), Some(SceneAction.Next))
    assertEquals(p.pointerUp(won, Vec2(160, 284), 320, 568), None)
    for (_ <- 0 until 11) p.advance(1, won, 0.25, paused = false)
    assertEquals(p.automaticAction(won), None)
    p.advance(1, won, 0.25, paused = false)
    assertEquals(p.automaticAction(won), Some(SceneAction.Next))
  }
  test("death replays after two seconds with no invented retry panel") {
    val p = new ScenePresentation()
    val dead = snapshot(Status.Dead)
    settle(p, dead)
    assertEquals(glyphs(p.commands(LevelData.all.head, dead, false, 320, 568)), font.layout("x2", 16, 8))
    for (_ <- 0 until 5) p.advance(1, dead, 0.25, paused = false)
    assertEquals(p.automaticAction(dead), None)
    p.advance(1, dead, 10, paused = true)
    assertEquals(p.automaticAction(dead), None)
    p.advance(1, dead, 0.25, paused = false)
    assertEquals(p.automaticAction(dead), Some(SceneAction.Replay))
  }
  test("HI scores remain separate for each original bubble mode") {
    val p = new ScenePresentation()
    val high = snapshot(Status.Won).copy(collected = 50)
    settle(p, high, BubbleMode.Normal)
    p.reset()
    val low = snapshot(Status.Won)
    settle(p, low, BubbleMode.ExtraBounce)
    val expected = font.layout(p.score(low).toString, 192, 308)
    val actual = glyphs(p.commands(LevelData.all.head, low, false, 320, 568, BubbleMode.ExtraBounce))
      .filter(q => q.destination.x >= 192 && q.destination.y >= 308)
    assertEquals(actual, expected)
  }
  test("both foreground styles retain paintings and translucent level overlays") {
    val p = new ScenePresentation()
    val state = snapshot().copy(collected = 0)
    settle(p, state)
    LevelData.all.foreach { level =>
      val page = s"level${level.number}-568h.png"
      val source = Rect(0, 0, 320, 568)
      val backdrop: Vector[UiDraw] = Vector(UiDraw.Image(GlyphQuad(page, source, Rect(0, 0, 320, 568)),
        UiColor(alpha = 190.0 / 255)))
      assert(PresentationData.requiredImages.contains(page))
      assertEquals(p.backdrop(level, 320, 568), backdrop)
      val commands = p.commands(level, state, false, 320, 568)
      val scanlines = commands.collect {
        case image @ UiDraw.Image(q, _, _, _) if q.page == "scanlines-568h.png" => image
      }
      val expectedScanlines: Vector[UiDraw] = if (level.number == 1 || level.number == 2)
        Vector(UiDraw.Image(GlyphQuad("scanlines-568h.png", source, Rect(0, 0, 320, 568)),
          UiColor(alpha = 128.0 / 255))) else Vector.empty
      assertEquals(scanlines, expectedScanlines)
      if (scanlines.nonEmpty) assert(PresentationData.requiredImages.contains("scanlines-568h.png"))
      val water = commands.collect { case fill @ UiDraw.Fill(_, _) => fill }
      assertEquals(water, if (level.number >= 4)
        Vector(UiDraw.Fill(Rect(0, 0, 320, 568), UiColor(102, 102, 255, 64.0 / 255))) else Vector.empty)
      if (level.number == 2 || level.number == 5) assertEquals(commands.last, UiDraw.Black(Rect(0, 544, 320, 24)))
      if (level.number == 1) assertEquals(commands.last, scanlines.head)
    }
  }
  test("translucent overlays retain viewport coverage through pause and replay") {
    val p = new ScenePresentation()
    def overlays(commands: Vector[UiDraw]): Vector[UiDraw] = commands.filter {
      case UiDraw.Image(q, _, _, _) => q.page == "scanlines-568h.png"
      case UiDraw.Fill(_, _) => true
      case _ => false
    }
    for (level <- LevelData.all; size <- Vector(Vec2(320, 480), Vec2(320, 568), Vec2(568, 320), Vec2(768, 1024))) {
      val state = new Game(level).snapshot
      val bounds = Rect(0, 0, size.x, size.y)
      val expected: Vector[UiDraw] = if (level.number <= 2)
        Vector(UiDraw.Image(GlyphQuad("scanlines-568h.png", Rect(0, 0, 320, 568), bounds),
          UiColor(alpha = 128.0 / 255)))
      else if (level.number >= 4) Vector(UiDraw.Fill(bounds, UiColor(102, 102, 255, 64.0 / 255)))
      else Vector.empty
      p.reset()
      p.advance(level.number, state, 0, paused = false)
      assertEquals(overlays(p.commands(level, state, false, size.x, size.y)), expected)
      p.advance(level.number, state, 10, paused = true)
      assertEquals(overlays(p.commands(level, state, true, size.x, size.y)), expected)
      p.reset()
      assertEquals(overlays(p.commands(level, state, false, size.x, size.y)), expected)
    }
  }
  test("paintings fill the viewport without changing the source crop or tint") {
    val p = new ScenePresentation()
    for (level <- LevelData.all; size <- Vector(Vec2(320, 480), Vec2(320, 568), Vec2(568, 320), Vec2(768, 1024))) {
      val expected: Vector[UiDraw] = Vector(UiDraw.Image(
        GlyphQuad(s"level${level.number}-568h.png", Rect(0, 0, 320, 568), Rect(0, 0, size.x, size.y)),
        UiColor(alpha = 190.0 / 255)))
      assertEquals(p.backdrop(level, size.x, size.y), expected)
    }
  }
  test("background artwork survives pause, replay and level changes") {
    val p = new ScenePresentation()
    LevelData.all.foreach { level =>
      val state = new Game(level).snapshot
      val expected = p.backdrop(level, 320, 568)
      p.advance(level.number, state, 0, paused = false)
      p.advance(level.number, state, 0.25, paused = false)
      p.advance(level.number, state, 10, paused = true)
      assertEquals(p.backdrop(level, 320, 568), expected)
      p.reset()
      assertEquals(p.backdrop(level, 320, 568), expected)
    }
  }
  test("entry mask vanishes as hard tiles, leaving one opaque top bar") {
    val p = new ScenePresentation()
    val playing = snapshot().copy(collected = 0)
    val level = LevelData.all.head
    p.advance(1, playing, 0, paused = false)
    assert(p.commands(level, playing, false, 320, 568).count {
      case UiDraw.Black(_) => true
      case _ => false
    } > 1)
    p.advance(1, playing, 0.25, paused = false)
    p.advance(1, playing, 0.25, paused = false)
    val rectangles = p.commands(level, playing, false, 320, 568).collect { case UiDraw.Black(r) => r }
    assertEquals(rectangles, Vector(Rect(0, 0, 320, 32)))
  }
  test("same inputs produce identical presentation commands for Native and JS") {
    val a = new ScenePresentation()
    val b = new ScenePresentation()
    val level = LevelData.all.head
    for (state <- Vector(snapshot(), snapshot(Status.Won)); _ <- 0 until 100) {
      a.advance(1, state, 1.0 / 60, paused = false)
      b.advance(1, state, 1.0 / 60, paused = false)
      assertEquals(a.commands(level, state, false, 320, 568), b.commands(level, state, false, 320, 568))
    }
  }
}
