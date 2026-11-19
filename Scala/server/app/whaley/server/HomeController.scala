package whaley.server

import cats.effect.IO
import cats.effect.unsafe.IORuntime
import cats.syntax.all.*
import com.google.inject.Inject
import natchez.Trace
import natchez.Trace.Implicits.noop
import play.api.Configuration
import play.api.mvc.*
import skunk.Session
import skunk.codec.all.varchar
import skunk.implicits.*
import whaley.core.GameInfo

import scala.concurrent.ExecutionContext

/** One page load = one committed INSERT. Failure is visible as an HTTP error. */
final class PageLoadStore(config: Configuration):
  given Trace[IO] = noop
  given IORuntime = IORuntime.global

  private val session = Session.single[IO](
    host = config.get[String]("whaley.db.host"),
    port = config.get[Int]("whaley.db.port"),
    user = config.get[String]("whaley.db.user"),
    database = config.get[String]("whaley.db.database"),
    password = Some(config.get[String]("whaley.db.password"))
  )

  private val insert = sql"INSERT INTO page_load (game_name) VALUES ($varchar)".command
  def record(name: String): IO[Unit] =
    session.use(s => s.prepare(insert).flatMap(_.execute(name)).void)

final class HomeController @Inject() (
  cc: ControllerComponents,
  config: Configuration
)(using ec: ExecutionContext) extends AbstractController(cc):

  private val store = PageLoadStore(config)
  private given IORuntime = IORuntime.global

  def index: Action[AnyContent] = Action.async:
    store.record(GameInfo.name).attempt.unsafeToFuture().map {
      case Right(_) => Ok(views.html.index(GameInfo.name))
      case Left(error) =>
        play.api.Logger(getClass).error("Page load recording failed", error)
        InternalServerError("Unable to record page load")
    }

  def health: Action[AnyContent] = Action:
    Ok("ok")
