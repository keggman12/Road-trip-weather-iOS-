// Expected Supercharger parsing + request URL from the web's api.js
// getSuperchargersNear, with fetch stubbed.
// Usage: WEB=../roadtrip-weather-app node tools/web-reference/gen-ocm.mjs Packages/RoadTripCore/Tests/RoadTripCoreTests/Fixtures/web-ocm.json
import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";
const WEB = process.env.WEB || path.resolve(process.cwd(), "../roadtrip-weather-app");
globalThis.CONFIG = { OCM_API_KEY: "test key/+&" };
globalThis.window = globalThis;

// Compact OCM payloads covering the parser's edge cases.
const payloads = {
  typical: [
    { AddressInfo: { Title: "Amarillo, TX Supercharger", Latitude: 35.1872, Longitude: -101.8695, Distance: 3.2671, Town: "Amarillo", StateOrProvince: "TX" },
      NumberOfPoints: 12, Connections: [{ PowerKW: 250 }, { PowerKW: 72 }, {}] },
    { AddressInfo: { Title: "Canyon Supercharger", Latitude: 34.9803, Longitude: -101.9188, Distance: 17.95, Town: "Canyon" },
      NumberOfPoints: 0, Connections: [] },
  ],
  sparse: [
    { AddressInfo: { Latitude: 36.0, Longitude: -102.0 } },
    { AddressInfo: { Title: "No coords" } },
    { AddressInfo: { Title: "Half coords", Latitude: 36.1 } },
    { AddressInfo: { Title: "Zero kW", Latitude: 36.2, Longitude: -102.2, Distance: 0.04, StateOrProvince: "NM" }, NumberOfPoints: 4, Connections: [{ PowerKW: 0 }, { PowerKW: null }] },
  ],
  notArray: { error: "bad key" },
};

let lastURL = null;
let reply = null;
globalThis.fetch = async (url) => {
  lastURL = url;
  return { ok: reply.ok, json: async () => reply.body };
};
const { getSuperchargersNear } = await import(pathToFileURL(path.join(WEB, "public/js/api.js")).href);

const out = { cases: [] };
for (const [name, body] of Object.entries(payloads)) {
  reply = { ok: true, body };
  const chargers = await getSuperchargersNear(35.22198765, -101.83129876);
  out.cases.push({ name, payload: body, chargers });
}
reply = { ok: false, body: payloads.typical };
out.cases.push({ name: "httpError", payload: payloads.typical, httpOK: false, chargers: await getSuperchargersNear(35.2, -101.8) });
await getSuperchargersNear(35.22198765, -101.83129876);
out.url = lastURL;
fs.writeFileSync(process.argv[2], JSON.stringify(out, null, 2) + "\n");
console.log("wrote", out.cases.length, "OCM cases");
