import { render } from "preact";
import { App } from "./app";

// Service Worker registration (app-shell-only cache) — TODO(#21).
const root = document.getElementById("app");
if (root) {
  render(<App />, root);
}
