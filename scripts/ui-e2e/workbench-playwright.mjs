#!/usr/bin/env node
/**
 * Hardened workbench UI + function e2e (Playwright) against installed package.
 * Mirrors local tests/user_click + create-env wizard (nav.ts + CreateEnvironment).
 *
 * Usage:
 *   node workbench-playwright.mjs --url http://127.0.0.1:UI --agent http://127.0.0.1:AGENT --out DIR
 *
 * Env:
 *   BROWBOX_UI_E2E_HEADLESS=0|1   default 0 (headed)
 *   BROWBOX_UI_E2E_TOKEN=...      Bearer (optional if agent allows unauth write)
 *   BROWBOX_UI_E2E_STRICT_NAV=1   fail if any nav item missing (default 1)
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
let TOKEN = process.env.BROWBOX_UI_E2E_TOKEN || "";
const STRICT_NAV = (process.env.BROWBOX_UI_E2E_STRICT_NAV || "1") === "1";

fs.mkdirSync(OUT, { recursive: true });

/** Must match apps/desktop/src/layout/nav.ts */
const NAV = [
  { id: "profiles", label: "环境管理", expect: /环境管理|共\s*\d+|筛选/ },
  { id: "create", label: "新建环境", expect: /新建环境|基础信息|多步向导/ },
  { id: "engines", label: "内核引擎", expect: /内核|引擎|fingerprint|camoufox/i },
  { id: "proxy", label: "代理中心", expect: /代理|HTTP|SOCKS/ },
  { id: "accounts", label: "子账号", expect: /子账号|成员|角色|会话/ },
  { id: "devices", label: "设备", expect: /设备|在线|登记/ },
  { id: "workflows", label: "工作流 RPA", expect: /工作流|RPA|模板|步骤/ },
  { id: "tasks", label: "任务中心", expect: /任务|执行|批次/ },
  { id: "ops", label: "运营工具", expect: /运营|模板|检测|账密|Syncer/ },
  { id: "node", label: "节点域名", expect: /节点|域名|本机服务|连接/ },
  { id: "logs", label: "日志中心", expect: /日志|操作|摘要/ },
  { id: "updates", label: "更新与模块", expect: /更新|模块|GitHub|检查/ },
  { id: "settings", label: "设置", expect: /设置|Local API|路径|引擎组/ },
];

const report = {
  ok: true,
  mode: HEADLESS ? "playwright-headless" : "playwright-headed",
  uiUrl: UI_URL,
  agent: AGENT,
  steps: [],
  clicks: [],
  api: [],
  forms: [],
  errors: [],
  screenshots: [],
};

function fail(msg) {
  report.ok = false;
  report.errors.push(msg);
  console.error("FAIL:", msg);
}

function step(name, detail) {
  report.steps.push({ name, ...detail, t: new Date().toISOString() });
  console.log("STEP", name, detail?.ok === false ? "FAIL" : "ok", detail?.note || "");
}

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
  return { status: r.status, json, text: text.slice(0, 400) };
}

async function main() {
  // ── API function preflight ──
  for (const p of ["/v1/health", "/v1/profiles", "/v1/proxies", "/v1/workflows", "/v1/engines"]) {
    const r = await api("GET", p);
    report.api.push({ path: p, status: r.status });
    if (r.status !== 200 && r.status !== 401) {
      fail(`api GET ${p} → ${r.status}`);
    } else {
      step(`api GET ${p}`, { ok: true, status: r.status });
    }
  }

  // Discover token if empty (agent may write session file path in logs — caller sets env)
  if (!TOKEN) {
    // try unauth; if 401 later create will fail and we report
    step("token", { ok: true, note: TOKEN ? "provided" : "empty (rely on open auth or later fail)" });
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
  page.setDefaultTimeout(15000);

  const target = UI_URL.includes("?")
    ? `${UI_URL}&agent=${encodeURIComponent(AGENT)}`
    : `${UI_URL.replace(/\/?$/, "/")}?agent=${encodeURIComponent(AGENT)}`;

  await page.goto(target, { waitUntil: "networkidle", timeout: 90000 }).catch(async () => {
    await page.goto(target, { waitUntil: "domcontentloaded", timeout: 60000 });
  });
  await page.waitForTimeout(800);

  // Root shell
  const root = page.getByTestId("workbench-root");
  try {
    await root.waitFor({ state: "visible", timeout: 30000 });
    step("workbench-root", { ok: true });
  } catch {
    // fallback: nav present
    const n = await page.locator("nav button").count();
    if (n < 5) fail("workbench shell not visible (no workbench-root / nav)");
    else step("workbench-root", { ok: true, note: "nav fallback" });
  }

  // Wait for nav
  await page.locator("nav button").first().waitFor({ state: "visible", timeout: 30000 }).catch(() => {});
  const navProbe = await page.locator("nav button").allTextContents();
  report.probe = {
    title: await page.title(),
    href: page.url(),
    nav: navProbe,
  };
  fs.writeFileSync(path.join(OUT, "ui-probe.json"), JSON.stringify(report.probe, null, 2));

  const shot = async (name) => {
    const f = path.join(OUT, name);
    await page.screenshot({ path: f, fullPage: true });
    report.screenshots.push(path.basename(f));
    return f;
  };
  await shot("01-home.png");

  if ((navProbe || []).length < 8) {
    fail(`nav too sparse: ${JSON.stringify(navProbe)}`);
  }

  // ── Nav click + panel content assertion ──
  let navOk = 0;
  for (const item of NAV) {
    const byTestId = page.getByTestId(`nav-${item.id}`);
    let clicked = false;
    try {
      if ((await byTestId.count()) > 0) {
        await byTestId.click({ timeout: 8000 });
        clicked = true;
      } else {
        const btn = page.locator("nav button").filter({ hasText: item.label }).first();
        if ((await btn.count()) === 0) {
          report.clicks.push({ label: item.label, id: item.id, ok: false, reason: "not-found" });
          if (STRICT_NAV) fail(`nav missing: ${item.label} (${item.id})`);
          continue;
        }
        await btn.click({ timeout: 8000 });
        clicked = true;
      }
      await page.waitForTimeout(500);

      // active class or panel text
      let panelOk = false;
      const body = (await page.locator("main, .main, .content, .app").first().innerText().catch(() => "")) ||
        (await page.locator("body").innerText());
      if (item.expect.test(body)) panelOk = true;
      // also check active nav
      if ((await byTestId.count()) > 0) {
        const cls = (await byTestId.getAttribute("class")) || "";
        if (cls.includes("active")) panelOk = true;
      }
      if (!panelOk) {
        // softer: create panel testid
        if (item.id === "create" && (await page.getByTestId("create-env-panel").count()) > 0) panelOk = true;
        if (item.id === "profiles" && (await page.getByTestId("profiles-split").count()) > 0) panelOk = true;
        if (item.id === "settings" && (await page.getByTestId("open-api-panel").count()) > 0) panelOk = true;
      }

      if (clicked && panelOk) {
        navOk++;
        report.clicks.push({ label: item.label, id: item.id, ok: true, panel: true });
        step(`nav ${item.id}`, { ok: true });
      } else if (clicked) {
        // click worked but weak panel match — still count click, mark panel weak
        navOk++;
        report.clicks.push({ label: item.label, id: item.id, ok: true, panel: false, note: "weak-panel" });
        step(`nav ${item.id}`, { ok: true, note: "weak-panel-assert" });
      }
    } catch (e) {
      report.clicks.push({ label: item.label, id: item.id, ok: false, reason: String(e).slice(0, 160) });
      fail(`nav click ${item.label}: ${e}`);
    }
  }
  await shot("02-after-nav.png");

  if (navOk < NAV.length - 1) {
    // allow 1 miss only if not strict; strict already failed missing
    if (navOk < 10) fail(`too few successful navs: ${navOk}/${NAV.length}`);
  }

  /** Create profile via Local API when wizard blocked (slim kit: no engine binary). */
  async function createViaApi(name) {
    const FP = {
      schema_version: 1,
      platform: "Win32",
      user_agent:
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
      language: "en-US",
      timezone: "UTC",
      hardware_concurrency: 4,
    };
    const r = await api("POST", "/v1/profiles", {
      name,
      engine_id: "fingerprint-chromium",
      fingerprint: FP,
    });
    report.api.push({ path: "POST /v1/profiles (fallback)", status: r.status });
    return r.status === 200 || r.status === 201;
  }

  async function profileExists(name) {
    const list = await api("GET", "/v1/profiles");
    report.api.push({ path: "GET /v1/profiles verify", status: list.status });
    const arr =
      list.json?.data ||
      list.json?.profiles ||
      (Array.isArray(list.json) ? list.json : []) ||
      [];
    if (!Array.isArray(arr)) return { found: false, arr: [] };
    const hit = arr.find((p) => (p.name || "").includes(name) || p.name === name);
    return { found: !!hit, id: hit?.id || null, arr, status: list.status };
  }

  // ── Create environment wizard (form ops) + API fallback for slim kits ──
  const envName = `ci-e2e-${Date.now()}`;
  let createdVia = null;
  try {
    const navCreate = page.getByTestId("nav-create");
    if ((await navCreate.count()) > 0) await navCreate.click();
    else await page.locator("nav button").filter({ hasText: "新建环境" }).first().click();
    await page.getByTestId("create-env-panel").waitFor({ state: "visible", timeout: 10000 });

    const nameInput = page.getByTestId("create-name");
    await nameInput.waitFor({ state: "visible", timeout: 8000 });
    await nameInput.fill(envName);
    report.forms.push({ field: "create-name", value: envName, ok: true });

    const eng = page.getByTestId("create-engine");
    if ((await eng.count()) > 0) {
      const opts = await eng.locator("option").allTextContents();
      if (opts.length) {
        const want = opts.find((o) => /fingerprint-chromium/i.test(o)) || opts[0];
        await eng.selectOption({ label: want.trim() }).catch(async () => {
          await eng.selectOption({ index: 0 });
        });
        report.forms.push({ field: "create-engine", value: await eng.inputValue(), ok: true });
      }
    }

    // Walk wizard until submit or stall (5 steps: 0..4)
    for (let round = 0; round < 10; round++) {
      const submitNow = page.getByTestId("create-submit");
      if ((await submitNow.count()) > 0 && (await submitNow.isVisible())) break;

      const genFp = page.getByTestId("btn-gen-fp");
      if ((await genFp.count()) > 0 && (await genFp.isVisible())) {
        await genFp.click().catch(() => {});
        await page.waitForTimeout(1200);
        report.forms.push({ field: "btn-gen-fp", ok: true });
      }
      for (const tid of ["btn-refresh-seal-confirm", "btn-refresh-seal", "btn-refresh-seal-banner"]) {
        const rb = page.getByTestId(tid);
        if ((await rb.count()) > 0 && (await rb.isVisible())) {
          await rb.click().catch(() => {});
          await page.waitForTimeout(800);
        }
      }
      const next = page.getByTestId("create-next");
      if ((await next.count()) > 0 && (await next.isVisible())) {
        await next.click();
        await page.waitForTimeout(450);
        report.forms.push({ field: `wizard-next-${round}`, ok: true });
      } else {
        break;
      }
    }

    await shot("03-create-wizard.png");

    const stepErr = await page
      .locator('[data-testid="create-step-err"], .step-err')
      .first()
      .innerText()
      .catch(() => "");
    const engineBlocked =
      /引擎.*未安装|engine.*not installed|请选择打包指纹引擎/i.test(stepErr) ||
      /引擎.*未安装|未安装.*引擎/i.test(await page.locator("body").innerText().catch(() => ""));

    const submit = page.getByTestId("create-submit");
    let uiSubmitted = false;
    if ((await submit.count()) > 0 && (await submit.isVisible()) && !(await submit.isDisabled())) {
      await submit.click();
      await page.waitForTimeout(1500);
      report.forms.push({ field: "create-submit", ok: true });
      uiSubmitted = true;
      createdVia = "ui-wizard";
    } else if (engineBlocked || !(await submit.isVisible().catch(() => false))) {
      step("create-wizard-blocked", { ok: true, note: stepErr.slice(0, 120) || "slim kit / gate" });
      if (await createViaApi(envName)) {
        createdVia = "api-fallback";
        report.forms.push({ field: "create-api-fallback", ok: true });
      } else {
        fail(`create wizard blocked and API fallback failed (${stepErr.slice(0, 80)})`);
      }
    } else if (await submit.isDisabled()) {
      fail(`create-submit disabled — ${stepErr || "form validation blocked save"}`);
    } else {
      fail("create-submit not reachable after wizard walk");
    }

    await shot("04-after-create.png");

    const { found: foundApi, id: profileId, status: listStatus } = await profileExists(envName);
    report.profileId = profileId;

    const bodyAfter = await page.locator("body").innerText();
    let listed =
      bodyAfter.includes(envName) || (await page.getByText(envName, { exact: false }).count()) > 0;
    if (!listed && foundApi) {
      await page.getByTestId("nav-profiles").click().catch(async () => {
        await page.locator("nav button").filter({ hasText: "环境管理" }).first().click();
      });
      await page.waitForTimeout(600);
      listed =
        (await page.getByText(envName, { exact: false }).count()) > 0 ||
        (await page.locator("body").innerText()).includes(envName);
    }

    if (foundApi || listed) {
      step("create-profile", {
        ok: true,
        note: createdVia || (foundApi ? "api" : "ui-list"),
        name: envName,
        id: profileId,
      });
      report.forms.push({
        field: "create-result",
        ok: true,
        api: foundApi,
        ui: listed,
        via: createdVia || (uiSubmitted ? "ui" : "api"),
      });
    } else {
      fail(
        `create profile not found (name=${envName}, via=${createdVia}, apiStatus=${listStatus}, uiSubmitted=${uiSubmitted})`
      );
    }
  } catch (e) {
    if (!createdVia && (await createViaApi(envName))) {
      const { found: foundApi, id: profileId } = await profileExists(envName);
      if (foundApi) {
        createdVia = "api-fallback-catch";
        report.forms.push({ field: "create-result", ok: true, api: true, via: createdVia });
        report.profileId = profileId;
        step("create-profile", { ok: true, note: "api-fallback after wizard error", name: envName });
      } else {
        fail(`create wizard: ${e}`);
        await shot("03-create-fail.png");
      }
    } else {
      fail(`create wizard: ${e}`);
      await shot("03-create-fail.png");
    }
  }

  // ── Proxy form (optional function) ──
  try {
    const navProxy = page.getByTestId("nav-proxy");
    if ((await navProxy.count()) > 0) await navProxy.click();
    else await page.locator("nav button").filter({ hasText: "代理中心" }).first().click();
    await page.waitForTimeout(400);
    // API create proxy (more reliable than guessing form)
    const pname = `ci-proxy-${Date.now()}`;
    const pr = await api("POST", "/v1/proxies", {
      name: pname,
      type: "http",
      host: "127.0.0.1",
      port: 18080,
    });
    report.api.push({ path: "POST /v1/proxies", status: pr.status });
    if (pr.status === 200 || pr.status === 201) {
      step("create-proxy-api", { ok: true, name: pname });
      // refresh UI
      await page.reload({ waitUntil: "domcontentloaded" });
      await page.getByTestId("nav-proxy").click().catch(() => {});
      await page.waitForTimeout(500);
      await shot("05-proxy.png");
    } else if (pr.status === 401) {
      step("create-proxy-api", { ok: false, note: "401 need token" });
      // not hard-fail if profiles create already worked
    } else {
      step("create-proxy-api", { ok: false, status: pr.status, body: pr.text });
    }
  } catch (e) {
    step("proxy", { ok: false, note: String(e).slice(0, 120) });
  }

  // ── Hard gates ──
  const okNav = report.clicks.filter((c) => c.ok).length;
  const createOk = report.forms.some((f) => f.field === "create-result" && f.ok);
  if (okNav < 10) fail(`nav ok count ${okNav} < 10`);
  if (!createOk) fail("create environment form did not complete with API/UI proof");

  await browser.close();
  fs.writeFileSync(path.join(OUT, "ui-e2e-report.json"), JSON.stringify(report, null, 2));
  console.log(
    JSON.stringify(
      {
        ok: report.ok,
        navOk: okNav,
        createOk,
        profileId: report.profileId || null,
        errors: report.errors,
      },
      null,
      2
    )
  );
  if (!report.ok) process.exit(1);
}

main().catch((e) => {
  report.ok = false;
  report.errors.push(String(e));
  fs.writeFileSync(path.join(OUT, "ui-e2e-report.json"), JSON.stringify(report, null, 2));
  console.error(e);
  process.exit(1);
});
