#!/bin/zsh
set -euo pipefail

source "$HOME/dev/machine/env.zsh"
: "${CLEAN_DEVELOPMENT_XCODE_SIMULATOR_UDID:?Use clean-development xcode test-run}"
: "${CLEAN_DEVELOPMENT_XCODE_RESULTS_PATH:?Use clean-development xcode test-run}"
: "${CLEAN_DEVELOPMENT_SCRATCH_ROOT:?Load the routed environment}"
: "${XCODE_DERIVED_DATA_PATH:?Load the routed environment}"
: "${SWIFTPM_SHARED_CACHE:?Load the routed environment}"

capture_phase="${1:-before}"
case "$capture_phase" in before|after|before-widgets|after-widgets|verify) ;; *) print -u2 'Use before, after, before-widgets, after-widgets or verify'; exit 2;; esac
capture_selection="${2:-both}"
case "$capture_selection" in both|codexex|claudexex) ;; *) print -u2 'Select both, codexex or claudexex'; exit 2;; esac
capture_codex_repo="${0:A:h:h}"
capture_claude_repo="${capture_codex_repo:h}/claudexex"
capture_root="$CLEAN_DEVELOPMENT_SCRATCH_ROOT/hig-review/$capture_phase"
capture_exit_status=0

for capture_slug in codexex claudexex; do
    if [[ "$capture_selection" != both && "$capture_selection" != "$capture_slug" ]]; then continue; fi
    if [[ "$capture_slug" == codexex ]]; then
        capture_repo="$capture_codex_repo"
        capture_project=CodexMeter.xcodeproj
        capture_scheme=CodexMeteriOSDesignReview
        capture_tests=CodexMeteriOSTests
        capture_app_suite=CodexiOSDesignRenderTests
        capture_widget_suite=CodexWidgetDesignRenderTests
    else
        capture_repo="$capture_claude_repo"
        capture_project=ClaudeMeter.xcodeproj
        capture_scheme=ClaudeMeteriOSDesignReview
        capture_tests=ClaudeMeteriOSTests
        capture_app_suite=ClaudeiOSDesignRenderTests
        capture_widget_suite=ClaudeWidgetDesignRenderTests
    fi
    mkdir -p "$capture_root/$capture_slug"
    if [[ "$capture_phase" == verify ]]; then capture_scheme="${capture_scheme%DesignReview}"; fi
    export TEST_RUNNER_CHILD_HIG_DESIGN_CAPTURE=1
    export TEST_RUNNER_CHILD_HIG_DESIGN_RENDER_OUTPUT="$capture_root/$capture_slug"
    cd "$capture_repo"
    print "Capturing $capture_slug ($capture_phase)"
    # The final pass also runs the existing iOS model, service and presentation tests.
    capture_test_filters=()
    if [[ "$capture_phase" == verify ]]; then
        capture_test_filters=(-skip-testing:"$capture_tests/$capture_widget_suite"
                              -skip-testing:"$capture_tests/$capture_app_suite")
    elif [[ "$capture_phase" == before-widgets || "$capture_phase" == after-widgets ]]; then
        capture_test_filters=(-only-testing:"$capture_tests/$capture_widget_suite")
    elif [[ "$capture_phase" == before ]]; then
        capture_test_filters=(-only-testing:"$capture_tests/$capture_widget_suite"
                              -only-testing:"$capture_tests/$capture_app_suite")
    fi
    capture_app_status=0
    clean-development run --session session-only -- xcodebuild \
        -project "$capture_project" -scheme "$capture_scheme" -configuration Debug \
        -destination "id=$CLEAN_DEVELOPMENT_XCODE_SIMULATOR_UDID" \
        -derivedDataPath "$XCODE_DERIVED_DATA_PATH/$capture_slug-hig-design" \
        -clonedSourcePackagesDirPath "$SWIFTPM_SHARED_CACHE/$capture_slug-swiftpm-cache" \
        -resultBundlePath "$CLEAN_DEVELOPMENT_XCODE_RESULTS_PATH/$capture_slug.xcresult" \
        "${capture_test_filters[@]}" \
        -parallel-testing-enabled NO -enableCodeCoverage NO -collect-test-diagnostics never CODE_SIGNING_ALLOWED=NO \
        test > "$capture_root/$capture_slug-test.log" 2>&1 || capture_app_status=$?
    if (( capture_app_status != 0 )); then
        capture_exit_status=$capture_app_status
        print "$capture_slug validation failed ($capture_app_status); retaining result bundle and capture evidence"
    else
        print "Captured $capture_slug; result bundle: $CLEAN_DEVELOPMENT_XCODE_RESULTS_PATH/$capture_slug.xcresult"
    fi
    if [[ "$capture_phase" == verify ]]; then continue; fi
    # xcresulttool requires a fresh manifest destination on repeat captures.
    capture_export="$capture_root/$capture_slug/exports/${CLEAN_DEVELOPMENT_XCODE_RESULTS_PATH:t}"
    clean-development run --session session-only -- xcrun xcresulttool export attachments \
        --path "$CLEAN_DEVELOPMENT_XCODE_RESULTS_PATH/$capture_slug.xcresult" \
        --output-path "$capture_export" > "$capture_root/$capture_slug-export.log" 2>&1
    print -r -- "$capture_export" > "$capture_root/$capture_slug/latest-export.txt"
done
exit "$capture_exit_status"
