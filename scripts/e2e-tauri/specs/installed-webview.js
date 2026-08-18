/**
 * Smoke-only fallback. Product gate on Linux is full_workbench_installed.py.
 */

async function dumpUi(label) {
  const out = process.env.BROWBOX_TAURI_E2E_REPORT;
  const text = await browser.execute(
    () => (document.body && document.body.innerText) || ""
  );
  console.log(`[ui ${label}]`, String(text).slice(0, 240));
  if (out) {
    try {
      await browser.saveScreenshot(`${out}/webview-${label}.png`);
    } catch {
      /* screenshot optional */
    }
  }
  return String(text || "");
}

async function switchToWorkbench(timeoutMs = 50000) {
  const end = Date.now() + timeoutMs;
  let last = "";
  while (Date.now() < end) {
    const handles = await browser.getWindowHandles();
    for (const h of handles) {
      try {
        await browser.switchToWindow(h);
      } catch {
        continue;
      }
      const hit = await browser.execute(() => {
        const nav = document.querySelector('[data-testid="workbench-nav"]');
        const text = (document.body && document.body.innerText) || "";
        return {
          nav: !!nav,
          profiles: !!document.querySelector('[data-testid="nav-profiles"]'),
          hasEnv: text.includes("环境管理"),
          splash: /正在启动本机服务/.test(text),
          sample: text.slice(0, 180),
        };
      });
      last = hit.sample || last;
      if (hit.nav || hit.profiles || hit.hasEnv) return hit;
    }
    await browser.pause(400);
  }
  throw new Error(`workbench WebView not ready; last text: ${last.slice(0, 180)}`);
}

async function clickTestId(id) {
  return browser.execute((tid) => {
    const el = document.querySelector(`[data-testid="${tid}"]`);
    if (!el) return { ok: false, id: tid };
    el.scrollIntoView({ block: "center" });
    el.click();
    return { ok: true, id: tid, text: (el.textContent || "").trim().slice(0, 80) };
  }, id);
}

describe("installed browboxs-desktop WebView", () => {
  it("boots past splash into workbench nav", async () => {
    await browser.pause(1500);
    const hit = await switchToWorkbench(50000);
    await dumpUi("boot");
    expect(hit.nav || hit.profiles || hit.hasEnv).toBe(true);
  });

  it("opens 环境管理 from the real nav", async () => {
    const r = await clickTestId("nav-profiles");
    if (!r.ok) {
      const fallback = await browser.execute(() => {
        const nodes = [...document.querySelectorAll("button, a, [role='button'], nav *")];
        const el = nodes.find((n) => (n.textContent || "").includes("环境管理"));
        if (!el) return { ok: false };
        el.click();
        return { ok: true };
      });
      expect(fallback.ok).toBe(true);
    } else {
      expect(r.ok).toBe(true);
    }
    await browser.pause(800);
    const text = await dumpUi("profiles");
    expect(/环境/.test(text)).toBe(true);
  });

  it("opens 设置 from the real nav", async () => {
    const r = await clickTestId("nav-settings");
    if (!r.ok) {
      const fallback = await browser.execute(() => {
        const nodes = [...document.querySelectorAll("button, a, [role='button'], nav *")];
        const el = nodes.find((n) => (n.textContent || "").includes("设置"));
        if (!el) return { ok: false };
        el.click();
        return { ok: true };
      });
      expect(fallback.ok).toBe(true);
    }
    await browser.pause(800);
    const text = await dumpUi("settings");
    expect(text.length).toBeGreaterThan(0);
  });
});
