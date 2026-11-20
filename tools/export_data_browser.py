import asyncio, json
from playwright.async_api import async_playwright
async def main():
    async with async_playwright() as p:
        b = await p.chromium.launch(); pg = await b.new_page()
        await pg.add_init_script("localStorage.setItem('realm-intro-seen','1')")
        await pg.goto('http://localhost:8777/realmlings_play.html'); await pg.wait_for_timeout(1500)
        await pg.evaluate("document.querySelector('#mNew').click()"); await pg.wait_for_timeout(200)
        await pg.evaluate("document.querySelector('#mRace [data-race=\"realm\"]').click()"); await pg.wait_for_timeout(200)
        await pg.evaluate("document.querySelector('#mStart').click()"); await pg.wait_for_timeout(3500)
        d = await pg.evaluate("JSON.stringify(window.__dumpAll())")
        open('/tmp/all_data.json','w').write(d)
        print(len(d))
        await b.close()
asyncio.run(main())
