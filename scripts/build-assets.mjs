// Minifies public/assets/{css,js} into sibling .min.css/.min.js files. Run via `npm run build`.
// app.bxs picks these up automatically when present (see its app.locals.assets block) — a
// checkout that hasn't run this yet just keeps serving the raw files, so this is opt-in, not
// required for the app to run.
import { build } from "esbuild";
import { readdirSync } from "node:fs";
import path from "node:path";

const cssDir = "public/assets/css";
const jsDir = "public/assets/js";

// site.css is the one stylesheet every page links to; it @imports every other file in this
// directory (see its own header comment). Left alone, that's a serial fetch chain the browser
// can't parallelize, and it bypasses per-file minification entirely (the .min.css produced
// below for e.g. feed.css is never linked from anywhere — site.css's browser-resolved @import
// still points at the raw file). bundle:true here resolves the whole @import chain into one
// physical file, so the page makes one request instead of a chain, and the previously-external
// rules get minified too.
await build({
	entryPoints: [path.join(cssDir, "site.css")],
	bundle: true,
	minify: true,
	outfile: path.join(cssDir, "site.min.css"),
	allowOverwrite: true,
	logLevel: "info",
	// url(/assets/fonts/...) references are already correct, server-root-relative paths —
	// not something the bundler should try to resolve/copy as a local file.
	external: ["/assets/*"],
});

// Every other CSS file, minified standalone in case a view ever links one directly instead
// of going through site.css's @import chain.
const otherCssEntries = readdirSync(cssDir)
	.filter((f) => f.endsWith(".css") && !f.endsWith(".min.css") && f !== "site.css")
	.map((f) => path.join(cssDir, f));

const jsEntries = readdirSync(jsDir)
	.filter((f) => f.endsWith(".js") && !f.endsWith(".min.js"))
	.map((f) => path.join(jsDir, f));

await build({
	entryPoints: otherCssEntries,
	minify: true,
	outdir: cssDir,
	outExtension: { ".css": ".min.css" },
	allowOverwrite: true,
	logLevel: "info",
});

await build({
	entryPoints: jsEntries,
	minify: true,
	outdir: jsDir,
	outExtension: { ".js": ".min.js" },
	target: "es2019",
	allowOverwrite: true,
	logLevel: "info",
});

console.log("Built minified CSS/JS assets.");
