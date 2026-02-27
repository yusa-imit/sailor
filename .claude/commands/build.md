Build the sailor library.

Steps:
1. Run `zig build` in the project root
2. If build fails, analyze the error output
3. If the error is in our code, fix it and rebuild
4. If build succeeds, report success

Optional flags from user input: $ARGUMENTS
- If user specifies a target (e.g., "linux"), cross-compile with `-Dtarget=x86_64-linux`
- If user says "release", add `-Doptimize=ReleaseSafe`
- If user says "clean", run `rm -rf zig-out .zig-cache` first
- If user says "all targets", build for all 6 cross-compile targets
