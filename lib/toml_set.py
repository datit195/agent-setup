"""Add missing keys to a TOML file without touching anything else.

Usage: python3 -I toml_set.py FILE < SPEC_JSON

SPEC_JSON is a list of {"table": [...], "key": "...", "value": <json>} items,
optionally with "new_table": true (set only when the table does not exist
yet). A key that is already set is never changed, except that a key whose line
is exactly `key = <one of "old">` (a value an older agent-setup wrote) is
replaced with the new value. Prints the resulting file
on stdout (unchanged when nothing is missing); the caller writes it.

An item {"array": [...], "marker": "...", "entries": [{...}, ...]} manages
array-of-tables entries: every `[[array]] # marker` block (the header and
the `key = value` lines right after it) is removed, and one such block per
entry is written at the end of the file. Unmarked entries are never changed;
an entry whose "path" an unmarked line already sets is left out.

Python 3.9+ without third-party modules: a line scanner finds tables and keys;
when tomllib (3.11+) is available it also checks presence and validates the
result. Keys in tables that exist only implicitly (dotted keys or inline
tables) are skipped with a note on stderr.
"""
import json
import re
import sys

try:
    import tomllib
except ImportError:
    tomllib = None

BARE = re.compile(r"^[A-Za-z0-9_-]+$")
HEADER = re.compile(r"^\s*\[\s*([^\[\]]+?)\s*\]\s*(#.*)?$")
ARRAY_HEADER = re.compile(r"^\s*\[\[")
KEY = re.compile(r"^\s*((?:[A-Za-z0-9_-]+|\"[^\"]*\"|'[^']*')(?:\s*\.\s*(?:[A-Za-z0-9_-]+|\"[^\"]*\"|'[^']*'))*)\s*=")


def split_key(text):
    parts = re.findall(r"[A-Za-z0-9_-]+|\"[^\"]*\"|'[^']*'", text)
    return tuple(p[1:-1] if p[0] in "\"'" else p for p in parts)


def fmt_key(k):
    return k if BARE.match(k) else json.dumps(k)


def fmt(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return json.dumps(v)
    if isinstance(v, str):
        return json.dumps(v)
    if isinstance(v, list):
        return "[" + ", ".join(fmt(x) for x in v) + "]"
    if isinstance(v, dict):
        return "{ " + ", ".join("%s = %s" % (fmt_key(k), fmt(x)) for k, x in v.items()) + " }"
    raise ValueError("unsupported value %r" % (v,))


def scan(lines):
    """Return (headers {table: [first line, end line]}, keys set, tables set,
    array-of-tables header lines)."""
    headers, keys, tables, arrays = {}, set(), set(), []
    cur, depth, mstr = (), 0, None
    for i, line in enumerate(lines):
        if mstr or depth > 0:
            # Continuation of a multi-line string or array/inline table value.
            if mstr:
                if line.count(mstr) % 2 == 1:
                    mstr = None
            else:
                depth += line.count("[") + line.count("{") - line.count("]") - line.count("}")
            if cur in headers:
                headers[cur][1] = i + 1
            continue
        m = HEADER.match(line)
        if m and not ARRAY_HEADER.match(line):
            cur = split_key(m.group(1))
            headers[cur] = [i, i + 1]
            for n in range(1, len(cur) + 1):
                tables.add(cur[:n])
            continue
        if ARRAY_HEADER.match(line):
            cur = ("[[array]]", str(i))
            arrays.append(i)
            continue
        m = KEY.match(line)
        if m:
            full = cur + split_key(m.group(1))
            keys.add(full)
            for n in range(len(cur) + 1, len(full)):
                tables.add(full[:n])
            rest = line[m.end():]
            for q in ('"""', "'''"):
                if rest.count(q) % 2 == 1:
                    mstr = q
            if rest.lstrip().startswith(("[", "{")):
                depth = rest.count("[") + rest.count("{") - rest.count("]") - rest.count("}")
                depth = max(depth, 0)
            if cur in headers:
                headers[cur][1] = i + 1
        elif line.strip() and cur in headers:
            headers[cur][1] = i + 1
    return headers, keys, tables, arrays


def parsed_has(data, path):
    d = data
    for p in path:
        if not isinstance(d, dict) or p not in d:
            return False
        d = d[p]
    return True


def managed_blocks(lines, item):
    """Remove the marked [[array]] blocks of ITEM from LINES; return the new blocks."""
    header = "[[%s]] # %s" % (".".join(fmt_key(p) for p in item["array"]), item["marker"])
    kept, i = [], 0
    while i < len(lines):
        if lines[i].strip() == header:
            i += 1
            while i < len(lines) and KEY.match(lines[i]) and not HEADER.match(lines[i]):
                i += 1
            while kept and not kept[-1].strip():
                kept.pop()
            continue
        kept.append(lines[i])
        i += 1
    lines[:] = kept
    blocks = []
    for entry in item["entries"]:
        if "path" in entry and any(KEY.match(l) and l.split("=", 1)[1].strip() == fmt(entry["path"])
                                   and split_key(KEY.match(l).group(1)) == ("path",) for l in lines):
            continue
        blocks.append([header] + ["%s = %s" % (fmt_key(k), fmt(v)) for k, v in entry.items()])
    return blocks


def main():
    path = sys.argv[1]
    try:
        with open(path, "rb") as f:
            text = f.read().decode("utf-8")
    except FileNotFoundError:
        text = ""
    spec = json.loads(sys.stdin.buffer.read())
    arrays = [item for item in spec if "array" in item]
    spec = [item for item in spec if "array" not in item]
    data = tomllib.loads(text) if tomllib else None
    lines = text.split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    blocks = []
    for item in arrays:
        blocks.extend(managed_blocks(lines, item))
    headers, keys, tables, arrays = scan(lines)

    def exists(p):
        return p in keys or p in tables or (data is not None and parsed_has(data, p))

    for item in spec:
        table, key = tuple(item["table"]), item["key"]
        if table not in headers or not item.get("old"):
            continue
        olds = ["%s = %s" % (fmt_key(key), fmt(o)) for o in item["old"]]
        start, end = headers[table]
        for i in range(start + 1, end):
            if lines[i].strip() in olds:
                lines[i] = "%s = %s" % (fmt_key(key), fmt(item["value"]))

    top, inserts, new_tables = [], {}, {}
    for item in spec:
        table, key = tuple(item["table"]), item["key"]
        if item.get("old"):
            continue
        if item.get("new_table") and table and exists(table):
            continue
        full = table + (key,)
        if exists(full) or any(table[:n] in keys for n in range(1, len(table) + 1)):
            continue
        entry = "%s = %s" % (fmt_key(key), fmt(item["value"]))
        if not table:
            top.append(entry)
        elif table in headers:
            inserts.setdefault(headers[table][1], []).append(entry)
        elif exists(table):
            sys.stderr.write("[%s] is not a plain table; %s not set\n" % (".".join(table), key))
        else:
            new_tables.setdefault(table, []).append(entry)

    out = []
    # Top-level keys go before the first table or array-of-tables header.
    first_header = min([h[0] for h in headers.values()] + arrays or [len(lines)])
    for i, line in enumerate(lines):
        if i == first_header and top:
            while out and not out[-1].strip():
                out.pop()
            out.extend(top)
            out.append("")
            top = []
        if i in inserts:
            # Insert after the last content line of the table (before blank lines).
            j = len(out)
            while j > 0 and not out[j - 1].strip():
                j -= 1
            out[j:j] = inserts.pop(i)
        out.append(line)
    if len(lines) in inserts:
        j = len(out)
        while j > 0 and not out[j - 1].strip():
            j -= 1
        out[j:j] = inserts.pop(len(lines))
    if top:
        out.extend(top)
    for table, entries in new_tables.items():
        if out and out[-1].strip():
            out.append("")
        out.append("[%s]" % ".".join(fmt_key(p) for p in table))
        out.extend(entries)
    for block in blocks:
        if out and out[-1].strip():
            out.append("")
        out.extend(block)
    result = "\n".join(out) + "\n" if out else ""
    if tomllib:
        tomllib.loads(result)  # raises on a broken result; the caller keeps the file
    sys.stdout.buffer.write(result.encode("utf-8"))


if __name__ == "__main__":
    main()
