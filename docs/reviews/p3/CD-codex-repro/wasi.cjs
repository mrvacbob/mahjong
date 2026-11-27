const fs = require("node:fs");
const { WASI } = require("node:wasi");

const args = process.argv.slice(2);
const wasi = new WASI({ version: "preview1", args });
const moduleBytes = fs.readFileSync(args[0]);
const instance = new WebAssembly.Instance(new WebAssembly.Module(moduleBytes),
    { wasi_snapshot_preview1: wasi.wasiImport });
wasi.start(instance);
