package whaley.core

/** Rendering-only data. TMX Background cells are deliberately separate from
  * the Meta cells used by Game's collision rules. Both come from original assets.
  */
final case class TileArt(page: String, source: Rect)
final case class VisualLevel(tileSize: Int, cells: Vector[(Int, Int, Int)], art: Map[Int, TileArt],
                             painting: TileArt, scanlines: Option[TileArt]) {
  def visible(view: Viewport): Vector[(TileArt, Vec2)] = cells.collect {
    case (x, y, gid) if (x + 1) * tileSize > view.cameraLeft &&
        x * tileSize < view.cameraLeft + view.viewWidth &&
        (y + 1) * tileSize > view.cameraBottom && y * tileSize < view.cameraBottom + view.viewHeight =>
      (art(gid), Vec2((x + 0.5) * tileSize, (y + 0.5) * tileSize))
  }
}

final case class BitmapGlyph(source: Rect, xOffset: Double, yOffset: Double, advance: Double)
final case class GlyphQuad(page: String, source: Rect, destination: Rect)
enum TextAlignment { case Left, Center, Right }

/** BMFont layout in top-left logical coordinates. Advances determine alignment;
  * offsets determine the painted glyph. No system font or per-character scaling.
  */
final case class BitmapFont(page: String, lineHeight: Double, glyphs: Map[Int, BitmapGlyph],
                            kernings: Map[(Int, Int), Double] = Map.empty) {
  private def glyph(code: Int): BitmapGlyph = glyphs.getOrElse(code,
    glyphs.getOrElse('?'.toInt, throw new IllegalArgumentException(s"Missing bitmap glyph $code")))

  def advance(text: String): Double = {
    var previous = -1
    text.foldLeft(0.0) { (width, char) =>
      val code = char.toInt
      val result = width + kernings.getOrElse((previous, code), 0.0) + glyph(code).advance
      previous = code
      result
    }
  }

  def layout(text: String, x: Double, top: Double,
             alignment: TextAlignment = TextAlignment.Left): Vector[GlyphQuad] = {
    val width = advance(text)
    var pen = alignment match {
      case TextAlignment.Left => x
      case TextAlignment.Center => x - width / 2
      case TextAlignment.Right => x - width
    }
    var previous = -1
    text.iterator.flatMap { char =>
      val code = char.toInt
      val g = glyph(code)
      pen += kernings.getOrElse((previous, code), 0.0)
      val destination = Rect(pen + g.xOffset, top + g.yOffset, g.source.width, g.source.height)
      pen += g.advance
      previous = code
      Option.when(g.source.width > 0 && g.source.height > 0)(GlyphQuad(page, g.source, destination))
    }.toVector
  }
}

/** TexturePacker/cocos2d trim offsets use a centered, upward-positive frame.
  * Keep the original logical box fixed as differently trimmed frames animate.
  */
final case class AtlasFrame(source: Rect, originalSize: Vec2, offset: Vec2) {
  def atBottomLeft(origin: Vec2): Rect = Rect(
    origin.x + (originalSize.x - source.width) / 2 + offset.x,
    origin.y + (originalSize.y - source.height) / 2 + offset.y,
    source.width, source.height)
}

final case class UiColor(red: Int = 255, green: Int = 255, blue: Int = 255, alpha: Double = 1)
enum UiDraw {
  case Black(rect: Rect)
  case Fill(rect: Rect, color: UiColor)
  case Image(quad: GlyphQuad, color: UiColor = UiColor(), flipX: Boolean = false, flipY: Boolean = false)
}

enum SceneAction { case Pause, Resume, Quit, Replay, Next }

object ScenePresentation {
  // Match Level.m's current painting titles in both the HUD and the results.
  private val levelNames = Vector("DRYDOCK AT LIVERPOOL", "THE CREATION", "IN THE OMNIBUS",
    "LAS MENINAS", "THE SCAPEGOAT", "PEARL EARRING")
  def levelName(number: Int): String = levelNames(number - 1)
}

/** A presentation clock, not another gameplay clock. A won Snapshot stops
  * advancing; the spout/interstitial/blink must nevertheless keep presenting.
  * Host suspension supplies zero elapsed time rather than catching up later.
  */
final class ScenePresentation {
  private val character = new CharacterPresentation()
  private var last: Option[(Int, Long, Status)] = None
  private var statusElapsed = 0.0
  private var entryElapsed = 0.0
  private var best = Map.empty[(Int, BubbleMode), Long] // Original per-mode scores, session-only.
  private var resultsPress = false
  private var sceneLevelsAchieved = 1
  private var winLevelsAchieved = 1

  def reset(levelsAchieved: Int = 1): Unit = {
    character.reset()
    last = None
    statusElapsed = 0
    entryElapsed = 0
    sceneLevelsAchieved = levelsAchieved
    winLevelsAchieved = levelsAchieved
    cancelPointer()
  }
  /** WhaleyWinScreen chooses its bubble before it unlocks the next painting. */
  def recordWinProgress(levelsAchieved: Int): Unit = winLevelsAchieved = levelsAchieved

  def elapsed: Double = statusElapsed
  def showingResults(state: Snapshot): Boolean = state.status == Status.Won && statusElapsed >= 0.5
  def scoresVisible: Boolean = ((math.max(0, statusElapsed - 0.5) / 0.5).toLong % 2) == 0

  private def frameIndex(count: Int, seconds: Double, interval: Double): Int =
    ((math.max(0, seconds) / interval + 1e-9).toLong % count).toInt

  private def frameAt(frames: Vector[Rect], seconds: Double, interval: Double): Rect =
    frames(frameIndex(frames.length, seconds, interval))

  /** HUD icons retain the original three-frame animation, independent of the
    * score clock restored from a coin checkpoint.
    */
  def whaleFrame: (String, Rect) = {
    val completed = sceneLevelsAchieved > LevelData.all.length
    val frames = if (completed) SpriteData.playerWinFrames else SpriteData.playerFrames
    (if (completed) "player-win.png" else "player.png", frameAt(frames, entryElapsed, 0.25))
  }
  def observeTick(level: Level, before: Snapshot, after: Snapshot,
                  cues: Vector[SoundCue]): Unit = character.observeTick(level, before, after, cues)

  def characterFrame(state: Snapshot): CharacterFrame = character.frame(state)

  /** Both scene styles use the original character, changing only its face.
    * The renderer retains the gameplay facing/death flips and 32-pixel bounds.
    */
  def worldWhaleFrame(state: Snapshot): (String, Rect) = {
    val completed = sceneLevelsAchieved > LevelData.all.length
    val frames = if (completed) SpriteData.playerWinFrames else SpriteData.playerFrames
    val bank = frameIndex(frames.length, entryElapsed, 0.25)
    val face = characterFrame(state).source
    (if (completed) "whaley-win-expressions.png" else "whaley-expressions.png",
      face.copy(x = face.x + bank * 288))
  }

  def coinFrame: Rect = frameAt(SpriteData.coinFrames, entryElapsed, 0.1)

  def advance(level: Int, state: Snapshot, seconds: Double, paused: Boolean,
              mode: BubbleMode = BubbleMode.Normal): Unit = {
    val delta = if (paused || !seconds.isFinite || seconds <= 0) 0.0 else math.min(seconds, 0.25)
    val restart = last.forall { case (number, tick, _) => number != level || state.tick < tick }
    val changed = last.forall(_._3 != state.status)
    if (restart) entryElapsed = 0 else entryElapsed += delta
    if (restart || changed) statusElapsed = 0 else statusElapsed += delta
    if (restart || changed) cancelPointer()
    val key = (level, mode)
    if (state.status == Status.Won) best = best.updated(key, math.max(best.getOrElse(key, 0L), score(state)))
    last = Some((level, state.tick, state.status))
  }

  /** The cocos2d HUD acts on press; results act on a fresh press/release pair.
    * Points are in top-left surface coordinates, independent of the camera.
    */
  def pointerDown(state: Snapshot, paused: Boolean, point: Vec2,
                  width: Double, height: Double): Option[SceneAction] = {
    cancelPointer()
    if (!inside(point, width, height)) None
    else if (showingResults(state)) { resultsPress = true; None }
    else if (state.status == Status.Playing && point.y < 32) {
      if (!paused) Some(SceneAction.Pause)
      else if (point.x < 24 + PresentationData.gameFont.advance("QUIT")) Some(SceneAction.Quit)
      else Some(SceneAction.Resume)
    } else None
  }

  def pointerUp(state: Snapshot, point: Vec2, width: Double, height: Double): Option[SceneAction] = {
    val next = resultsPress && showingResults(state) && inside(point, width, height)
    cancelPointer()
    Option.when(next)(SceneAction.Next)
  }

  def cancelPointer(): Unit = resultsPress = false

  /** Hosts replace/reset the scene when taking an automatic action. The half
    * second spout precedes the original three-second results delay.
    */
  def automaticAction(state: Snapshot): Option[SceneAction] = state.status match {
    case Status.Dead if statusElapsed >= 2.0 => Some(SceneAction.Replay)
    case Status.Won if statusElapsed >= 3.5 => Some(SceneAction.Next)
    case _ => None
  }

  private def inside(point: Vec2, width: Double, height: Double): Boolean =
    point.finite && point.x >= 0 && point.y >= 0 && point.x < width && point.y < height

  def score(state: Snapshot): Long =
    state.collected.toLong * 100L + 5000L / (state.bubblesUsed.toLong + 1L) +
      (30000.0 / (state.time + 0.1)).toLong

  def spout(state: Snapshot): Option[(AtlasFrame, Rect)] = {
    if (state.status != Status.Won || showingResults(state)) None
    else {
      val frames = PresentationData.spout
      val frame = frames((statusElapsed / 0.1).toInt % frames.size)
      Some(frame -> frame.atBottomLeft(state.player.position + Vec2(0, 31)))
    }
  }

  /** WhaleyScene puts the painting beside the camera-moving game layer. It
    * fills the screen at opacity 190 in both foreground styles, not the map.
    */
  def backdrop(level: Level, width: Double, height: Double): Vector[UiDraw] = {
    val art = PresentationData.levels(level.number).painting
    Vector(UiDraw.Image(GlyphQuad(art.page, art.source, Rect(0, 0, width, height)),
      UiColor(alpha = 190.0 / 255)))
  }

  def commands(level: Level, state: Snapshot, paused: Boolean, width: Double, height: Double,
               mode: BubbleMode = BubbleMode.Normal): Vector[UiDraw] = {
    val out = Vector.newBuilder[UiDraw]
    val font = PresentationData.gameFont
    def text(value: String, x: Double, y: Double, alignment: TextAlignment = TextAlignment.Left): Unit =
      font.layout(value, x, y, alignment).foreach(q => out += UiDraw.Image(q))
    def black(rect: Rect): Unit = out += UiDraw.Black(rect)

    // The result's Collectible is a new node, created after the spout delay.
    val currentCoinFrame = if (showingResults(state)) frameAt(SpriteData.coinFrames, statusElapsed - 0.5, 0.1)
      else coinFrame
    def coin(x: Double, top: Double): Unit =
      out += UiDraw.Image(GlyphQuad("coin.png", currentCoinFrame, Rect(x, top, 16, 16)))

    if (showingResults(state)) {
      black(Rect(0, 0, width, height))
      // WhaleyWinScreen's 16-pixel rows and padding are intentional: the two
      // counters are identified by their icons, with no added word labels.
      text(ScenePresentation.levelName(level.number), width / 2, height / 2 - 88, TextAlignment.Center)
      text(s"      x ${state.collected}", 64, height / 2 - 56)
      text(s"      x ${state.bubblesUsed}", 64, height / 2 - 40)
      text(s"   TIME ${state.time.toInt}", 64, height / 2 - 24)
      text("  SCORE ", 64, height / 2 + 8)
      text("     HI ", 64, height / 2 + 24)
      if (scoresVisible) {
        text(score(state).toString, 192, height / 2 + 8)
        text(best.getOrElse((level.number, mode), score(state)).toString, 192, height / 2 + 24)
      }
      coin(128, height / 2 - 56)
      val bubblePage = if (winLevelsAchieved >= LevelData.all.length) "infinite_bubble.png" else "bubble01.png"
      val bubbleColor = if (winLevelsAchieved > LevelData.all.length) UiColor()
        else if (mode == BubbleMode.ExtraBounce) UiColor(211, 24, 149) else UiColor(153, 153, 255)
      out += UiDraw.Image(GlyphQuad(bubblePage, Rect(0, 0, 128, 128),
        Rect(128, height / 2 - 40, 16, 16)), bubbleColor)
    } else {
      // Exactly the original top 32 logical pixels, including pause controls.
      black(Rect(0, 0, width, 32))
      if (paused) {
        val (page, frame) = whaleFrame
        out += UiDraw.Image(GlyphQuad(page, frame, Rect(4, 8, 16, 16)), UiColor(255, 0, 0), flipY = true)
        text("QUIT", 24, 8)
        text("CONTINUE", width, 8, TextAlignment.Right)
        out += UiDraw.Image(GlyphQuad(page, frame,
          Rect(width - font.advance("CONTINUE") - 20, 8, 16, 16)))
      } else {
        // The source warns when a held bubble intersects any flame, even one
        // in its dim phase; it leaves an existing coin readout in place.
        val warning = state.bubbles.exists(b => b.selected && state.hazards.exists { h =>
          val d = b.position - h.position
          d.x * d.x + d.y * d.y <= (b.radius + 12) * (b.radius + 12)
        })
        if (state.collected > 0) {
          coin(0, 8)
          text(s"x${state.collected}", 16, 8)
        } else if (!warning) text(ScenePresentation.levelName(level.number), width / 2, 8, TextAlignment.Center)
        if (warning) text("!", width / 2, 8, TextAlignment.Center)
      }
    }

    // These were scene siblings above both the game and its HUD/results.
    // Level three has neither overlay. The short horizontal maps have the
    // source's black 24-pixel bottom strip above their full-height painting.
    val visual = PresentationData.levels(level.number)
    visual.scanlines.foreach { art =>
      out += UiDraw.Image(GlyphQuad(art.page, art.source, Rect(0, 0, width, height)),
        UiColor(alpha = 128.0 / 255))
    }
    if (level.number >= 4) out += UiDraw.Fill(Rect(0, 0, width, height), UiColor(102, 102, 255, 64.0 / 255))
    if (level.number == 2 || level.number == 5) black(Rect(0, height - 24, width, 24))

    // Binary tile reveal: no intermediate alpha, and no global fade.
    if (entryElapsed < 0.5 && state.status == Status.Playing) {
      val columns = math.ceil(width / 32).toInt
      val rows = math.ceil(height / 32).toInt
      for (row <- 0 until rows; column <- 0 until columns) {
        val offAt = (((row * 7 + column * 13) % 43) + 1) * 0.5 / 43
        if (entryElapsed < offAt) black(Rect(column * 32, row * 32,
          math.min(32, width - column * 32), math.min(32, height - row * 32)))
      }
    }
    out.result()
  }
}
