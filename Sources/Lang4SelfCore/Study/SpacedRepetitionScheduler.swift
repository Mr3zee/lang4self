import Foundation

public enum SpacedRepetitionScheduler {
    public static func reviewed(
        _ original: PersonalCard,
        rating: ReviewRating,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> PersonalCard {
        var card = original
        card.lastReviewedAt = now

        switch rating {
        case .again:
            card.repetitions = 0
            card.lapses += 1
            card.intervalDays = 10.0 / (24 * 60) // relearn in ten minutes
            card.easeFactor = max(1.3, card.easeFactor - 0.20)
        case .hard:
            card.repetitions += 1
            card.intervalDays = max(1, max(card.intervalDays, 1) * 1.2)
            card.easeFactor = max(1.3, card.easeFactor - 0.15)
        case .good:
            if card.repetitions == 0 {
                card.intervalDays = 1
            } else if card.repetitions == 1 {
                card.intervalDays = 6
            } else {
                card.intervalDays = max(1, card.intervalDays * card.easeFactor)
            }
            card.repetitions += 1
        case .easy:
            if card.repetitions == 0 {
                card.intervalDays = 4
            } else {
                card.intervalDays = max(4, card.intervalDays * card.easeFactor * 1.3)
            }
            card.repetitions += 1
            card.easeFactor = min(3.0, card.easeFactor + 0.15)
        }

        card.dueAt = calendar.date(byAdding: .minute, value: Int(card.intervalDays * 24 * 60), to: now) ?? now
        return card
    }
}
