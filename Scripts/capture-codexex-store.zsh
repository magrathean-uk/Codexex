#!/bin/zsh
# Native sample-data captures and optional local asc-screens framing. No uploads.
set -euo pipefail
source "$HOME/dev/machine/env.zsh"
cd "${0:A:h:h}"

usage() {
  cat <<'USAGE'
Usage: zsh Scripts/capture-codexex-store.zsh --simulator UUID --output ABSOLUTE_DIR
       [--appearance dark|light] [--family all|iphone|ipad] [--medium-iphone]
       [--generate-project] [--frame]
Use a booted simulator, or the available disposable device selected by Clean Development.
This script does not create or boot devices; xcodebuild may boot the managed destination.
Default: seven 1320x2868 iPhone and seven 2064x2752 iPad native screenshots.
--medium-iphone uses 1206x2622; --frame always renders latest large store sizes.
Framed captions disclose Sample data. All ASC commands are local validation only.
USAGE
}
fail() { print -u2 -- "capture-codexex-store: $*"; exit 1; }
simulator=""; output=""; appearance=dark; family=all; iphone_size=large
generate_project=0; frame=0
while (( $# )); do
  case "$1" in
    --simulator|--output|--appearance|--family)
      (( $# >= 2 )) || fail "Missing value for $1"
      case "$1" in
        --simulator) simulator="$2";; --output) output="$2";;
        --appearance) appearance="$2";; --family) family="$2";;
      esac
      shift 2;;
    --medium-iphone) iphone_size=medium; shift;;
    --generate-project) generate_project=1; shift;;
    --frame) frame=1; shift;;
    --help|-h) usage; exit 0;;
    *) fail "Unknown option: $1";;
  esac
done
[[ -n "$simulator" && "$output" == /* ]] || { usage; fail "Supply a simulator UUID and absolute output directory"; }
[[ "$appearance" == dark || "$appearance" == light ]] || fail "Appearance must be dark or light"
[[ "$family" == all || "$family" == iphone || "$family" == ipad ]] || fail "Family must be all, iphone or ipad"
[[ ! -e "$output" ]] || fail "Output already exists; choose a fresh directory to avoid mixed screenshots"
: "${CLEAN_DEVELOPMENT_SCRATCH_ROOT:?Load routed environment}"
: "${XCODE_DERIVED_DATA_PATH:?Load routed environment}"
: "${SWIFTPM_SHARED_CACHE:?Load routed environment}"
[[ -d "$CLEAN_DEVELOPMENT_SCRATCH_ROOT" && -w "$CLEAN_DEVELOPMENT_SCRATCH_ROOT" ]] || fail "Reviewed scratch route is unavailable"
for tool in clean-development xcodebuild xcrun python3 asc; do command -v "$tool" >/dev/null || fail "Missing $tool"; done
if (( frame )); then
  command -v asc-screens >/dev/null || fail "Missing asc-screens"
  command -v magick >/dev/null || fail "Missing ImageMagick magick"
  command -v "${ASC_SCREENS_FRAMES_BIN:-frames}" >/dev/null || fail "Missing Apple Frames CLI"
fi
# No lifecycle mutation: xcodebuild may boot only the owner-selected disposable device.
xcrun simctl list devices --json | python3 -c '
import json,sys
device=next((d for ds in json.load(sys.stdin)["devices"].values() for d in ds if d["udid"]==sys.argv[1]),None)
managed_shutdown=device and device.get("state")=="Shutdown" and sys.argv[1]==sys.argv[2] and bool(sys.argv[2])
if not device or not device.get("isAvailable",False) or (device.get("state")!="Booted" and not managed_shutdown):
    raise SystemExit("Selected simulator must be booted or the available owner-selected Clean Development disposable device")
' "$simulator" "${CLEAN_DEVELOPMENT_XCODE_SIMULATOR_UDID:-}"
clean-development session --dry-run --json
run() { clean-development run --session session-only -- "$@"; }
if (( generate_project )); then run xcodegen generate --spec project.yml; fi
rg -q CodexiOSStoreRenderTests.swift CodexMeter.xcodeproj/project.pbxproj || fail "Regenerate with xcodegen first, or pass --generate-project"
run mkdir -p "$output/raw"
export TEST_RUNNER_CHILD_CODEXEX_STORE_CAPTURE=1
export TEST_RUNNER_CHILD_CODEXEX_STORE_RENDER_OUTPUT="$output/raw"
export TEST_RUNNER_CHILD_CODEXEX_STORE_APPEARANCE="$appearance"
export TEST_RUNNER_CHILD_CODEXEX_STORE_IPHONE_SIZE="$iphone_size"
export TEST_RUNNER_CHILD_CODEXEX_STORE_FAMILY="$family"
export CODEXEX_STORE_CAPTURE=1 CODEXEX_STORE_RENDER_OUTPUT="$output/raw"
export CODEXEX_STORE_APPEARANCE="$appearance" CODEXEX_STORE_IPHONE_SIZE="$iphone_size" CODEXEX_STORE_FAMILY="$family"
run xcodebuild -project CodexMeter.xcodeproj -scheme CodexMeteriOSStoreScreens \
  -configuration Debug -destination "platform=iOS Simulator,id=$simulator" \
  -derivedDataPath "$XCODE_DERIVED_DATA_PATH/codexex-store-derived-data" \
  -clonedSourcePackagesDirPath "$SWIFTPM_SHARED_CACHE/codexex-store-swiftpm-cache" \
  -resultBundlePath "$output/capture.xcresult" -parallel-testing-enabled NO -collect-test-diagnostics never \
  -only-testing:CodexMeteriOSTests/CodexiOSStoreRenderTests/testCaptureAppStoreScreenshots \
  CODEXEX_STORE_APPEARANCE="$appearance" CODEXEX_STORE_FAMILY="$family" CODEXEX_STORE_IPHONE_SIZE="$iphone_size" \
  CODEXEX_STORE_RENDER_OUTPUT="$output/raw" CODE_SIGNING_ALLOWED=NO test 2>&1 | tee "$output/capture.log"
# XCTest attachments are authoritative, including when sandboxed direct writes fail.
run xcrun xcresulttool export attachments --path "$output/capture.xcresult" \
  --output-path "$output/attachments"
run python3 - "$output" "$family" "$iphone_size" <<'PY'
import json,pathlib,re,shutil,struct,sys
root=pathlib.Path(sys.argv[1]); families=["iphone","ipad"] if sys.argv[2]=="all" else [sys.argv[2]]
names=["01-quota","02-weekly","03-history","04-api-balance","05-settings","06-onboarding","07-api-setup"]
pattern=re.compile(r"^codexex-store-(iphone|ipad)-(\d{2}-[a-z-]+)(?:_|\.png|$)")
for group in json.loads((root/"attachments/manifest.json").read_text()):
    for item in group.get("attachments",[]):
        match=pattern.match(item.get("suggestedHumanReadableName",""))
        if not match: continue
        device,name=match.groups()
        if device not in families or name not in names: continue
        destination=root/"raw"/device/(name+".png"); destination.parent.mkdir(parents=True,exist_ok=True)
        shutil.copy2(root/"attachments"/item["exportedFileName"],destination)
dimensions={"iphone":(1206,2622) if sys.argv[3]=="medium" else (1320,2868),"ipad":(2064,2752)}
receipt=[]
for device in families:
    files=sorted((root/"raw"/device).glob("*.png"))
    if [p.stem for p in files]!=names: raise SystemExit(f"Expected seven ordered {device} screenshots")
    for path in files:
        data=path.read_bytes()
        if data[:8]!=b"\x89PNG\r\n\x1a\n" or struct.unpack(">II",data[16:24])!=dimensions[device]:
            raise SystemExit(f"Unexpected PNG size: {path.name}")
        receipt.append({"family":device,"filename":path.name,"pixels":list(dimensions[device]),"sampleData":True})
(root/"native-captures.json").write_text(json.dumps({"screenshots":receipt},indent=2)+"\n")
print(f"Native screenshots ready: {len(receipt)}")
PY
validate() {
  local dir="$1" phone_slot="$2"
  if [[ -d "$dir/iphone" ]]; then run asc screenshots validate --path "$dir/iphone" --device-type "$phone_slot" --pretty; fi
  if [[ -d "$dir/ipad" ]]; then run asc screenshots validate --path "$dir/ipad" --device-type IPAD_PRO_3GEN_129 --pretty; fi
}
phone_slot=IPHONE_69
[[ "$iphone_size" == medium ]] && phone_slot=IPHONE_61
validate "$output/raw" "$phone_slot"
if (( frame )); then
  run python3 - "$output" "$family" <<'PY'
import json,pathlib,shutil,sys
root=pathlib.Path(sys.argv[1]); families=["iphone","ipad"] if sys.argv[2]=="all" else [sys.argv[2]]
titles={"01-quota":"Know your remaining quota","02-weekly":"Plan your week","03-history":"Follow your usage","04-api-balance":"Track API balance","05-settings":"Make it yours","06-onboarding":"Connect in a few steps","07-api-setup":"Monitor your API account"}
for name,title in titles.items():
    job=root/"framing-inputs"/name; job.mkdir(parents=True)
    for family in families:
        destination=job/"source"/family; destination.mkdir(parents=True)
        shutil.copy2(root/"raw"/family/(name+".png"),destination)
    (job/"copy.json").write_text(json.dumps({"en-GB":{"title":title,"subtitle":"Sample data"}},indent=2))
    config={"source":"source","output_root":str(root/"framing-renders"/name),"kind":"all-latest" if len(families)==2 else families[0]+"-latest","template":"title-top","copy_file":"copy.json","locale":"en-GB","background":"#060A13,#17283E,#2B4B6C","validate":True}
    (job/"config.json").write_text(json.dumps(config,indent=2))
PY
  for config in "$output"/framing-inputs/*/config.json; do run asc-screens --config "$config"; done
  run python3 - "$output" "$family" <<'PY'
import json,pathlib,shutil,sys
root=pathlib.Path(sys.argv[1]); families=["iphone","ipad"] if sys.argv[2]=="all" else [sys.argv[2]]
receipt=[]
for family in families:
    destination=root/"screenshots"/family; destination.mkdir(parents=True)
    for job in sorted((root/"framing-renders").iterdir()):
        files=list((job/"en-GB"/family).glob("*.png"))
        if len(files)!=1: raise SystemExit(f"Framing did not produce exactly one {family} image for {job.name}")
        target=destination/(job.name+".png"); shutil.copy2(files[0],target)
        receipt.append({"family":family,"filename":target.name,"locale":"en-GB","sampleData":True})
    if len(list(destination.glob("*.png")))!=7: raise SystemExit("Incomplete framed set")
(root/"framed-captures.json").write_text(json.dumps({"screenshots":receipt},indent=2)+"\n")
PY
  validate "$output/screenshots" IPHONE_69
fi
print -- "Review native screenshots: $output/raw"
(( ! frame )) || print -- "Review framed screenshots with Sample data disclosure: $output/screenshots"
