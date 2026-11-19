package whaley.web

import org.scalajs.dom
import org.scalajs.dom.html
import scala.concurrent.{Future, Promise}
import scala.scalajs.js
import scala.scalajs.concurrent.JSExecutionContext.Implicits.queue
import scala.util.{Failure, Success}
import whaley.core.*

/** Browser input, durable storage and drawing; original scene rules are shared. */
object Main {
  def main(args: Array[String]): Unit = {
    dom.document.title = GameInfo.name
    try new CanvasGame().start()
    catch {
      case error: Throwable =>
        val panel = dom.document.getElementById("error").asInstanceOf[html.Element]
        dom.document.getElementById("loading").setAttribute("hidden", "")
        panel.removeAttribute("hidden")
        panel.textContent = s"Whaley could not start: ${error.getMessage}"
    }
  }
}

private final class CanvasGame {
  private def element[A <: dom.Element](id: String): A =
    Option(dom.document.getElementById(id)).getOrElse(
      throw new IllegalStateException(s"Missing page element: $id")
    ).asInstanceOf[A]

  private val canvas = element[html.Canvas]("game")
  private val ctx = Option(canvas.getContext("2d")).getOrElse(
    throw new IllegalStateException("Canvas 2D is not available in this browser.")
  ).asInstanceOf[dom.CanvasRenderingContext2D]
  private val invincibilityButton = element[html.Button]("invincibility")
  private val loading = element[html.Element]("loading")
  private val errorPanel = element[html.Element]("error")
  private val statusLabel = element[html.Element]("status")
  private val clock = new FixedStepClock()
  private val presentation = new ScenePresentation()
  private val jumpTrail = new JumpTrail()
  private val flames = new FlameAnimation()
  private val reducedMotion = dom.window.matchMedia("(prefers-reduced-motion: reduce)")
  private val gallery = new GalleryScene()
  private val audio = Audio.open("assets/")
  private var progress = ProgressStorage.load()
  gallery.restoreProgress(progress.levelsAchieved, progress.rewardVisible)
  private var game = new Game(LevelData.all.head)
  game.setInvincible(progress.invincible)
  private var inGallery = true
  private var recordedCompletion = false
  private var textures = Map.empty[String, html.Image]
  private var tintedTextures = Map.empty[(String, Int, Int, Int), html.Canvas]
  private var viewport = Viewport(320, 568, 0)
  private var pointer: Option[Double] = None
  private var pointerIsResults = false
  private var lastWorld = Vec2(0, 0)
  private var previousTime: Option[Double] = None
  private var cssWidth = 320.0
  private var cssHeight = 568.0
  private var dpr = 1.0
  private var paused = false
  private var ready = false
  private var failed = false
  private var suspended = false
  private var animationID: Option[Int] = None

  def start(): Unit = {
    element[dom.Element]("invincibility-star").setAttribute("points",
      InvincibilityToggle.starPoints.map(point => s"${point.x},${point.y}").mkString(" "))
    installInput()
    val files = PresentationData.requiredImages
    Future.sequence(files.map(loadImage)).onComplete {
      case Success(images) =>
        textures = files.zip(images).toMap
        ready = true
        loading.setAttribute("hidden", "")
        invincibilityButton.disabled = false
        syncMusic()
        updateAccessibility()
        scheduleFrame()
      case Failure(error) => showError(error)
    }
  }

  private def loadImage(name: String): Future[html.Image] = {
    val result = Promise[html.Image]()
    val image = dom.document.createElement("img").asInstanceOf[html.Image]
    image.onload = (_: dom.Event) => { result.trySuccess(image); () }
    image.addEventListener("error", (_: dom.Event) => {
      result.tryFailure(new IllegalStateException(s"Could not load assets/$name."))
      ()
    })
    image.src = s"assets/$name"
    result.future
  }

  private def showError(error: Throwable): Unit = {
    failed = true
    cancelGesture()
    audio.close()
    stopFrame()
    loading.setAttribute("hidden", "")
    errorPanel.removeAttribute("hidden")
    errorPanel.textContent = Option(error.getMessage).getOrElse(error.toString)
    invincibilityButton.disabled = true
    dom.console.error(error.toString)
  }

  private def installInput(): Unit = {
    canvas.addEventListener("pointerdown", (raw: dom.Event) => {
      val event = raw.asInstanceOf[dom.PointerEvent]
      if (ready && !failed && !suspended && !dom.document.hidden && pointer.isEmpty &&
          event.isPrimary && event.button == 0) {
        audio.unlock()
        logicalPoint(event).foreach { point =>
          event.preventDefault()
          canvas.focus()
          if (inGallery) {
            capture(event)
            gallery.pointerDown(point)
            gallery.drainSounds().foreach(audio.play)
            saveGalleryProgress()
          } else {
            presentation.pointerDown(game.snapshot, paused, point, 320, 568) match {
              case Some(action) => perform(action)
              case None if presentation.showingResults(game.snapshot) =>
                capture(event)
                pointerIsResults = true
              case None if !paused && game.snapshot.status == Status.Playing =>
                capture(event)
                lastWorld = toWorld(point)
                game.pointerDown(lastWorld)
              case _ => ()
            }
          }
        }
      }
    })
    canvas.addEventListener("pointermove", (raw: dom.Event) => {
      val event = raw.asInstanceOf[dom.PointerEvent]
      if (pointer.contains(event.pointerId.toDouble) && !pointerIsResults) {
        event.preventDefault()
        logicalPoint(event) match {
          case Some(point) if inGallery => gallery.pointerMove(point)
          case Some(point) => lastWorld = toWorld(point); game.pointerMove(lastWorld)
          case None if inGallery => gallery.pointerMove(Vec2(-1, -1))
          case None => cancelGesture()
        }
      }
    })
    canvas.addEventListener("pointerup", (raw: dom.Event) => {
      val event = raw.asInstanceOf[dom.PointerEvent]
      if (pointer.contains(event.pointerId.toDouble)) {
        event.preventDefault()
        if (inGallery) {
          val request = logicalPoint(event).flatMap(gallery.pointerUp)
          if (request.isEmpty) gallery.cancelPointer()
          releaseCapture()
          request.foreach(start => startLevel(start.level, start.mode))
        } else if (pointerIsResults) {
          val action = logicalPoint(event).flatMap(point => presentation.pointerUp(game.snapshot, point, 320, 568))
          releaseCapture()
          if (action.isEmpty) presentation.cancelPointer()
          action.foreach(perform)
        } else {
          game.pointerUp(logicalPoint(event).map(toWorld).getOrElse(lastWorld))
          releaseCapture()
        }
      }
    })
    canvas.addEventListener("pointercancel", (raw: dom.Event) => {
      if (pointer.contains(raw.asInstanceOf[dom.PointerEvent].pointerId.toDouble)) cancelGesture()
    })
    canvas.addEventListener("lostpointercapture", (raw: dom.Event) => {
      if (pointer.contains(raw.asInstanceOf[dom.PointerEvent].pointerId.toDouble)) cancelGesture()
    })
    canvas.addEventListener("contextmenu", (event: dom.Event) => event.preventDefault())
    invincibilityButton.addEventListener("click", (_: dom.Event) => {
      if (ready && !failed && !suspended && !dom.document.hidden) {
        audio.unlock()
        toggleInvincibility()
      }
    })
    dom.window.addEventListener("keydown", (raw: dom.Event) => {
      val event = raw.asInstanceOf[dom.KeyboardEvent]
      val tag = Option(event.target).collect { case element: dom.Element => element.tagName.toLowerCase }.getOrElse("")
      if (ready && !failed && !event.repeat && !event.altKey && !event.ctrlKey && !event.metaKey &&
          tag != "input" && tag != "textarea" && tag != "select") {
        audio.unlock()
        event.key.toLowerCase match {
          case "f1" | "i" => event.preventDefault(); toggleInvincibility()
          case "r" if !inGallery => event.preventDefault(); restart()
          case " " if !inGallery && tag != "button" && game.snapshot.status == Status.Playing =>
            event.preventDefault(); setPaused(!paused)
          case "m" | "escape" if !inGallery => event.preventDefault(); perform(SceneAction.Quit)
          case "enter" if inGallery && tag != "button" =>
            event.preventDefault(); startLevel(math.min(6, gallery.levelsAchieved), gallery.gameMode)
          case value if value.length == 1 && value.head >= '1' && value.head <= '6' =>
            event.preventDefault(); startLevel(value.toInt, BubbleMode.Normal)
          case _ => ()
        }
      }
    })
    dom.window.addEventListener("blur", (_: dom.Event) => {
      if (ready) setPaused(true, sound = false)
      audio.setSuspended(true)
    })
    dom.window.addEventListener("focus", (_: dom.Event) => {
      resetClock()
      updateAudioSuspension()
    })
    dom.document.addEventListener("visibilitychange", (_: dom.Event) => {
      if (dom.document.hidden && ready) setPaused(true, sound = false)
      resetClock()
      updateAudioSuspension()
    })
    dom.window.addEventListener("resize", (_: dom.Event) => { cancelGesture(); resetClock() })
    dom.window.addEventListener("pagehide", (_: dom.Event) => {
      suspended = true
      cancelGesture()
      stopFrame()
      resetClock()
      audio.setSuspended(true)
    })
    dom.window.addEventListener("pageshow", (_: dom.Event) => {
      suspended = false
      resetClock()
      updateAudioSuspension()
      if (ready) { setPaused(true, sound = false); scheduleFrame() }
    })
  }

  private def logicalPoint(event: dom.PointerEvent): Option[Vec2] = {
    val rect = canvas.getBoundingClientRect()
    viewport = currentViewport(math.max(1, rect.width), math.max(1, rect.height))
    val x = (event.clientX - rect.left - viewport.left) / viewport.scale
    val y = (event.clientY - rect.top - viewport.top) / viewport.scale
    if (x >= 0 && x < 320 && y >= 0 && y < 568) Some(Vec2(x, y)) else None
  }
  private def toWorld(point: Vec2): Vec2 =
    Vec2(viewport.cameraLeft + point.x, viewport.cameraBottom + 568 - point.y)
  private def currentViewport(width: Double, height: Double): Viewport =
    if (inGallery) Viewport(width, height, 0)
    else Viewport.forGame(game.level, game.snapshot, width, height)
  private def capture(event: dom.PointerEvent): Unit = {
    pointer = Some(event.pointerId.toDouble)
    try canvas.asInstanceOf[js.Dynamic].setPointerCapture(event.pointerId)
    catch { case _: Throwable => () }
  }
  private def releaseCapture(): Unit = {
    val old = pointer
    pointer = None
    pointerIsResults = false
    old.foreach { id =>
      try canvas.asInstanceOf[js.Dynamic].releasePointerCapture(id)
      catch { case _: Throwable => () }
    }
  }
  private def cancelGesture(): Unit = {
    game.cancelPointer()
    gallery.cancelPointer()
    presentation.cancelPointer()
    releaseCapture()
  }
  private def resetClock(): Unit = { previousTime = None; clock.reset() }
  private def save(next: PlayerProgress): Unit = if (next != progress) {
    progress = next
    ProgressStorage.save(progress)
  }
  private def saveGalleryProgress(): Unit = save(progress.copy(
    levelsAchieved = gallery.levelsAchieved, rewardVisible = gallery.rewardVisible))
  private def saveCheckpoint(): Unit = game.checkpoint.foreach { checkpoint =>
    val achieved = math.max(gallery.levelsAchieved, checkpoint.levelNumber)
    if (achieved != gallery.levelsAchieved) gallery.restoreProgress(achieved, gallery.rewardVisible)
    save(progress.copy(levelsAchieved = achieved, rewardVisible = gallery.rewardVisible,
      checkpoints = progress.checkpoints.updated(checkpoint.levelNumber, checkpoint)))
  }
  private def clearCheckpoint(): Unit =
    save(progress.copy(checkpoints = progress.checkpoints.removed(game.level.number)))
  private def syncMusic(): Unit =
    audio.setMusic(if (inGallery) Some(if (gallery.completedGame) MenuMusic.Glad else MenuMusic.Gray) else None)
  private def updateAudioSuspension(): Unit =
    audio.setSuspended(suspended || dom.document.hidden || !dom.document.hasFocus())

  private def setPaused(value: Boolean, sound: Boolean = true): Unit = {
    val next = value && !inGallery && game.snapshot.status == Status.Playing
    if (next && !paused) {
      audio.stopEffects()
      if (sound && game.snapshot.status == Status.Playing) audio.play(SoundCue.Pause)
    }
    paused = next
    cancelGesture()
    resetClock()
    updateAccessibility()
  }
  private def toggleInvincibility(): Unit = {
    cancelGesture()
    save(progress.copy(invincible = !progress.invincible))
    game.setInvincible(progress.invincible)
    updateAccessibility()
  }
  private def restart(): Unit = {
    if (inGallery) return
    cancelGesture()
    audio.stopEffects()
    game.restart()
    clearCheckpoint()
    presentation.reset(gallery.levelsAchieved)
    jumpTrail.reset()
    flames.reset()
    recordedCompletion = false
    paused = false
    resetClock()
    updateAccessibility()
  }
  private def replay(): Unit = {
    cancelGesture()
    audio.stopEffects()
    game.resume()
    presentation.reset(gallery.levelsAchieved)
    jumpTrail.reset()
    flames.reset()
    recordedCompletion = false
    paused = false
    resetClock()
  }
  private def showGallery(): Unit = {
    cancelGesture()
    audio.stopEffects()
    inGallery = true
    gallery.enter()
    paused = false
    resetClock()
    syncMusic()
    updateAccessibility()
  }
  private def startLevel(number: Int, mode: BubbleMode): Unit = {
    LevelData.all.find(_.number == number).foreach { level =>
      cancelGesture()
      audio.stopEffects()
      val saved = progress.checkpoints.get(number)
      game = new Game(level, saved.map(_.mode).getOrElse(mode))
      saved.foreach(game.restoreCheckpoint)
      game.setInvincible(progress.invincible)
      inGallery = false
      recordedCompletion = false
      presentation.reset(gallery.levelsAchieved)
      jumpTrail.reset()
      flames.reset()
      paused = false
      resetClock()
      syncMusic()
      updateAccessibility()
    }
  }
  private def perform(action: SceneAction): Unit = action match {
    case SceneAction.Pause => setPaused(true)
    case SceneAction.Resume => setPaused(false)
    case SceneAction.Quit => clearCheckpoint(); showGallery()
    case SceneAction.Replay => replay()
    case SceneAction.Next =>
      if (game.level.number < 6) startLevel(game.level.number + 1, game.mode) else showGallery()
  }
  private def scheduleFrame(): Unit = {
    if (animationID.isEmpty && ready && !failed && !suspended)
      animationID = Some(dom.window.requestAnimationFrame((now: Double) => frame(now)))
  }
  private def stopFrame(): Unit = {
    animationID.foreach(dom.window.cancelAnimationFrame)
    animationID = None
  }
  private def frame(now: Double): Unit = {
    animationID = None
    if (!failed && !suspended) {
      try {
        val delta = previousTime.map(previous => (now - previous) / 1000).getOrElse(0.0)
        previousTime = Some(now)
        val inactive = dom.document.hidden || !dom.document.hasFocus()
        jumpTrail.setReducedMotion(reducedMotion.matches)
        if (inGallery) {
          if (!inactive) gallery.advance(delta)
          gallery.drainSounds().foreach(audio.play)
        } else {
          if (!paused && !inactive) clock.advance(delta) { () =>
            val before = game.snapshot
            game.tick()
            val after = game.snapshot
            val cues = game.drainSounds()
            presentation.observeTick(game.level, before, after, cues)
            jumpTrail.observeTick(game.level, before, after, cues)
            cues.foreach(audio.play)
          }
          val state = game.snapshot
          if (state.status != Status.Playing && pointer.nonEmpty && !pointerIsResults) cancelGesture()
          if (state.status != Status.Won) saveCheckpoint()
          presentation.advance(game.level.number, state, delta, paused || inactive, game.mode)
          flames.advance(delta, paused || inactive || state.status != Status.Playing)
          if (state.status == Status.Won && !recordedCompletion) {
            presentation.recordWinProgress(gallery.levelsAchieved)
            gallery.completeLevel(game.level.number)
            clearCheckpoint()
            saveGalleryProgress()
            recordedCompletion = true
          }
          if (state.status == Status.Won && game.level.number == 6 && presentation.showingResults(state))
            audio.setMusic(Some(MenuMusic.Glad))
          if (!paused && !inactive) presentation.automaticAction(state).foreach(perform)
        }
        fitCanvas()
        if (inGallery) drawGallery() else draw()
        updateAccessibility()
        scheduleFrame()
      } catch { case error: Throwable => showError(error) }
    }
  }

  private def fitCanvas(): Unit = {
    val rect = canvas.getBoundingClientRect()
    cssWidth = math.max(1.0, rect.width)
    cssHeight = math.max(1.0, rect.height)
    dpr = math.max(1.0, math.min(3.0, dom.window.devicePixelRatio))
    val width = math.round(cssWidth * dpr).toInt
    val height = math.round(cssHeight * dpr).toInt
    if (canvas.width != width || canvas.height != height) {
      canvas.width = width
      canvas.height = height
    }
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0)
    ctx.imageSmoothingEnabled = false
    viewport = currentViewport(cssWidth, cssHeight)
  }

  private def draw(): Unit = {
    val state = game.snapshot
    ctx.fillStyle = "#000000"
    ctx.fillRect(0, 0, cssWidth, cssHeight)
    ctx.save()
    ctx.beginPath()
    ctx.rect(viewport.left, viewport.top, viewport.viewWidth * viewport.scale, viewport.viewHeight * viewport.scale)
    ctx.clip()
    drawUi(presentation.backdrop(game.level, viewport.viewWidth, viewport.viewHeight))
    drawUi(jumpTrail.commands(viewport))
    val visual = PresentationData.levels(game.level.number)
    visual.visible(viewport).foreach { case (art, center) =>
      sprite(art.page, center, visual.tileSize, visual.tileSize, Some(art.source))
    }
    val bubbleColor = game.mode match {
      case BubbleMode.Normal => UiColor(153, 153, 255)
      case BubbleMode.ExtraBounce => UiColor(211, 24, 149)
      case BubbleMode.Infinite => UiColor()
    }
    state.bubbles.foreach { bubble =>
      sprite(if (game.mode == BubbleMode.Infinite) "infinite_bubble.png" else "bubble01.png",
        bubble.position, bubble.radius * 2, bubble.radius * 2, tint = bubbleColor)
    }
    val coinFrame = presentation.coinFrame
    state.coins.foreach(coin => sprite("coin.png", coin.position, 32, 32, Some(coinFrame)))
    state.hazards.zipWithIndex.foreach { case (hazard, index) =>
      val pose = if (PresentationData.whalelandArt) flames.pose(index, reducedMotion.matches) else FlamePose()
      ctx.globalAlpha = if (hazard.active) 1.0 else 0.3
      sprite(if (game.level.number >= 4) "flame02.png" else "flame01.png",
        hazard.position + Vec2(pose.offsetX, 0), 24, 24, rotation = pose.clockwiseDegrees)
    }
    ctx.globalAlpha = 1.0
    if (state.status != Status.Won) sprite("goal01.png", state.goal, 32, 32)
    val (playerPage, playerFrame) = presentation.worldWhaleFrame(state)
    val playerColor = if (state.status == Status.Dead) UiColor(255, 0, 0)
      else if (paused) UiColor(166, 166, 166) else UiColor()
    sprite(playerPage,
      state.player.center, 32, 32, Some(playerFrame), state.player.facingLeft,
      flipY = state.status == Status.Dead, tint = playerColor)
    presentation.spout(state).foreach { case (frame, bounds) =>
      sprite("spout.png", bounds.center, bounds.width, bounds.height, Some(frame.source))
    }
    drawUi(presentation.commands(game.level, state, paused, viewport.viewWidth, viewport.viewHeight, game.mode))
    ctx.restore()
  }

  private def drawGallery(): Unit = {
    ctx.fillStyle = "#000000"
    ctx.fillRect(0, 0, cssWidth, cssHeight)
    ctx.save()
    ctx.beginPath()
    ctx.rect(viewport.left, viewport.top, 320 * viewport.scale, 568 * viewport.scale)
    ctx.clip()
    def transform(color: GalleryColor, rotation: Double, pivot: Vec2): Unit = {
      ctx.globalAlpha = color.alpha
      ctx.translate(viewport.left + pivot.x * viewport.scale, viewport.top + pivot.y * viewport.scale)
      ctx.rotate(rotation * math.Pi / 180)
      ctx.scale(viewport.scale, viewport.scale)
    }
    gallery.commands.foreach {
      case GalleryDraw.Image(quad, color, rotation, pivot, additive) =>
        ctx.save()
        transform(color, rotation, pivot)
        if (additive) ctx.globalCompositeOperation = "lighter"
        val source = quad.source
        val dest = quad.destination
        if (color.red == 255 && color.green == 255 && color.blue == 255)
          ctx.drawImage(textures(quad.page), source.x, source.y, source.width, source.height,
            dest.x - pivot.x, dest.y - pivot.y, dest.width, dest.height)
        else ctx.drawImage(tintedTexture(quad.page, color), source.x, source.y, source.width, source.height,
          dest.x - pivot.x, dest.y - pivot.y, dest.width, dest.height)
        ctx.restore()
      case GalleryDraw.Fill(rect, color, rotation, pivot) =>
        ctx.save()
        transform(color, rotation, pivot)
        ctx.fillStyle = s"rgb(${color.red},${color.green},${color.blue})"
        ctx.fillRect(rect.x - pivot.x, rect.y - pivot.y, rect.width, rect.height)
        ctx.restore()
    }
    ctx.restore()
  }

  /** Cache color multiplication once per texture/tint, matching S2D's shader.
    * The alpha mask is restored after multiplication so transparent pixels
    * do not become a colored rectangle around the reward bubble.
    */
  private def tintedTexture(page: String, color: GalleryColor): html.Canvas = {
    val key = (page, color.red, color.green, color.blue)
    tintedTextures.getOrElse(key, {
      val image = textures(page)
      val offscreen = dom.document.createElement("canvas").asInstanceOf[html.Canvas]
      offscreen.width = image.naturalWidth
      offscreen.height = image.naturalHeight
      offscreen.setAttribute("data-whaley-asset", page)
      val paint = offscreen.getContext("2d").asInstanceOf[dom.CanvasRenderingContext2D]
      paint.drawImage(image, 0, 0)
      paint.globalCompositeOperation = "multiply"
      paint.fillStyle = s"rgb(${color.red},${color.green},${color.blue})"
      paint.fillRect(0, 0, offscreen.width, offscreen.height)
      paint.globalCompositeOperation = "destination-in"
      paint.drawImage(image, 0, 0)
      tintedTextures += key -> offscreen
      offscreen
    })
  }

  private def sprite(file: String, position: Vec2, width: Double, height: Double,
                     source: Option[Rect] = None, flipX: Boolean = false,
                     flipY: Boolean = false, tint: UiColor = UiColor(), rotation: Double = 0): Unit = {
    val radians = rotation * math.Pi / 180
    val halfWidth = (math.abs(math.cos(radians)) * width + math.abs(math.sin(radians)) * height) / 2
    val halfHeight = (math.abs(math.sin(radians)) * width + math.abs(math.cos(radians)) * height) / 2
    if (width <= 0 || height <= 0 || position.y + halfHeight < viewport.cameraBottom ||
        position.y - halfHeight > viewport.cameraBottom + viewport.viewHeight ||
        position.x + halfWidth < viewport.cameraLeft || position.x - halfWidth > viewport.cameraLeft + viewport.viewWidth) return
    val image = textures(file)
    val rect = source.getOrElse(Rect(0, 0, image.naturalWidth.toDouble, image.naturalHeight.toDouble))
    val center = viewport.toScreen(position)
    val w = width * viewport.scale
    val h = height * viewport.scale
    ctx.save()
    ctx.translate(center.x, center.y)
    ctx.rotate(radians)
    ctx.scale(if (flipX) -1 else 1, if (flipY) -1 else 1)
    ctx.globalAlpha *= tint.alpha
    if (tint.red == 255 && tint.green == 255 && tint.blue == 255)
      ctx.drawImage(image, rect.x, rect.y, rect.width, rect.height, -w / 2, -h / 2, w, h)
    else ctx.drawImage(tintedTexture(file, GalleryColor(tint.red, tint.green, tint.blue)),
      rect.x, rect.y, rect.width, rect.height, -w / 2, -h / 2, w, h)
    ctx.restore()
  }

  private def drawUi(commands: Vector[UiDraw]): Unit = commands.foreach {
    case UiDraw.Black(rect) => drawFill(rect, UiColor(0, 0, 0))
    case UiDraw.Fill(rect, color) => drawFill(rect, color)
    case UiDraw.Image(quad, color, flipX, flipY) =>
      val source = quad.source
      val dest = quad.destination
      ctx.save()
      ctx.globalAlpha = color.alpha
      ctx.translate(viewport.left + dest.center.x * viewport.scale,
        viewport.top + dest.center.y * viewport.scale)
      ctx.scale(if (flipX) -1 else 1, if (flipY) -1 else 1)
      val width = dest.width * viewport.scale
      val height = dest.height * viewport.scale
      if (color.red == 255 && color.green == 255 && color.blue == 255)
        ctx.drawImage(textures(quad.page), source.x, source.y, source.width, source.height,
          -width / 2, -height / 2, width, height)
      else ctx.drawImage(tintedTexture(quad.page, GalleryColor(color.red, color.green, color.blue)),
        source.x, source.y, source.width, source.height, -width / 2, -height / 2, width, height)
      ctx.restore()
  }
  private def drawFill(rect: Rect, color: UiColor): Unit = {
    ctx.save()
    ctx.globalAlpha = color.alpha
    ctx.fillStyle = s"rgb(${color.red},${color.green},${color.blue})"
    ctx.fillRect(viewport.left + rect.x * viewport.scale, viewport.top + rect.y * viewport.scale,
      rect.width * viewport.scale, rect.height * viewport.scale)
    ctx.restore()
  }
  private def updateAccessibility(): Unit = {
    val title = if (gallery.completedGame) GameInfo.completedName else GameInfo.name
    if (dom.document.title != title) dom.document.title = title
    def attribute(name: String, value: String): Unit =
      if (canvas.getAttribute(name) != value) canvas.setAttribute(name, value)
    attribute("data-scene", if (inGallery) "gallery" else "game")
    attribute("data-paused", paused.toString)
    attribute("data-invincible", progress.invincible.toString)
    val label = if (inGallery) s"$title. Select a painting, or hold for its preview. Enter opens the latest unlocked level. F1 or I toggles invincibility."
      else s"${ScenePresentation.levelName(game.level.number)}. Space pauses. F1 or I toggles invincibility."
    attribute("aria-label", label)
    if (invincibilityButton.getAttribute("aria-checked") != progress.invincible.toString)
      invincibilityButton.setAttribute("aria-checked", progress.invincible.toString)
    val invincibility = s"Invincibility ${if (progress.invincible) "on" else "off"}"
    val tooltip = s"$invincibility (F1 or I)"
    if (invincibilityButton.title != tooltip) invincibilityButton.title = tooltip
    val sceneStatus = if (paused) "QUIT. CONTINUE."
      else if (inGallery) title
      else ScenePresentation.levelName(game.level.number)
    val status = s"$sceneStatus. $invincibility."
    if (statusLabel.textContent != status) statusLabel.textContent = status
  }
}
