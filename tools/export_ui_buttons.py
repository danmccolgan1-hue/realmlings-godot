"""Render the web game's Armory and Diplomacy button icons (inline SVG in its HTML) to PNG for the Godot port.

Usage (with the web build served on localhost:8777, as for tools/export_art.py):
    python3 tools/export_ui_buttons.py <repo>/assets/art/icons/common
"""
import sys
import asyncio
from playwright.async_api import async_playwright
async def main():
    async with async_playwright() as p:
        b = await p.chromium.launch()
        pg = await b.new_page(viewport={'width':1600,'height':1000}, device_scale_factor=4)
        await pg.add_init_script("localStorage.setItem('realm-intro-seen','1')")
        await pg.goto('http://localhost:8777/realmlings_play.html'); await pg.wait_for_timeout(1500)
        await pg.evaluate("document.querySelector('#mNew').click()"); await pg.wait_for_timeout(200)
        await pg.evaluate("document.querySelector('#mStart').click()"); await pg.wait_for_timeout(3500)
        for sel, name in [('#armBtn svg', 'armory'), ('#dip svg', 'dove')]:
            el = await pg.query_selector(sel)
            if el:
                await el.evaluate("e => { e.style.background = 'transparent'; }")
                await el.screenshot(path=f'{OUT}/ui_{name}.png', omit_background=True)
                print('ok', name)
            else:
                print('none', name)
        await b.close()
OUT = sys.argv[1] if len(sys.argv) > 1 else 'assets/art/icons/common'
asyncio.run(main())
