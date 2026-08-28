#!/usr/bin/env python3
import threading
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from playwright.sync_api import expect, sync_playwright

ROOT = Path(__file__).resolve().parents[1]


class QuietHandler(SimpleHTTPRequestHandler):
    def log_message(self, *_):
        pass


def set_storage(page, value):
    page.locator("#storage").evaluate(
        "(el, value) => { el.value = value; el.dispatchEvent(new Event('input', { bubbles: true })); }",
        str(value),
    )


def open_demo(browser, url, **context_options):
    context = browser.new_context(**context_options)
    context.route("**/*.mp4", lambda route: route.abort())
    page = context.new_page()
    page.goto(url)
    page.wait_for_load_state("networkidle")
    return context, page


def run_e2e(url):
    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(channel="chrome", headless=True)
        context, page = open_demo(browser, url, viewport={"width": 1440, "height": 1000})
        console_errors = []
        page_errors = []
        page.on("console", lambda message: console_errors.append(message.text) if message.type == "error" else None)
        page.on("pageerror", lambda error: page_errors.append(str(error)))

        assert page.locator("[data-storage-console]").is_visible()
        assert page.locator("[data-percent]").inner_text() == "72%"
        assert page.locator("[data-state]").inner_text() == "NORMAL"
        set_storage(page, 74.9)
        assert page.locator("[data-state]").inner_text() == "NORMAL"
        set_storage(page, 75)
        assert page.locator("[data-state]").inner_text() == "75% ALERT"

        auto_clean = page.locator("[data-auto-clean]")
        auto_clean.focus()
        page.keyboard.press("Enter")
        assert auto_clean.get_attribute("aria-pressed") == "false"
        set_storage(page, 81)
        page.wait_for_timeout(1200)
        assert float(page.locator("#storage").input_value()) == 81
        assert page.locator("[data-state]").inner_text() == "78% CLEANUP"

        page.keyboard.press("Enter")
        expect(page.locator("[data-state]")).to_have_text("OPTIMIZED", timeout=10_000)
        assert float(page.locator("#storage").input_value()) == 72
        assert page.locator(".cleanup-timeline li.is-done").count() == 4
        assert page.locator('[data-download-cta][href="#download"]').count() == 2
        assert page.locator('a[href*="releases/latest/download"]').count() == 0

        download_url = "https://github.com/luisroquette/clean-my-mac/releases/latest/download/Clean-My-Mac.zip"
        page.route(
            "https://cfgauss.com.br/api/lead/clean-my-mac",
            lambda route: route.fulfill(status=200, content_type="application/json", body=f'{{"success":true,"downloadUrl":"{download_url}"}}'),
        )
        page.locator('[data-lead-form] input[name="name"]').fill("Ana Silva")
        page.locator('[data-lead-form] input[name="whatsapp"]').fill("11999998888")
        page.locator('[data-lead-form] input[name="email"]').fill("ana@example.com")
        page.locator('[data-lead-form] button[type="submit"]').click()
        expect(page.locator("[data-download-ready]")).to_be_visible()
        expect(page.locator("[data-download-link]")).to_have_attribute("href", download_url)
        assert not console_errors, console_errors
        assert not page_errors, page_errors
        context.close()

        failed, page = open_demo(browser, url, viewport={"width": 1440, "height": 1000})
        page.route(
            "https://cfgauss.com.br/api/lead/clean-my-mac",
            lambda route: route.fulfill(status=503, content_type="application/json", body='{"error":"Trello unavailable"}'),
        )
        page.locator('[data-lead-form] input[name="name"]').fill("Ana Silva")
        page.locator('[data-lead-form] input[name="whatsapp"]').fill("11999998888")
        page.locator('[data-lead-form] input[name="email"]').fill("ana@example.com")
        page.locator('[data-lead-form] button[type="submit"]').click()
        expect(page.locator("[data-form-status]")).to_have_text("Trello unavailable")
        expect(page.locator("[data-download-ready]")).to_be_hidden()
        failed.close()

        reduced, page = open_demo(browser, url, viewport={"width": 1440, "height": 1000}, reduced_motion="reduce")
        set_storage(page, 81)
        expect(page.locator("[data-state]")).to_have_text("OPTIMIZED", timeout=3_000)
        assert float(page.locator("#storage").input_value()) == 72
        reduced.close()

        mobile, page = open_demo(browser, url, viewport={"width": 390, "height": 844}, device_scale_factor=1)
        dimensions = page.evaluate("({ client: document.documentElement.clientWidth, scroll: document.documentElement.scrollWidth })")
        assert dimensions["scroll"] == dimensions["client"], dimensions
        box = page.locator("[data-storage-console]").bounding_box()
        assert box and box["x"] >= 0 and box["x"] + box["width"] <= 390.5, box
        mobile.close()
        browser.close()


def main():
    handler = partial(QuietHandler, directory=str(ROOT / "docs"))
    server = ThreadingHTTPServer(("127.0.0.1", 0), handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        run_e2e(f"http://127.0.0.1:{server.server_port}/#proof")
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=3)
    print("Storage Control E2E: OK")


if __name__ == "__main__":
    main()
