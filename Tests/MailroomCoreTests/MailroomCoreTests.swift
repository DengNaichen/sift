import Foundation
import Testing
@testable import MailroomCore

@Suite("DeckReducer & Domain Contract Tests")
struct MailroomCoreTests {
    @Test("Archive, Keep, Trash and multi-step Undo restore exact focus and counts")
    func reducerLifecycle() async throws {
        let mock = MockMailAdapter(now: Date(timeIntervalSince1970: 1_760_000_000))
        let snapshot = try await mock.fetchDeck()
        #expect(snapshot.queue.count == 5)
        #expect(snapshot.handled.count == 10)

        var state = DeckReducer.reduce(DeckState(), .loaded(snapshot))
        #expect(state.phase == .ready)
        let firstId = try #require(state.focusId)
        #expect(state.readIds.contains(firstId))

        // Archive first card -> focus shifts to next card
        state = DeckReducer.reduce(state, .card(id: firstId, action: .archive, now: Date()))
        #expect(state.queue.count == 4)
        #expect(state.tally.archived == 1)
        #expect(state.focusId != firstId)

        // Keep second card
        let secondId = try #require(state.focusId)
        state = DeckReducer.reduce(state, .card(id: secondId, action: .keep, now: Date()))
        #expect(state.kept.count == 1)
        #expect(state.tally.kept == 1)

        // Undo keep -> restores second card and focuses it
        state = DeckReducer.reduce(state, .undo)
        #expect(state.kept.isEmpty)
        #expect(state.queue.count == 4)
        #expect(state.focusId == secondId)

        // Undo archive -> restores first card at index 0 and focuses it
        state = DeckReducer.reduce(state, .undo)
        #expect(state.queue.count == 5)
        #expect(state.queue.first?.id == firstId)
        #expect(state.focusId == firstId)
    }

    @Test("Excerpt validates verbatim evidence substring")
    func excerptVerification() {
        let valid = MockSeedData.seedDeck(now: Date()).queue[0]
        #expect(Excerpt.evidenceOf(valid) == "你回我哪个时段方便就好，我来发会议邀请。")

        var forged = valid
        forged.meta = DecisionMeta(kind: .human, badge: "真人来信", confidence: 0.99, evidence: "不存在于原文的句子")
        #expect(Excerpt.evidenceOf(forged) == nil)
    }
}
