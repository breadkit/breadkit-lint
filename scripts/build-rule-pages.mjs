import { readFileSync, readdirSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import MarkdownIt from "markdown-it";

const markdown = new MarkdownIt({ html: false, linkify: true });
const source = "docs/rules";
const output = "_site/rules";
const categories = ["Layout", "Electrical", "Intent", "Style", "Lint"];
const files = readdirSync(source, { recursive: true }).filter(file => file.endsWith(".md") && file.includes("/"));
const rules = files.map(file => {
  const id = file.replace(/\.md$/, "");
  const contents = readFileSync(join(source, file), "utf8");
  const summary = contents.split(/\n\s*\n/).slice(1).find(part => part && !part.startsWith("```")) || "";
  return { id, contents, summary };
}).sort((a, b) => a.id.localeCompare(b.id));

function escapeHtml(value) {
  return value.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;").replaceAll('"', "&quot;");
}

function layout(title, content, depth) {
  const root = "../".repeat(depth);
  const pageTitle = title === "Rule reference" ? "Rule reference | breadkit-lint" : `${title} | breadkit-lint`;
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="theme-color" content="#101719">
  <meta name="description" content="Breadkit lint rule reference: ${escapeHtml(title)}">
  <title>${escapeHtml(pageTitle)}</title>
  <link rel="canonical" href="https://breadkit.github.io/breadkit-lint/rules/${depth === 1 ? "" : `${title}/`}">
  <link rel="icon" href="${root}favicon.svg" type="image/svg+xml">
  <link rel="stylesheet" href="${root}assets/site.css">
</head>
<body class="min-h-dvh bg-ink font-sans text-paper antialiased">
  <a class="sr-only rounded-sm bg-copper px-4 py-3 font-semibold text-ink focus:not-sr-only focus:fixed focus:left-4 focus:top-4" href="#main">Skip to content</a>
  <header class="border-b border-line"><div class="mx-auto flex max-w-7xl flex-wrap items-center justify-between gap-4 px-5 py-5 sm:px-8 lg:px-10">
    <a class="flex items-center gap-3 rounded-sm text-xl font-semibold focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-copper" href="${root}" aria-label="breadkit-lint home"><img class="size-8" src="${root}favicon.svg" alt="" width="32" height="32"><span>breadkit-lint</span></a>
    <nav aria-label="Main navigation" class="flex flex-wrap items-center gap-x-5 gap-y-2 text-sm text-muted"><a class="text-paper focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-copper" href="${root}rules/" aria-current="page">Rules</a><a class="hover:text-paper focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-copper" href="https://breadkit.github.io/breadkit/guide/">Guide</a><a class="hover:text-paper focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-copper" href="https://github.com/breadkit/breadkit-lint">GitHub</a></nav>
  </div></header>
  <main id="main" class="mx-auto max-w-7xl px-5 py-12 sm:px-8 lg:px-10">${content}</main>
  <footer class="mt-16 border-t border-line"><div class="mx-auto max-w-7xl px-5 py-7 text-sm text-muted sm:px-8 lg:px-10">breadkit-lint is published independently from breadkit.</div></footer>
</body>
</html>`;
}

rmSync(output, { recursive: true, force: true });
mkdirSync(output, { recursive: true });
for (const rule of rules) {
  const directory = join(output, rule.id);
  mkdirSync(directory, { recursive: true });
  const content = `<a class="text-sm text-muted underline decoration-line underline-offset-4 hover:text-paper" href="../../">All rules</a>
    <article class="rule-doc mt-8">${markdown.render(rule.contents)}</article>`;
  writeFileSync(join(directory, "index.html"), layout(rule.id, content, 3));
}

const sections = categories.map(category => {
  const entries = rules.filter(rule => rule.id.startsWith(`${category}/`));
  if (!entries.length) return "";
  const items = entries.map(rule => `<li class="rule-item border-t border-line py-4" data-rule="${escapeHtml(rule.id.toLowerCase())}">
    <a class="font-mono text-paper underline decoration-line underline-offset-4 hover:decoration-copper focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-copper" href="${rule.id}/">${escapeHtml(rule.id)}</a>
    <p class="rule-summary mt-2 text-pretty text-sm leading-6 text-muted">${markdown.renderInline(rule.summary)}</p>
  </li>`).join("");
  return `<section class="rule-category mt-10" aria-labelledby="${category.toLowerCase()}-heading"><h2 id="${category.toLowerCase()}-heading" class="text-balance text-2xl font-semibold">${category}</h2><ul class="mt-4">${items}</ul></section>`;
}).join("");
const index = `<div class="max-w-3xl"><h1 class="text-balance text-4xl font-semibold leading-tight sm:text-5xl">Rule reference</h1>
  <p class="mt-4 text-pretty text-lg leading-8 text-muted">Find what each check means, see an example, and learn how to fix it.</p>
  <label class="mt-8 block text-sm font-medium" for="rule-search">Search rules</label>
  <input id="rule-search" class="mt-2 w-full rounded-md border border-line bg-board px-4 py-3 text-paper focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-copper" type="search" autocomplete="off" placeholder="Search by rule name" aria-controls="rule-list">
  <p id="rule-count" class="mt-3 text-sm text-muted" role="status">${rules.length} rules</p>
  <div id="rule-list">${sections}</div>
  <p id="rule-empty" class="mt-8 text-muted" hidden>No rules match. Try a shorter name.</p>
</div>
<script>
  const search = document.querySelector('#rule-search');
  const items = [...document.querySelectorAll('.rule-item')];
  search.addEventListener('input', () => {
    const query = search.value.trim().toLowerCase();
    let count = 0;
    for (const item of items) { item.hidden = !item.dataset.rule.includes(query); if (!item.hidden) count++; }
    for (const section of document.querySelectorAll('.rule-category')) section.hidden = !section.querySelector('.rule-item:not([hidden])');
    document.querySelector('#rule-count').textContent = count + (count === 1 ? ' rule' : ' rules');
    document.querySelector('#rule-empty').hidden = count !== 0;
  });
</script>`;
writeFileSync(join(output, "index.html"), layout("Rule reference", index, 1));
