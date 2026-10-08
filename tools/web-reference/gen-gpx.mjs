// Expected GPX documents from the web app's own gpx.js for GPXBuilder tests.
// Usage: WEB=../roadtrip-weather-app node tools/web-reference/gen-gpx.mjs Packages/RoadTripCore/Tests/RoadTripCoreTests/Fixtures/web-gpx.json
import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";
const WEB = process.env.WEB || path.resolve(process.cwd(), "../roadtrip-weather-app");
const { buildGPX } = await import(pathToFileURL(path.join(WEB, "public/js/gpx.js")).href);

// The metadata <time> is "now" in the web; tests compare with it masked.
const mask = (gpx) => gpx.replace(/<metadata><name>(.*?)<\/name><time>[^<]*<\/time>/, "<metadata><name>$1</name><time>NOW</time>");

const coords = [
  { lat: 39.7392, lon: -104.9903 }, { lat: 38.2544123, lon: -104.6091456 },
  { lat: 35.2219971, lon: -101.8312969 }, { lat: 32.7766642, lon: -96.7969879 },
];
const stops = [
  { lat: 39.7392, lon: -104.9903, etaEpoch: 1781096400, label: "Denver, CO",
    weather: { temp: 71, category: "partly-cloudy", desc: "partly cloudy", windSpeed: 12, pop: null }, overnight: false },
  { lat: 38.2544123, lon: -104.6091456, etaEpoch: 1781106000, label: "Pueblo <I-25 & US-50>",
    weather: { temp: 84, category: "thunderstorm", desc: "thunderstorm", windSpeed: 20, pop: 0.645 }, overnight: false },
  { lat: 35.2219971, lon: -101.8312969, etaEpoch: 1781125200, label: "Amarillo \"Big Texan\" 'stop'",
    weather: { temp: 66, category: "clear", desc: "clear", windSpeed: 5, pop: 0 }, overnight: true },
  { lat: 32.7766642, lon: -96.7969879, etaEpoch: 1781190000, label: "Dallas, TX", weather: null, overnight: false },
];
const cases = [
  { name: "Denver → Dallas & back", coords, stops },
  { name: "Two stops", coords: coords.slice(0, 2), stops: [stops[0], { ...stops[3], overnight: true }] },
];
const out = cases.map((c) => ({ ...c, gpx: mask(buildGPX(c)) }));
fs.writeFileSync(process.argv[2], JSON.stringify(out, null, 2) + "\n");
console.log("wrote", out.length, "GPX cases");
