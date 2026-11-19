package whaley.core

final case class GalleryColor(red: Int = 255, green: Int = 255, blue: Int = 255, alpha: Double = 1)

/** Top-left coordinates on the original 320 x 568 surface. Rotations are
  * clockwise degrees around an absolute point on that same surface.
  */
enum GalleryDraw {
  case Image(quad: GlyphQuad, color: GalleryColor, rotation: Double, pivot: Vec2,
             additive: Boolean = false)
  case Fill(rect: Rect, color: GalleryColor, rotation: Double, pivot: Vec2)
}

final case class GalleryStart(level: Int, mode: BubbleMode)

/** Gallery state shared by Native and Canvas. Hosts own window
  * events, scene switching and suspension; they advance this clock only while
  * the gallery is active. No browser or graphics state lives in the model.
  *
  * Layout and normal interactions follow Apps/Whaley2010/Legacy/MainMenu.m.
  * The approved difference is one real magenta reward interpunct: there is no
  * additional decorative bubble when the title changes to Glad Whale.
  */
final class GalleryScene(randomAngle: () => Double = () => GalleryScene.randomFrameAngle()) {
  private val width = 320.0
  private val height = 568.0
  private val levelCount = 6
  private val chalkAlpha = 100.0 / 255.0
  private val animationDuration = 0.1
  private val holdDuration = 1.0
  private var time = 0.0
  private var enteredAt = 0.0
  private var achieved = 1
  private var extraBounce = true
  private var faded = Map.empty[Int, Double]

  private case class Angle(from: Double, target: Double, began: Double) {
    def value: Double = from + (target - from) * fraction(time - began)
  }
  private var angles = Vector.fill(levelCount) {
    val value = nextAngle()
    Angle(value, value, time)
  }

  private enum Gesture {
    case Idle
    case Card(level: Int, inside: Boolean, heldSince: Double)
    case Consumed
  }
  private var gesture: Gesture = Gesture.Idle

  private case class Preview(level: Int, began: Double, closing: Option[(Double, Double)] = None) {
    def alpha: Double = closing match {
      case Some((started, from)) => from * (1 - fraction(time - started))
      case None => fraction(time - began)
    }
  }
  private var preview: Option[Preview] = None

  private case class Dust(origin: Vec2, velocity: Vec2, size: Double, life: Double, born: Double)
  private var dust = Vector.empty[Dust]
  private var burst = 0
  private var sounds = Vector.empty[SoundCue]

  def levelsAchieved: Int = achieved
  def completedGame: Boolean = achieved > levelCount
  def rewardVisible: Boolean = extraBounce
  def previewLevel: Option[Int] = preview.filter(_.closing.isEmpty).map(_.level)
  def gameMode: BubbleMode =
    if (extraBounce) BubbleMode.ExtraBounce
    else if (completedGame) BubbleMode.Infinite
    else BubbleMode.Normal
  def levelUnlocked(level: Int): Boolean = level >= 1 && level <= levelCount && level <= achieved

  def restoreProgress(levels: Int, reward: Boolean): Unit = {
    achieved = math.max(1, math.min(levelCount + 1, levels))
    extraBounce = reward
    enter()
  }

  def drainSounds(): Vector[SoundCue] = {
    val result = sounds
    sounds = Vector.empty
    result
  }

  /** Return from gameplay without discarding progress, chalk or the puzzle. */
  def enter(): Unit = {
    cancelPointer()
    preview = None
    dust = Vector.empty
    sounds = Vector.empty
    angles = angles.map(a => Angle(a.target, a.target, time))
    faded = faded.map { case (index, _) => index -> (time - animationDuration) }
    enteredAt = time
  }

  def completeLevel(level: Int): Unit = {
    require(level >= 1 && level <= levelCount, s"Unknown gallery level $level")
    if (level == levelCount && !completedGame) {
      // Only the changed letters are restored: Gray -> Glad.
      faded = faded.removed(1).removed(3)
      extraBounce = false
    }
    achieved = math.max(achieved, level + 1)
  }

  def advance(seconds: Double): Unit = {
    if (!seconds.isFinite || seconds <= 0 || !(time + seconds).isFinite) return
    time += seconds
    gesture match {
      case Gesture.Card(level, true, since) if time - since + 1e-10 >= holdDuration =>
        preview = Some(Preview(level, since + holdDuration))
        gesture = Gesture.Consumed
      case _ => ()
    }
    preview = preview.filterNot(p => p.closing.exists { case (started, _) =>
      time - started + 1e-10 >= animationDuration
    })
    dust = dust.filter(p => time - p.born < p.life)
  }

  def pointerDown(point: Vec2): Unit = {
    if (gesture != Gesture.Idle || !onSurface(point)) return
    preview match {
      case Some(current) =>
        if (current.closing.isEmpty) preview = Some(current.copy(closing = Some(time -> current.alpha)))
        gesture = Gesture.Consumed // Dismissal cannot also select the painting underneath.
      case None =>
        levelAt(point) match {
          case Some(level) => gesture = Gesture.Card(level, inside = true, heldSince = time)
          case None =>
            gesture = Gesture.Consumed
            val center = rewardCenter
            val distanceSquared = math.pow(point.x - center.x, 2) + math.pow(point.y - center.y, 2)
            if (extraBounce && distanceSquared < 28.0 * 28.0) extraBounce = false
            else {
              sounds :+= SoundCue.Knock
              rotateFrames()
              titleQuads.foreach { case (index, quad) =>
                if (!faded.contains(index) && titleAlpha(index) >= 1 - 1e-10 && contains(quad.destination, point)) {
                  faded = faded.updated(index, time)
                  emitDust(point)
                }
              }
            }
        }
    }
  }

  def pointerMove(point: Vec2): Unit = gesture match {
    case Gesture.Card(level, inside, since) =>
      val nowInside = onSurface(point) && levelAt(point).contains(level)
      gesture = Gesture.Card(level, nowInside, if (inside && nowInside) since else time)
    case _ => ()
  }

  def pointerUp(point: Vec2): Option[GalleryStart] = {
    val result = gesture match {
      case Gesture.Card(level, _, _) if onSurface(point) && levelAt(point).contains(level) =>
        Some(GalleryStart(level, gameMode))
      case _ => None
    }
    cancelPointer()
    result
  }

  /** Releasing capture after a long press must leave its preview open. */
  def cancelPointer(): Unit = gesture = Gesture.Idle

  def commands: Vector[GalleryDraw] = {
    val output = Vector.newBuilder[GalleryDraw]
    def image(file: String, destination: Rect, color: GalleryColor = GalleryColor(),
              rotation: Double = 0, pivot: Vec2 = Vec2(0, 0), additive: Boolean = false): Unit = {
      val size = GalleryData.images(file)
      output += GalleryDraw.Image(GlyphQuad(file, Rect(0, 0, size.x, size.y), destination),
        color, rotation, pivot, additive)
    }

    image("Default-568h@2x.png", Rect(0, 0, width, height))
    titleQuads.foreach { case (index, quad) =>
      output += GalleryDraw.Image(quad, GalleryColor(alpha = titleAlpha(index)), 0, Vec2(0, 0))
    }
    (1 to levelCount).foreach { level =>
      val rect = frameRect(level)
      val pivot = Vec2(rect.x, rect.y + rect.height)
      val angle = angles(level - 1).value
      if (levelUnlocked(level)) {
        // Original 200 x 300 painting inside a 344 x 514 frame, then scale .2.
        val painting = Rect(rect.center.x - 20, rect.center.y - 30, 40, 60)
        image(GalleryData.paintings(level), painting, rotation = angle, pivot = pivot)
      }
      image("frame.png", rect, rotation = angle, pivot = pivot)
      gesture match {
        case Gesture.Card(selected, true, _) if selected == level =>
          output += GalleryDraw.Fill(rect, GalleryColor(0, 0, 0, 100.0 / 255.0), angle, pivot)
        case _ => ()
      }
    }
    if (extraBounce) {
      val center = rewardCenter
      image("bubble01.png", Rect(center.x - 8, center.y - 8, 16, 16),
        GalleryColor(211, 24, 149, 150.0 / 255.0))
    }
    dust.foreach { particle =>
      val age = time - particle.born
      val progress = math.max(0, math.min(1, age / particle.life))
      val center = particle.origin + particle.velocity * age
      val size = particle.size + (7 - particle.size) * progress
      image("dust.png", Rect(center.x - size / 2, center.y - size / 2, size, size),
        GalleryColor(alpha = 1 - progress), additive = true)
    }
    preview.foreach { current =>
      image(GalleryData.previews(current.level), Rect(0, 0, width, height),
        GalleryColor(alpha = current.alpha))
    }
    output.result()
  }

  private def font: BitmapFont = if (completedGame) GalleryData.gladFont else GalleryData.grayFont
  private def title: String = if (completedGame) GameInfo.completedName else GameInfo.name
  private def titleQuads: Vector[(Int, GlyphQuad)] = {
    val text = title
    val bitmap = font
    val indices = text.indices.filter { index =>
      val glyph = bitmap.glyphs(text.charAt(index).toInt)
      glyph.source.width > 0 && glyph.source.height > 0
    }.toVector
    indices.zip(bitmap.layout(text, 24, 20))
  }
  private def titleAlpha(index: Int): Double = {
    val chalk = faded.get(index).map(start => 1 + (chalkAlpha - 1) * fraction(time - start)).getOrElse(1.0)
    chalk * fraction(time - enteredAt)
  }
  private def rewardCenter: Vec2 = Vec2(width / 2 - 19, 20 + font.lineHeight - 65)
  private def frameRect(level: Int): Rect = {
    val size = GalleryData.images("frame.png") * 0.2
    val column = (level - 1) % 3
    val row = (level - 1) / 3
    val startX = (width - (size.x + 20) * 3) / 2 + 10
    Rect(startX + column * (size.x + 20), 20 + font.lineHeight + 15 + row * (size.y + 15), size.x, size.y)
  }
  private def levelAt(point: Vec2): Option[Int] =
    (1 to levelCount).find(level => levelUnlocked(level) && contains(frameRect(level), point))
  private def contains(rect: Rect, point: Vec2): Boolean =
    point.finite && point.x >= rect.x && point.x < rect.x + rect.width &&
      point.y >= rect.y && point.y < rect.y + rect.height
  private def onSurface(point: Vec2): Boolean = contains(Rect(0, 0, width, height), point)
  private def fraction(elapsed: Double): Double = math.max(0, math.min(1, elapsed / animationDuration))
  private def nextAngle(): Double = {
    val angle = randomAngle()
    require(angle.isFinite && math.abs(angle) <= 3, "Gallery angles must be finite and between -3 and 3 degrees")
    angle
  }
  private def rotateFrames(): Unit = {
    angles = angles.map { current =>
      val target = if (current.target != 0) 0.0 else nextAngle()
      Angle(current.value, target, time)
    }
    if (!completedGame && angles.forall(a => math.abs(a.target) <= 0.5)) extraBounce = true
  }
  private def emitDust(point: Vec2): Unit = {
    // Fixed, bounded emission avoids coupling cosmetic randomness to the puzzle.
    // Original chalk uses dust.png, 4..6-unit starts, 7-unit ends and additive white.
    val particles = Vector.tabulate(32) { index =>
      val seed = index + burst * 7
      val angle = (seed % 32) * math.Pi * 2 / 32
      val speed = 20.0 + (seed % 5) * 8
      Dust(point, Vec2(math.cos(angle) * speed, math.sin(angle) * speed),
        4.0 + seed % 3, 0.04 + (seed % 9) * 0.02, time)
    }
    burst = (burst + 1) % 32
    dust = (dust ++ particles).takeRight(250)
  }
}

object GalleryScene {
  private def randomFrameAngle(): Double =
    if (scala.util.Random.nextBoolean()) 0.0
    else (scala.util.Random.nextInt(3) + 1).toDouble * (if (scala.util.Random.nextBoolean()) 1 else -1)
}
