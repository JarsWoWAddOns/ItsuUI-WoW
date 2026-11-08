"""Rebuild retail Itsu:UI's controller module from retail JarStick (JarStick-WoW).

Edit JarStick in JarStick-WoW, then run this. Never edit Modules/Controller/*.lua by hand.

What it does to each JarStick file:
  - wraps the whole file in a function JarForever calls when the module is on, with
    JarStick's own private namespace as `ns` (so nothing collides with JarForever's ns)
  - JarStickDB / JarStickCharDB become ns.acct / ns.charDB (JarForeverDB.controller and
    JarForeverCharDB.controller, set up by Modules/Controller.lua)
  - JarStick.lua and Interact.lua get their ADDON_LOADED handler replayed once every
    file has run, since JarForever's own ADDON_LOADED is already firing by then
  - no /js: the slash handler becomes ns.SlashCommand (JarForever's /jf passes JarStick's
    subcommands to it) and its settings window is left out. JarForever draws the settings
    itself in Modules/Controller.lua
"""
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
SRC = HERE.parent / "JarStick-WoW"  # flat repo, no addon subfolder
DST = HERE / "ItsuUI" / "Modules" / "Controller"
FILES = ["JarStick.lua", "Interact.lua", "Book.lua", "Wheel.lua"]
# JarStick bits that only make sense as a standalone addon
REPLACE = {
    "JarStick.lua": [
        ('SLASH_JARSTICK1 = "/jarstick"\nSLASH_JARSTICK2 = "/jstick"\nSLASH_JARSTICK3 = "/js"\n'
         'SlashCmdList.JARSTICK = function(msg)\n', "ns.SlashCommand = function(msg)\n"),
        ("JarStick_ToggleConfig()", "ns.OpenSettings()"),
        ("gamepad input enabled, /js for options", "gamepad input enabled, /jf for options"),
        # in game the whole thing is Itsu:UI
        ('print("|cff66ccffJarStick|r: " .. msg)', 'print("|cffff8c00Itsu:UI|r " .. msg)'),
        ("everything reset to JarStick defaults", "controller settings reset to defaults"),
    ],
    "Book.lua": [
        ('title:SetText("JarStick")', 'title:SetText("Itsu:UI")'),
    ],
}

# event frame per file whose ADDON_LOADED needs replaying
LOAD_FRAMES = {"JarStick.lua": "events", "Interact.lua": "ev"}

HEADER = "-- generated from JarStick-WoW by sync_jarstick.py, edit it there and re-run\n"
WRAP_OPEN = """local _, jf = ...
jf.jsParts = jf.jsParts or {}
jf.jsParts[#jf.jsParts + 1] = function(ns, ADDON)
"""


def convert(name: str, text: str) -> str:
    nl = "\r\n" if "\r\n" in text else "\n"
    text = text.replace("\r\n", "\n")
    marker = "local ADDON, ns = ...\n"
    if text.count(marker) != 1:
        sys.exit(f"{name}: expected one '{marker.strip()}' line")
    text = text.replace(marker, WRAP_OPEN)
    for old, new in REPLACE.get(name, []):
        if text.count(old) != 1:
            sys.exit(f"{name}: expected one match for {old[:50]!r}")
        text = text.replace(old, new)
    text = text.replace("JarStickCharDB", "ns.charDB").replace("JarStickDB", "ns.acct")
    tail = ""
    frame = LOAD_FRAMES.get(name)
    if frame:
        tail = (f'ns.loadHooks[#ns.loadHooks + 1] = function() '
                f'{frame}:GetScript("OnEvent")({frame}, "ADDON_LOADED", ADDON) end\n')
    text = HEADER + text.rstrip("\n") + "\n\n" + tail + "end\n"
    return text.replace("\n", nl)


def main() -> None:
    # retired 2026-11-08: Itsu:UI owns these files now, a sync would wipe its own changes
    sys.exit("retired, edit ItsuUI/Modules/Controller directly")
    DST.mkdir(parents=True, exist_ok=True)
    # anything generated before that isnt in FILES anymore
    for old in DST.glob("*.lua"):
        if old.name not in FILES:
            old.unlink()
            print(f"removed {old}")
    for name in FILES:
        src = SRC / name
        out = convert(name, src.read_text(encoding="utf-8", newline=""))
        (DST / name).write_text(out, encoding="utf-8", newline="")
        print(f"{src} -> {DST / name}")


if __name__ == "__main__":
    main()
