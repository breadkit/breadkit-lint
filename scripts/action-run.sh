#!/usr/bin/env bash
set -euo pipefail

: "${GITHUB_ACTION_PATH:?}"
: "${GITHUB_WORKSPACE:?}"
: "${GITHUB_OUTPUT:?}"
: "${RUNNER_TEMP:?}"
: "${INPUT_PATH:?}"

case "${INPUT_UPLOAD_SARIF:-true}" in
  true|false) ;;
  *) echo "upload-sarif must be true or false" >&2; exit 2 ;;
esac

# Pin core source until the 0.2 gem is published. The action's own checkout is
# the lint source, so both gems resolve without relying on an unpublished gem.
core_dir="${BREADKIT_ACTION_CORE_DIR:-$(mktemp -d "$RUNNER_TEMP/breadkit-core.XXXXXX")}"
if [[ -z "${BREADKIT_ACTION_CORE_DIR:-}" ]]; then
  git init --quiet "$core_dir"
  git -C "$core_dir" remote add origin https://github.com/breadkit/breadkit.git
  git -C "$core_dir" fetch --quiet --depth 1 origin 37423f7035a032ec5c7700f8634959eb3b225a4a
  git -C "$core_dir" checkout --quiet --detach FETCH_HEAD
fi

bundle_file="$(mktemp "$RUNNER_TEMP/breadkit-action-Gemfile.XXXXXX")"
ruby -e 'core, lint, file = ARGV; File.write(file, "source \"https://rubygems.org\"\ngem \"breadkit\", path: #{core.inspect}\ngem \"breadkit-lint\", path: #{lint.inspect}\n")' \
  "$core_dir" "$GITHUB_ACTION_PATH" "$bundle_file"
export BUNDLE_GEMFILE="$bundle_file"
bundle install --quiet

cd "$GITHUB_WORKSPACE"
set +e
if [[ "${INPUT_UPLOAD_SARIF:-true}" == "true" ]]; then
  report_dir="$(mktemp -d "$GITHUB_WORKSPACE/.breadkit-lint.XXXXXX")"
  report="$report_dir/bklint.sarif"
  bundle exec ruby "$GITHUB_ACTION_PATH/exe/bklint" --format sarif --out "$report" --fail-level "${INPUT_FAIL_LEVEL:-warning}" -- "$INPUT_PATH"
  status=$?
  if [[ -s "$report" ]]; then
    printf 'sarif-file=%s\n' "${report#"$GITHUB_WORKSPACE"/}" >> "$GITHUB_OUTPUT"
  elif [[ "$status" -lt 2 ]]; then
    echo "bklint produced no SARIF report" >&2
    exit 2
  fi
else
  bundle exec ruby "$GITHUB_ACTION_PATH/exe/bklint" --format github --fail-level "${INPUT_FAIL_LEVEL:-warning}" -- "$INPUT_PATH"
  status=$?
fi
set -e
printf 'exit-code=%s\n' "$status" >> "$GITHUB_OUTPUT"
