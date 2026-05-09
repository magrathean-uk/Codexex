Release Codexex via fastlane.

Steps:
1. `source /Users/bolyki/dev/source/build-env.sh`
2. Run smoke check: `bash Scripts/release-smoke.sh`
3. Review `fastlane/metadata/` — ensure release notes are current
4. `bundle exec fastlane submit` (or the appropriate lane)
5. Verify App Store Connect upload succeeded
