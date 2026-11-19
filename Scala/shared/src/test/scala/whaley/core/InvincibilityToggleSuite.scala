package whaley.core

class InvincibilityToggleSuite extends munit.FunSuite:
  test("the host star stays clickable outside the game letterbox after resizing"):
    val portraitCenter = Vec2(290, 538)
    assert(InvincibilityToggle.contains(portraitCenter, 320, 568))
    val landscapeCenter = Vec2(1250, 690)
    assertEquals(Viewport(1280, 720, 0).toWorld(landscapeCenter), None)
    assert(InvincibilityToggle.contains(landscapeCenter, 1280, 720))
    assert(!InvincibilityToggle.contains(portraitCenter, 1280, 720))

  test("the star consumes only its visible window target"):
    assert(InvincibilityToggle.contains(Vec2(268, 516), 320, 568))
    assert(InvincibilityToggle.contains(Vec2(311, 559), 320, 568))
    assert(!InvincibilityToggle.contains(Vec2(267, 538), 320, 568))
    assert(!InvincibilityToggle.contains(Vec2(312, 538), 320, 568))
    assert(!InvincibilityToggle.contains(Vec2(290, 560), 320, 568))
    assert(!InvincibilityToggle.contains(Vec2(Double.NaN, 538), 320, 568))
    assert(!InvincibilityToggle.contains(Vec2(290, 538), 0, 0))
    assert(!InvincibilityToggle.contains(Vec2(290, 538), Double.PositiveInfinity, 568))
