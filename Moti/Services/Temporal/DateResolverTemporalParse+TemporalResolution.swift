import Foundation

// Converts a [TemporalResolution] array (from the new layer) into the DateResolver.TemporalParse
// format that RuleBasedTaskUnderstandingService expects.
// When a calendarDate and a clockTime co-exist, the hour/minute from clockTime is applied
// to the calendar date to produce a fully-specified scheduled moment.
extension DateResolver.TemporalParse {
    init(from resolutions: [TemporalResolution], input: String) {
        let now = Date.now

        let usable = resolutions.filter {
            $0.interpretation != .unknown && $0.resolverPath != .noSignal
        }

        guard !usable.isEmpty else {
            self = DateResolver.resolveTemporal(in: input)
            return
        }

        let dateRes     = usable.first { $0.interpretation == .calendarDate }
        let durationRes = usable.first { $0.interpretation == .relativeDuration }
        let clockRes    = usable.first { $0.interpretation == .clockTime }

        if let dateRes, let date = dateRes.resolvedDate {
            var finalDate = date
            if let clockRes, let clockComps = clockRes.resolvedClockTime,
               let hour = clockComps.hour {
                let cal = Calendar.current
                var comps = cal.dateComponents([.year, .month, .day], from: date)
                comps.hour = hour
                comps.minute = clockComps.minute ?? 0
                comps.second = 0
                finalDate = cal.date(from: comps) ?? date
            }
            self.init(
                dueDate: finalDate,
                dueLabel: dateRes.originalText,
                workingStartDate: now,
                workingEndDate: finalDate,
                isVague: false,
                hasTimeInformation: true
            )

        } else if let durationRes, let duration = durationRes.resolvedDuration {
            let date = Date(timeInterval: duration, since: now)
            self.init(
                dueDate: date,
                dueLabel: durationRes.originalText,
                workingStartDate: now,
                workingEndDate: date,
                isVague: false,
                hasTimeInformation: true
            )

        } else {
            // clockTime-only or unresolvable — let DateResolver handle the compound expression
            self = DateResolver.resolveTemporal(in: input)
        }
    }
}
