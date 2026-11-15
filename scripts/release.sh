#!/bin/sh
set -eu

# Print help message
usage() {
  printf "Usage: %s <version> [--push]\n" "$0" >&2
  printf "Example: %s 0.3.2\n" "$0" >&2
  exit 1
}

if [ "$#" -lt 1 ]; then
  usage
fi

TARGET_VERSION=""
AUTO_PUSH=0

for arg in "$@"; do
  case "$arg" in
    --push|-p)
      AUTO_PUSH=1
      ;;
    -h|--help)
      usage
      ;;
    *)
      if [ -z "$TARGET_VERSION" ]; then
        TARGET_VERSION="$arg"
      else
        printf "Error: unexpected argument: %s\n" "$arg" >&2
        usage
      fi
      ;;
  esac
done

if [ -z "$TARGET_VERSION" ]; then
  usage
fi

# Strip optional leading 'v'
TARGET_VERSION="${TARGET_VERSION#v}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

printf "==> Preparing release v%s...\n" "$TARGET_VERSION"

# 1. Ensure working directory is clean
if [ -n "$(git status --porcelain)" ]; then
  printf "Error: git working directory is not clean. Commit or stash changes first.\n" >&2
  exit 1
fi

# 2. Ensure tag does not already exist
TAG_NAME="v$TARGET_VERSION"
if git rev-parse "$TAG_NAME" >/dev/null 2>&1; then
  printf "Error: Git tag %s already exists.\n" "$TAG_NAME" >&2
  exit 1
fi

# 3. Update package.json version
printf "==> Updating package.json version to %s...\n" "$TARGET_VERSION"
node -e '
  const fs = require("fs");
  const p = "package.json";
  const data = JSON.parse(fs.readFileSync(p, "utf8"));
  data.version = process.argv[1];
  fs.writeFileSync(p, JSON.stringify(data, null, 2) + "\n");
' "$TARGET_VERSION"

# 4. Update integrity.json version if present
if [ -f "integrity.json" ]; then
  printf "==> Updating integrity.json version to %s...\n" "$TARGET_VERSION"
  node -e '
    const fs = require("fs");
    const p = "integrity.json";
    const data = JSON.parse(fs.readFileSync(p, "utf8"));
    data.version = process.argv[1];
    fs.writeFileSync(p, JSON.stringify(data, null, 2) + "\n");
  ' "$TARGET_VERSION"
fi

# 5. Update CHANGELOG.md (respects manual entry if present, otherwise parses Conventional Commits)
if [ -f "CHANGELOG.md" ]; then
  if grep -q "## $TARGET_VERSION" CHANGELOG.md; then
    printf "==> CHANGELOG.md already has section for %s, keeping manual entry.\n" "$TARGET_VERSION"
  else
    printf "==> Generating %s section in CHANGELOG.md from Conventional Commits...\n" "$TARGET_VERSION"
    PREV_TAG="$(git describe --tags --abbrev=0 2>/dev/null || echo "")"
    node -e '
      const fs = require("fs");
      const { execSync } = require("child_process");
      const ver = process.argv[1];
      const prevTag = process.argv[2];
      const range = prevTag ? `${prevTag}..HEAD` : "HEAD";

      let commits = [];
      try {
        commits = execSync(`git log --format="%s" ${range}`, {encoding: "utf8"}).trim().split("\n");
      } catch {}

      const categories = {
        Added: [],
        Fixed: [],
        Performance: [],
        Documentation: [],
        Other: []
      };

      for (const line of commits) {
        if (!line || line.startsWith("chore(release):") || line.startsWith("build:")) continue;
        if (/^feat(\([^)]+\))?:\s*/i.test(line)) {
          categories.Added.push(line.replace(/^feat(\([^)]+\))?:\s*/i, ""));
        } else if (/^fix(\([^)]+\))?:\s*/i.test(line)) {
          categories.Fixed.push(line.replace(/^fix(\([^)]+\))?:\s*/i, ""));
        } else if (/^perf(\([^)]+\))?:\s*/i.test(line)) {
          categories.Performance.push(line.replace(/^perf(\([^)]+\))?:\s*/i, ""));
        } else if (/^docs(\([^)]+\))?:\s*/i.test(line)) {
          categories.Documentation.push(line.replace(/^docs(\([^)]+\))?:\s*/i, ""));
        } else {
          categories.Other.push(line);
        }
      }

      let entry = `## ${ver}\n\n`;
      let hasEntries = false;
      for (const [title, items] of Object.entries(categories)) {
        if (items.length > 0) {
          hasEntries = true;
          entry += `### ${title}\n` + items.map(i => `- ${i}`).join("\n") + "\n\n";
        }
      }
      if (!hasEntries) {
        entry += `### Changes\n- Maintenance release.\n\n`;
      }

      const content = fs.readFileSync("CHANGELOG.md", "utf8");
      const header = "# Changelog\n\n";
      if (content.startsWith(header)) {
        fs.writeFileSync("CHANGELOG.md", header + entry + content.slice(header.length));
      } else {
        fs.writeFileSync("CHANGELOG.md", entry + content);
      }
    ' "$TARGET_VERSION" "$PREV_TAG"
  fi
fi

# 6. Run test suite to verify release readiness
printf "==> Running test suite...\n"
if ! npm test; then
  printf "Error: Test suite failed! Reverting modified files...\n" >&2
  git checkout -- package.json integrity.json CHANGELOG.md
  exit 1
fi

# 7. Git commit and tag
printf "==> Creating release commit and tag %s...\n" "$TAG_NAME"
git add package.json integrity.json CHANGELOG.md
git commit -m "chore(release): bump version to $TARGET_VERSION"
git tag -a "$TAG_NAME" -m "Release $TAG_NAME"

printf "==> Release %s prepared successfully!\n" "$TAG_NAME"
printf "    Commit: %s\n" "$(git rev-parse --short HEAD)"
printf "    Tag:    %s\n" "$TAG_NAME"

# 8. Push to remote
do_push() {
  printf "==> Pushing commits and tag %s to origin...\n" "$TAG_NAME"
  git push origin main
  git push origin "$TAG_NAME"
  printf "==> Successfully pushed to remote! GitHub Actions will build and publish the release.\n"
}

if [ "$AUTO_PUSH" -eq 1 ]; then
  do_push
else
  printf "\nDo you want to push to remote origin now? [y/N] "
  read -r REPLY
  case "$REPLY" in
    [yY]|[yY][eE][sS])
      do_push
      ;;
    *)
      printf "==> Remote push skipped. You can push manually when ready with:\n"
      printf "    git push origin main && git push origin %s\n" "$TAG_NAME"
      ;;
  esac
fi
