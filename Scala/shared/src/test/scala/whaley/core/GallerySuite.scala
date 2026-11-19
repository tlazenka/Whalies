package whaley.core

class GallerySuite extends munit.FunSuite {
  private val cardOne = Vec2(71, 195)
  private val cardTwo = Vec2(160, 195)
  private val outside = Vec2(20, 500)
  private val reward = Vec2(141, 64)

  private def images(scene: GalleryScene, page: String): Vector[GalleryDraw.Image] =
    scene.commands.collect { case image: GalleryDraw.Image if image.quad.page == page => image }
  private def click(scene: GalleryScene, point: Vec2): Option[GalleryStart] = {
    scene.pointerDown(point)
    scene.pointerUp(point)
  }
  private def close(actual: Double, expected: Double): Unit = assertEqualsDouble(actual, expected, 1e-9)

  test("Gray and Glad titles keep original fixed origin, offsets and overhangs") {
    val scene = new GalleryScene(() => 0)
    val gray = images(scene, "title_font.png").map(_.quad)
    assertEquals(gray, GalleryData.grayFont.layout("Gray Whale", 24, 20))
    assertEquals(gray.head.destination, Rect(32, 44, 50, 59))
    assertEquals(gray(3).destination, Rect(74, 61, 91, 54)) // y overhangs its advance cell.
    (1 to 6).foreach(scene.completeLevel)
    val glad = images(scene, "title_font2.png").map(_.quad)
    assertEquals(glad, GalleryData.gladFont.layout("Glad Whale", 24, 20))
    assertEquals(glad(1).destination, Rect(72, 26, 66, 56))
    assertEquals(images(scene, "title_font.png"), Vector.empty)
  }

  test("gallery uses original frame grid, painting size, bottom-left pivot and layer order") {
    val scene = new GalleryScene(() => 2)
    val frames = images(scene, "frame.png")
    assertEquals(frames.size, 6)
    val first = frames.head
    close(first.quad.destination.x, 36.8)
    close(first.quad.destination.y, 144)
    close(first.quad.destination.width, 68.8)
    close(first.quad.destination.height, 102.8)
    close(frames(1).quad.destination.x, 125.6)
    close(frames(3).quad.destination.y, 261.8)
    close(first.pivot.x, 36.8)
    close(first.pivot.y, 246.8)
    assertEquals(first.rotation, 2.0)
    val painting = images(scene, "level1.png").head
    assertEquals(painting.quad.destination.width, 40.0)
    assertEquals(painting.quad.destination.height, 60.0)
    assertEquals(painting.quad.destination.center, first.quad.destination.center)
    assertEquals(painting.pivot, first.pivot)
    assertEquals(images(scene, "level2.png"), Vector.empty)
    assert(scene.commands.indexOf(painting) < scene.commands.indexOf(first))
    scene.pointerDown(cardOne)
    val highlight = scene.commands.collectFirst { case fill: GalleryDraw.Fill => fill }.get
    assertEquals(highlight.color, GalleryColor(0, 0, 0, 100.0 / 255.0))
    assert(scene.commands.indexOf(first) < scene.commands.indexOf(highlight))
  }

  test("only the real reward bubble is shown and popping it leaves the frames untouched") {
    val scene = new GalleryScene(() => 2)
    val bubble = images(scene, "bubble01.png").head
    assertEquals(images(scene, "bubble01.png").size, 1)
    assertEquals(bubble.quad.destination, Rect(133, 56, 16, 16))
    assertEquals(bubble.color, GalleryColor(211, 24, 149, 150.0 / 255.0))
    val before = images(scene, "frame.png")
    assertEquals(click(scene, Vec2(165, 64)), None) // Original 8 + 20 radius hit area.
    assert(!scene.rewardVisible)
    assertEquals(images(scene, "bubble01.png"), Vector.empty)
    assertEquals(images(scene, "frame.png"), before)
    assertEquals(scene.gameMode, BubbleMode.Normal)
    click(scene, outside)
    scene.advance(0.1)
    assert(scene.rewardVisible)
    assert(images(scene, "frame.png").forall(_.rotation == 0))
    assertEquals(click(scene, cardOne), Some(GalleryStart(1, BubbleMode.ExtraBounce)))
    assert(scene.rewardVisible) // Starting a level does not spend the reward.
  }

  test("already straight frames may tilt and only all-aligned targets earn the reward") {
    val draws = Iterator.fill(6)(0.0) ++ Iterator(1.0, 0.0, 0.0, 0.0, 0.0, 0.0) ++ Iterator.continually(0.0)
    val scene = new GalleryScene(() => draws.next())
    click(scene, reward)
    click(scene, outside)
    scene.advance(0.1)
    assert(!scene.rewardVisible)
    assertEquals(images(scene, "frame.png").map(_.rotation), Vector(1.0, 0.0, 0.0, 0.0, 0.0, 0.0))
    click(scene, outside)
    scene.advance(0.1)
    assert(scene.rewardVisible)
    assert(images(scene, "frame.png").forall(_.rotation == 0))
  }

  test("title chalk fades retain 100/255 across gallery entries and dust expires") {
    val scene = new GalleryScene(() => 0)
    scene.advance(0.1)
    click(scene, Vec2(50, 90)) // Only the painted G rectangle contains this point.
    assert(images(scene, "dust.png").nonEmpty)
    assert(images(scene, "dust.png").forall(_.additive))
    scene.advance(0.1)
    close(images(scene, "title_font.png").head.color.alpha, 100.0 / 255.0)
    scene.advance(0.2)
    assertEquals(images(scene, "dust.png"), Vector.empty)
    scene.enter()
    scene.advance(0.1)
    close(images(scene, "title_font.png").head.color.alpha, 100.0 / 255.0)
    click(scene, Vec2(50, 90))
    assertEquals(images(scene, "dust.png"), Vector.empty)
  }

  test("first game completion restores changed title letters and enables infinite mode") {
    val scene = new GalleryScene(() => 0)
    scene.advance(0.1)
    click(scene, Vec2(80, 70)) // Original rectangle hit tests overlap G, r and y.
    scene.advance(0.1)
    val gray = images(scene, "title_font.png")
    Vector(0, 1, 3).foreach(index => close(gray(index).color.alpha, 100.0 / 255.0))
    (1 to 6).foreach(scene.completeLevel)
    scene.enter()
    scene.advance(0.1)
    val glad = images(scene, "title_font2.png")
    close(glad(0).color.alpha, 100.0 / 255.0)
    close(glad(1).color.alpha, 1)
    close(glad(3).color.alpha, 1)
    assertEquals(scene.levelsAchieved, 7)
    assert(scene.completedGame)
    assert(!scene.rewardVisible)
    assertEquals(scene.gameMode, BubbleMode.Infinite)
    click(scene, outside)
    assert(!scene.rewardVisible)
    assertEquals(images(scene, "bubble01.png"), Vector.empty)
    assertEquals(click(scene, cardOne), Some(GalleryStart(1, BubbleMode.Infinite)))
  }

  test("locked paintings cannot launch or preview and a completed level unlocks the next") {
    val scene = new GalleryScene(() => 0)
    assert(scene.levelUnlocked(1))
    assert(!scene.levelUnlocked(2))
    assert(!scene.levelUnlocked(0))
    assert(!scene.levelUnlocked(7))
    scene.pointerDown(cardTwo)
    scene.advance(2)
    assertEquals(scene.previewLevel, None)
    assertEquals(scene.pointerUp(cardTwo), None)
    scene.completeLevel(1)
    assert(scene.levelUnlocked(2))
    assertEquals(images(scene, "level2.png").size, 1)
    assertEquals(click(scene, cardTwo), Some(GalleryStart(2, scene.gameMode)))
  }

  test("one-second hold previews, release keeps it open, and dismissal cannot launch") {
    val scene = new GalleryScene(() => 0)
    scene.pointerDown(cardOne)
    scene.advance(0.99)
    assertEquals(scene.previewLevel, None)
    scene.advance(0.01)
    assertEquals(scene.previewLevel, Some(1))
    scene.advance(0.1)
    val preview = images(scene, "level1-568h.png").head
    assertEquals(preview.quad.destination, Rect(0, 0, 320, 568))
    close(preview.color.alpha, 1)
    assertEquals(scene.commands.last, preview)
    assertEquals(scene.pointerUp(cardOne), None)
    scene.cancelPointer() // Hosts may release capture separately.
    assertEquals(scene.previewLevel, Some(1))
    scene.pointerDown(cardOne)
    assertEquals(scene.previewLevel, None)
    assertEquals(scene.pointerUp(cardOne), None)
    scene.advance(0.1)
    assertEquals(images(scene, "level1-568h.png"), Vector.empty)
    assertEquals(click(scene, cardOne), Some(GalleryStart(1, scene.gameMode)))
  }

  test("all paintings use standard cards and tall previews and gameplay") {
    (1 to 6).foreach { level =>
      val scene = new GalleryScene(() => 0)
      scene.restoreProgress(6, reward = false)
      val page = s"level$level.png"
      val previewPage = s"level$level-568h.png"
      val card = images(scene, page).head
      assertEquals(card.quad.source, Rect(0, 0, 320, 480))
      assertEquals(card.quad.destination.width, 40.0)
      assertEquals(card.quad.destination.height, 60.0)
      assertEquals(GalleryData.paintings(level), page)
      assertEquals(GalleryData.previews(level), previewPage)
      assertEquals(PresentationData.levels(level).painting, TileArt(previewPage, Rect(0, 0, 320, 568)))
      assertEquals(PresentationData.requiredImages.count(_ == previewPage), 1)
      assert(!PresentationData.requiredImages.contains(s"level$level.jpg"))

      scene.pointerDown(card.quad.destination.center)
      scene.advance(1.1)
      val painted = images(scene, previewPage)
      assertEquals(images(scene, page).size, 1)
      assertEquals(painted.size, 1)
      assertEquals(painted.last.quad.source, Rect(0, 0, 320, 568))
      assertEquals(painted.last.quad.destination, Rect(0, 0, 320, 568))
      assertEquals(scene.commands.last, painted.last)
    }
  }

  test("leaving and re-entering a held painting resets its preview deadline") {
    val scene = new GalleryScene(() => 0)
    scene.pointerDown(cardOne)
    scene.advance(0.8)
    scene.pointerMove(outside)
    scene.advance(1)
    assertEquals(scene.previewLevel, None)
    assertEquals(scene.commands.collect { case fill: GalleryDraw.Fill => fill }, Vector.empty)
    scene.pointerMove(cardOne)
    scene.advance(0.99)
    assertEquals(scene.previewLevel, None)
    scene.advance(0.01)
    assertEquals(scene.previewLevel, Some(1))
  }

  test("cancellation clears pending work and a drag cannot select another painting") {
    val scene = new GalleryScene(() => 0)
    scene.completeLevel(1)
    scene.pointerDown(cardOne)
    scene.advance(0.9)
    scene.cancelPointer()
    scene.advance(5)
    assertEquals(scene.previewLevel, None)
    assertEquals(scene.pointerUp(cardOne), None)
    scene.pointerDown(cardOne)
    scene.pointerMove(cardTwo)
    scene.advance(2)
    assertEquals(scene.previewLevel, None)
    assertEquals(scene.pointerUp(cardTwo), None)
    scene.pointerDown(cardOne)
    scene.advance(1)
    assertEquals(scene.previewLevel, Some(1))
    scene.enter()
    assertEquals(scene.previewLevel, None)
    assertEquals(scene.levelsAchieved, 2)
    assertEquals(scene.pointerUp(cardOne), None)
  }
}
