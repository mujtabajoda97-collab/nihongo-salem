/// Local calendar date as `yyyy-MM-dd`. Used for the daily call quota and streaks.
String dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// The calendar day before [d] (safe across daylight-saving changes).
DateTime previousDay(DateTime d) => DateTime(d.year, d.month, d.day - 1);

/// `HH:mm`, the format of {{LOCAL_TIME}} in the free-talk prompt.
String hhmm(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
