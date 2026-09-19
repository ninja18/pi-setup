# Optional environment for pi. Source it from ~/.zshrc if you want these applied globally:
#
#   echo 'source ~/pi-setup/env.example.sh' >> ~/.zshrc
#
# Everything is commented out by default; none of it is needed for the setup to work.

# Skip the pi.dev "latest version" check at startup (one fewer network call, faster cold start).
# export PI_SKIP_VERSION_CHECK=1

# Disable every startup network operation: version check, package updates, telemetry.
# Useful on metered or offline connections.
# export PI_OFFLINE=1

# The install/update ping is already disabled in settings.json (enableInstallTelemetry: false).
# This is the belt-and-braces equivalent, and it also drops the provider attribution headers.
# export PI_TELEMETRY=0

# Brave Search key for the brave-search skill. Prefer the Keychain path instead:
#   pbpaste | node ~/.pi/agent/skills/brave-search/brave.mjs setkey
# export BRAVE_API_KEY=...
