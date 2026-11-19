package whaley.nativeapp

import java.io.File
import s2d.core.{Drawing, Window}
import s2d.shapes.{BasicRenderer, Basics}
import s2d.textures.Textures
import s2d.types.{BlendMode, Color, Rectangle, Texture2D, TextureFilter, TextureWrap, Vector2}
import whaley.core.*

private object Renderer {
  // Input and drawing share the same fitted play surface; there is no separate
  // native header shifting the game/HUD relative to the Canvas implementation.
  val headerHeight: Double = 0
  val footerHeight: Double = 0

  def viewport(level: Level, state: Snapshot): Viewport =
    Viewport.forGame(level, state, math.max(1, Window.width).toDouble,
      math.max(1, Window.height).toDouble)

  def galleryViewport: Viewport =
    Viewport(math.max(1, Window.width).toDouble, math.max(1, Window.height).toDouble, 0)

  def load(directory: File): Renderer = {
    var loaded = Map.empty[String, Texture2D]
    try {
      Assets.required.foreach { name =>
        val path = new File(directory, name).getAbsolutePath
        val texture = Textures.load(path).getOrElse(
          throw new IllegalStateException(s"S2D could not decode/upload $path"))
        loaded += name -> texture
        Textures.setFilter(texture, TextureFilter.Point)
        Textures.setWrap(texture, TextureWrap.Clamp)
      }
      new Renderer(loaded)
    } catch {
      case error: Throwable => loaded.values.foreach(Textures.unload); throw error
    }
  }
}

/** Gameplay remains in Game; shared presentation produces all text and masks. */
private final class Renderer private(textures: Map[String, Texture2D]) {
  private val presentation = new ScenePresentation()
  private val jumpTrail = new JumpTrail()
  private val flames = new FlameAnimation()
  def close(): Unit = textures.values.foreach(Textures.unload)
  def resetPresentation(levelsAchieved: Int = 1): Unit = {
    presentation.reset(levelsAchieved)
    jumpTrail.reset()
    flames.reset()
  }
  def observeTick(level: Level, before: Snapshot, after: Snapshot, cues: Vector[SoundCue]): Unit = {
    presentation.observeTick(level, before, after, cues)
    jumpTrail.observeTick(level, before, after, cues)
  }
  def recordWinProgress(levelsAchieved: Int): Unit = presentation.recordWinProgress(levelsAchieved)
  def pointerDown(state: Snapshot, paused: Boolean, point: Vec2,
                  width: Double, height: Double): Option[SceneAction] =
    presentation.pointerDown(state, paused, point, width, height)
  def pointerUp(state: Snapshot, point: Vec2, width: Double, height: Double): Option[SceneAction] =
    presentation.pointerUp(state, point, width, height)
  def cancelPointer(): Unit = presentation.cancelPointer()
  def automaticAction(state: Snapshot): Option[SceneAction] = presentation.automaticAction(state)
  def showingResults(state: Snapshot): Boolean = presentation.showingResults(state)

  def drawInvincibilityToggle(invincible: Boolean): Unit = {
    val bounds = InvincibilityToggle.bounds(Window.width.toDouble, Window.height.toDouble)
    val button = Rectangle(bounds.x.toFloat, bounds.y.toFloat, bounds.width.toFloat, bounds.height.toFloat)
    val color = if (invincible) Color(255, 210, 74) else Color(255, 255, 255)
    val background = if (invincible) Color(43, 36, 10, 230) else Color(0, 0, 0, 204)
    Basics.rectangleRounded(button, 0.36f, 6, background)
    Basics.rectangleRoundedOutline(button, 0.36f, 6, if (invincible) color else Color(102, 102, 102))
    val inset = (InvincibilityToggle.size - InvincibilityToggle.iconSize) / 2
    val points = InvincibilityToggle.starPoints.map { point =>
      Vector2((bounds.x + inset + point.x).toFloat, (bounds.y + inset + point.y).toFloat)
    }
    val center = Vector2(bounds.center.x.toFloat, bounds.center.y.toFloat)
    points.indices.foreach { index =>
      val start = points(index)
      val end = points((index + 1) % points.length)
      if (invincible) Basics.triangle(center, start, end, color)
      Basics.lineThick(start, end, 1.8f, color)
    }
    BasicRenderer.flush()
  }

  /** Gallery commands use top-left logical coordinates. S2D's drawPro origin
    * is relative to the destination rectangle, not an absolute pivot. Keep
    * each painting, frame and highlight on the same bottom-left card pivot.
    */
  def drawGallery(gallery: GalleryScene): Unit = {
    val view = Renderer.galleryViewport
    Drawing.clear(Color(0, 0, 0))
    Drawing.beginScissor(math.floor(view.left).toInt, math.floor(view.top).toInt,
      math.ceil(view.viewWidth * view.scale).toInt, math.ceil(view.viewHeight * view.scale).toInt)
    gallery.commands.foreach {
      case GalleryDraw.Image(quad, color, rotation, pivot, additive) =>
        BasicRenderer.flush()
        if (additive) Drawing.beginBlend(BlendMode.Additive)
        val source = quad.source
        val destination = quad.destination
        Textures.drawPro(textures(quad.page),
          Rectangle(source.x.toFloat, source.y.toFloat, source.width.toFloat, source.height.toFloat),
          screenRect(view, destination), galleryOrigin(view, destination, pivot),
          rotation.toFloat, galleryColor(color))
        if (additive) Drawing.endBlend()
      case GalleryDraw.Fill(rect, color, rotation, pivot) =>
        Basics.rectangleRotated(screenRect(view, rect), galleryOrigin(view, rect, pivot),
          rotation.toFloat, galleryColor(color))
        // Shapes batch, textures draw immediately: preserve command order.
        BasicRenderer.flush()
    }
    Drawing.endScissor()
  }

  private def galleryOrigin(view: Viewport, rect: Rect, pivot: Vec2): Vector2 =
    Vector2(((pivot.x - rect.x) * view.scale).toFloat, ((pivot.y - rect.y) * view.scale).toFloat)

  private def galleryColor(color: GalleryColor): Color =
    Color(color.red, color.green, color.blue, math.round(math.max(0, math.min(1, color.alpha)) * 255).toInt)

  def draw(level: Level, state: Snapshot, paused: Boolean, seconds: Double = 1.0 / 60,
           mode: BubbleMode = BubbleMode.Normal): Unit = {
    val view = Renderer.viewport(level, state)
    presentation.advance(level.number, state, seconds, paused, mode)
    flames.advance(seconds, paused || state.status != Status.Playing)
    Drawing.clear(Color(0, 0, 0))
    Drawing.beginScissor(math.floor(view.left).toInt, math.floor(view.top).toInt,
      math.ceil(view.viewWidth * view.scale).toInt, math.ceil(view.viewHeight * view.scale).toInt)
    drawUiCommands(view, presentation.backdrop(level, view.viewWidth, view.viewHeight))
    jumpTrail.marks.foreach { mark =>
      val center = view.toScreen(mark.center)
      val width = mark.width * view.scale
      val height = mark.height * view.scale
      Basics.rectangle(Rectangle((center.x - width / 2).toFloat, (center.y - height / 2).toFloat,
        width.toFloat, height.toFloat), uiColor(mark.color))
    }
    BasicRenderer.flush()

    val visual = PresentationData.levels(level.number)
    visual.visible(view).foreach { case (art, center) =>
      sprite(view, art.page, center, visual.tileSize, visual.tileSize, Some(art.source))
    }
    val bubbleColor = mode match {
      case BubbleMode.Normal => Color(153, 153, 255)
      case BubbleMode.ExtraBounce => Color(211, 24, 149)
      case BubbleMode.Infinite => Color.White
    }
    state.bubbles.foreach { bubble =>
      sprite(view, if (mode == BubbleMode.Infinite) "infinite_bubble.png" else "bubble01.png",
        bubble.position, bubble.radius * 2, bubble.radius * 2, tint = bubbleColor)
    }
    val coinFrame = presentation.coinFrame
    state.coins.foreach(coin => sprite(view, "coin.png", coin.position, 32, 32, Some(coinFrame)))
    state.hazards.zipWithIndex.foreach { case (hazard, index) =>
      val pose = if (PresentationData.whalelandArt) flames.pose(index) else FlamePose()
      sprite(view, if (level.number >= 4) "flame02.png" else "flame01.png",
        hazard.position + Vec2(pose.offsetX, 0), 24, 24,
        tint = Color(255, 255, 255, if (hazard.active) 255 else 77), rotation = pose.clockwiseDegrees)
    }
    if (state.status != Status.Won) sprite(view, "goal01.png", state.goal, 32, 32)
    val (playerPage, playerFrame) = presentation.worldWhaleFrame(state)
    val playerColor = if (state.status == Status.Dead) Color(255, 0, 0)
      else if (paused) Color(166, 166, 166) else Color.White
    sprite(view, playerPage,
      state.player.center, 32, 32, Some(playerFrame), state.player.facingLeft,
      playerColor, flipY = state.status == Status.Dead)
    presentation.spout(state).foreach { case (frame, bounds) =>
      sprite(view, "spout.png", bounds.center, bounds.width, bounds.height, Some(frame.source))
    }
    BasicRenderer.flush()

    drawUiCommands(view, presentation.commands(level, state, paused, view.viewWidth, view.viewHeight, mode))
    Drawing.endScissor()
  }

  private def uiColor(color: UiColor): Color =
    Color(color.red, color.green, color.blue, math.round(math.max(0, math.min(1, color.alpha)) * 255).toInt)

  private def drawUiCommands(view: Viewport, commands: Vector[UiDraw]): Unit = {
    commands.foreach {
      case UiDraw.Black(rect) =>
        Basics.rectangle(screenRect(view, rect), Color(0, 0, 0))
        // S2D batches shapes but draws textures immediately. Flush here so a
        // background cannot later cover the text that was drawn on top of it.
        BasicRenderer.flush()
      case UiDraw.Fill(rect, color) =>
        Basics.rectangle(screenRect(view, rect), uiColor(color))
        BasicRenderer.flush()
      case UiDraw.Image(quad, color, flipX, flipY) =>
        BasicRenderer.flush()
        val r = quad.source
        val destination = screenRect(view, quad.destination)
        // S2D exposes horizontal flipping. A half-turn plus its horizontal
        // flip gives the source's vertical flip about the unchanged center.
        val origin = if (flipY) Vector2(destination.width / 2, destination.height / 2) else Vector2(0, 0)
        Textures.drawPro(textures(quad.page),
          Rectangle(r.x.toFloat, r.y.toFloat, r.width.toFloat, r.height.toFloat),
          destination, origin, if (flipY) 180 else 0, uiColor(color), flipX != flipY)
    }
  }

  private def screenRect(view: Viewport, rect: Rect): Rectangle = Rectangle(
    (view.left + rect.x * view.scale).toFloat, (view.top + rect.y * view.scale).toFloat,
    (rect.width * view.scale).toFloat, (rect.height * view.scale).toFloat)

  private def sprite(view: Viewport, name: String, center: Vec2, width: Double, height: Double,
                     source: Option[Rect] = None, flipX: Boolean = false,
                     tint: Color = Color.White, flipY: Boolean = false, rotation: Double = 0): Unit = {
    val radians = rotation * math.Pi / 180
    val halfWidth = (math.abs(math.cos(radians)) * width + math.abs(math.sin(radians)) * height) / 2
    val halfHeight = (math.abs(math.sin(radians)) * width + math.abs(math.cos(radians)) * height) / 2
    if (width <= 0 || height <= 0 || center.y + halfHeight < view.cameraBottom ||
        center.y - halfHeight > view.cameraBottom + view.viewHeight ||
        center.x + halfWidth < view.cameraLeft || center.x - halfWidth > view.cameraLeft + view.viewWidth) return
    val texture = textures(name)
    val frame = source.getOrElse(Rect(0, 0, texture.width, texture.height))
    val crop = Rectangle(frame.x.toFloat, frame.y.toFloat, frame.width.toFloat, frame.height.toFloat)
    val point = view.toScreen(center)
    val w = width * view.scale
    val h = height * view.scale
    Textures.drawPro(texture, crop,
      Rectangle((point.x - w / 2).toFloat, (point.y - h / 2).toFloat, w.toFloat, h.toFloat),
      if (flipY || rotation != 0) Vector2((w / 2).toFloat, (h / 2).toFloat) else Vector2(0, 0),
      (rotation + (if (flipY) 180 else 0)).toFloat, tint, flipX != flipY)
  }
}
