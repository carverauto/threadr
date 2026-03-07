"""Lightweight rule to run `mix release` hermetically using rules_elixir toolchains."""

def _mix_release_impl(ctx):
    toolchain = ctx.toolchains["@rules_elixir//:toolchain_type"]

    otp = toolchain.otpinfo
    elixir = toolchain.elixirinfo

    erlang_home = otp.erlang_home
    otp_tar = getattr(otp, "release_dir_tar", None)
    elixir_home = elixir.elixir_home or elixir.release_dir.short_path
    tar_out = ctx.outputs.out

    toolchain_inputs = [
        otp.version_file,
        elixir.version_file,
    ]

    if otp_tar:
        toolchain_inputs.append(otp_tar)
    if getattr(elixir, "release_dir", None):
        toolchain_inputs.append(elixir.release_dir)

    hex_cache = ctx.file.hex_cache

    direct_inputs = toolchain_inputs + ctx.files.srcs + ctx.files.data + ctx.files.extra_dir_srcs
    if hex_cache:
        direct_inputs.append(hex_cache)

    inputs = depset(direct = direct_inputs)

    extra_copy_cmds = []
    for d in ctx.attr.extra_dirs:
        parent = d.rpartition("/")[0] or "."
        extra_copy_cmds.append(
            'mkdir -p "$WORKDIR/{parent}"\ncopy_dir "$EXECROOT/{dir}/" "$WORKDIR/{dir}/"\n'.format(
                dir = d,
                parent = parent,
            ),
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
export PATH="/opt/cargo/bin:$ELIXIR_HOME/bin:$ERLANG_HOME/bin:/usr/local/bin:/usr/bin:/bin"
export CARGO_TARGET_DIR="$WORKDIR/_cargo_target"
export TMPDIR="$WORKDIR/_tmp"
mkdir -p "$TMPDIR"

if [ -n "{hex_cache_tar}" ] && [ -f "$EXECROOT/{hex_cache_tar}" ]; then
  case "$EXECROOT/{hex_cache_tar}" in
    *.tar.gz|*.tgz) tar -xzf "$EXECROOT/{hex_cache_tar}" -C "$HOME" ;;
    *) tar -xf "$EXECROOT/{hex_cache_tar}" -C "$HOME" ;;
  esac
fi

if [ -d /cache ] && [ -w /cache ]; then
  export CARGO_HOME="/cache/cargo"
else
  export CARGO_HOME="$HOME/.cargo"
fi
mkdir -p "$CARGO_HOME"

if ! command -v cargo >/dev/null 2>&1; then
  echo "cargo not found in PATH; expected in the RBE executor image or local host toolchain" >&2
  exit 1
fi

if ! command -v rustc >/dev/null 2>&1; then
  echo "rustc not found in PATH; expected in the RBE executor image or local host toolchain" >&2
  exit 1
fi

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
{extra_copy}
cd "$WORKDIR"
chmod -R u+w .

mix local.hex --force
mix local.rebar --force
mix deps.get --only prod
mix deps.compile
mix compile

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
            src_dir = ctx.attr.src_dir,
            tar_out = tar_out.path,
            run_assets = run_assets,
            extra_copy = "".join(extra_copy_cmds),
            hex_cache_tar = hex_cache.path if hex_cache else "",
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
        "data": attr.label_list(allow_files = True),
        "extra_dirs": attr.string_list(),
        "extra_dir_srcs": attr.label_list(allow_files = True),
        "hex_cache": attr.label(allow_single_file = True),
        "src_dir": attr.string(mandatory = True),
        "out": attr.output(mandatory = True),
        "run_assets": attr.bool(default = True),
    },
    toolchains = [
        "@rules_elixir//:toolchain_type",
    ],
)
