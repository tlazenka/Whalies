package whaley.core

class GameInfoSuite extends munit.FunSuite:
  test("The shared name is available to every game platform"):
    assertEquals(GameInfo.name, "Gray Whale")
    assertEquals(GameInfo.completedName, "Glad Whale")
