import Foundation

extension L10n {
    static var calendarEventFilters: String { localized("Event Filters") }
    static var calendarEventFiltersDescription: String {
        localized("Hide events from Home and calendar notifications when they match any selected condition.")
    }

    static var calendarFilterAllDayEvents: String { localized("All-day events") }
    static var calendarFilterAllDayEventsDescription: String { localized("Hide events marked as all-day.") }
    static var calendarFilterUserOnlyEvents: String { localized("Events with only you") }
    static var calendarFilterUserOnlyEventsDescription: String { localized("Hide events with no attendees other than you.") }
    static var calendarFilterEventsWithoutMeetingURL: String { localized("Events without a meeting URL") }
    static var calendarFilterEventsWithoutMeetingURLDescription: String {
        localized("Hide events that do not include a supported meeting URL.")
    }

    static var calendarFilterDeclinedEvents: String { localized("Declined events") }
    static var calendarFilterDeclinedEventsDescription: String { localized("Hide events you declined.") }
    static var calendarFilterOutOfOfficeEvents: String { localized("OOO / OOTO events") }
    static var calendarFilterOutOfOfficeEventsDescription: String {
        localized("Hide out-of-office events and events whose title includes OOO or OOTO.")
    }

    static var calendarNoEventsMatchFiltersTitle: String { localized("No events match your filters") }
    static var calendarNoEventsMatchFiltersMessage: String {
        localized("Upcoming events were found, but all of them are hidden by your event filters.")
    }
}
