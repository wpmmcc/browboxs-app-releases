#!/usr/bin/env node
/**
 * Headed workbench UI click e2e (Playwright) against installed package UI static.
 * Product menus are clicked in a real Chromium window (use xvfb-run on Linux CI).
 *
 * Usage:
 *   node workbench-playwright.mjs --url http://127.0.0.1:UI --agent http://127.0.0.1:AGENT --out DIR
 *
 * Env:
 *   BROWBOX_UI_E2E_HEADLESS=0|1   default 0 (headed)
 *   BROWBOX_UI_E2E_TOKEN=...      optional Bearer for API checks
 */
import fs from "fs";
import path from "path";
import { chromium } from "playwright";

function arg(name, def) {
  const i = process.argv.indexOf(name);
  if (i >= 0 && process.argv[i + 1]) return process.argv[i + 1];
  return def;
}

const UI_URL = arg("--url", process.env.BROWBOX_UI_E2E_URL || "http://127.0.0.1:18980/");
const AGENT = (arg("--agent", process.env.BROWBOX_UI_E2E_AGENT || "http://127.0.0.1:18971")).replace(
  /\/$/,
  ""
);
const OUT = arg("--out", process.env.BROWBOX_UI_E2E_OUT || "/tmp/bb-ui-e2e");
const HEADLESS = (process.env.BROWBOX_UI_E2E_HEADLESS || "0") === "1";
const TOKEN = process.env.BROWBOX_UI_E2E_TOKEN || "";

fs.mkdirSync(OUT, { recursive: true });

// Must match apps/desktop/src/layout/nav.ts NAV_GROUPS labels
const MENUS = [
  "环境管理",
  "新建环境",
  "内核引擎",
  "代理中心",
  "子账号",
  "设备",
  "工作流 RPA",
  "任务中心",
  "运营工具",
  "节点域名",
  "日志中心",
  "更新与模块",
  "设置",
];

const report = {
  ok: true,
  mode: HEADLESS ? "playwright-headless" : "playwright-headed",
  uiUrl: UI_URL,
  agent: AGENT,
  clicks: [],
  api: [],
  errors: [],
  screenshots: [],
};

async function api(method, p, body) {
  const headers = { "Content-Type": "application/json" };
  if (TOKEN) headers.Authorization = `Bearer ${TOKEN}`;
  const r = await fetch(`${AGENT}${p}`, {
    method,
    headers,
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await r.text();
  let json = null;
  try {
    json = JSON.parse(text);
  } catch {
    /* ignore */
  }
  return { status: r.status, json, text: text.slice(0, 200) };
}

async function main() {
  // API preflight (workbench dependencies)
  for (const p of ["/v1/health", "/v1/profiles", "/v1/proxies", "/v1/workflows", "/v1/engines"]) {
    const r = await api("GET", p);
    report.api.push({ path: p, status: r.status });
    if (r.status !== 200 && r.status !== 401) {
      report.errors.push(`api ${p} → ${r.status}`);
    }
  }

  const browser = await chromium.launch({
    headless: HEADLESS,
    args: ["--no-sandbox", "--disable-dev-shm-usage", "--window-size=1440,900"],
  });
  const context = await browser.newContext({
    viewport: { width: 1440, height: 900 },
    ignoreHTTPSErrors: true,
  });
  const page = await context.newPage();

  const target = UI_URL.includes("?")
    ? `${UI_URL}&agent=${encodeURIComponent(AGENT)}`
    : `${UI_URL.replace(/\/?$/, "/")}?agent=${encodeURIComponent(AGENT)}`;

  await page.goto(target, { waitUntil: "domcontentloaded", timeout: 60000 });
  await page.waitForTimeout(1500);

  // Wait for nav shell
  let hasNav = false;
  for (let i = 0; i < 40; i++) {
    hasNav = (await page.locator("nav button").count()) > 0;
    if (hasNav) break;
    await page.waitForTimeout(250);
  }

  const probe = {
    title: await page.title(),
    href: page.url(),
    nav: await page.locator("nav button").allTextContents(),
    bodySnippet: ((await page.locator("body").innerText().catch(() => "")) || "").slice(0, 200),
  };
  report.probe = probe;
  fs.writeFileSync(path.join(OUT, "ui-probe.json"), JSON.stringify(probe, null, 2));

  const shot = async (name) => {
    const f = path.join(OUT, name);
    await page.screenshot({ path: f, fullPage: true });
    report.screenshots.push(f);
  };
  await shot("01-home.png");

  if (!hasNav || !(probe.nav || []).length) {
    report.ok = false;
    report.errors.push("no-nav-buttons — workbench shell did not render");
  } else {
    for (const label of MENUS) {
      const btn = page.locator("nav button").filter({ hasText: label }).first();
      const n = await btn.count();
      if (n === 0) {
        // partial match across all nav
        const all = probe.nav || [];
        const hit = all.find((t) => (t || "").includes(label));
        if (!hit) {
          report.clicks.push({ label, ok: false, reason: "not-found" });
          continue;
        }
      }
      try {
        const targetBtn =
          n > 0 ? btn : page.locator("nav button").filter({ hasText: new RegExp(label) }).first();
        await targetBtn.click({ timeout: 5000 });
        await page.waitForTimeout(400);
        report.clicks.push({ label, ok: true });
      } catch (e) {
        report.clicks.push({ label, ok: false, reason: String(e).slice(0, 120) });
        report.errors.push(`click ${label}: ${e}`);
      }
    }
    await shot("02-after-nav.png");

    // Create environment panel interaction (best-effort DOM)
    try {
      const createNav = page.locator("nav button").filter({ hasText: /新建|创建/ }).first();
      if ((await createNav.count()) > 0) {
        await createNav.click();
        await page.waitForTimeout(500);
        const nameInput = page.locator('input[type="text"], input:not([type])').first();
        if ((await nameInput.count()) > 0) {
          await nameInput.fill(`ci-e2e-${Date.now()}`);
          report.clicks.push({ label: "fill-create-name", ok: true });
        }
        await shot("03-create-env.png");
      }
    } catch (e) {
      report.errors.push(`create-env: ${e}`);
    }
  }

  // API create profile (function, not only UI)
  if (TOKEN) {
    const fp = {
      schema_version: 1,
      platform: "Win32",
      user_agent:
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
      language: "en-US",
      timezone: "UTC",
    };
    const r = await api("POST", "/v1/profiles", {
      name: `ui-e2e-${Date.now()}`,
      engine_id: "fingerprint-chromium",
      fingerprint: fp,
    });
    report.api.push({ path: "POST /v1/profiles", status: r.status });
    if (r.status !== 200 && r.status !== 201) {
      report.errors.push(`create profile → ${r.status}`);
    } else {
      report.profileId = (r.json?.data || r.json || {}).id || null;
    }
  }

  // Require at least some successful menu clicks when nav exists
  const okClicks = report.clicks.filter((c) => c.ok).length;
  if (hasNav && okClicks < 3) {
    report.ok = false;
    report.errors.push(`too-few-menu-clicks: ${okClicks}`);
  }

  await browser.close();
  fs.writeFileSync(path.join(OUT, "ui-e2e-report.json"), JSON.stringify(report, null, 2));
  console.log(JSON.stringify({ ok: report.ok, clicks: okClicks, errors: report.errors }, null, 2));
  if (!report.ok) process.exit(1);
}

main().catch((e) => {
  report.ok = false;
  report.errors.push(String(e));
  fs.writeFileSync(path.join(OUT, "ui-e2e-report.json"), JSON.stringify(report, null, 2));
  console.error(e);
  process.exit(1);
});
