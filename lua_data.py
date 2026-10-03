"""Read data-only Lua files (a `return { ... }` of tables, strings, numbers and
booleans), such as scripts/locale/<lang>.lua, without running Lua.

Tables with only positional entries become lists; any other table becomes a
dict that keeps source order (positional entries get integer keys 1..n).
Code (function calls, concatenation, variables) is rejected with a clear error,
which also keeps the locale files pure data.

scan() tokenizes any Lua source, for tools that only need to walk its structure
(check_locale.py reads the item registry's keys this way).
"""
import re

_CODE_TOKEN = re.compile(r"""
    (?P<ws>\s+)
  | (?P<lcomment>--\[(?P<leq>=*)\[.*?\](?P=leq)\])
  | (?P<comment>--[^\n]*)
  | (?P<lstring>\[(?P<seq>=*)\[.*?\](?P=seq)\])
  | (?P<string>"(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*')
  | (?P<number>0[xX][0-9a-fA-F]+|\d+\.?\d*(?:[eE][+-]?\d+)?|\.\d+)
  | (?P<name>[A-Za-z_][A-Za-z0-9_]*)
  | (?P<op>\.\.\.|\.\.|==|~=|<=|>=|<<|>>|//|::|[{}\[\]()=,;.:#+\-*/%^<>~&|])
""", re.S | re.X)


def scan(src):
    """Tokens of Lua source as (kind, text, line); comments and spaces dropped.
    kind is string (text keeps its quotes), number, name, op, or eof."""
    pos, toks = 0, []
    while pos < len(src):
        m = _CODE_TOKEN.match(src, pos)
        if not m:
            line = src.count("\n", 0, pos) + 1
            raise LuaDataError("line %d: cannot tokenize %r" % (line, src[pos:pos + 20]))
        kind = m.lastgroup
        if kind in ("leq", "seq"):
            kind = "lcomment" if m.group("lcomment") else "lstring"
        if kind not in ("ws", "comment", "lcomment"):
            toks.append(("string" if kind == "lstring" else kind, m.group(0), src.count("\n", 0, m.start()) + 1))
        pos = m.end()
    toks.append(("eof", "", src.count("\n") + 1))
    return toks

_TOKEN = re.compile(r"""
    (?P<ws>\s+)
  | (?P<lcomment>--\[(?P<leq>=*)\[.*?\](?P=leq)\])
  | (?P<comment>--[^\n]*)
  | (?P<lstring>\[(?P<seq>=*)\[(?P<lbody>.*?)\](?P=seq)\])
  | (?P<string>"(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*')
  | (?P<number>0[xX][0-9a-fA-F]+|\d+\.?\d*(?:[eE][+-]?\d+)?|\.\d+)
  | (?P<name>[A-Za-z_][A-Za-z0-9_]*)
  | (?P<op>[{}\[\]=,;-])
""", re.S | re.X)

_ESCAPES = {"n": "\n", "t": "\t", "r": "\r", "a": "\a", "b": "\b", "f": "\f", "v": "\v",
            "\\": "\\", '"': '"', "'": "'", "\n": "\n"}


class LuaDataError(ValueError):
    pass


def _unescape(body, line):
    out, i = [], 0
    while i < len(body):
        ch = body[i]
        if ch != "\\":
            out.append(ch)
            i += 1
            continue
        nxt = body[i + 1]
        if nxt in _ESCAPES:
            out.append(_ESCAPES[nxt])
            i += 2
        elif nxt == "x":
            out.append(chr(int(body[i + 2:i + 4], 16)))
            i += 4
        elif nxt == "z":
            i += 2
            while i < len(body) and body[i].isspace():
                i += 1
        elif nxt.isdigit():
            j = i + 1
            while j < len(body) and j < i + 4 and body[j].isdigit():
                j += 1
            out.append(chr(int(body[i + 1:j])))
            i = j
        elif nxt == "u" and body[i + 2] == "{":
            j = body.index("}", i)
            out.append(chr(int(body[i + 3:j], 16)))
            i = j + 1
        else:
            raise LuaDataError("line %d: unsupported escape \\%s" % (line, nxt))
    # Lua strings are bytes; decoding the UTF-8 escapes back keeps text intact.
    return "".join(out)


def _tokens(src):
    pos, toks = 0, []
    while pos < len(src):
        m = _TOKEN.match(src, pos)
        if not m:
            line = src.count("\n", 0, pos) + 1
            found = src[pos:pos + 20].split("\n")[0]
            raise LuaDataError("line %d: only data is allowed here, found %r" % (line, found))
        kind = m.lastgroup
        if kind in ("leq", "seq", "lbody"):
            kind = "lcomment" if m.group("lcomment") else "lstring"
        line = src.count("\n", 0, m.start()) + 1
        if kind == "string":
            toks.append(("string", _unescape(m.group(0)[1:-1], line), line))
        elif kind == "lstring":
            body = m.group("lbody")
            toks.append(("string", body[1:] if body.startswith("\n") else body, line))
        elif kind in ("number", "name", "op"):
            toks.append((kind, m.group(0), line))
        pos = m.end()
    toks.append(("eof", "", src.count("\n") + 1))
    return toks


class _Parser:
    def __init__(self, toks):
        self.toks, self.i = toks, 0

    def peek(self):
        return self.toks[self.i]

    def take(self, text=None):
        tok = self.toks[self.i]
        if text is not None and tok[1] != text:
            raise LuaDataError("line %d: expected %r, found %r" % (tok[2], text, tok[1]))
        self.i += 1
        return tok

    def value(self):
        kind, text, line = self.peek()
        if kind == "string":
            self.take()
            return text
        if kind == "number":
            self.take()
            if text.lower().startswith("0x"):
                return int(text, 16)
            return float(text) if any(c in text for c in ".eE") else int(text)
        if kind == "op" and text == "-" and self.toks[self.i + 1][0] == "number":
            self.take()
            return -self.value()
        if kind == "name" and text in ("true", "false", "nil"):
            self.take()
            return {"true": True, "false": False, "nil": None}[text]
        if kind == "op" and text == "{":
            return self.table()
        raise LuaDataError("line %d: only data is allowed here, found %r" % (line, text))

    def table(self):
        self.take("{")
        entries, positional = [], 0
        while self.peek()[1] != "}":
            kind, text, line = self.peek()
            if kind == "name" and self.toks[self.i + 1][1] == "=":
                self.take()
                self.take("=")
                key = text
            elif kind == "op" and text == "[":
                self.take()
                key = self.value()
                self.take("]")
                self.take("=")
            else:
                positional += 1
                key = positional
            entries.append((key, self.value(), line))
            if self.peek()[1] in (",", ";"):
                self.take()
            elif self.peek()[1] != "}":
                raise LuaDataError("line %d: expected , or }" % self.peek()[2])
        self.take("}")
        if entries and all(isinstance(k, int) for k, _, _ in entries) and [k for k, _, _ in entries] == list(range(1, len(entries) + 1)):
            return [v for _, v, _ in entries]
        if not entries:
            return {}
        result = {}
        for key, value, line in entries:
            if key in result:
                raise LuaDataError("line %d: duplicate key %r" % (line, key))
            result[key] = value
        return result


def loads(src):
    """Parse `return <data>` (the leading `return` is optional)."""
    parser = _Parser(_tokens(src))
    if parser.peek()[:2] == ("name", "return"):
        parser.take()
    data = parser.value()
    if parser.peek()[0] != "eof":
        raise LuaDataError("line %d: unexpected trailing %r" % (parser.peek()[2], parser.peek()[1]))
    return data


def load(path):
    with open(path, encoding="utf-8") as handle:
        return loads(handle.read())
