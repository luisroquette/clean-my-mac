#!/usr/bin/env python3
import socket
import subprocess
import sys
import time
from pathlib import Path

from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parents[1]


def free_port():
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        return listener.getsockname()[1]


def wait_for_server(port):
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.2):
                return
        except OSError:
            time.sleep(0.1)
    raise RuntimeError(f"Demo server did not start on port {port}")


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
        assert page.locator("[data-percent]").inner_text() == "84%"
        assert page.locator("[data-state]").inner_text() == "NORMAL"
        set_storage(page, 89.9)
        assert page.locator("[data-state]").inner_text() == "NORMAL"
        set_storage(page, 90)
        assert page.locator("[data-state]").inner_text() == "90% ALERT"

        auto_clean = page.locator("[data-auto-clean]")
        auto_clean.focus()
        page.keyboard.press("Enter")
        assert auto_clean.get_attribute("aria-pressed") == "false"
        set_storage(page, 96)
        page.wait_for_timeout(1200)
        assert float(page.locator("#storage").input_value()) == 96
        assert page.locator("[data-state]").inner_text() == "95% CLEANUP"

        page.keyboard.press("Enter")
        page.wait_for_timeout(4400)
        assert float(page.locator("#storage").input_value()) == 84
        assert page.locator("[data-state]").inner_text() == "OPTIMIZED"
        assert page.locator(".cleanup-timeline li.is-done").count() == 4
        assert not console_errors, console_errors
        assert not page_errors, page_errors
        context.close()

        reduced, page = open_demo(browser, url, viewport={"width": 1440, "height": 1000}, reduced_motion="reduce")
        set_storage(page, 96)
        page.wait_for_timeout(1000)
        assert float(page.locator("#storage").input_value()) == 84
        assert page.locator("[data-state]").inner_text() == "OPTIMIZED"
        reduced.close()

        mobile, page = open_demo(browser, url, viewport={"width": 390, "height": 844}, device_scale_factor=1)
        dimensions = page.evaluate("({ client: document.documentElement.clientWidth, scroll: document.documentElement.scrollWidth })")
        assert dimensions["scroll"] == dimensions["client"], dimensions
        box = page.locator("[data-storage-console]").bounding_box()
        assert box and box["x"] >= 0 and box["x"] + box["width"] <= 390.5, box
        mobile.close()
        browser.close()


def main():
    port = free_port()
    server = subprocess.Popen(
        [sys.executable, "-m", "http.server", str(port), "-d", str(ROOT / "docs")],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    try:
        wait_for_server(port)
        run_e2e(f"http://127.0.0.1:{port}/#proof")
    finally:
        server.terminate()
        try:
            server.wait(timeout=3)
        except subprocess.TimeoutExpired:
            server.kill()
    print("Storage Control E2E: OK")


if __name__ == "__main__":
    main()
