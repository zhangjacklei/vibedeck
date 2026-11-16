# Contributing to vibedeck

Thanks for your interest in improving vibedeck!

## Setup

1. Install Xcode Command Line Tools: `xcode-select --install`
2. Clone and build:
   ```bash
   git clone https://github.com/<你的账号>/videdeck.git
   cd videdeck
   ./build.sh
   ./create_app_bundle.sh
   open vibedeck.app
   ```
3. Grant the three required permissions (Bluetooth, Input Monitoring, Accessibility) in System Settings → Privacy & Security, then restart the app. See the [README](README.md#首次使用三项权限缺一不可) for details.

## Code Style

- Follow Swift conventions
- Use meaningful names
- Keep functions focused
- Prefer `let` over `var`

## Before Submitting

- Run `./build.sh` and make sure it builds with no errors
- Run `./vibedeck --selftest` and make sure all checks pass
- If you change permission / connection logic, run `./vibedeck.app/Contents/MacOS/vibedeck --diag` to verify the reported status
- Never commit device identifiers (Bluetooth MAC/UUID), local absolute paths, certificates, or personal configuration. Use environment variables or local config files (already covered by `.gitignore`) instead.

## Submitting Changes

1. Fork and create a feature branch
2. Make changes following code style
3. Test with a real Siri Remote if your change touches HID / trackpad / permissions
4. Submit a PR with a clear description

## Areas for Contribution

Bug fixes, performance improvements, new features, documentation, and testing.
