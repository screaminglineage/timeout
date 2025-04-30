package main

import "base:intrinsics"
import "core:encoding/cbor"
import "core:fmt"
import "core:flags"
import "core:os"
import "core:reflect"
import "core:strconv"
import "core:strings"
import "core:time"
import "core:time/datetime"

// TODO: grab from an environment variable
TASKS_FILE_PATH :: "timeout-tasks.cbor"

parse_datetime_string :: proc(datetime_string: string) -> (datetime.DateTime, bool) {
    // TODO: add support for parsing time strings like
    // 2026 (default to 2026-01-01) and 2026-05 (default to 2026-05-01)
    date_elements := strings.split(datetime_string, "-")
    defer delete(date_elements)
    if len(date_elements) != 3 {
        fmt.eprintln("Error: invalid date")
        return datetime.DateTime{}, false
    }

    // TODO: could add support for formats like `2025-jan` and `14[th] jan 2025` (?)
    year, year_ok := strconv.parse_int(date_elements[0])
    month, month_ok := strconv.parse_int(date_elements[1])
    day, day_ok := strconv.parse_int(date_elements[2])

    // TODO: mention specific errors for invalid year/month/day
    if !year_ok || !month_ok || !day_ok {
        fmt.eprintln("Error: invalid date")
        return datetime.DateTime{}, false
    }
    // TODO: add support for passing in hour/min/sec
    // TODO: look into adding TimeZone info (currently only supports UTC)
    date, err := datetime.components_to_datetime(year, month, day, hour=0, minute=0, second=0)
    if err != nil {
        fmt.eprintln("Error: invalid date:", err)
        return datetime.DateTime{}, false
    }
    return date, true
}

Task :: struct {
    name: string,
    start_date: datetime.DateTime,
    end_date: datetime.DateTime,
}

// Temporary function for testing
task_new :: proc(name: string, start_date: datetime.Date, end_date: datetime.Date) -> Task {
    return Task {
        name = name,
        start_date = {start_date, datetime.Time{}, nil},
        end_date = {end_date, datetime.Time{}, nil}
    }
}

task_create :: proc(name: string, end_date_str: string) -> (task: Task, ok: bool) {
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

task_get_progress :: proc(task: Task) -> (ratio_done: f64, duration_left: datetime.Delta) {
    panic_msg :: "dates are supposed to be valid"

    t1 := time.datetime_to_time(task.start_date) or_else panic(panic_msg)
    t2 := time.datetime_to_time(task.end_date)   or_else panic(panic_msg)
    ratio_done = f64(time.since(t1)) / f64(time.diff(t1, t2))

    now           := time.time_to_datetime(time.now()) or_else panic(panic_msg)
    left          := datetime.sub(task.end_date, now)  or_else panic(panic_msg)
    duration_left = datetime.normalize_delta(left)     or_else panic(panic_msg)
    return
}

tasks_load :: proc(tasks_file_path: string) -> (tasks: [dynamic]Task, ok: bool) {
    if os.exists(tasks_file_path) {
        tasks_data, read_ok := os.read_entire_file(tasks_file_path)
        if !read_ok {
            fmt.println("Error: failed to read file")
            return
        }
        defer delete(tasks_data)
        fmt.println("Opened file:", tasks_file_path)
        if decode_err := cbor.unmarshal(string(tasks_data), &tasks); decode_err != nil {
            fmt.println("Error:", decode_err)
            return
        }
    }
    fmt.println("Read tasks file with", len(tasks), "tasks")
    ok = true
    return
}

tasks_save :: proc(tasks: []Task, tasks_file_path: string) -> (ok: bool) {
    binary, err := cbor.marshal(tasks, cbor.ENCODE_SMALL|cbor.Encoder_Flags{.Self_Described_CBOR})
    if err != nil {
        fmt.println("Error:", err)
        return
    }
    defer delete(binary)

    if write_err := os.write_entire_file_or_err(TASKS_FILE_PATH, binary); err != nil {
        fmt.println("Error:", write_err)
        return
    }
    fmt.println("Generated:", TASKS_FILE_PATH)
    ok = true
    return
}

tasks_display :: proc(tasks: []Task, max_progress_value: int = 50) {
    for task in tasks {
        ratio_done, duration_left := task_get_progress(task)
        progress_bar := render_progress_bar(ratio_done, max_progress_value)
        progress_left := (1 - ratio_done) * 100

        delta_to_days_hrs_mins :: proc(delta: datetime.Delta) -> (days, hours, mins: i64) {
            days_rounded := delta.days
            hours_ := f64(delta.seconds)/(60*60)
            hours_rounded := i64(hours_)
            mins_rounded := i64((hours_ - f64(hours_rounded))*60)
            return days_rounded, hours_rounded, mins_rounded
        }

        fmt.printfln("%s: %s (%.2f %% left) (%d days %d hours and %d minutes to go!) ",
            task.name, progress_bar, progress_left, delta_to_days_hrs_mins(duration_left))
    }
}

render_progress_bar :: proc(progress_ratio: f64, max_slots: int = 100) -> string {
    progress_bar: strings.Builder
    strings.write_byte(&progress_bar, '[')
    progress_percent := int(progress_ratio * f64(max_slots))
    for i in 0..<progress_percent {
        strings.write_byte(&progress_bar, '=')
    }
    strings.write_byte(&progress_bar, '>')
    for i in progress_percent..=max_slots {
        strings.write_byte(&progress_bar, '.')
    }
    strings.write_byte(&progress_bar, ']')
    return strings.to_string(progress_bar)
}


initialize_cbor :: proc() {
    cbor_tag :: cbor.TAG_EPOCH_TIME_NR

    impl := cbor.Tag_Implementation {
        marshal = proc(self: ^cbor.Tag_Implementation, e: cbor.Encoder, v: any) -> cbor.Marshal_Error {
            datetime := v.(datetime.DateTime)
            time := time.datetime_to_time(datetime) or_else panic("datetime was validated before this")
            cbor._encode_u8(e.writer, cbor_tag, .Tag) or_return
            return cbor.err_conv(cbor._encode_bytes(e, reflect.as_bytes(v)))
        },
        unmarshal = proc(self: ^cbor.Tag_Implementation, d: cbor.Decoder, tag_nr: u64, v: any) -> cbor.Unmarshal_Error {
            header := cbor._decode_header(d.reader) or_return
            major, add := cbor._header_split(header)
            if major != .Bytes {
                return .Bad_Tag_Value
            }
            bytes := cbor.err_conv(cbor._decode_bytes(d, add, major)) or_return
            intrinsics.mem_copy_non_overlapping(v.data, raw_data(bytes), len(bytes))
            return nil
        }
    }

    cbor.tag_register_type(impl, cbor_tag, typeid_of(datetime.DateTime))
}

main :: proc() {
    Options :: struct {
        name: string        `args:"name=n,required" usage:"name of the task"`,
        date: string        `args:"name=d,required" usage:"date of the task"`,
        list: bool          `args:"name=l" usage:"list all tasks"`,
        remove: string      `args:"name=r" usage:"remove task by name"`,
        search: string      `args:"name=s" usage:"search and display task by name"`,
        remove_all: string  `args:"name=R" usage:"remove all tasks from file"`,
        file: os.Handle     `args:"name=f" usage:"specify tasks file"`
    }
    options: Options
    flags.parse_or_exit(&options, os.args[:], flags.Parsing_Style.Unix)

    initialize_cbor()
    tasks, loaded := tasks_load(TASKS_FILE_PATH)
    defer delete(tasks)
    if !loaded {
        os.exit(1) 
    }

    task, created := task_create(options.name, options.date)
    if !created {
        os.exit(1)
    }
    append(&tasks, task)
    fmt.println("Task created with end date of:", task.end_date.date)

    if options.list {
        tasks_display(tasks[:], 30)
    }
    // TODO: implement remove and remove-all
    // TODO: implement search
    // TODO: implement file selection through cli

    saved := tasks_save(tasks[:], TASKS_FILE_PATH)
    if !saved {
        os.exit(1)
    }
}
