package main

import "core:fmt"
import "core:os"
import "core:strings"
import "core:strconv"
import "core:time"
import "core:time/datetime"

Task :: struct {
    name: string,
    start_date: datetime.DateTime,
    end_date: datetime.DateTime,
}

parse_datetime_string :: proc(datetime_string: string) -> (datetime.DateTime, bool) {
    // TODO: add support for parsing time strings like
    // 2026 (default to 2026-01-01) and 2026-05 (default to 2026-05-01)
    date_elements := strings.split(datetime_string, "-")
    if len(date_elements) != 3 {
        fmt.eprintln("Error: invalid date")
        return datetime.DateTime{}, false
    }
    year, year_ok := strconv.parse_int(date_elements[0])
    month, month_ok := strconv.parse_int(date_elements[1])
    day, day_ok := strconv.parse_int(date_elements[2])

    // TODO: mention specific errors for invalid year/month/day
    if !year_ok || !month_ok || !day_ok {
        fmt.eprintln("Error: invalid date")
        return datetime.DateTime{}, false
    }
    // TODO: add support for passing in hour/min/sec
    // TODO: look into adding TimeZone info (currently stores time as UTC)
    date, err := datetime.components_to_datetime(year, month, day, hour=0, minute=0, second=0)
    if err != nil {
        fmt.eprintln("Error: invalid date:", err)
        return datetime.DateTime{}, false
    }
    return date, true
}

create_task :: proc(name: string, end_date_str: string) -> (task: Task, ok: bool) {
    end_date := parse_datetime_string(end_date_str) or_return

    now := time.now()
    start_date, start_date_ok := time.time_to_datetime(now)
    assert(start_date_ok, "time.now() should be a valid DateTime")

    end_time, end_time_ok := time.datetime_to_time(end_date)
    assert(end_time_ok, "end_date has been validated to be a valid date")
    if time.time_to_unix(end_time) <= time.time_to_unix(now) {
        fmt.eprintln("Error: end date has already passed")
        return Task{}, false
    }

    return Task{name, start_date, end_date}, true
}

get_progress_ratio :: proc(task: Task) -> f64 {
    end_time, end_time_ok := time.datetime_to_time(task.end_date)
    end_time_unix := time.time_to_unix(end_time)
    start_time, start_time_ok := time.datetime_to_time(task.start_date)
    start_time_unix := time.time_to_unix(start_time)
    now := time.time_to_unix(time.now())

    // https://pkg.odin-lang.org/core/time/#Time
    assert(end_time_ok && start_time_ok, "year 2262 problem is still ways off! ...right??...\n")
    return f64(now - start_time_unix)/f64(end_time_unix - start_time_unix)
}

main :: proc() {
    args := os.args[1:]
    if len(args) < 2 {
        fmt.println("Not enough arguments")
        os.exit(1)
    }
    task, ok := create_task(os.args[1], os.args[2])
    if !ok {
        os.exit(1)
    }
    fmt.println("Task created with end date of:", task.end_date.date)

    progress_ratio := get_progress_ratio(task)
    fmt.printf("Done: %.2f%%\n", progress_ratio * 100)
    fmt.printf("Left: %.2f%%\n", (1-progress_ratio) * 100)
}
