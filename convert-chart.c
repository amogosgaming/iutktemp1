/*
this is converter for my fnf engine.
to use, compile with
gcc -O2 -o convert-chart convert-chart.c
and run with
./convert-chart (chart).json (finalfile).bin
after that, put in data folder in my engine and make sure it named "Chart.bin".
also replace the inst and voices or add them if they aren't there. vocal are optional.

if you have any issues. make an issue in the repo.

notes on the same time + lane are stored once with a 64-bit count,
so the file size depends on the song length, not on how many notes the chart has.
the total note count can go all the way up to 18,446,744,073,709,551,615 (2^64 - 1).
*/
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stdarg.h>
#include <errno.h>
#include <sys/stat.h>

#define FILE_MAGIC "FNC1"
#define FILE_VERSION 3
#define HEADER_SIZE 17
#define MAX_ENGINE_CELLS 268435455u

#define JSON_READ_BUFFER_SIZE (1 * 1024 * 1024)
#define WRITE_CHUNK_CELLS 65536
#define PROGRESS_INTERVAL 1000000

#define LANE_BITS 3
#define LANE_MASK 7
#define TIME_SIGN_FLIP 0x80000000u

#define NUMBER_BUFFER_SIZE 64
#define NUMBER_MAX_CHARS 62
#define KEY_BUFFER_SIZE 128
#define INITIAL_TABLE_CAPACITY (1 << 16)
#define INITIAL_NOTE_LIST_CAPACITY 64

static void die(const char *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    fprintf(stderr, "ERROR: ");
    vfprintf(stderr, fmt, args);
    fprintf(stderr, "\n");
    va_end(args);
    exit(1);
}

static void *checked_malloc(size_t size) {
    void *ptr = malloc(size ? size : 1);
    if (!ptr) die("out of memory allocating %zu bytes", size);
    return ptr;
}

static void *checked_realloc(void *old_ptr, size_t size) {
    void *ptr = realloc(old_ptr, size ? size : 1);
    if (!ptr) die("out of memory reallocating %zu bytes", size);
    return ptr;
}

static char *format_with_commas(uint64_t value) {
    static char buffers[4][32];
    static int next_buffer = 0;

    char *result = buffers[next_buffer];
    next_buffer = (next_buffer + 1) % 4;

    char digits[32];
    int digit_count = snprintf(digits, sizeof digits, "%llu", (unsigned long long)value);

    int out = 0;
    for (int i = 0; i < digit_count; i++) {
        int digits_remaining = digit_count - i;
        if (i > 0 && digits_remaining % 3 == 0) result[out++] = ',';
        result[out++] = digits[i];
    }
    result[out] = '\0';
    return result;
}

static int64_t python_style_mod(int64_t a, int64_t b) {
    int64_t remainder = a % b;
    int signs_differ = (remainder < 0) != (b < 0);
    if (remainder != 0 && signs_differ) remainder += b;
    return remainder;
}

static int is_digit(int c) {
    return c >= '0' && c <= '9';
}

static double file_size_in_mib(const char *path) {
    struct stat info;
    if (stat(path, &info) != 0) return 0.0;
    return (double)info.st_size / (1024.0 * 1024.0);
}

typedef struct {
    FILE *file;
    unsigned char *buffer;
    size_t capacity;
    size_t length;
    size_t position;
} JsonReader;

static void json_init(JsonReader *r, FILE *file, size_t buffer_size) {
    r->file = file;
    r->capacity = buffer_size;
    r->buffer = checked_malloc(buffer_size);
    r->length = 0;
    r->position = 0;
}

static void json_free(JsonReader *r) {
    free(r->buffer);
    r->buffer = NULL;
}

static int json_refill(JsonReader *r) {
    size_t bytes_read = fread(r->buffer, 1, r->capacity, r->file);
    r->position = 0;
    r->length = bytes_read;
    return bytes_read > 0;
}

static inline int json_peek(JsonReader *r) {
    if (r->position >= r->length && !json_refill(r)) return -1;
    return r->buffer[r->position];
}

static inline int json_getc(JsonReader *r) {
    if (r->position >= r->length && !json_refill(r)) return -1;
    return r->buffer[r->position++];
}

static inline void json_skip_whitespace(JsonReader *r) {
    for (;;) {
        int c = json_peek(r);
        int is_whitespace = (c == ' ' || c == '\t' || c == '\r' || c == '\n');
        if (!is_whitespace) return;
        r->position++;
    }
}

static void json_expect_char(JsonReader *r, char expected) {
    int c = json_getc(r);
    if (c == (unsigned char)expected) return;

    if (c == -1) die("unexpected EOF (expected '%c')", expected);
    die("expected '%c' but got '%c'", expected, (char)c);
}

static void json_expect_literal(JsonReader *r, const char *literal) {
    for (const char *p = literal; *p; p++) {
        int c = json_getc(r);
        if (c != (unsigned char)*p) die("expected literal '%s' in json", literal);
    }
}

static int json_next_item(JsonReader *r, char closing, const char *where) {
    json_skip_whitespace(r);
    int c = json_getc(r);
    if (c == ',') return 1;
    if (c == closing) return 0;
    die("expected ',' or '%c' %s", closing, where);
    return 0;
}

static char decode_simple_escape(int escape_char) {
    switch (escape_char) {
        case '"':  return '"';
        case '\\': return '\\';
        case '/':  return '/';
        case 'b':  return '\b';
        case 'f':  return '\f';
        case 'n':  return '\n';
        case 'r':  return '\r';
        case 't':  return '\t';
        default:   return (char)escape_char;
    }
}

static void json_read_string(JsonReader *r, char *out, size_t capacity) {
    json_skip_whitespace(r);
    json_expect_char(r, '"');

    size_t length = 0;

    for (;;) {
        int c = json_getc(r);
        if (c == -1) die("unexpected EOF inside string");
        if (c == '"') break;

        char decoded = (char)c;

        if (c == '\\') {
            int escape_char = json_getc(r);
            if (escape_char == -1) die("unexpected EOF inside string escape");

            if (escape_char == 'u') {
                for (int i = 0; i < 4; i++) {
                    if (json_getc(r) == -1) die("unexpected EOF inside \\u escape");
                }
                continue;
            }

            decoded = decode_simple_escape(escape_char);
        }

        if (length + 1 < capacity) out[length] = decoded;
        length++;
    }

    if (capacity > 0) {
        size_t end = (length < capacity) ? length : capacity - 1;
        out[end] = '\0';
    }
}

static void number_take_char(JsonReader *r, char *text, int *length) {
    int c = json_getc(r);
    if (*length < NUMBER_MAX_CHARS) text[(*length)++] = (char)c;
}

static void number_take_digits(JsonReader *r, char *text, int *length) {
    while (is_digit(json_peek(r))) number_take_char(r, text, length);
}

static double json_read_number(JsonReader *r) {
    char text[NUMBER_BUFFER_SIZE];
    int length = 0;

    json_skip_whitespace(r);

    if (json_peek(r) == '-') number_take_char(r, text, &length);

    if (!is_digit(json_peek(r))) die("expected number in JSON");
    number_take_digits(r, text, &length);

    if (json_peek(r) == '.') {
        number_take_char(r, text, &length);
        number_take_digits(r, text, &length);
    }

    if (json_peek(r) == 'e' || json_peek(r) == 'E') {
        number_take_char(r, text, &length);
        if (json_peek(r) == '+' || json_peek(r) == '-') number_take_char(r, text, &length);
        number_take_digits(r, text, &length);
    }

    text[length] = '\0';
    return atof(text);
}

static int json_read_bool(JsonReader *r) {
    json_skip_whitespace(r);
    int c = json_peek(r);

    if (c == 't') {
        json_expect_literal(r, "true");
        return 1;
    }
    if (c == 'f') {
        json_expect_literal(r, "false");
        return 0;
    }

    die("expected boolean in JSON");
    return 0;
}

static void json_skip_value(JsonReader *r);

static void json_skip_string(JsonReader *r) {
    json_expect_char(r, '"');
    for (;;) {
        int c = json_getc(r);
        if (c == -1) die("unexpected EOF inside string");

        if (c == '\\') {
            if (json_getc(r) == -1) die("unexpected EOF inside string escape");
            continue;
        }

        if (c == '"') return;
    }
}

static void json_skip_object(JsonReader *r) {
    json_expect_char(r, '{');
    json_skip_whitespace(r);
    if (json_peek(r) == '}') {
        json_getc(r);
        return;
    }

    do {
        json_skip_whitespace(r);
        json_skip_string(r);
        json_skip_whitespace(r);
        json_expect_char(r, ':');
        json_skip_value(r);
    } while (json_next_item(r, '}', "while skipping object"));
}

static void json_skip_array(JsonReader *r) {
    json_expect_char(r, '[');
    json_skip_whitespace(r);
    if (json_peek(r) == ']') {
        json_getc(r);
        return;
    }

    do {
        json_skip_whitespace(r);
        json_skip_value(r);
    } while (json_next_item(r, ']', "while skipping array"));
}

static void json_skip_value(JsonReader *r) {
    json_skip_whitespace(r);
    int c = json_peek(r);

    if (c == '"')                           json_skip_string(r);
    else if (c == '{')                      json_skip_object(r);
    else if (c == '[')                      json_skip_array(r);
    else if (c == 't')                      json_expect_literal(r, "true");
    else if (c == 'f')                      json_expect_literal(r, "false");
    else if (c == 'n')                      json_expect_literal(r, "null");
    else if (c == '-' || is_digit(c))       json_read_number(r);
    else die("unexpected character while skipping json value: 0x%02x", c);
}

typedef struct {
    uint64_t key;
    uint64_t count;
} NoteCell;

typedef struct {
    NoteCell *slots;
    size_t capacity;
    size_t used;
    uint64_t notes_parsed;
    uint64_t total_notes;
} NoteTable;

static uint64_t make_cell_key(int32_t time, uint8_t lane) {
    uint64_t shifted_time = (uint32_t)time ^ TIME_SIGN_FLIP;
    return (shifted_time << LANE_BITS) | (uint64_t)(lane & LANE_MASK);
}

static int32_t cell_key_time(uint64_t key) {
    return (int32_t)((uint32_t)(key >> LANE_BITS) ^ TIME_SIGN_FLIP);
}

static uint8_t cell_key_lane(uint64_t key) {
    return (uint8_t)(key & LANE_MASK);
}

static inline uint64_t hash_key(uint64_t k) {
    k ^= k >> 33;
    k *= 0xff51afd7ed558ccdULL;
    k ^= k >> 33;
    k *= 0xc4ceb9fe1a85ec53ULL;
    k ^= k >> 33;
    return k;
}

static NoteCell *allocate_empty_slots(size_t capacity) {
    NoteCell *slots = checked_malloc(capacity * sizeof(NoteCell));
    memset(slots, 0, capacity * sizeof(NoteCell));
    return slots;
}

static size_t find_slot(NoteCell *slots, size_t capacity, uint64_t key) {
    size_t index = (size_t)hash_key(key) & (capacity - 1);
    while (slots[index].count != 0 && slots[index].key != key) {
        index = (index + 1) & (capacity - 1);
    }
    return index;
}

static void table_init(NoteTable *t) {
    t->capacity = INITIAL_TABLE_CAPACITY;
    t->slots = allocate_empty_slots(t->capacity);
    t->used = 0;
    t->notes_parsed = 0;
    t->total_notes = 0;
}

static void table_free(NoteTable *t) {
    free(t->slots);
    t->slots = NULL;
}

static void table_grow(NoteTable *t) {
    size_t new_capacity = t->capacity * 2;
    NoteCell *new_slots = allocate_empty_slots(new_capacity);

    for (size_t i = 0; i < t->capacity; i++) {
        if (t->slots[i].count == 0) continue;
        size_t index = find_slot(new_slots, new_capacity, t->slots[i].key);
        new_slots[index] = t->slots[i];
    }

    free(t->slots);
    t->slots = new_slots;
    t->capacity = new_capacity;
}

static void table_add_note(NoteTable *t, int32_t time, uint8_t lane) {
    uint64_t key = make_cell_key(time, lane);

    if ((t->used + 1) * 2 > t->capacity) table_grow(t);

    size_t index = find_slot(t->slots, t->capacity, key);
    NoteCell *cell = &t->slots[index];

    if (cell->count == 0) {
        cell->key = key;
        cell->count = 1;
        t->used++;
    } else {
        cell->count++;
    }

    t->notes_parsed++;
    t->total_notes++;
    if (t->notes_parsed % PROGRESS_INTERVAL == 0) {
        printf("  ...%s notes parsed so far (%s unique time+lane cells)\n",
               format_with_commas(t->notes_parsed), format_with_commas(t->used));
    }
}

typedef struct {
    double time;
    double lane;
} RawNote;

typedef struct {
    RawNote *items;
    size_t length;
    size_t capacity;
} RawNoteList;

static void note_list_init(RawNoteList *list) {
    list->items = NULL;
    list->length = 0;
    list->capacity = 0;
}

static void note_list_free(RawNoteList *list) {
    free(list->items);
    list->items = NULL;
    list->length = 0;
    list->capacity = 0;
}

static void note_list_push(RawNoteList *list, RawNote note) {
    if (list->length == list->capacity) {
        list->capacity = list->capacity ? list->capacity * 2 : INITIAL_NOTE_LIST_CAPACITY;
        list->items = checked_realloc(list->items, list->capacity * sizeof(RawNote));
    }
    list->items[list->length++] = note;
}

static void parse_note_entry(JsonReader *r, RawNoteList *notes) {
    json_skip_whitespace(r);
    json_expect_char(r, '[');
    json_skip_whitespace(r);

    RawNote note = {0.0, 0.0};

    if (json_peek(r) == ']') {
        json_getc(r);
    } else {
        int field_index = 0;
        do {
            json_skip_whitespace(r);
            if (field_index == 0)      note.time = json_read_number(r);
            else if (field_index == 1) note.lane = json_read_number(r);
            else                       json_skip_value(r);
            field_index++;
        } while (json_next_item(r, ']', "in note entry"));
    }

    note_list_push(notes, note);
}

static void parse_section_notes_array(JsonReader *r, RawNoteList *notes) {
    json_skip_whitespace(r);
    json_expect_char(r, '[');
    json_skip_whitespace(r);
    if (json_peek(r) == ']') {
        json_getc(r);
        return;
    }

    do {
        json_skip_whitespace(r);
        parse_note_entry(r, notes);
    } while (json_next_item(r, ']', "in sectionNotes array"));
}

static int lane_for_note(int64_t raw_lane, int must_hit_section) {
    int64_t direction = python_style_mod(raw_lane, 4);

    int belongs_to_player = must_hit_section;
    if (raw_lane > 3) belongs_to_player = !belongs_to_player;

    return (int)direction + (belongs_to_player ? 4 : 0);
}

static void add_section_notes_to_table(NoteTable *table, const RawNoteList *notes, int must_hit_section) {
    for (size_t i = 0; i < notes->length; i++) {
        int64_t time = (int64_t)notes->items[i].time;
        int64_t raw_lane = (int64_t)notes->items[i].lane;
        int lane = lane_for_note(raw_lane, must_hit_section);

        table_add_note(table, (int32_t)time, (uint8_t)lane);
    }
}

static void parse_section(JsonReader *r, NoteTable *table) {
    int must_hit_section = 0;
    RawNoteList notes;
    note_list_init(&notes);

    json_skip_whitespace(r);
    json_expect_char(r, '{');
    json_skip_whitespace(r);

    if (json_peek(r) == '}') {
        json_getc(r);
    } else {
        char key[KEY_BUFFER_SIZE];
        do {
            json_skip_whitespace(r);
            json_read_string(r, key, sizeof key);
            json_skip_whitespace(r);
            json_expect_char(r, ':');

            if (strcmp(key, "mustHitSection") == 0) {
                must_hit_section = json_read_bool(r);
            } else if (strcmp(key, "sectionNotes") == 0) {
                parse_section_notes_array(r, &notes);
            } else {
                json_skip_value(r);
            }
        } while (json_next_item(r, '}', "in section object"));
    }

    add_section_notes_to_table(table, &notes, must_hit_section);
    note_list_free(&notes);
}

static void parse_notes_array(JsonReader *r, NoteTable *table) {
    json_skip_whitespace(r);
    json_expect_char(r, '[');
    json_skip_whitespace(r);
    if (json_peek(r) == ']') {
        json_getc(r);
        return;
    }

    do {
        json_skip_whitespace(r);
        parse_section(r, table);
    } while (json_next_item(r, ']', "in notes array"));
}

static void parse_song_object(JsonReader *r, NoteTable *table) {
    json_skip_whitespace(r);
    json_expect_char(r, '{');
    json_skip_whitespace(r);
    if (json_peek(r) == '}') {
        json_getc(r);
        return;
    }

    char key[KEY_BUFFER_SIZE];
    do {
        json_skip_whitespace(r);
        json_read_string(r, key, sizeof key);
        json_skip_whitespace(r);
        json_expect_char(r, ':');

        if (strcmp(key, "notes") == 0) {
            parse_notes_array(r, table);
            return;
        }
        json_skip_value(r);
    } while (json_next_item(r, '}', "in song object"));
}

static void read_chart_file(const char *input_path, NoteTable *table) {
    FILE *file = fopen(input_path, "rb");
    if (!file) die("cannot open %s (%s)", input_path, strerror(errno));

    JsonReader reader;
    json_init(&reader, file, JSON_READ_BUFFER_SIZE);

    json_skip_whitespace(&reader);
    json_expect_char(&reader, '{');
    json_skip_whitespace(&reader);

    int found_notes = 0;

    if (json_peek(&reader) != '}') {
        char key[KEY_BUFFER_SIZE];
        do {
            json_skip_whitespace(&reader);
            json_read_string(&reader, key, sizeof key);
            json_skip_whitespace(&reader);
            json_expect_char(&reader, ':');

            if (strcmp(key, "notes") == 0) {
                printf("detected root prefix: notes.item\n");
                parse_notes_array(&reader, table);
                found_notes = 1;
                break;
            }
            if (strcmp(key, "song") == 0) {
                printf("detected root prefix: song.notes.item\n");
                parse_song_object(&reader, table);
                found_notes = 1;
                break;
            }
            json_skip_value(&reader);
        } while (json_next_item(&reader, '}', "in root object"));
    }

    json_free(&reader);
    fclose(file);

    if (!found_notes) die("could not find a 'notes' or 'song' key in the jSON root");
}

static void store_u32_le(unsigned char *out, uint32_t value) {
    out[0] = (unsigned char)(value & 0xFF);
    out[1] = (unsigned char)((value >> 8) & 0xFF);
    out[2] = (unsigned char)((value >> 16) & 0xFF);
    out[3] = (unsigned char)((value >> 24) & 0xFF);
}

static void store_u64_le(unsigned char *out, uint64_t value) {
    store_u32_le(out, (uint32_t)(value & 0xFFFFFFFFu));
    store_u32_le(out + 4, (uint32_t)(value >> 32));
}

static void write_bytes(FILE *out, const void *data, size_t size, const char *path) {
    if (size && fwrite(data, 1, size, out) != size) {
        die("write to %s failed (%s)", path, strerror(errno));
    }
}

static int compare_cells_by_key(const void *a, const void *b) {
    uint64_t key_a = ((const NoteCell *)a)->key;
    uint64_t key_b = ((const NoteCell *)b)->key;
    if (key_a < key_b) return -1;
    return key_a > key_b;
}

static NoteCell *collect_sorted_cells(const NoteTable *t) {
    NoteCell *cells = checked_malloc(t->used * sizeof(NoteCell));

    size_t count = 0;
    for (size_t i = 0; i < t->capacity; i++) {
        if (t->slots[i].count != 0) cells[count++] = t->slots[i];
    }

    qsort(cells, t->used, sizeof(NoteCell), compare_cells_by_key);
    return cells;
}

static void write_header(FILE *out, const char *path, uint32_t cell_count, uint64_t total_notes) {
    unsigned char header[HEADER_SIZE];

    memcpy(header, FILE_MAGIC, 4);
    header[4] = (unsigned char)FILE_VERSION;
    store_u32_le(header + 5, cell_count);
    store_u64_le(header + 9, total_notes);

    write_bytes(out, header, sizeof header, path);
}

static size_t chunk_size(size_t total, size_t start) {
    size_t remaining = total - start;
    return (remaining < WRITE_CHUNK_CELLS) ? remaining : WRITE_CHUNK_CELLS;
}

static void write_time_block(FILE *out, const char *path, const NoteCell *cells, size_t n, unsigned char *buffer) {
    for (size_t start = 0; start < n; start += WRITE_CHUNK_CELLS) {
        size_t count = chunk_size(n, start);
        for (size_t i = 0; i < count; i++) {
            uint32_t time = (uint32_t)cell_key_time(cells[start + i].key);
            store_u32_le(buffer + i * 4, time);
        }
        write_bytes(out, buffer, count * 4, path);
    }
}

static void write_lane_block(FILE *out, const char *path, const NoteCell *cells, size_t n, unsigned char *buffer) {
    for (size_t start = 0; start < n; start += WRITE_CHUNK_CELLS) {
        size_t count = chunk_size(n, start);
        for (size_t i = 0; i < count; i++) {
            buffer[i] = cell_key_lane(cells[start + i].key);
        }
        write_bytes(out, buffer, count, path);
    }
}

static void write_count_block(FILE *out, const char *path, const NoteCell *cells, size_t n, unsigned char *buffer) {
    for (size_t start = 0; start < n; start += WRITE_CHUNK_CELLS) {
        size_t count = chunk_size(n, start);
        for (size_t i = 0; i < count; i++) {
            store_u64_le(buffer + i * 8, cells[start + i].count);
        }
        write_bytes(out, buffer, count * 8, path);
    }
}

static void write_binary_file(const char *output_path, const NoteTable *table) {
    size_t cell_count = table->used;

    if (cell_count > MAX_ENGINE_CELLS) {
        die("%s unique time+lane cells is more than the engine can load (%s). "
            "that is a song longer than 9 hours.",
            format_with_commas(cell_count), format_with_commas(MAX_ENGINE_CELLS));
    }

    printf("sorting %s cells...\n", format_with_commas(cell_count));
    NoteCell *cells = collect_sorted_cells(table);

    printf("writing %s...\n", output_path);
    FILE *out = fopen(output_path, "wb");
    if (!out) die("cannot open %s for writing (%s)", output_path, strerror(errno));

    unsigned char *buffer = checked_malloc((size_t)WRITE_CHUNK_CELLS * 8);

    write_header(out, output_path, (uint32_t)cell_count, table->total_notes);
    write_time_block(out, output_path, cells, cell_count, buffer);
    write_lane_block(out, output_path, cells, cell_count, buffer);
    write_count_block(out, output_path, cells, cell_count, buffer);

    free(buffer);
    free(cells);

    if (fclose(out) != 0) die("closing %s failed (%s)", output_path, strerror(errno));
}

static void print_usage(void) {
    printf("usage:\n");
    printf("  ./convert-chart input.json output.bin\n");
}

int main(int argc, char **argv) {
    if (argc != 3) {
        print_usage();
        return 1;
    }

    const char *input_path = argv[1];
    const char *output_path = argv[2];

    printf("streaming %s...\n", input_path);

    NoteTable table;
    table_init(&table);

    read_chart_file(input_path, &table);

    printf("notes in json: %s\n", format_with_commas(table.notes_parsed));
    printf("total notes: %s\n", format_with_commas(table.total_notes));
    printf("unique time+lane cells: %s\n", format_with_commas(table.used));

    write_binary_file(output_path, &table);

    table_free(&table);

    printf("\ndone!\n");
    printf("binary size: %.2f MiB\n", file_size_in_mib(output_path));

    return 0;
}
