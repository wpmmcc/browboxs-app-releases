/**
 * WebdriverIO + tauri-driver against **installed** browboxs-desktop.
 * Public pack-and-test S3b. Not Playwright / not a static http.server page.
 */
import path from "node:path";
import os from "node:os";
import { spawn } from "node:child_process";
import fs from "node:fs";

const PREFIX = process.env.BROWBOX_PREFIX || process.env.BROWBOX_INSTALL_ROOT || "";
const exe = process.platform === "win32" ? ".exe" : "";
const DESKTOP =
  process.env.BROWBOX_DESKTOP ||
  (PREFIX ? path.join(PREFIX, "bin", `browboxs-desktop${exe}`) : "");
const DRIVER_BIN =
  process.env.TAURI_DRIVER ||
  (process.platform === "win32"
    ? path.join(os.homedir(), ".cargo", "bin", "tauri-driver.exe")
    : path.join(os.homedir(), ".cargo", "bin", "tauri-driver"));
const DRIVER_PORT = String(process.env.TAURI_DRIVER_PORT || "4444");
const NATIVE_PORT = String(process.env.TAURI_NATIVE_PORT || "4445");
const AGENT_PORT = String(process.env.BROWBOX_AGENT_PORT || "18985");

let tauriDriver;

export const config = {
  runner: "local",
  hostname: "127.0.0.1",
  port: Number(DRIVER_PORT),
  path: "/",
  specs: ["./specs/**/*.js"],
  maxInstances: 1,
  capabilities: [
    {
      maxInstances: 1,
      "tauri:options": {
        application: DESKTOP,
        args: [],
      },
    },
  ],
  logLevel: "info",
  bail: 1,
  waitforTimeout: 25000,
  connectionRetryTimeout: 180000,
  connectionRetryCount: 2,
  framework: "mocha",
  reporters: ["spec"],
  mochaOpts: {
    ui: "bdd",
    timeout: 180000,
  },
  onPrepare() {
    if (!DESKTOP || !fs.existsSync(DESKTOP)) {
      throw new Error(`browboxs-desktop missing: ${DESKTOP}`);
    }
    if (!fs.existsSync(DRIVER_BIN)) {
      throw new Error(`tauri-driver missing: ${DRIVER_BIN}`);
    }
    console.log("[e2e-tauri] desktop:", DESKTOP);
    console.log("[e2e-tauri] tauri-driver:", DRIVER_BIN);
    console.log("[e2e-tauri] install-root:", PREFIX);
    const nativeArgs = ["--port", DRIVER_PORT, "--native-port", NATIVE_PORT];
    if (process.env.TAURI_NATIVE_DRIVER) {
      nativeArgs.push("--native-driver", process.env.TAURI_NATIVE_DRIVER);
    }
    tauriDriver = spawn(DRIVER_BIN, nativeArgs, {
      stdio: "inherit",
      env: {
        ...process.env,
        BROWBOX_INSTALL_ROOT: PREFIX,
        BROWBOX_AGENT_BIN: PREFIX
          ? path.join(PREFIX, "bin", `browboxs-agent${exe}`)
          : "",
        BROWBOX_PREFIX: PREFIX,
        BROWBOX_AGENT_PORT: AGENT_PORT,
        BROWBOX_AGENT_DATA: PREFIX ? path.join(PREFIX, "data", "agent") : "",
        BROWBOX_E2E_KEEP_SPLASH: "1",
        DISPLAY: process.env.DISPLAY || ":0",
      },
    });
    return new Promise((r) => setTimeout(r, 2000));
  },
  onComplete() {
    try {
      tauriDriver?.kill();
    } catch {
      /* ignore */
    }
  },
};
