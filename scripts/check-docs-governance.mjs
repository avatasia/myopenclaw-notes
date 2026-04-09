#!/usr/bin/env node

import childProcess from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import process from "node:process";

function parseArgs(argv) {
  const args = {
    all: false,
    repoRoot: process.cwd(),
    docsDir: ".",
  };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--all") {
      args.all = true;
      continue;
    }
    if (arg === "--repo-root") {
      args.repoRoot = argv[i + 1];
      i += 1;
      continue;
    }
    if (arg === "--docs-dir") {
      args.docsDir = argv[i + 1];
      i += 1;
      continue;
    }
    throw new Error(`Unknown argument: ${arg}`);
  }
  return args;
}

function abs(value) {
  return path.resolve(value);
}

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function walk(dir, out = []) {
  const entries = fs.readdirSync(dir, { withFileTypes: true });
  for (const entry of entries) {
    if (entry.name === ".git" || entry.name === "node_modules") continue;
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      walk(full, out);
      continue;
    }
    out.push(full);
  }
  return out;
}

function listStagedMarkdownFiles(repoRoot, docsRoot) {
  let output;
  try {
    output = childProcess.execSync("git diff --cached --name-only --diff-filter=ACMR", {
      cwd: repoRoot,
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
    });
  } catch (err) {
    throw new Error(`Failed to read staged files from git: ${String(err)}`);
  }
  const docsRootNorm = `${docsRoot}${path.sep}`;
  return output
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean)
    .map((relPath) => path.resolve(repoRoot, relPath))
    .filter((file) => file === docsRoot || file.startsWith(docsRootNorm))
    .filter((file) => file.endsWith(".md"))
    .filter((file) => fs.existsSync(file));
}

function rel(repoRoot, file) {
  return path.relative(repoRoot, file);
}

function isSkippableLink(target) {
  return target.startsWith("http://")
    || target.startsWith("https://")
    || target.startsWith("mailto:")
    || target.startsWith("#");
}

function cleanLinkTarget(target) {
  const trimmed = target.trim().replace(/^<|>$/g, "");
  const noAnchor = trimmed.split("#")[0];
  return noAnchor.split("?")[0];
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const repoRoot = abs(args.repoRoot);
  const docsRoot = abs(path.join(repoRoot, args.docsDir));
  const errors = [];

  if (!fs.existsSync(repoRoot) || !fs.statSync(repoRoot).isDirectory()) {
    throw new Error(`Invalid --repo-root: ${repoRoot}`);
  }
  if (!fs.existsSync(docsRoot) || !fs.statSync(docsRoot).isDirectory()) {
    throw new Error(`Invalid --docs-dir under repo root: ${docsRoot}`);
  }

  const markdownLinkRe = /\[([^\]]+)\]\(([^)]+)\)/g;
  const targetFiles = args.all
    ? walk(docsRoot).filter((file) => file.endsWith(".md"))
    : listStagedMarkdownFiles(repoRoot, docsRoot);

  const docsDirName = path.basename(docsRoot);
  if (docsDirName === "docs") {
    for (const entry of fs.readdirSync(docsRoot, { withFileTypes: true })) {
      if (!entry.isFile()) continue;
      if (!entry.name.endsWith(".md")) continue;
      if (/\d{4}-\d{2}-\d{2}/.test(entry.name)) {
        errors.push(`Top-level docs filename must not include date: ${path.join("docs", entry.name)}`);
      }
    }
  }

  const historyDir = path.join(docsRoot, "archive", "history");
  const historyReadme = path.join(historyDir, "README.md");
  if (fs.existsSync(historyDir) && fs.existsSync(historyReadme)) {
    const historyContent = fs.readFileSync(historyReadme, "utf8");
    const historyFiles = fs.readdirSync(historyDir).filter((name) => name.endsWith("_HISTORY.md"));
    for (const file of historyFiles) {
      const targetRe = new RegExp(`\\[[^\\]]+\\]\\((?:\\./)?${escapeRegExp(file)}\\)`);
      if (!targetRe.test(historyContent)) {
        errors.push(`History file is not indexed in ${rel(repoRoot, historyReadme)}: ${file}`);
      }
    }
  }

  if (targetFiles.length === 0) {
    console.log("No target markdown changes found. Structural checks only.");
  } else {
    const repoRootRe = new RegExp(escapeRegExp(repoRoot));
    for (const file of targetFiles) {
      const content = fs.readFileSync(file, "utf8");

      if (repoRootRe.test(content)) {
        errors.push(`Absolute repo path found in ${rel(repoRoot, file)}`);
      }

      let match;
      while ((match = markdownLinkRe.exec(content)) !== null) {
        const rawTarget = match[2];
        if (isSkippableLink(rawTarget)) continue;
        const target = cleanLinkTarget(rawTarget);
        if (!target) continue;
        if (path.isAbsolute(target)) {
          errors.push(`Absolute link path is not allowed in ${rel(repoRoot, file)}: ${rawTarget}`);
          continue;
        }
        const resolved = path.resolve(path.dirname(file), target);
        if (!fs.existsSync(resolved)) {
          errors.push(`Broken link in ${rel(repoRoot, file)}: ${rawTarget}`);
        }
      }
    }
  }

  if (errors.length > 0) {
    console.error("Docs governance checks failed:");
    for (const error of errors) console.error(`- ${error}`);
    process.exit(1);
  }
  console.log("Docs governance checks passed.");
}

try {
  main();
} catch (err) {
  console.error(`Docs governance check error: ${String(err)}`);
  process.exit(1);
}
