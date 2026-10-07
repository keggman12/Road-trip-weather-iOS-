// Generates reference values from the web app's own code for RoadTripCore tests.
// Usage: WEB=/path/to/roadtrip-weather-app node tools/web-reference/gen.mjs Packages/RoadTripCore/Tests/RoadTripCoreTests/Fixtures/web-reference.json
import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";
const WEB = process.env.WEB || path.resolve(process.cwd(), "../roadtrip-weather-app");
const util = await import(pathToFileURL(path.join(WEB, "public/js/util.js")).href);
const { sampleWaypoints, haversineMi, bearingDeg, relativeWind, windCompass, windArrowRotation, thinPolyline, minDistToPolylineMi } = util;
const { categorize } = await import(pathToFileURL(path.join(WEB, "public/js/icons.js")).href);

const appSrc = fs.readFileSync(path.join(WEB, "public/js/app.js"), "utf8");
function extract(name) {
  const start = appSrc.indexOf(`function ${name}(`);
  if (start < 0) throw new Error("missing " + name);
  let depth = 0, i = appSrc.indexOf("{", start);
  for (; i < appSrc.length; i++) {
    if (appSrc[i] === "{") depth++;
    else if (appSrc[i] === "}") { depth--; if (depth === 0) break; }
  }
  return appSrc.slice(start, i + 1);
}
const code = [extract("nextResumeEpoch"), extract("computeEtas"), extract("scoreStops"), extract("projectOntoRoute"),
  extract("assignTravelBearings")].join("\n") +
  "\nreturn { nextResumeEpoch, computeEtas, scoreStops, projectOntoRoute, assignTravelBearings };";
const { computeEtas, scoreStops, projectOntoRoute, assignTravelBearings } = new Function("haversineMi", "bearingDeg", code)(haversineMi, bearingDeg);

const out = {};

// Synthetic route: Denver -> Dallas-ish straight line with 200 points.
const A = { lat: 39.7392, lon: -104.9903 }, B = { lat: 32.7767, lon: -96.797 };
const route = [];
for (let i = 0; i < 200; i++) {
  const f = i / 199;
  // slight curve so it is not a perfect line
  route.push({ lat: A.lat + (B.lat - A.lat) * f + 0.4 * Math.sin(f * Math.PI), lon: A.lon + (B.lon - A.lon) * f });
}
out.route = route.map((c) => [c.lat, c.lon]);
out.haversine = { denverDallas: haversineMi(A, B), zero: haversineMi(A, A) };
out.bearing = { denverToDallas: bearingDeg(A, B), dallasToDenver: bearingDeg(B, A), north: bearingDeg({lat:0,lon:0},{lat:1,lon:0}), east: bearingDeg({lat:0,lon:0},{lat:0,lon:1}) };

function wps(range) {
  const r = sampleWaypoints(route, range);
  return { totalMi: r.totalMi, waypoints: r.waypoints.map((w) => ({ lat: w.lat, lon: w.lon, routeIndex: w.routeIndex, distanceMi: w.distanceMi })) };
}
out.sample300 = wps(300);
out.sample180 = wps(180);
out.sample5 = wps(5);     // overflow -> 25 waypoints
out.sample2 = wps(2);     // interval clamps to 5 then overflow
out.sampleHuge = wps(5000);

// ETA: use UTC "browser" timezone for reference; departure 2026-06-10T13:00:00Z
process.env.TZ = "UTC";
const depart = Date.UTC(2026, 5, 10, 13, 0, 0) / 1000;
const DEFAULT_DWELL = 15;
function mkStops(sample) {
  return sample.waypoints.map((w, i) => ({ ...w, dwellMin: (i === 0 || i === sample.waypoints.length - 1) ? 0 : DEFAULT_DWELL, manualOvernight: false }));
}
const durationSec = 11.5 * 3600;
{
  const s = mkStops(out.sample300);
  computeEtas(s, out.sample300.totalMi, durationSec, depart, { enabled: false, maxDriveSec: 10 * 3600, resume: "08:00" });
  assignTravelBearings(s);
  out.eta300 = s.map((x) => ({ etaEpoch: x.etaEpoch, legMi: x.legMi, overnight: x.overnight, resumeEpoch: x.resumeEpoch, travelBearing: x.travelBearing }));
}
{
  const s = mkStops(out.sample180);
  s[2].dwellMin = 45;
  computeEtas(s, out.sample180.totalMi, durationSec, depart, { enabled: true, maxDriveSec: 6 * 3600, resume: "08:30" });
  out.eta180multiday = s.map((x) => ({ etaEpoch: x.etaEpoch, legMi: x.legMi, overnight: x.overnight, autoOvernight: x.autoOvernight, resumeEpoch: x.resumeEpoch }));
}
{
  const s = mkStops(out.sample300);
  s[1].manualOvernight = true;
  computeEtas(s, out.sample300.totalMi, durationSec, depart, { enabled: false, maxDriveSec: 10 * 3600, resume: "07:15" });
  out.eta300manual = s.map((x) => ({ etaEpoch: x.etaEpoch, overnight: x.overnight, resumeEpoch: x.resumeEpoch }));
}

// Wind
out.wind = [];
for (const [w, t] of [[0, 0], [180, 0], [90, 0], [45, 0], [135, 0], [225, 0], [315, 0], [10, 200], [350, 170], [270, 90], [0, 180], [44.9, 180+0], [45.1, 0]]) {
  out.wind.push({ w, t, rel: relativeWind(w, t), compass: windCompass(w), rot: windArrowRotation(w) });
}
out.compassAll = Array.from({ length: 36 }, (_, i) => [i * 10, windCompass(i * 10)]);
out.compassEdge = [[11.24, windCompass(11.24)], [11.25, windCompass(11.25)], [359, windCompass(359)], [348.75, windCompass(348.75)]];

// Categorize
out.categorize = [];
for (const id of [200, 232, 299, 300, 500, 511, 599, 600, 622, 701, 741, 762, 771, 781, 800, 801, 802, 803, 804, null, undefined]) {
  for (const cl of [null, 0, 14, 15, 49, 50, 100]) out.categorize.push({ id: id === undefined ? "undef" : id, cl, cat: categorize(id, cl) });
}

// Scoring
const mkW = (temp, pop, category, windSpeed) => ({ temp, pop, category, windSpeed });
const scoreStopsInput = [
  { weather: mkW(65, 0, "clear", 5), alerts: [] },
  { weather: mkW(72, 0.3, "rain", 18), alerts: [] },
  { weather: null, alerts: [] },
  { weather: mkW(40, 0.9, "thunderstorm", 25), alerts: [{ id: "x" }] },
  { weather: mkW(95, null, "mostly-cloudy", 10), alerts: [] },
  { weather: mkW(55, 0.5, "snow", 0), alerts: [] },
];
const sc = scoreStops(scoreStopsInput);
out.score = { score: sc.score, worstIdx: scoreStopsInput.indexOf(sc.worst.stop), worstP: sc.worst.p };
out.scoreEmpty = scoreStops([]);
out.scoreAllUnknown = scoreStops([{}, {}, {}]).score;
out.scoreRounding = scoreStops([{ weather: mkW(66, 0.0125, "clear", 10), alerts: [] }]).score; // 0.5+0.3 = 0.8 -> 1

// Projection
const P = { lat: 36.0, lon: -100.5 };
out.project = projectOntoRoute(route, P);
out.minDist = minDistToPolylineMi(P, route);
out.thin = { len: thinPolyline(route, 120).length, first: thinPolyline(route, 120)[0], last: thinPolyline(route, 120)[119], idx7: thinPolyline(route, 120)[7] };

// Optimizer candidate math (copied from runOptimizer)
function candCount(spanH, routes) {
  let n = Math.max(2, Math.min(6, Math.round(spanH / 2.5) + 1));
  if (routes > 1) n = Math.max(2, Math.min(n, Math.floor(12 / routes)));
  return n;
}
out.candidates = [];
for (const spanH of [0.5, 1, 2, 3, 5, 6, 10, 12, 24, 48]) for (const r of [1, 2, 3, 4, 5, 7]) out.candidates.push({ spanH, r, n: candCount(spanH, r) });

fs.writeFileSync(process.argv[2], JSON.stringify(out, null, 1));
console.log("wrote", process.argv[2]);
