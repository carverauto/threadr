"""Minimal Bazel rule for producing a Phoenix Mix release tarball."""

def _mix_release_impl(ctx):
    toolchain = ctx.toolchains["@rules_elixir//:toolchain_type"]
    rust_toolchain = ctx.toolchains["@rules_rust//rust:toolchain"]

    otp = toolchain.otpinfo
    elixir = toolchain.elixirinfo
    cargo = rust_toolchain.cargo
    rustc = rust_toolchain.rustc

    erlang_home = otp.erlang_home
    otp_tar = getattr(otp, "release_dir_tar", None)
    elixir_home = elixir.elixir_home or elixir.release_dir.short_path
    tar_out = ctx.outputs.out

    toolchain_inputs = [
        otp.version_file,
        elixir.version_file,
        cargo,
        rustc,
    ]

    if otp_tar:
        toolchain_inputs.append(otp_tar)
    if getattr(elixir, "release_dir", None):
        toolchain_inputs.append(elixir.release_dir)

    transitive_inputs = []
    if getattr(rust_toolchain, "rustc_lib", None):
        transitive_inputs.append(rust_toolchain.rustc_lib)
    if getattr(rust_toolchain, "rust_std", None):
        transitive_inputs.append(rust_toolchain.rust_std)

    inputs = depset(
        direct = toolchain_inputs + ctx.files.srcs,
        transitive = transitive_inputs,
    )

    run_assets = "true" if ctx.attr.run_assets else "false"

    ctx.actions.run_shell(
        mnemonic = "MixRelease",
        inputs = inputs,
        outputs = [tar_out],
        progress_message = "mix release ({})".format(ctx.label.name),
        use_default_shell_env = False,
        command = """
set -euo pipefail

EXECROOT="$PWD"

ELIXIR_HOME_RAW="{elixir_home}"
ELIXIR_HOME="$(cd "$EXECROOT" && cd "$ELIXIR_HOME_RAW" && pwd)"

if [ -n "{otp_tar}" ] && [ -f "$EXECROOT/{otp_tar}" ]; then
  OTP_ROOT="$(mktemp -d)"
  tar -xf "$EXECROOT/{otp_tar}" -C "$OTP_ROOT"
  if [ -d "$OTP_ROOT/lib/erlang" ]; then
    ERLANG_HOME="$OTP_ROOT/lib/erlang"
  else
    ERLANG_HOME="$(find "$OTP_ROOT" -maxdepth 2 -type d -name erlang -print | head -n1)"
  fi
else
  ERLANG_HOME_RAW="{erlang_home}"
  ERLANG_HOME="$(cd "$EXECROOT" && cd "$ERLANG_HOME_RAW" && pwd)"
fi

WORKDIR="$(mktemp -d)"
export HOME="$WORKDIR/.home"
export MIX_HOME="$HOME/.mix"
export HEX_HOME="$HOME/.hex"
export REBAR_BASE_DIR="$HOME/.cache/rebar3"
export MIX_ENV=prod
export LANG=C.UTF-8
export LC_ALL=C.UTF-8
export ELIXIR_ERL_OPTIONS="+fnu"
export CARGO="$EXECROOT/{cargo_path}"
export RUSTC="$EXECROOT/{rustc_path}"
export PATH="$(dirname "$CARGO"):$(dirname "$RUSTC"):$ELIXIR_HOME/bin:$ERLANG_HOME/bin:/usr/bin:/bin"

RUST_LIB_ROOT="$(cd "$(dirname "$RUSTC")/.." && pwd)"
export LD_LIBRARY_PATH="$RUST_LIB_ROOT/lib:$RUST_LIB_ROOT/lib/rustlib/x86_64-unknown-linux-gnu/lib:${{LD_LIBRARY_PATH:-}}"
export CARGO_TARGET_DIR="$WORKDIR/_cargo_target"
export TMPDIR="$WORKDIR/_tmp"
mkdir -p "$TMPDIR"

copy_dir() {{
  local src="$1"
  local dest="$2"
  if command -v rsync >/dev/null 2>&1; then
    rsync -aL "$src" "$dest"
  else
    mkdir -p "$dest"
    cp -aL "${{src%/}}/." "$dest"
  fi
}}

copy_dir "$EXECROOT/{src_dir}/" "$WORKDIR/"
cd "$WORKDIR"
chmod -R u+w .

mix local.hex --force
mix local.rebar --force
mix deps.get --only prod
mix deps.compile

if [ "{run_assets}" = "true" ]; then
  mix tailwind.install --if-missing
  mix esbuild.install --if-missing
  mix assets.deploy
fi

RELEASE_DIR="$(mktemp -d)"
mix release --path "$RELEASE_DIR"

mkdir -p "$(dirname "$EXECROOT/{tar_out}")"
tar -czf "$EXECROOT/{tar_out}" -C "$RELEASE_DIR" .
""".format(
            elixir_home = elixir_home,
            otp_tar = otp_tar.path if otp_tar else "",
            erlang_home = erlang_home,
            cargo_path = cargo.path,
            rustc_path = rustc.path,
            src_dir = ctx.attr.src_dir,
            tar_out = tar_out.path,
            run_assets = run_assets,
        ),
    )

    return [
        DefaultInfo(
            files = depset([tar_out]),
        ),
    ]

mix_release = rule(
    implementation = _mix_release_impl,
    attrs = {
        "srcs": attr.label_list(allow_files = True),
        "src_dir": attr.string(mandatory = True),
        "out": attr.output(mandatory = True),
        "run_assets": attr.bool(default = True),
    },
    toolchains = [
        "@rules_elixir//:toolchain_type",
        "@rules_rust//rust:toolchain",
    ],
)
