import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";

const rules = readdirSync("docs/rules", { recursive: true })
  .filter(file => file.endsWith(".md") && file.includes("/"))
  .map(file => file.replace(/\.md$/, ""));
assert.ok(rules.length > 40, "Expected the complete rule reference");

const index = readFileSync("_site/rules/index.html", "utf8");
assert.match(index, /<input[^>]+type="search"/);
for (const rule of rules) {
  assert.ok(index.includes(`href="${rule}/"`), `Missing index link for ${rule}`);
  const page = readFileSync(join("_site/rules", rule, "index.html"), "utf8");
  assert.ok(page.includes(rule), `Missing title for ${rule}`);
  assert.ok(page.includes("<main"), `Missing page content for ${rule}`);
}
console.log(`Published ${rules.length} rule reference pages.`);
