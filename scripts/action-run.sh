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
case "${INPUT_ANNOTATED_IMAGE:-false}" in
  true|false) ;;
  *) echo "annotated-image must be true or false" >&2; exit 2 ;;
esac

# Pin the tested core revision until its next gem release includes bounded DC
# analysis and model-specific LED ratings.
core_sha=41149c921d4424f8b8b9cd2c853735790a6ce88e
core_dir="${BREADKIT_ACTION_CORE_DIR:-$(mktemp -d "$RUNNER_TEMP/breadkit-core.XXXXXX")}"
if [[ -z "${BREADKIT_ACTION_CORE_DIR:-}" ]]; then
  git init --quiet "$core_dir"
  git -C "$core_dir" remote add origin https://github.com/breadkit/breadkit.git
  git -C "$core_dir" fetch --quiet --depth 1 origin "$core_sha"
  git -C "$core_dir" checkout --quiet --detach FETCH_HEAD
fi

bundle_file="$(mktemp "$RUNNER_TEMP/breadkit-action-Gemfile.XXXXXX")"
ruby -e 'core, lint, file, image = ARGV; gems = "source \"https://rubygems.org\"\ngem \"breadkit\", path: #{core.inspect}\ngem \"breadkit-lint\", path: #{lint.inspect}\n"; gems << "gem \"breadkit-render\", \"~> 0.2.0\"\n" if image == "true"; File.write(file, gems)' \
  "$core_dir" "$GITHUB_ACTION_PATH" "$bundle_file" "${INPUT_ANNOTATED_IMAGE:-false}"
export BUNDLE_GEMFILE="$bundle_file"
bundle install --quiet

cd "$GITHUB_WORKSPACE"
if [[ "${INPUT_ANNOTATED_IMAGE:-false}" == "true" && ! -f "$INPUT_PATH" ]]; then
  echo "annotated-image requires a single circuit file" >&2
  exit 2
fi
report_dir=""
if [[ "${INPUT_UPLOAD_SARIF:-true}" == "true" || "${INPUT_ANNOTATED_IMAGE:-false}" == "true" ]]; then
  report_dir="$(mktemp -d "$GITHUB_WORKSPACE/.breadkit-lint.XXXXXX")"
fi
set +e
if [[ "${INPUT_UPLOAD_SARIF:-true}" == "true" ]]; then
  # Keep the upload path inside the workspace, as required by upload-sarif.
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
if [[ "${INPUT_ANNOTATED_IMAGE:-false}" == "true" ]]; then
  json_report="$report_dir/bklint.json"
  image_path="$report_dir/annotated.png"
  set +e
  bundle exec ruby "$GITHUB_ACTION_PATH/exe/bklint" --format json --out "$json_report" -- "$INPUT_PATH"
  json_status=$?
  if [[ "$json_status" -lt 2 && -s "$json_report" ]]; then
    bundle exec bkrender --format png --annotations "$json_report" --force --output "$image_path" -- "$INPUT_PATH"
    image_status=$?
  else
    image_status=2
  fi
  set -e
  if [[ "$image_status" -eq 0 && -s "$image_path" ]]; then
    printf 'image-file=%s\n' "${image_path#"$GITHUB_WORKSPACE"/}" >> "$GITHUB_OUTPUT"
  else
    echo "annotated image unavailable for $INPUT_PATH" >&2
  fi
fi
printf 'exit-code=%s\n' "$status" >> "$GITHUB_OUTPUT"
