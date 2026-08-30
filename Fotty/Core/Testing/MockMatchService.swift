import Foundation

class MockMatchService {
    static let shared = MockMatchService()
    
    func getMockFixture(id: String = "fixture-001") -> ArenaFixture {
        ArenaFixture(
            id: id,
            homeTeam: ArenaTeam(id: "t1", name: "Real Madrid", shortName: "RMA", badgeURL: URL(string: "https://example.com/madrid.png")),
            awayTeam: ArenaTeam(id: "t2", name: "Barcelona", shortName: "BAR", badgeURL: URL(string: "https://example.com/barca.png")),
            status: .live,
            startTime: Date().addingTimeInterval(-3600),
            score: ArenaMatchScore(home: 2, away: 1),
            venue: "Santiago Bernabéu",
            competition: "La Liga",
            matchMinute: 68
        )
    }
    
    func getMockEvents() -> [ArenaMatchEvent] {
        [
            ArenaMatchEvent(id: "e1", minute: 12, type: .goal, teamId: "t1", playerName: "Vinícius Jr", detail: "Assist by Bellingham"),
            ArenaMatchEvent(id: "e2", minute: 34, type: .yellowCard, teamId: "t2", playerName: "Gavi", detail: "Late challenge"),
            ArenaMatchEvent(id: "e3", minute: 45, type: .goal, teamId: "t2", playerName: "Lewandowski", detail: "Penalty"),
            ArenaMatchEvent(id: "e4", minute: 55, type: .goal, teamId: "t1", playerName: "Rodrygo", detail: "Solo run"),
            ArenaMatchEvent(id: "e5", minute: 62, type: .substitution, teamId: "t1", playerName: "Joselu", detail: "In for Bellingham")
        ]
    }
    
    func getMockMessages() -> [ArenaChatEntry] {
        [
            ArenaChatEntry(id: "m1", userId: "u1", username: "Madridista4Life", text: "HALA MADRID!!! What a goal by Rodrygo!", timestamp: Date().addingTimeInterval(-300), avatarURL: nil, isPinned: false),
            ArenaChatEntry(id: "m2", userId: "u2", username: "BarcaFan88", text: "That was never a foul in the buildup. Robbery.", timestamp: Date().addingTimeInterval(-240), avatarURL: nil, isPinned: false),
            ArenaChatEntry(id: "m3", userId: "u3", username: "TacticsMaster", text: "Ancelotti's midfield diamond is working perfectly today.", timestamp: Date().addingTimeInterval(-180), avatarURL: nil, isPinned: true),
            ArenaChatEntry(id: "m4", userId: "u4", username: "GoalAlert", text: "Goal! Rodrygo puts Madrid ahead again!", timestamp: Date().addingTimeInterval(-600), avatarURL: nil, isPinned: false)
        ]
    }
    
    func getMockPoll() -> ArenaPoll {
        ArenaPoll(
            id: "p1",
            question: "Who was the Man of the Match so far?",
            options: [
                ArenaPoll.PollOption(id: "o1", text: "Rodrygo", voteCount: 1250),
                ArenaPoll.PollOption(id: "o2", text: "Vinícius Jr", voteCount: 840),
                ArenaPoll.PollOption(id: "o3", text: "Lewandowski", voteCount: 450)
            ],
            totalVotes: 2540,
            expiresAt: Date().addingTimeInterval(3600)
        )
    }
    
    func getMockReactions() -> [ArenaReaction] {
        [
            ArenaReaction(id: "r1", emoji: "🔥", count: 156, isSelectedByMe: true),
            ArenaReaction(id: "r2", emoji: "😮", count: 42, isSelectedByMe: false),
            ArenaReaction(id: "r3", emoji: "👏", count: 89, isSelectedByMe: false),
            ArenaReaction(id: "r4", emoji: "😤", count: 23, isSelectedByMe: false)
        ]
    }
    
    func getMockStory() -> ArenaMatchStory {
        ArenaMatchStory(
            summary: "A thrilling Clásico at the Bernabéu saw Real Madrid edge past Barcelona. Madrid took an early lead through Vinícius Jr, but Barcelona fought back with a Lewandowski penalty. Ultimately, Rodrygo's second-half brilliance secured the three points for the hosts.",
            keyTakeaway: "Madrid's clinical finishing made the difference in a balanced encounter."
        )
    }
}
