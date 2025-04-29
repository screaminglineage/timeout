package main

import "base:intrinsics"
import "core:encoding/cbor"
import "core:fmt"
import "core:os"
import "core:reflect"
import "core:strconv"
import "core:strings"
import "core:time"
import "core:time/datetime"

// TODO: grab from an environment variable
TASKS_FILE_PATH :: "timeout-tasks.cbor"

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

    // NOTE: see https://pkg.odin-lang.org/core/time/#Time for the range of Time
    assert(end_time_ok && start_time_ok, "year 2262 problem is still ways off! ...right??...\n")
    return f64(now - start_time_unix)/f64(end_time_unix - start_time_unix)
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
    initialize_cbor()

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
    fmt.printf("Progress: Done: %.2f%%, ", progress_ratio * 100)
    fmt.printf("Left: %.2f%%\n", (1-progress_ratio) * 100)

    binary, err := cbor.marshal(task, cbor.ENCODE_SMALL|cbor.Encoder_Flags{.Self_Described_CBOR})
    if err != nil {
        fmt.println("Error:", err)
    }
    fmt.println("Encoded into", len(binary), "bytes")
    defer delete(binary)

    // TODO: check how to return an error exit code without os.exit() as that wont call defers
    if write_err := os.write_entire_file_or_err(TASKS_FILE_PATH, binary); err != nil {
        fmt.println("Error:", write_err)
        return
    }
    fmt.println("Generated:", TASKS_FILE_PATH)

    decoded_task := Task{}
    // TODO: check how to return an error exit code without os.exit() as that wont call defers
    if decode_err := cbor.unmarshal(string(binary), &decoded_task); decode_err != nil {
        fmt.println("Error:", decode_err)
        return
    }
    fmt.println(decoded_task)
}
