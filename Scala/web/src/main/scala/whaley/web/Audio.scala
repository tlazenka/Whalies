package whaley.web

import org.scalajs.dom
import scala.collection.mutable
import scala.concurrent.{Future, Promise}
import scala.scalajs.concurrent.JSExecutionContext.Implicits.queue
import scala.scalajs.js
import scala.scalajs.js.Thenable.Implicits.*
import whaley.core.{AudioPlayer, MenuMusic, SoundCue}

private object Audio {
  def open(assetBase: String): AudioPlayer = new BrowserAudio(assetBase.stripSuffix("/"))
}

/** One Web Audio context owns short, overlapping effects. Menu music streams
  * through one media element instead of decoding the long MP3 into PCM memory.
  * Both are activated from the host's real pointer/keyboard gesture.
  */
private final class BrowserAudio(assetBase: String) extends AudioPlayer {
  private final case class Voice(cue: SoundCue, source: dom.AudioBufferSourceNode, gain: dom.GainNode)
  private var context: Option[dom.AudioContext] = None
  private val buffers = mutable.Map.empty[SoundCue, Future[dom.AudioBuffer]]
  private var voices = Vector.empty[Voice]
  private var pending = Map.empty[SoundCue, Long]
  private var generation = 0L
  private var activated = false
  private var suspended = false
  private var closed = false
  private var desiredMusic: Option[MenuMusic] = None
  private var music: Option[(MenuMusic, dom.HTMLAudioElement)] = None
  private var musicStarting: Option[(dom.HTMLAudioElement, Long)] = None
  private var musicRequest = 0L
  private var reported = Set.empty[String]

  def unlock(): Unit = if (!closed) {
    activated = true
    if (context.isEmpty) {
      try context = Some(new dom.AudioContext())
      catch { case error: Throwable => report(s"Web Audio could not start: ${error.getMessage}") }
    }
    context.foreach { ctx =>
      if (!suspended) resume(ctx)
      SoundCue.values.foreach(cue => buffer(ctx, cue).failed.foreach { error =>
        if (!closed) report(s"${cue.file}: ${error.getMessage}")
      })
    }
    // A legacy media element may report a blocked play only by staying paused.
    // A new real gesture must remain able to retry that request.
    if (!suspended && music.exists(_._2.paused)) musicStarting = None
    // This play() call deliberately occurs inside the user gesture too.
    syncMusic()
  }

  def play(cue: SoundCue): Unit = if (!closed && !suspended && activated) {
    context.foreach { ctx =>
      val busy = voices.exists(_.cue == cue) || pending.contains(cue)
      if (!cue.onlyWhenIdle || !busy) {
        val token = generation
        if (cue.onlyWhenIdle) pending += cue -> token
        val running = resume(ctx)
        val decoded = buffer(ctx, cue)
        running.flatMap(_ => decoded).map { audio =>
          if (pending.get(cue).contains(token)) pending -= cue
          // Decoding or autoplay completion from a departed scene must never
          // produce a delayed sound in the next scene or in the background.
          if (!closed && !suspended && generation == token && ctx.state.toString == "running") {
            if (voices.size >= 32) stopVoice(voices.head)
            val source = ctx.createBufferSource()
            val gain = ctx.createGain()
            source.buffer = audio
            gain.gain.value = cue.gain
            source.connect(gain)
            gain.connect(ctx.destination)
            val voice = Voice(cue, source, gain)
            voices :+= voice
            source.onended = (_: dom.Event) => releaseVoice(voice)
            source.start(0)
          }
        }.failed.foreach { error =>
          if (pending.get(cue).contains(token)) pending -= cue
          if (!closed) report(s"${cue.file}: ${error.getMessage}")
        }
      }
    }
  }

  def setMusic(track: Option[MenuMusic]): Unit = if (!closed) {
    desiredMusic = track
    track.foreach { selected =>
      if (!music.exists(_._1 == selected)) {
        music.foreach { case (_, element) =>
          element.pause()
          element.removeAttribute("src")
          element.load()
        }
        val element = dom.document.createElement("audio").asInstanceOf[dom.HTMLAudioElement]
        element.preload = "metadata"
        element.loop = false // Original playBackgroundMusic(..., loop:NO).
        element.volume = 1.0
        element.src = url(selected.file)
        element.addEventListener("error", (_: dom.Event) => {
          if (!closed && music.exists(_._2 eq element))
            report(s"Unable to load original menu music ${selected.file}")
        })
        music = Some(selected -> element)
        musicStarting = None
      }
    }
    syncMusic()
  }

  def setSuspended(value: Boolean): Unit = if (!closed && suspended != value) {
    suspended = value
    if (value) {
      stopEffects()
      context.foreach(suspend)
    } else if (activated) context.foreach(resume)
    syncMusic()
  }

  def stopEffects(): Unit = {
    generation += 1
    pending = Map.empty
    voices.foreach(stopVoice)
    voices = Vector.empty
  }

  def close(): Unit = if (!closed) {
    closed = true
    stopEffects()
    desiredMusic = None
    music.foreach { case (_, element) =>
      element.pause()
      element.removeAttribute("src")
      element.load()
    }
    music = None
    musicStarting = None
    context.foreach(ctx => ctx.close().toFuture.failed.foreach(_ => ()))
    context = None
    buffers.clear()
  }

  private def buffer(ctx: dom.AudioContext, cue: SoundCue): Future[dom.AudioBuffer] =
    buffers.getOrElseUpdate(cue, {
      for {
        response <- dom.fetch(url(cue.file)).toFuture
        data <- if (response.ok) response.arrayBuffer().toFuture
                else Future.failed(new IllegalStateException(s"HTTP ${response.status} loading original audio"))
        decoded <- ctx.decodeAudioData(data).toFuture
      } yield decoded
    })

  private def resume(ctx: dom.AudioContext): Future[Unit] = {
    val ready = if (ctx.state.toString == "running") Future.successful(()) else ctx.resume().toFuture
    ready.foreach { _ =>
      // Reconcile a visibility/close change that happened across resume().
      if (closed) ctx.close().toFuture.failed.foreach(_ => ())
      else if (suspended) suspend(ctx)
    }
    ready.failed.foreach { error => if (!closed) report(s"Audio activation failed: ${error.getMessage}") }
    ready
  }

  private def suspend(ctx: dom.AudioContext): Unit = {
    ctx.suspend().toFuture.map { _ =>
      // A focus return can race the asynchronous suspend request. Reconcile
      // its completion too, so the final state follows the current lifecycle.
      if (!closed && !suspended && activated) resume(ctx)
    }.failed.foreach { error => if (!closed) report(s"Audio suspension failed: ${error.getMessage}") }
  }

  private def syncMusic(): Unit = music.foreach { case (track, element) =>
    if (closed || suspended || !activated || !desiredMusic.contains(track)) {
      musicStarting = None
      element.pause()
    } else if (element.paused && !element.ended && !musicStarting.exists(_._1 eq element)) {
      musicRequest += 1
      val request = musicRequest
      musicStarting = Some(element -> request)
      def currentRequest: Boolean = musicStarting.exists { case (current, token) =>
        (current eq element) && token == request
      }
      val playback = try {
        element.play().toOption.map(_.toFuture).getOrElse(awaitLegacyPlayback(element))
      } catch { case error: Throwable => Future.failed(error) }
      playback.map { _ =>
        if (currentRequest) musicStarting = None
        if (closed || suspended || !desiredMusic.contains(track) || !music.exists(_._2 eq element)) element.pause()
      }.failed.foreach { error =>
        val current = currentRequest
        if (current) musicStarting = None
        // Scene changes deliberately abort a pending play request. A blocked
        // initial play remains eligible for retry on the next real gesture.
        if (current && !closed && !suspended && desiredMusic.contains(track) && music.exists(_._2 eq element))
          report(s"${track.file} playback: ${error.getMessage}")
      }
    }
  }

  /** Older browsers return undefined from play(). Observe actual media state
    * and events in that case instead of treating the missing Promise as success.
    */
  private def awaitLegacyPlayback(element: dom.HTMLAudioElement): Future[Unit] = {
    val result = Promise[Unit]()
    val onPlaying: js.Function1[dom.Event, Unit] = _ => { result.trySuccess(()); () }
    val onError: js.Function1[dom.Event, Unit] = _ => {
      result.tryFailure(new IllegalStateException("The media element could not play the original track")); ()
    }
    val onPause: js.Function1[dom.Event, Unit] = _ => {
      result.tryFailure(new IllegalStateException("The media play request was interrupted")); ()
    }
    element.addEventListener("playing", onPlaying)
    element.addEventListener("error", onError)
    element.addEventListener("pause", onPause)
    element.addEventListener("abort", onPause)
    result.future.onComplete { _ =>
      element.removeEventListener("playing", onPlaying)
      element.removeEventListener("error", onError)
      element.removeEventListener("pause", onPause)
      element.removeEventListener("abort", onPause)
    }
    if (element.error != null) onError(new dom.Event("error"))
    else if (!element.paused && element.readyState.asInstanceOf[Int] >= 3) onPlaying(new dom.Event("playing"))
    result.future
  }

  private def stopVoice(voice: Voice): Unit = {
    voice.source.onended = null
    try voice.source.stop(0) catch { case _: Throwable => () }
    releaseVoice(voice)
  }

  private def releaseVoice(voice: Voice): Unit = {
    voices = voices.filterNot(_ eq voice)
    voice.source.disconnect()
    voice.gain.disconnect()
  }

  private def url(file: String): String = s"$assetBase/$file"
  private def report(message: String): Unit = if (!reported(message)) {
    reported += message
    dom.console.warn(s"Whaley audio: $message")
  }
}
