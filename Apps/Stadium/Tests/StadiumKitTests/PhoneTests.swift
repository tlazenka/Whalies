// Expected camera timings and geometry follow the deterministic Stadium state.

import Foundation
#if canImport(simd)
import simd
#endif
import Testing
import StadiumCore
import CrowdCore
import StadiumGame
import JSONViewKit
@testable import StadiumKit

@MainActor
private func session() -> StadiumSession {
    let s = StadiumSession()
    s.audioOutput = .off
    s.stop()
    s.reset(to: .stadium)
    s.stop()
    return s
}

@MainActor
private func ticks(_ s: StadiumSession, _ n: Int) { for _ in 0..<n { s.advance() } }

@MainActor
private func happened(_ s: StadiumSession, _ match: (RideEvent) -> Bool) -> Bool { s.snapshot.ride.events.contains(where: match) }

@MainActor
private func leaf(_ item: JSONNode, _ name: String) -> String? {
    guard let properties = item.children.first(where: { $0.name == "properties" }),
          let node = properties.children.first(where: { $0.name == name }) else { return nil }
    switch node.value {
    case .string(let s): return s
    case .number(let n): return n
    default: return nil
    }
}

@MainActor
private func items(_ root: JSONNode) -> [JSONNode] { root.children.first { $0.name == "items" }?.children ?? [] }

@Test
@MainActor
func theScriptedRidesMomentsAndTheirPoints() throws {
    let p = StadiumParameters.stadium
    let snapshots = StadiumScript.recording(kind: .ride, parameters: p).replay()
    var log = MomentLog()
    for s in snapshots { log.observe(s, parameters: p) }
    let m = log.moments
    #expect(m.map(\.kind) == [.bubble, .bounce, .bounce, .bounce, .bounce, .bounce, .bubble, .bounce, .bounce, .shot, .doll, .bubble, .shot, .doll])
    #expect(m.map(\.tick) == [30, 92, 133, 169, 222, 242, 641, 706, 742, 956, 956, 1536, 1851, 1851] && m.map(\.id) == Array(0..<14))
    let bounces = m.filter { $0.kind == .bounce }
    #expect(bounces.map(\.points) == [10, 20, 30, 0, 10, 0, 0] && bounces.map { $0.int("run") } == [1, 2, 3, 0, 1, 0, 0])
    #expect(bounces.map(\.title) == ["Bounce on the beat", "Bounce on the beat \u{00D7}2", "Bounce on the beat \u{00D7}3", "Bounce off the beat",
                                     "Bounce on the beat", "Bounce off the beat", "Bounce off the beat"])
    #expect(bounces.allSatisfy { $0.text("wheel") == "rear right" } && m.filter { $0.kind == .bubble }.allSatisfy { $0.text("pipe") == "right" })
    let last = try #require(snapshots.last)
    #expect(m.reduce(0) { $0 + $1.points } == last.ride.tally.points && last.ride.tally.points == 70)
    #expect(m.prefix(6).allSatisfy { $0.level == .whaley } && m.dropFirst(6).allSatisfy { $0.level == .cannon } && m.allSatisfy { $0.round == 1 })
    let dolls = m.filter { $0.kind == .doll }
    #expect(dolls.map(\.title) == ["Thought \u{00B7} Hot dog served", "Thought \u{00B7} Unwanted hot dog"])
    #expect(dolls[0].details["fan"] == .int(85) && dolls[0].details["garden"] == .flag(true) && dolls[0].details["right"] == .flag(true))
    #expect(dolls[0].details["reaction"] == .number(5.3) && dolls[0].text("item") == "hot dog" && dolls[0].details["beep"] == .int(636))
    #expect(dolls[0].details["requiresHotDog"] == .flag(true) && dolls[0].text("symbol") == ThoughtSymbol.hotDog.label)
    #expect(ThoughtSymbol.allCases.filter { $0 != .hotDog }.map(\.label).contains(dolls[1].text("symbol")))
    #expect(dolls[1].details["requiresHotDog"] == .flag(false) && dolls[1].details["right"] == .flag(false) && dolls[1].details["fan"] == .int(26))
    let shots = m.filter { $0.kind == .shot }
    #expect(shots.map(\.title) == ["A hot dog at fan 85", "A hot dog at fan 26"])
    #expect(shots.map { $0.text("part") } == ["head", "head"] && shots.map { $0.details["metres"] ?? .int(-1) } == [.number(40.4), .number(60.1)])
    let feed = log.feed(number: 1)
    let root = feed.root
    #expect(feed.count == 14 && items(root).count == 14)
    #expect(JSONNode.itemIDs(in: root, from: root) == (0..<14).map { "moment/\($0)" })
    let third = items(root)[3]
    #expect(leaf(third, "title") == "Bounce on the beat \u{00D7}3" && leaf(third, "kind") == "bounce" && leaf(third, "level") == "Whaley 2D")
    #expect(leaf(third, "points") == "30" && leaf(third, "tick") == "169" && leaf(third, "round") == "1" && leaf(third, "wheel") == "rear right")
    #expect(leaf(items(root)[9], "metres").flatMap(Double.init) == 40.4 && leaf(items(root)[10], "result") == "hot dog served")
    let scrubbed = try #require(root.filtering(.minimum(path: "$.properties.points", value: 20, values: [0, 10, 20, 30])))
    #expect(JSONNode.itemIDs(in: scrubbed, from: root) == ["moment/2", "moment/3"])
    let faceted = try #require(root.filtering(fieldName: "kind", categoricalValue: "doll"))
    #expect(JSONNode.itemIDs(in: faceted, from: root) == ["moment/10", "moment/13"])
}

@Test
@MainActor
func theInterludeFliesTheViewIntoHisEyesAndBackWithoutACut() throws {
    let s = session()
    let p = s.parameters
    let size = SIMD2<Float>(390, 844)
    ticks(s, 3905)
    #expect(s.tick == 3905 && s.phone == nil && s.snapshot.ride.interlude.on == nil && s.acceptsStroke)
    var views = [s.tick: s.camera]
    var downs: [Int: Double] = [:], shares: [Int: Double] = [:]
    func step(to t: Int) {
        while s.tick < t {
            ticks(s, 1)
            views[s.tick] = s.camera
            downs[s.tick] = RideRig.phoneDown(s.snapshot, parameters: p)
            shares[s.tick] = RideRig.interludeShare(s.snapshot, parameters: p)
        }
    }
    step(to: 3906)
    let on = try #require(s.snapshot.ride.interlude.on)
    #expect(s.tick == 3906 && on.fan == 153 && on.number == 1 && on.phase == .turningIn)
    let feed = try #require(s.phone)
    let m = s.moments.moments
    #expect(feed.number == 1 && feed.count == 7 && m.count == 7 && items(feed.root).count == 7)
    #expect(m.map(\.kind) == [.doll, .doll, .doll, .lap, .doll, .round, .interlude] && m.map(\.tick) == [996, 1931, 2766, 3467, 3497, 3906, 3906])
    #expect(m.filter { $0.kind == .doll }.map { $0.text("result") } == ["hot dog request missed", "correct hold", "hot dog request missed", "hot dog request missed"])
    #expect(m[3].level == .whaley && m[4].level == .cannon && m[5].level == .interlude && m[6].title == "Interlude 1 \u{00B7} fan 153 on his phone")
    let round = m[5]
    #expect(round.title == "Round 1 \u{00B7} 0 points" && round.round == 1 && round.int("dolls") == 4 && round.int("calledRight") == 1)
    #expect(round.points == 0 && round.int("total") == 0, "its points its total, so the moments' add up to the tally's")
    #expect(round.int("calledWrong") == 3 && round.details["length"] == .number(65.1))
    #expect(feed.cards.map(\.id) == ["round-points", "round-dolls", "round-game"])
    #expect(feed.cards[0].eyebrow == "Round 1" && feed.cards[0].value == "0 points" && feed.cards[0].detail == "and not a bounce this time round")
    #expect(feed.cards[1].value == "1 of 4 called right" && feed.cards[1].detail == "3 hot dog requests missed, 1 correct hold")
    #expect(feed.cards[2].value == "0 points" && feed.cards[2].detail == "1 round, 1 lap")
    #expect(!s.fingerBegan(at: CGPoint(x: 100, y: 700)) && !s.acceptsStroke)
    #expect(RideRig.jumbotron(s.snapshot, parameters: p) == .fan && s.crewLive != nil)
    let fan = s.game.figures[153]
    let head = SceneMapping.scene(fan.head)
    let bowed = RideRig.lookingDown(RideRig.pose(fan, state: .seated))
    let ride = Cameras.rideView(s.snapshot, parameters: p)
    step(to: 3994)
    #expect((3906...3911).allSatisfy { views[$0] == ride } && views[3912] != ride, "the ride's view held, then off")
    #expect(RideRig.interludeShare(s.snapshot, parameters: p) == 1)
    for t in 3912...3962 {
        let v = try #require(views[t]?.project(head, viewSize: size), "his head ahead of the view at \(t)")
        #expect(v.x >= 0 && v.x <= 390 && v.y >= 0 && v.y <= 844, "his head on the view at \(t): \(v)")
    }
    let middle = try #require(views[3936]?.project(head, viewSize: size))
    #expect(abs(Double(middle.x) - 195) < 1, "the view on him on the way, his head across its middle")
    let nearest = (3906...3994).compactMap { views[$0] }.map { simd_length($0.position - bowed.head) }.min() ?? 0
    #expect(nearest > 0.28, "never into his head: \(nearest)")
    #expect(shares[3906].map { $0 > 0 && $0 < 0.1 } == true && shares[3911] == 1 && (3911...3994).allSatisfy { shares[$0] == 1 })
    #expect((3906...3985).allSatisfy { downs[$0] == 1 } && (3986...3994).allSatisfy { t in downs[t].map { $0 > 0 && $0 < 1 } == true })
    #expect((3986..<3994).allSatisfy { t in (downs[t] ?? 0) > (downs[t + 1] ?? 1) } && abs((downs[3990] ?? 0) - 0.5) < 1e-6)
    step(to: 3995)
    let browsing = try #require(s.snapshot.ride.interlude.on)
    #expect(browsing.isBrowsing && browsing.left == 0 && RideRig.phoneDown(s.snapshot, parameters: p) == 0)
    let eyes = s.camera
    #expect(eyes == Cameras.eyes(on: fan, parameters: p))
    #expect(abs(Double(simd_length(eyes.position - bowed.head)) - 0.2807) < 0.001, "three centimetres out from his face")
    let level = simd_normalize(SIMD3<Float>(eyes.forward.x, 0, eyes.forward.z))
    #expect(simd_dot(level, RideRig.facing(fan)) > 0.9999, "along his facing")
    #expect(abs(Double(eyes.forward.y) + 0.4226) < 0.001, "25 degrees down")
    #expect(simd_dot(bowed.head - eyes.position, eyes.forward) < 0)
    #expect((eyes.project(RideRig.phoneInHand(bowed).phone, viewSize: size)?.y ?? 9999) > 844)
    step(to: 4055)
    #expect(s.snapshot.ride.interlude.on?.isBrowsing == true && s.camera == eyes)
    let shot = try #require(RideRig.liveShot(s.snapshot, figures: s.game.figures, parameters: p, flight: s.lastFlight))
    #expect(shot.parts(.phone).count >= 1 && shot.parts(.head).count == 1 && !shot.parts(.torso).isEmpty && shot.parts(.hand).count == 1)
    #expect(RideRig.onHisPhone(s.snapshot, figure: 153) && !RideRig.onHisPhone(s.snapshot, figure: 152))
    step(to: 4414)
    s.phoneDone()
    step(to: 4415)
    #expect(happened(s) { if case .fired(.hotDog, 153, 0, _) = $0 { true } else { false } } && s.lastFlight?.item == .hotDog)
    let caught = try #require(s.moments.moments.last)
    #expect(caught.kind == .shot && caught.level == .interlude && caught.round == 1 && caught.title == "The hot dog for fan 153")
    #expect(caught.details["metres"] == .number(107.3))
    let flight = try #require(s.lastFlight)
    step(to: 4565)
    let atShot = try #require(views[4415])
    #expect(atShot.position == eyes.position && simd_dot(atShot.forward, eyes.forward) > 0.99999, "his eyes, on his phone, at the shot")
    #expect((3995...4415).allSatisfy { downs[$0] == 0 } && abs((downs[4419] ?? 0) - 0.5) < 1e-6 && (4423...4564).allSatisfy { downs[$0] == 1 })
    #expect((3995...4556).allSatisfy { shares[$0] == 1 } && abs((shares[4561] ?? 0) - 0.5) < 1e-6 && downs[4565] == nil && shares[4565] == 0)
    let muzzle = try #require(views[4427]?.project(Cameras.muzzle(s.snapshot.car, parameters: p), viewSize: size))
    #expect(abs(Double(muzzle.x) - 195) < 1 && abs(Double(muzzle.y) - 422) < 1, "his eyes on the cannon: \(muzzle)")
    let seen = (0..<20).filter { t in
        let k = Float(t) / 20
        let dog = flight.from + (flight.to - flight.from) * k + SIMD3(0, 2.5 * k * (1 - k), 0)
        guard let v = views[4415 + t]?.project(dog, viewSize: size) else { return false }
        return v.x >= 0 && v.x <= 390 && v.y >= 0 && v.y <= 844
    }
    #expect(seen.count >= 12 && seen.last == 19, "the hot dog coming at him on the view: \(seen)")
    let front = try #require(views[4486])
    let him = try #require(front.project(head, viewSize: size))
    #expect(abs(Double(him.x) - 195) < 20 && abs(Double(simd_length(front.position - head)) - 4.5) < 0.2, "facing him from the front: \(him)")
    #expect((4557...4565).allSatisfy { views[$0] == ride } && views[4556] != ride, "back to the ride's view, held, and on as it was")
    for t in 3905..<4565 {
        let a = try #require(views[t]), b = try #require(views[t + 1])
        #expect(simd_length(b.position - a.position) < 3.5 && simd_dot(a.forward, b.forward) > 0.99452, "the step into \(t + 1)")
    }
    #expect(s.tick == 4565 && s.phone == nil && s.snapshot.ride.interlude.on == nil)
    #expect(RideRig.jumbotron(s.snapshot, parameters: p) != .fan && s.crewLive == nil && s.acceptsStroke)
}

@Test
@MainActor
func theFansMomentsOnThePhoneAreHisToReviewTheNextTimeRound() throws {
    let s = session()
    s.setRepeat(.interlude)
    s.setParked(true)
    ticks(s, 1)
    #expect(s.tick == 1 && s.snapshot.ride.interlude.on?.number == 1 && s.phone?.number == 1)
    #expect(s.moments.moments.map(\.kind) == [.round, .interlude] && s.phone?.count == 2)
    #expect(s.phone?.cards.map(\.id) == ["round-points", "round-dolls", "round-game"])
    ticks(s, 100 - s.tick)
    #expect(s.snapshot.ride.interlude.on?.isBrowsing == true)
    s.phoneTouch(.began, at: CGPoint(x: 100, y: 200))
    ticks(s, 10)
    s.phoneTouch(.moved, at: CGPoint(x: 100, y: 230))
    s.phoneTouch(.moved, at: CGPoint(x: 100, y: 260))
    ticks(s, 5)
    s.phoneTouch(.ended, at: CGPoint(x: 100, y: 260))
    s.phoneTouch(.began, at: CGPoint(x: 50, y: 50))
    s.phoneTouch(.began, at: CGPoint(x: 60, y: 60))
    s.phoneTouch(.ended, at: CGPoint(x: 50, y: 50))
    s.phoneRecorded("filter_changed", ["path": "$.properties.points", "kind": "numeric", "value": 10.0])
    s.phoneRecorded("filter_finished", ["path": "$.properties.points", "kind": "numeric", "value": 10.0, "description": "points \u{2265} 10",
                                        "resultsAfter": 0, "source": "touch"])
    s.phoneRecorded("filter_suggestion_selected", ["fieldName": "kind", "value": "round", "source": "field_name_value_tokens", "resultsAfter": 1])
    s.phoneTabbed(.wrapped)
    s.phoneTabbed(.wrapped)
    s.phoneTouch(.began, at: CGPoint(x: 120, y: 300))
    ticks(s, 40)
    s.phoneTouch(.ended, at: CGPoint(x: 122, y: 301))
    #expect(s.snapshot.ride.interlude.on?.isBrowsing == true, "touches, filtering and tabs leave the phone open")
    let phone = s.moments.phoneMoments(1)
    #expect(phone.map(\.kind) == [.touch, .touch, .scrub, .facet, .tab, .touch])
    #expect(phone.map(\.title) == ["A swipe on the phone", "A tap on the phone", "Scrubbed points \u{2265} 10", "Faceted kind = round", "Opened Wrapped",
                                   "A press on the phone"])
    #expect(phone.map(\.tick) == [115, 115, 115, 115, 115, 155] && phone.allSatisfy { $0.level == .interlude && $0.round == 1 && $0.points == 0 })
    #expect(phone[0].details["travel"] == .int(60) && phone[0].details["heldFor"] == .number(0.3) && phone[0].text("tab") == "Stats")
    #expect(phone[1].details["travel"] == .int(0) && phone[1].text("gesture") == "tap")
    #expect(phone[2].details["results"] == .int(0) && phone[2].text("path") == "$.properties.points" && phone[3].details["results"] == .int(1))
    #expect(phone[5].text("tab") == "Wrapped" && phone[5].details["travel"] == .int(2) && phone[5].details["heldFor"] == .number(0.7))
    ticks(s, 509 - s.tick)
    s.phoneDone()
    ticks(s, 780 - s.tick)
    #expect(s.tick == 780 && s.snapshot.ride.interlude.on?.number == 2)
    let feed = try #require(s.phone)
    #expect(feed.number == 2 && feed.count == 12 && s.moments.moments.count == 12)
    #expect(s.moments.moments.map(\.kind) == [.round, .interlude, .touch, .touch, .scrub, .facet, .tab, .touch, .done, .shot, .round, .interlude])
    #expect(s.moments.moments[10].details["length"] == .number(2.0) && s.moments.moments[10].round == 2)
    #expect(feed.cards.map(\.id) == ["round-points", "round-dolls", "round-phone", "round-game"])
    let last = try #require(feed.cards.first { $0.id == "round-phone" })
    #expect(last.eyebrow == "Last time on the phone" && last.value == "3 touches" && last.detail == "1 scrub and 1 facet, selected Done to continue")
    #expect(feed.cards[0].eyebrow == "Round 2" && feed.cards.last?.detail == "2 rounds, 0 laps")
    let root = feed.root
    let touches = try #require(root.filtering(fieldName: "kind", categoricalValue: "touch"))
    #expect(JSONNode.itemIDs(in: touches, from: root) == ["moment/2", "moment/3", "moment/7"])
    let far = try #require(root.filtering(.minimum(path: "$.properties.travel", value: 50, values: [0, 2, 60])))
    #expect(JSONNode.itemIDs(in: far, from: root) == ["moment/2"])
    ticks(s, 781 - s.tick)
    s.phoneDone()
    #expect(s.moments.moments.count == 12)
    ticks(s, 920 - s.tick)
    #expect(s.snapshot.ride.interlude.on?.isBrowsing == true)
    s.phoneDone()
    s.phoneDone()
    let done = try #require(s.moments.moments.last)
    #expect(s.moments.moments.count == 13 && done.kind == .done && done.round == 2 && done.level == .interlude && done.tick == 920)
    #expect(done.title == "Finished exploring" && done.details.isEmpty)
    ticks(s, 1)
    #expect(s.recording.inputs.last?.done == true && happened(s) { if case .fired(.hotDog, 153, 0, _) = $0 { true } else { false } })
    #expect(s.snapshot.ride.interlude.on?.phase == .catchWatched && s.snapshot.ride.interlude.on?.shot == 921)
    ticks(s, 1071 - s.tick)
    #expect(s.snapshot.ride.interlude.on == nil && s.phone == nil && s.recording.inputs.filter(\.done).count == 2)
    let next = try #require(s.moments.cards(round: 3).first { $0.id == "round-phone" })
    #expect(next.value == "Not a touch" && next.detail == "the phone sat in his hands, selected Done to continue")
    s.reset(to: .stadium)
    s.stop()
    #expect(s.moments.moments.isEmpty && s.phone == nil)
}

@Test
@MainActor
func thePhoneIsDirectlyAheadOfHisEyes() {
    let phone = RideRig.phoneFrame(viewSize: SIMD2(390, 844))
    #expect(phone.centre.x == 195 && phone.screen.width == 280 && abs(phone.screen.height - 497) < 1e-9)
    #expect(abs(phone.centre.y - 506.4) < 1e-9 && abs(phone.top - 242.9) < 1e-9)
    let short = RideRig.phoneFrame(viewSize: SIMD2(375, 667))
    #expect(abs(short.screen.height - 430.25) < 1e-9 && abs(short.top - 166.75) < 1e-9)
    #expect(abs(short.centre.y + short.screen.height / 2 + 15 - 627) < 1e-9)
    let pad = RideRig.phoneFrame(viewSize: SIMD2(1024, 1366))
    #expect(pad.centre.x == 512 && pad.screen.width == 300 && pad.screen.height == 532.5 && abs(pad.centre.y - 819.6) < 1e-9)
    let small = RideRig.phoneFrame(viewSize: SIMD2(420, 820))
    #expect(small.screen.width == 300 && abs(small.centre.y - 492) < 1e-9 && abs(small.top - 210.75) < 1e-9)
    let wide = RideRig.phoneFrame(viewSize: SIMD2(1366, 1024))
    #expect(wide.centre.x == 683 && wide.screen.width == 300 && abs(wide.centre.y - 614.4) < 1e-9 && abs(wide.top - 333.15) < 1e-9)
}

/// Minimum distance between limb centreline segments; zero at intersections.
@MainActor
private func gap(_ a: RideRig.Limb, _ b: RideRig.Limb) -> Double {
    typealias V = SIMD2<Double>
    let p = V(Double(a.from.x), Double(a.from.y)), q = V(Double(a.to.x), Double(a.to.y))
    let r = V(Double(b.from.x), Double(b.from.y)), s = V(Double(b.to.x), Double(b.to.y))
    func cross(_ u: V, _ v: V) -> Double { u.x * v.y - u.y * v.x }
    func toSegment(_ x: V, _ a: V, _ b: V) -> Double {
        let d = b - a, len2 = (d * d).sum()
        let t = len2 > 0 ? max(0, min(1, ((x - a) * d).sum() / len2)) : 0
        let e = x - (a + d * t)
        return (e * e).sum().squareRoot()
    }
    let d1 = cross(q - p, r - p), d2 = cross(q - p, s - p), d3 = cross(s - r, p - r), d4 = cross(s - r, q - r)
    if d1 * d2 < 0 && d3 * d4 < 0 { return 0 }
    return min(toSegment(p, r, s), toSegment(q, r, s), toSegment(r, p, q), toSegment(s, p, q))
}

// Every limb must connect, through other limbs, to an offscreen forearm.
@MainActor
private func attached(_ limbs: [RideRig.Limb], view: CGSize) -> Bool {
    func off(_ p: CGPoint) -> Bool { p.x < 0 || p.y < 0 || p.x > view.width || p.y > view.height }
    var reached = Set(limbs.indices.filter { off(limbs[$0].from) || off(limbs[$0].to) })
    var grew = true
    while grew {
        grew = false
        for i in limbs.indices where !reached.contains(i) {
            let joined = reached.contains { j in
                gap(limbs[i], limbs[j]) <= max(limbs[i].fromRadius, limbs[i].toRadius) + max(limbs[j].fromRadius, limbs[j].toRadius)
            }
            if joined { reached.insert(i); grew = true }
        }
    }
    return !reached.isEmpty && reached.count == limbs.count
}

@Test
@MainActor
func theFansFingerFollowsYoursOnAHandAndAnArm() {
    let screen = CGSize(width: 280, height: 497)
    let rest = RideRig.handRest(screen: screen)
    #expect(abs(Double(rest.x) - 218.4) < 1e-9 && abs(Double(rest.y) - 539.72) < 1e-9)
    func near(_ a: CGPoint, _ x: Double, _ y: Double) -> Bool { abs(Double(a.x) - x) < 1e-9 && abs(Double(a.y) - y) < 1e-9 }
    var hand = RideRig.PhoneHand()
    #expect(hand.tip(at: 0, rest: rest).point == rest && !hand.tip(at: 0, rest: rest).pressed)
    hand.touch(.began, at: CGPoint(x: 100, y: 200), tick: 10, rest: rest)
    #expect(hand.tip(at: 10, rest: rest).point == rest && !hand.tip(at: 14, rest: rest).pressed)
    #expect(near(hand.tip(at: 15, rest: rest).point, 100, 200) && hand.tip(at: 15, rest: rest).pressed)
    hand.touch(.moved, at: CGPoint(x: 120, y: 260), tick: 16, rest: rest)
    #expect(near(hand.tip(at: 16, rest: rest).point, 120, 260) && hand.tip(at: 16, rest: rest).pressed)
    hand.touch(.ended, at: CGPoint(x: 120, y: 260), tick: 20, rest: rest)
    #expect(hand.tip(at: 38, rest: rest).point == CGPoint(x: 120, y: 260) && !hand.tip(at: 38, rest: rest).pressed)
    #expect(near(hand.tip(at: 50, rest: rest).point, 169.2, 399.86) && near(hand.tip(at: 62, rest: rest).point, 218.4, 539.72))
    hand.touch(.began, at: CGPoint(x: 50, y: 60), tick: 50, rest: rest)
    #expect(near(hand.tip(at: 50, rest: rest).point, 169.2, 399.86) && near(hand.tip(at: 55, rest: rest).point, 50, 60))
    let view = CGSize(width: 390, height: 844)
    let frame = RideRig.phoneFrame(viewSize: SIMD2(390, 844))
    let hands = RideRig.fanHands(frame: frame, offset: 0, viewSize: SIMD2(390, 844), tip: CGPoint(x: 140, y: 248.5), pressed: true)
    #expect(near(hands.tip, 195, 506.4) && hands.pressed && abs(hands.unit - 30.8) < 1e-9)
    #expect(hands.over.last.map { near($0.to, 195, 506.4) } == true, "the forefinger the last piece, its tip on the finger")
    #expect(hands.over.count == 8 && hands.behind.count == 2)
    #expect(hands.over[1].to.x > 390 && hands.over[1].to.y > 844 && hands.behind[0].to.x < 0 && hands.behind[0].to.y > 844)
    #expect(attached(hands.behind + hands.over, view: view), "nothing disembodied")
    let resting = RideRig.fanHands(frame: frame, offset: 0, viewSize: SIMD2(390, 844), tip: rest, pressed: false)
    #expect(Double(resting.tip.y) > Double(frame.centre.y) + Double(frame.screen.height) / 2 + 15 && !resting.pressed)
    #expect(attached(resting.behind + resting.over, view: view))
    let lower = RideRig.fanHands(frame: frame, offset: 100, viewSize: SIMD2(390, 844), tip: rest, pressed: false)
    #expect(abs(Double(lower.tip.y - resting.tip.y) - 100) < 1e-9 && abs(Double(lower.behind[1].to.y - resting.behind[1].to.y) - 100) < 1e-9)
    let pad = RideRig.phoneFrame(viewSize: SIMD2(1024, 1366))
    let big = RideRig.fanHands(frame: pad, offset: 0, viewSize: SIMD2(1024, 1366), tip: CGPoint(x: 10, y: 10), pressed: true)
    #expect(abs(big.unit - 33) < 1e-9 && attached(big.behind + big.over, view: CGSize(width: 1024, height: 1366)))
}
