"""One-off rewrite for multiplayer step 1: the player's own fields in scripts/sim/game.gd become properties backed by
the current seat's record (`cur`), so every human nation has its own copy. Run once; kept for the record."""
import re
import sys

SEAT_FIELDS = """leader capital stock income income_parts army_counter tech rep surveyed designs exhaust exhaust_ok harvest
upgrades xup cd harvest_by trap school_popup reveals eyes haunts mana_pool mana_prev mana_prev_t mage_gear auto_tech
queues rally wf known explored visible my_nation train_orders met dipl fallen ally_ask met_at dx_step_t gift_vault
demand ally_offer BUILD_DEFS TECH_BY_ID TECHS TECH_TREES UNIT_BASE BUILD_ORDER CMD""".split()

DEFAULT_OF_TYPE = {"Dictionary": "{}", "Array": "[]", "String": '""', "int": "0", "float": "0.0", "bool": "false"}


def type_of(init: str) -> str:
    s = init.strip()
    if s.startswith("{"):
        return "Dictionary"
    if s.startswith("["):
        return "Array"
    if s.startswith('"'):
        return "String"
    if s in ("true", "false"):
        return "bool"
    if re.fullmatch(r"-?\d+", s):
        return "int"
    if re.fullmatch(r"-?\d+\.\d*", s):
        return "float"
    raise ValueError(init)


def main(path: str) -> None:
    src = open(path, encoding="utf-8").read().split("\n")
    out = []
    defaults = []
    found = set()
    for line in src:
        m = re.match(r"^var ([A-Za-z_0-9]+)(\s*:=\s*|\s*=\s*|\s*:\s*([A-Za-z]+)\s*(=\s*)?)?(.*)$", line)
        if m and m.group(1) in SEAT_FIELDS and m.group(1) not in found:
            name = m.group(1)
            rest = m.group(5)
            comment = ""
            # split an initializer from its trailing comment (no '#' inside these literals)
            if "#" in rest:
                rest, comment = rest.split("#", 1)
                comment = "  #" + comment
            rest = rest.strip()
            sep = m.group(2) or ""
            if sep.strip() == ":=":
                typ, init = type_of(rest), rest
            elif sep.strip() == "=":
                typ, init = None, rest
            else:   # `var X: Type` (or `var X: Type = v`)
                typ = m.group(3)
                init = rest if rest else DEFAULT_OF_TYPE[typ]
            defaults.append((name, init))
            found.add(name)
            head = "var %s: %s:" % (name, typ) if typ else "var %s:" % name
            out.append(head + comment.rstrip())
            out.append('\tget: return cur["%s"]' % name)
            out.append('\tset(v): cur["%s"] = v' % name)
            continue
        out.append(line)
    missing = [f for f in SEAT_FIELDS if f not in found]
    if missing:
        sys.exit("not found: %s" % missing)
    text = "\n".join(out)
    body = "\n".join('\t\t"%s": %s,' % (n, i) for n, i in defaults)
    block = (
        "\n# --- seats (multiplayer step 1): each human nation's own fields ---\n"
        "## The fields each human nation has its own copy of. The properties above read and write the current seat's\n"
        "## record (`cur`); use_seat() switches it. A single-player game has one seat, HOST.\n"
        "const SEAT_FIELDS := [%s]\n\n"
        "## A new seat's record: every seat field at its starting value.\n"
        "static func seat_defaults() -> Dictionary:\n\treturn {\n%s\n\t}\n"
    ) % (", ".join('"%s"' % f for f in SEAT_FIELDS), body)
    marker = "\n\nfunc _init() -> void:"
    assert marker in text
    text = text.replace(marker, block + marker, 1)
    open(path, "w", encoding="utf-8").write(text)
    print("converted %d fields" % len(found))


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "scripts/sim/game.gd")
