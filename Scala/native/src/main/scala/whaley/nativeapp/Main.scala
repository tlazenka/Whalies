package whaley.nativeapp

import java.io.File
import s2d.backend.gl.GL.glGetError
import s2d.backend.sdl2.SDL.{SDL_CaptureMouse, SDL_Quit}
import s2d.backend.sdl2.Extras.{SDL_FALSE, SDL_TRUE}
import s2d.core.{Drawing, Input, Timing, Window}
import s2d.shapes.BasicRenderer
import s2d.textures.TextureRenderer
import s2d.types.{Key, MouseButton}
import whaley.core.*

/** SDL/OpenGL host: original scene rules, rendering commands and saves are shared. */
object Main {
  def main(args: Array[String]): Unit = {
    if (args.contains("--help") || args.contains("-h")) {
      println(Options.usage)
      return
    }
    val options = Options.parse(args)
    val initial = LevelData.all.find(_.number == options.level).getOrElse(
      throw new IllegalArgumentException(s"Unknown level ${options.level}; choose ${LevelData.all.map(_.number).mkString(", ")}."))
    options.headlessTicks match {
      case Some(ticks) => runHeadless(initial, ticks); return
      case None => ()
    }
    val assetRoot = Assets.find(options.assets)
    val storage = new ProgressStorage(enabled = options.smokeFrames.isEmpty)
    var progress = storage.load()
    val gallery = new GalleryScene()
    gallery.restoreProgress(progress.levelsAchieved, progress.rewardVisible)
    var game = new Game(initial, progress.checkpoints.get(initial.number).map(_.mode).getOrElse(BubbleMode.Normal))
    if (options.levelSpecified) progress.checkpoints.get(initial.number).foreach(game.restoreCheckpoint)
    game.setInvincible(progress.invincible)
    var showingGallery = !options.levelSpecified && options.smokeFrames.isEmpty
    var recordedWin = false
    var sceneGeneration = 0L
    var exitRequested = false
    val clock = new FixedStepClock()
    var renderer: Option[Renderer] = None
    var audio: AudioPlayer = AudioPlayer.unavailable
    var pointer: Option[Vec2] = None
    var pointerIsResults = false
    var lastWorld = Vec2(0, 0)
    var paused = false
    var discardDelta = true
    var lastTitle = ""
    var frames = 0
    val demonstration = new DemonstrationInput()

    def releaseCapture(): Unit = {
      pointer = None
      pointerIsResults = false
      SDL_CaptureMouse(SDL_FALSE)
    }
    def cancelPointer(): Unit = {
      game.cancelPointer()
      gallery.cancelPointer()
      renderer.foreach(_.cancelPointer())
      releaseCapture()
    }
    def resetClock(): Unit = { clock.reset(); discardDelta = true }
    def save(next: PlayerProgress): Unit = if (next != progress) {
      progress = next
      storage.save(progress)
    }
    def saveGalleryProgress(): Unit = save(progress.copy(
      levelsAchieved = gallery.levelsAchieved, rewardVisible = gallery.rewardVisible))
    def saveCheckpoint(): Unit = game.checkpoint.foreach { checkpoint =>
      val achieved = math.max(gallery.levelsAchieved, checkpoint.levelNumber)
      if (achieved != gallery.levelsAchieved) gallery.restoreProgress(achieved, gallery.rewardVisible)
      save(progress.copy(levelsAchieved = achieved, rewardVisible = gallery.rewardVisible,
        checkpoints = progress.checkpoints.updated(checkpoint.levelNumber, checkpoint)))
    }
    def clearCheckpoint(): Unit = save(progress.copy(checkpoints = progress.checkpoints.removed(game.level.number)))
    def syncMusic(): Unit =
      audio.setMusic(if (showingGallery) Some(if (gallery.completedGame) MenuMusic.Glad else MenuMusic.Gray) else None)
    def setPaused(value: Boolean, sound: Boolean = true): Unit = {
      val next = value && !showingGallery && game.snapshot.status == Status.Playing
      if (next && !paused) {
        audio.stopEffects()
        if (sound && game.snapshot.status == Status.Playing) audio.play(SoundCue.Pause)
      }
      paused = next
      cancelPointer()
      resetClock()
      sceneGeneration += 1
    }
    def toggleInvincibility(): Unit = {
      cancelPointer()
      save(progress.copy(invincible = !progress.invincible))
      game.setInvincible(progress.invincible)
    }
    def restart(): Unit = {
      cancelPointer()
      audio.stopEffects()
      game.restart()
      clearCheckpoint()
      renderer.foreach(_.resetPresentation(gallery.levelsAchieved))
      recordedWin = false
      sceneGeneration += 1
      paused = false
      resetClock()
    }
    def replay(): Unit = {
      cancelPointer()
      audio.stopEffects()
      game.resume()
      renderer.foreach(_.resetPresentation(gallery.levelsAchieved))
      recordedWin = false
      sceneGeneration += 1
      paused = false
      resetClock()
    }
    def selectLevel(number: Int, mode: BubbleMode = BubbleMode.Normal): Unit = LevelData.all.find(_.number == number).foreach { level =>
      cancelPointer()
      audio.stopEffects()
      val saved = progress.checkpoints.get(number)
      game = new Game(level, saved.map(_.mode).getOrElse(mode))
      saved.foreach(game.restoreCheckpoint)
      game.setInvincible(progress.invincible)
      showingGallery = false
      recordedWin = false
      sceneGeneration += 1
      renderer.foreach(_.resetPresentation(gallery.levelsAchieved))
      paused = false
      resetClock()
      syncMusic()
    }
    def showGallery(): Unit = {
      cancelPointer()
      audio.stopEffects()
      gallery.enter()
      showingGallery = true
      sceneGeneration += 1
      paused = false
      resetClock()
      syncMusic()
    }
    def perform(action: SceneAction): Unit = action match {
      case SceneAction.Pause => setPaused(true)
      case SceneAction.Resume => setPaused(false)
      case SceneAction.Quit => clearCheckpoint(); showGallery()
      case SceneAction.Replay => replay()
      case SceneAction.Next =>
        if (game.level.number < 6) selectLevel(game.level.number + 1, game.mode) else showGallery()
    }

    try {
      Window.create(options.width, options.height, GameInfo.name)
      Input.setExitKey(Key.Unknown)
      Timing.setTargetFPS(if (options.smokeFrames.nonEmpty) 0 else 60)
      while (glGetError().toInt != 0) ()
      require(BasicRenderer.initialize(), "S2D could not initialize its shape renderer")
      require(TextureRenderer.initialize(), "S2D could not initialize its texture renderer")
      renderer = Some(Renderer.load(assetRoot))
      renderer.foreach(_.resetPresentation(gallery.levelsAchieved))
      audio = Audio.open(assetRoot)
      syncMusic()
      checkGraphics("loading the game textures")
      println(s"Whaley: Scala Native / S2D. Assets: ${assetRoot.getAbsolutePath}")
      println("Gallery: click a painting to play; hold for a preview, then click to dismiss.")
      println("Top bar / Space: pause. QUIT clears this level's checkpoint; CONTINUE resumes.")
      println("Star / F1 / I: toggle invincibility. Settings and coin checkpoints are saved.")
      println("R: restart. 1-6: select level. M/Esc: quit level. Esc in gallery: close window.")

      while (!exitRequested && Window.isOpen() && options.smokeFrames.forall(frames < _)) {
        Drawing.beginFrame()
        val screen = Vec2(Input.getMouseX().toDouble, Input.getMouseY().toDouble)
        var view = Renderer.viewport(game.level, game.snapshot)
        def worldPoint: Option[Vec2] = view.toWorld(screen)
        def surfacePoint: Option[Vec2] = Renderer.galleryViewport.toWorld(screen).map(p => Vec2(p.x, 568 - p.y))
        val suspended = options.smokeFrames.isEmpty && (!Window.isFocused || Window.isMinimized)
        audio.setSuspended(suspended)

        if (options.smokeFrames.isEmpty) {
          if (suspended || Window.didLoseFocus) {
            cancelPointer()
            resetClock()
            if (!showingGallery && game.snapshot.status == Status.Playing) paused = true
          }
          if (Window.isResized) { cancelPointer(); resetClock() }
          if (!suspended) {
            val inputGeneration = sceneGeneration
            val toggleKey = !Input.isKeyDown(Key.LeftControl) && !Input.isKeyDown(Key.RightControl) &&
              !Input.isKeyDown(Key.LeftAlt) && !Input.isKeyDown(Key.RightAlt) &&
              (Input.isKeyPressed(Key.F1) || Input.isKeyPressed(Key.I))
            val togglePressed = toggleKey ||
              (Input.isMouseButtonPressed(MouseButton.Left) &&
                InvincibilityToggle.contains(screen, Window.width.toDouble, Window.height.toDouble))
            if (togglePressed) toggleInvincibility()
            else if (Input.isKeyPressed(Key.Escape)) {
              if (showingGallery) exitRequested = true else perform(SceneAction.Quit)
            } else if (Input.isKeyPressed(Key.M) && !showingGallery) perform(SceneAction.Quit)
            else {
              if (!showingGallery && Input.isKeyPressed(Key.R)) restart()
              if (!showingGallery && Input.isKeyPressed(Key.N)) {
                val next = (LevelData.all.indexWhere(_.number == game.level.number) + 1) % LevelData.all.length
                selectLevel(LevelData.all(next).number)
              }
              Vector(Key.One, Key.Two, Key.Three, Key.Four, Key.Five, Key.Six).zipWithIndex.foreach {
                case (key, index) => if (Input.isKeyPressed(key)) selectLevel(index + 1)
              }
              if (showingGallery && Input.isKeyPressed(Key.Enter))
                selectLevel(math.min(6, gallery.levelsAchieved), gallery.gameMode)
              if (!showingGallery && game.snapshot.status == Status.Playing && Input.isKeyPressed(Key.Space)) setPaused(!paused)
            }
            view = Renderer.viewport(game.level, game.snapshot)

            // A star press consumes this gesture, including its later release:
            // no game/gallery pointer is captured, and toggling cancels any
            // previous drag without pausing the simulation or its audio.
            if (!togglePressed && !exitRequested && inputGeneration == sceneGeneration) {
              if (showingGallery) {
                if (Input.isMouseButtonPressed(MouseButton.Left) && pointer.isEmpty) {
                  surfacePoint.foreach { point =>
                    pointer = Some(screen)
                    gallery.pointerDown(point)
                    gallery.drainSounds().foreach(audio.play)
                    saveGalleryProgress()
                    SDL_CaptureMouse(SDL_TRUE)
                  }
                }
                if (pointer.exists(_ != screen) && Input.isMouseButtonDown(MouseButton.Left)) {
                  gallery.pointerMove(surfacePoint.getOrElse(Vec2(-1, -1)))
                  pointer = Some(screen)
                }
                if (pointer.nonEmpty && Input.isMouseButtonReleased(MouseButton.Left)) {
                  val start = surfacePoint.flatMap(gallery.pointerUp)
                  releaseCapture()
                  gallery.cancelPointer()
                  start.foreach(request => selectLevel(request.level, request.mode))
                }
              } else {
                if (Input.isMouseButtonPressed(MouseButton.Left) && pointer.isEmpty) {
                  surfacePoint.foreach { point =>
                    renderer.get.pointerDown(game.snapshot, paused, point, 320, 568) match {
                      case Some(action) => perform(action)
                      case None if renderer.get.showingResults(game.snapshot) =>
                        pointer = Some(screen)
                        pointerIsResults = true
                        SDL_CaptureMouse(SDL_TRUE)
                      case None if !paused && game.snapshot.status == Status.Playing =>
                        worldPoint.foreach { world =>
                          pointer = Some(screen)
                          lastWorld = world
                          game.pointerDown(world)
                          SDL_CaptureMouse(SDL_TRUE)
                        }
                      case _ => ()
                    }
                  }
                }
                if (pointer.nonEmpty && Input.isMouseButtonReleased(MouseButton.Left)) {
                  if (pointerIsResults) {
                    val action = surfacePoint.flatMap(point => renderer.get.pointerUp(game.snapshot, point, 320, 568))
                    releaseCapture()
                    if (action.isEmpty) renderer.get.cancelPointer()
                    action.foreach(perform)
                  } else {
                    game.pointerUp(worldPoint.getOrElse(lastWorld))
                    releaseCapture()
                  }
                } else if (!pointerIsResults && pointer.exists(_ != screen) && Input.isMouseButtonDown(MouseButton.Left)) {
                  worldPoint match {
                    case Some(point) =>
                      lastWorld = point
                      game.pointerMove(point)
                      pointer = Some(screen)
                    case None => cancelPointer()
                  }
                }
              }
            }
          }
        } else demonstration.beforeTick(game, frames)

        val elapsed = if (options.smokeFrames.nonEmpty) clock.step
          else if (discardDelta || suspended) 0.0 else Timing.delta
        if (showingGallery || paused) clock.reset()
        else clock.advance(elapsed) { () =>
          val before = game.snapshot
          game.tick()
          val after = game.snapshot
          val cues = game.drainSounds()
          renderer.get.observeTick(game.level, before, after, cues)
          cues.foreach(audio.play)
        }
        discardDelta = suspended
        val state = game.snapshot
        if (showingGallery) {
          gallery.advance(elapsed)
          gallery.drainSounds().foreach(audio.play)
          renderer.get.drawGallery(gallery)
        } else {
          if (state.status != Status.Playing && pointer.nonEmpty && !pointerIsResults) cancelPointer()
          if (state.status != Status.Won) saveCheckpoint()
          if (state.status == Status.Won && !recordedWin) {
            renderer.get.recordWinProgress(gallery.levelsAchieved)
            gallery.completeLevel(game.level.number)
            clearCheckpoint()
            saveGalleryProgress()
            recordedWin = true
          }
          renderer.get.draw(game.level, state, paused, elapsed, game.mode)
          if (state.status == Status.Won && game.level.number == 6 && renderer.get.showingResults(state))
            audio.setMusic(Some(MenuMusic.Glad))
          if (!paused && !suspended) renderer.get.automaticAction(state).foreach(perform)
        }
        renderer.get.drawInvincibilityToggle(progress.invincible)
        val title = if (gallery.completedGame) GameInfo.completedName else GameInfo.name
        if (title != lastTitle) { Window.setTitle(title); lastTitle = title }
        Drawing.endFrame()
        if (options.smokeFrames.nonEmpty) checkGraphics(s"rendering frame $frames")
        require(state.player.position.finite, "The simulation produced an invalid player position")
        frames += 1
      }
      options.smokeFrames.foreach { expected =>
        require(frames == expected, s"Smoke run closed early: $frames / $expected frames")
        val state = game.snapshot
        println(s"SMOKE OK frames=$frames level=${game.level.number} ticks=${state.tick} coins=${state.collected} bubbles=${state.bubblesUsed}")
      }
    } finally {
      audio.close()
      if (Window.isReady) {
        cancelPointer()
        renderer.foreach(_.close())
        TextureRenderer.cleanup()
        BasicRenderer.cleanup()
        Window.close()
      }
      SDL_Quit()
    }
  }

  private def checkGraphics(stage: String): Unit = {
    val error = glGetError().toInt
    if (error != 0) throw new IllegalStateException(f"OpenGL error 0x$error%04x while $stage")
  }
  private def runHeadless(level: Level, ticks: Int): Unit = {
    def run(): Snapshot = {
      val game = new Game(level)
      val input = new DemonstrationInput()
      var index = 0
      while (index < ticks) {
        input.beforeTick(game, index)
        game.tick()
        require(game.snapshot.player.position.finite, s"Invalid position at step $index")
        index += 1
      }
      game.cancelPointer()
      game.snapshot
    }
    val result = run()
    require(result == run(), "Identical fixed-step input produced different native snapshots")
    println(f"HEADLESS OK steps=$ticks level=${level.number} tick=${result.tick} x=${result.player.position.x}%.3f y=${result.player.position.y}%.3f coins=${result.collected} bubbles=${result.bubblesUsed} status=${result.status}")
  }
}

private final class DemonstrationInput {
  private var point = Vec2(0, 0)
  def beforeTick(game: Game, frame: Int): Unit = frame match {
    case 0 =>
      point = game.snapshot.player.center + Vec2(48, -72)
      game.pointerDown(point)
    case 1 => game.pointerUp(point)
    case 12 => game.snapshot.bubbles.headOption.foreach { bubble =>
      point = bubble.position
      game.pointerDown(point)
    }
    case 20 => point = point + Vec2(8, 0); game.pointerMove(point)
    case 30 => game.pointerUp(point)
    case _ => ()
  }
}

private final case class Options(assets: Option[File] = None, level: Int = 1, levelSpecified: Boolean = false,
                                 width: Int = 640, height: Int = 900,
                                 smokeFrames: Option[Int] = None,
                                 headlessTicks: Option[Int] = None)
private object Options {
  val usage: String = """Whaley — Scala Native / S2D
    |Usage: whaley [--assets DIRECTORY] [--level 1..6] [--width N] [--height N]
    |              [--smoke [FRAMES] | --headless [TICKS]] [--help]
    |
    |Assets default to ./target/assets, ./Scala/target/assets, or an assets
    |directory beside the executable. WHALEY_ASSET_ROOT also sets the directory.
    |Interactive launch opens the gallery. --level starts that practice level.
    |Click a painting to play; hold for one second to preview; click to dismiss.
    |M/Escape returns to the gallery. Escape from the gallery exits.
    |--smoke runs 120 rendered fixed-step frames by default and exits; use Xvfb
    |on a Linux CI host. OpenGL/shader/asset errors fail the process.
    |--headless runs 600 deterministic core ticks by default, checks reproducibility,
    |and exits without loading assets or opening an SDL/OpenGL window.
    |""".stripMargin

  def parse(args: Array[String]): Options = {
    var result = Options()
    var index = 0
    def value(): String = {
      index += 1
      if (index >= args.length) throw new IllegalArgumentException(s"Missing value after ${args(index - 1)}")
      args(index)
    }
    def positive(raw: String, name: String): Int = raw.toIntOption.filter(_ > 0).getOrElse(
      throw new IllegalArgumentException(s"$name requires a positive integer, got '$raw'"))
    while (index < args.length) {
      args(index) match {
        case "--assets" => result = result.copy(assets = Some(new File(value())))
        case "--level" => result = result.copy(level = positive(value(), "--level"), levelSpecified = true)
        case "--width" => result = result.copy(width = positive(value(), "--width"))
        case "--height" => result = result.copy(height = positive(value(), "--height"))
        case "--smoke" =>
          val frames = if (index + 1 < args.length && !args(index + 1).startsWith("--")) positive(value(), "--smoke") else 120
          result = result.copy(smokeFrames = Some(frames))
        case "--headless" =>
          val ticks = if (index + 1 < args.length && !args(index + 1).startsWith("--")) positive(value(), "--headless") else 600
          result = result.copy(headlessTicks = Some(ticks))
        case other => throw new IllegalArgumentException(s"Unknown argument '$other'.\n$usage")
      }
      index += 1
    }
    require(result.width >= 320 && result.height >= 480, "The initial window must be at least 320 x 480")
    require(result.smokeFrames.isEmpty || result.headlessTicks.isEmpty, "Choose --smoke or --headless, not both")
    result
  }
}
