# Changelog — Road Trip Weather (iOS)

Changes in user-visible behavior, written so the Android port can match them.
Each entry names the iOS issue/PR. Platform details are in brackets.

## TestFlight 0.1.0 build 5

### Added
- **Drop a pin to add a via-point** (PR #16). On the Routes map, long-press and confirm "Add
  via-point and find routes"; routes are found again through that spot. Tap a pin to remove it.
  Several pins are allowed; each slots in between the points it detours least. A pin's text is
  its coordinate ("38.05412, -104.98761"), labelled "Pin near Pueblo, CO" by reverse geocoding,
  so it survives saved trips without geocoding by name. "lat, lon" typed in any place field
  resolves the same way. Pins stay out of recents and mismatch notices.
- **Every via-point is a stop with its own weather** (PR #16, owner decision). Typed vias and
  pins become VIA stops on the routes chained through them, forecast at the via's own
  coordinate ("Via-point · 3.2 mi off route"), dwell 0, removed with the via-point (no Remove
  button on the card). Direct/alternate/suggested routes don't get them.
  *Port note:* not on Android yet; Android's picked-places pattern and OSRM routing take it
  directly (OSRM accepts waypoints in one request).

### Fixed
- **Weather and itinerary fixes** (PR #14) and their follow-ups (PR #15):
  - A failed refresh keeps cached forecasts and alerts and says how many failed; missing
    forecasts can't win the optimizer's Best badge.
  - Regenerate keeps the edited itinerary, but re-plans when the range/vehicle changed, keeping
    added stops and removals. The optimizer scores planned stops only (§4).
  - Past departures: Plan rejects them and offers Depart today; a new briefing or an optimizer
    result for a passed departure is refused; underway trips refresh upcoming stops only; ETAs
    over an hour past get no forecast (WeatherKit used to crash or return the current hour).
  - Manual stops keep the address's coordinates for weather and navigation.
  - The weekly POI refresh runs in the foreground when due; an interrupted one stays due.
  *Port note:* Android has these in its PRs #8 and #9.

## Unreleased (TestFlight 0.1.0 builds 2–4)

### Distribution
- **Build 4 can go to external testers** (TestFlight external groups, after Apple's Beta App
  Review). Builds 1–3 were uploaded as internal-only and can only go to App Store Connect team
  members. Build 4 has the same features as build 3; no app behavior changed.
  *Port note:* the Android equivalent is a Play Console closed or open testing track, not
  internal testing only.

### Fixed
- **Crash when editing or removing a via-point row** (#2, PR #6). The Plan form identified via
  rows by their position in the list. Removing a row while another row was redrawing (e.g.
  during voice dictation) read a position that no longer existed and crashed. Each via row now
  has a stable ID, and edits and removals find the row by that ID. Saved sessions still store
  vias as a plain list of strings.
  *Port note:* key list rows by a stable ID, never by index, in any editable list.

### Added
- **Address suggestions while typing** (#4, PR #6) in Origin, Via, Destination and Add a stop.
  - Suggestions start at 3 characters; show at most 5, each with a title and subtitle
    (e.g. "Denver International Airport" / "Denver, CO"), listed under the field being edited.
  - Picking one fills the field with "Title, Subtitle" and resolves it to an exact place
    (coordinates + time zone). Find Routes and Add stop then use that place directly: no second
    geocode and no "check the spelling" mismatch notice.
  - Typing freely without picking still works and is geocoded as before. Suggestions
    disappear when the field loses focus.
  - Free, no API key, no server. [iOS: MapKit `MKLocalSearchCompleter`, results of type
    address + point of interest.]
- **Use current location** (#3, PR #6): a crosshairs button in each location field.
  - The first tap asks for when-in-use location permission. The app takes one location fix and
    reverse geocodes it.
  - The field gets the street address ("123 Main St, Thornton, CO"). The place's display label is
    the town ("Thornton, CO"), so trip names read "Thornton → Dallas".
  - If nothing reverse geocodes, the field gets "lat, lon" to 5 decimals.
  - Errors are shown under the field: permission off ("turn it on in Settings") or no fix
    within 15 s ("try again, or type an address"). A spinner replaces the button while it works.
- **Add a stop field (briefing screen) works like the Plan fields** (#8, PR #10):
  suggestions, current location, recent places, clear button. A picked place is added as is.
  Placeholder: "Add a stop (address, city or place)".
- **Clear (ⓧ) button** (#9, PR #10) in every location field, shown only while the field has text.
  Tapping it empties the field and keeps the cursor in it.

### Changed
- **Placeholders say what to type** (#5, PR #6): "Origin address or city",
  "Via-point address or city", "Destination address or city". Once a field has text, a small
  caption above it keeps the field's name ("Origin", "Via", "Destination", "New stop").
- **Removing a via row** (#9, PR #10) uses a red minus (−) instead of ✕, so it can't be confused
  with the clear button.
- Field layout, left to right: [text] [ⓧ clear] [⌖ current location] [🕘 recents], then the via
  row's red minus outside the field.

### Not a change
- #7, "precip chart doesn't work": works as designed. The chart is hidden unless at least
  2 stops have a precipitation chance.
